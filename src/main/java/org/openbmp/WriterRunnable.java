/*
 * Copyright (c) 2018 Cisco Systems, Inc. and others.  All rights reserved.
 * Copyright (c) 2018 Tim Evens (tim@evensweb.com).  All rights reserved.
 *
 * This program and the accompanying materials are made available under the
 * terms of the Eclipse Public License v1.0 which accompanies this distribution,
 * and is available at http://www.eclipse.org/legal/epl-v10.html
 *
 */
package org.openbmp;

import java.util.LinkedHashMap;
import java.util.LinkedList;
import java.util.List;
import java.util.Map;
import java.util.concurrent.BlockingQueue;
import java.util.concurrent.TimeUnit;

import org.apache.logging.log4j.LogManager;
import org.apache.logging.log4j.Logger;

/**
 * PSQL writer thread class
 *
 * Inserts messages in bulk and batch (multi-statement) into PSQL by reading
 *      the FIFO queue.
 */
public class WriterRunnable implements  Runnable {
    private static final Logger logger = LogManager.getFormatterLogger(WriterRunnable.class.getName());

    private PSQLHandler db;                                     // DB handler
    private Config cfg;
    private BlockingQueue<Map<String, String>> writerQueue;     // Reference to the writer FIFO queue
    private boolean run;

    /**
     * Constructor
     *
     * @param cfg       Configuration - e.g. DB credentials
     * @param queue     FIFO queue to read from
     */
    public WriterRunnable(Config cfg, BlockingQueue queue) {

        this.cfg = cfg;
        writerQueue = queue;
        run = true;

        db = new PSQLHandler(cfg);
        db.connect();
    }

    /**
     * Shutdown this thread
     */
    public synchronized void shutdown() {
        db.disconnect();
        run = false;
    }

    /**
     * Run the thread
     */
    public void run() {
        if (!db.isDbConnected()) {
            logger.debug("Will not run writer thread since DB isn't connected");
            return;
        }
        logger.debug("writer thread started");

        long cur_time = 0;
        long prev_time = System.currentTimeMillis();

        int bulk_count = 0;

        /*
         * bulk query map has a key of : <prefix|suffix>
         *      Prefix and suffix are from the query FIFO message.  Value is the VALUE to be inserted/updated/deleted
         */
        Map<String, LinkedList<String>> bulk_query = new LinkedHashMap<>();

        try {
            while (run) {
                cur_time = System.currentTimeMillis();

                /*
                 * Do insert/query if max wait/duration has been reached or if max statements have been reached.
                 */
                if (cur_time - prev_time > cfg.getDb_batch_time_millis() ||
                        bulk_count >= cfg.getDb_batch_records()) {

                    if (bulk_count > 0) {
                        logger.trace("Max reached, doing insert: wait_ms=%d bulk_count=%d",
                                    cur_time - prev_time, bulk_count);

                        StringBuilder query = new StringBuilder();

                        // Loop through queries and add them as multi-statements
                        for (Map.Entry<String, LinkedList<String>> entry : bulk_query.entrySet()) {
                            String key = entry.getKey().toString();

                            String[] ins = key.split("[|]");

                            for (String value : entry.getValue()) {

                                if (query.length() > 0)
                                    query.append(';');

                                query.append(ins[0]);
                                query.append(' ');
                                query.append(value);
                                query.append(' ');

                                if (ins.length > 1 && ins[1] != null && ins[1].length() > 0)
                                    query.append(ins[1]);
                            }
                        }

                        if (query.length() > 0) {
                            db.updateQuery(query.toString(), cfg.getDb_retries());
                        }

                        bulk_count = 0;
                        bulk_query.clear();
                    }

                    prev_time = System.currentTimeMillis();
                }

                // Get next query from queue
                Map<String, String> cur_query = writerQueue.poll(cfg.getDb_batch_time_millis(), TimeUnit.MILLISECONDS);

                if (cur_query != null) {
                    if (cur_query.containsKey("prefix")) {
                        String key = cur_query.get("prefix") + "|" + cur_query.get("suffix");
                        ++bulk_count;

                        // merge the data to existing bulk map if already present
                        if (bulk_query.containsKey(key)) {
                            bulk_query.get(key).add(cur_query.get("value"));
                            //bulk_query.put(key, bulk_query.get(key).concat("," + cur_query.get("value")));
                        } else {
                            LinkedList<String> value = new LinkedList<>();
                            value.add(cur_query.get("value"));
                            bulk_query.put(key, value);
                        }

                        if (cur_query.get("value").length() > 100000) {
                            bulk_count = cfg.getDb_batch_records();
                            logger.debug("value length is: %d", cur_query.get("value").length());
                        }
                    }
                    else if (cur_query.containsKey("query")) {  // Null prefix means run query now, not in bulk
                        logger.debug("Non bulk query");

                        db.updateQuery(cur_query.get("query"), 3);
                    }
                }
            }
        } catch (InterruptedException e) {
            e.printStackTrace();
        } catch (Exception e) {
            logger.error("Exception: ", e);
        }

        logger.info("Writer thread done");
    }
}

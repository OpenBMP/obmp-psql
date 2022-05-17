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
    private BlockingQueue<WriterQueueMsg> writerQueue;          // Reference to the writer FIFO queue
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
        Map<String, Map<String, String>> bulk_query = new LinkedHashMap<>();

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


                        // Loop through queries and add as unique values to map
                        for (Map.Entry<String, Map<String, String>> entry : bulk_query.entrySet()) {
                            StringBuilder query = new StringBuilder();

                            String key = entry.getKey();

                            String[] ins = key.split("[|]");
                            query.append(ins[0]);       // Insert statement

                            boolean add_comma = false;
                            for (String value : entry.getValue().values()) {

                                if (add_comma) {
                                    query.append(',');
                                } else {
                                    add_comma = true;
                                }

                                query.append(value);
                            }

                            // Ending suffix statement, such as on conflict
                            if (ins.length > 1 && ins[1] != null && ins[1].length() > 0)
                                query.append(ins[1]);

                            query.append(';');
                            db.updateQuery(query.toString(), cfg.getDb_retries());
                        }

                        bulk_count = 0;
                        bulk_query.clear();
                    }

                    prev_time = System.currentTimeMillis();
                }

                // Get next query from queue
                WriterQueueMsg wmsg = writerQueue.poll(cfg.getDb_batch_time_millis(), TimeUnit.MILLISECONDS);

                if (wmsg != null && wmsg.prefix != null && wmsg != null && wmsg.values.size() > 0) {
                    if (wmsg.bulk_ok) {

                        // First map key is the key for the bulk query statement
                        String key = wmsg.prefix + "|" + wmsg.suffix;

                        // merge the data to existing bulk map if already present
                        if (bulk_query.containsKey(key)) {
                            Map<String, String> query_entry = bulk_query.get(key);

                            // Below will state compress records based on the value hash_id/key.  The last entry
                            //   will be the final one that gets added to postgres.  State compression will only happen
                            //   for same hash_id in the batch_time_millis timeframe. This is normally 500ms or less.
                            for (Map.Entry<String, String> value: wmsg.values.entrySet()) {
                                query_entry.put(value.getKey(), value.getValue());
                                ++bulk_count;
                            }
                        } else { // Add new statement/query to bulk map
                            bulk_query.put(key, wmsg.values);
                            bulk_count += wmsg.values.size();
                        }
                    }
                    else {  // Do not bulk/batch this query, run it now
                        logger.debug("Non bulk query");

                        StringBuilder queryStr = new StringBuilder();
                        queryStr.append(wmsg.prefix);

                        boolean add_comma = false;
                        for (String value: wmsg.values.values()) {
                            if (add_comma) {
                                queryStr.append(',');
                            } else {
                                add_comma = true;
                            }

                            queryStr.append(value);
                        }

                        queryStr.append(wmsg.suffix);

                        db.updateQuery(queryStr.toString(), 3);
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

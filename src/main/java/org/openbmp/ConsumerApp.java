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


import java.util.*;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.TimeUnit;
import org.apache.logging.log4j.LogManager;
import org.apache.logging.log4j.Logger;


/**
 * Postgres OpenBMP consumer
 *      Consumes the openbmp.parsed.* topic streams and stores the data into PostgreSQL.
 */
public class ConsumerApp
{
    private static final Logger logger = LogManager.getFormatterLogger(ConsumerApp.class.getName());
    private ExecutorService executor;
    private final Config cfg;
    private List<ConsumerRunnable> consumerThreads;

    /**
     *
     * @param cfg       Configuration - e.g. DB credentials
     */
    public ConsumerApp(Config cfg) {

        this.cfg = cfg;
        consumerThreads = new ArrayList<>();
    }

    public void shutdown() {
        logger.info("Shutting down Postgres consumer app");

        for (ConsumerRunnable thr: consumerThreads) {
            thr.safe_shutdown();
        }

        // Wait for consumers to finish
        for (ConsumerRunnable consumer: consumerThreads) {

            while (consumer.isRunning()) {
                logger.debug("Consumer still running, waiting for it to shutdown");

                try {
                    Thread.sleep(1000);
                } catch (InterruptedException e) {
                    e.printStackTrace();
                }
            }
        }

        if (executor != null) executor.shutdown();
        try {
            if (!executor.awaitTermination(5000, TimeUnit.MILLISECONDS)) {
                logger.warn("Timed out waiting for consumer threads to shut down, exiting uncleanly");
            }
        } catch (InterruptedException e) {
            logger.warn("Interrupted during shutdown, exiting uncleanly");
        }
    }

    public void run() {
        executor = Executors.newFixedThreadPool(cfg.getConsumer_threads());

        for (int i=0; i < cfg.getConsumer_threads(); i++) {
            ConsumerRunnable consumer = new ConsumerRunnable(cfg);
            executor.submit(consumer);
            consumerThreads.add(consumer);
        }
    }

    public static void main(String[] args) {
        Config cfg = Config.getInstance();

        cfg.parse(args);

        if (! cfg.loadConfig()) {
            logger.error("Failed to load the configuration file, exiting");
            System.exit(1);
        }

        // Validate DB connection
        PSQLHandler db = new PSQLHandler(cfg);
        db.connect();
        if (!db.isDbConnected()) {
            logger.error("Failed to connect to db.  Check configuration and try again.");
            System.exit(2);
        }

        // start the consumer app
        ConsumerApp psqlApp = new ConsumerApp(cfg);

        Runtime.getRuntime().addShutdownHook(new Thread() {
            public void run() {
                this.setName("psqlApp");
                psqlApp.shutdown();
            }
        });

        psqlApp.run();

        try {

            // Give some time to connect
            Thread.sleep(5000);

            boolean run = true;
            while (run) {
                for (ConsumerRunnable consumer: psqlApp.consumerThreads) {
                    if (! consumer.isRunning()) {
                        logger.error("Consumer is not running, exiting");
                        Thread.sleep(1000);
                        run = false;
                    }
                }

                if (cfg.getStatsInterval() > 0) {
                    Thread.sleep(cfg.getStatsInterval() * 1000);

                    for (int i = 0; i < psqlApp.consumerThreads.size(); i++ ) {
                        logger.info("-- STATS --   thread: %d  read: %-10d  consumer_queue: %-10d writer_queues: %-10d",
                                    i, psqlApp.consumerThreads.get(i).getMessageCount(),
                                    psqlApp.consumerThreads.get(i).getConsumerQueueSize(),
                                    psqlApp.consumerThreads.get(i).getQueueSize());
                        logger.info("           collector messages: %d",
                                psqlApp.consumerThreads.get(i).getCollector_msg_count());
                        logger.info("              router messages: %d",
                                psqlApp.consumerThreads.get(i).getRouter_msg_count());
                        logger.info("                peer messages: %d",
                                psqlApp.consumerThreads.get(i).getPeer_msg_count());
                        logger.info("             reports messages: %d",
                                psqlApp.consumerThreads.get(i).getStat_msg_count());
                        logger.info("      base attribute messages: %d",
                                psqlApp.consumerThreads.get(i).getBase_attribute_msg_count());
                        logger.info("      unicast prefix messages: %d",
                                psqlApp.consumerThreads.get(i).getUnicast_prefix_msg_count());
                        logger.info("        l3vpn prefix messages: %d",
                                psqlApp.consumerThreads.get(i).getL3vpn_prefix_msg_count());
                        logger.info("             LS node messages: %d",
                                psqlApp.consumerThreads.get(i).getLs_node_msg_count());
                        logger.info("             LS link messages: %d",
                                psqlApp.consumerThreads.get(i).getLs_link_msg_count());
                        logger.info("           LS prefix messages: %d",
                                psqlApp.consumerThreads.get(i).getLs_prefix_msg_count());
                    }

                } else {
                    Thread.sleep(15000);
                }
            }
        } catch (InterruptedException ie) {
        }

        psqlApp.shutdown();
    }
}

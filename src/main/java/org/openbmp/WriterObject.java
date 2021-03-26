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

import java.util.HashMap;
import java.util.Map;
import java.util.concurrent.ArrayBlockingQueue;
import java.util.concurrent.BlockingQueue;

/**
 *
 */
public class WriterObject {
    ///< Map of assigned record keys to this writer object/thread
    Map<String, Integer> assigned;

    ///< Number of times this object has been above queue high threashold
    Integer above_count;


    Long message_count;
    WriterRunnable writerThread;

    /**
     * FIFO queue for SQL messages to be written/inserted
     *      Queue message:
     *          Object is a hash map where the key is:
     *              prefix:     Insert statement including the VALUES keyword
     *              suffix:     ON DUPLICATE KEY UPDATE suffix, can be empty if not used
     *              value:      Comma delimited set of VALUES
     */
    BlockingQueue<Map<String, String>> writerQueue;

    /**
     * Constructor
     *
     * @param cfg            Configuration from cli/config file
     */
    WriterObject(Config cfg) {
        message_count = 0L;
        assigned = new HashMap<>();
        writerQueue = new ArrayBlockingQueue(cfg.getWriter_queue_size());
        writerThread = new WriterRunnable(cfg, writerQueue);
        above_count = 0;
    }
}

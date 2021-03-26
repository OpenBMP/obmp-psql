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

import org.apache.kafka.clients.consumer.KafkaConsumer;
import org.apache.kafka.common.TopicPartition;
import org.apache.logging.log4j.LogManager;
import org.apache.logging.log4j.Logger;

import java.util.Collection;

/**
 * Rebalance Listener - Handle partition changes
 */
public class ConsumerRebalanceListener implements org.apache.kafka.clients.consumer.ConsumerRebalanceListener {
    private static final Logger logger = LogManager.getFormatterLogger(ConsumerRebalanceListener.class.getName());

    private KafkaConsumer<?,?> consumer;

    public ConsumerRebalanceListener(KafkaConsumer<?,?> consumer) {

        this.consumer = consumer;
    }

    public void onPartitionsRevoked(Collection<TopicPartition> partitions) {
        // save the offsets in an external store using some custom code not described here
        for(TopicPartition partition: partitions)
            logger.info("Revoke partition %s [ %d ] ", partition.topic(), partition.partition());

    }

    public void onPartitionsAssigned(Collection<TopicPartition> partitions) {

        // read the offsets from an external store using some custom code not described here
        for(TopicPartition partition: partitions)
            logger.info("Assign partition %s [ %d ] ", partition.topic(), partition.partition());
    }
}

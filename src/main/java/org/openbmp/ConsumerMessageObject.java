/*
 * Copyright (c) 2018-2022 Cisco Systems, Inc. and others.  All rights reserved.
 * Copyright (c) 2018-2022 Tim Evens (tim@evensweb.com).  All rights reserved.
 */
package org.openbmp;

import java.util.Map;

/**
 * Consumer message object to be sent to writer
 */
public class ConsumerMessageObject {
    public String key;
    public Map<String, String> query;
    public ConsumerRunnable.ThreadType thread_type;
}

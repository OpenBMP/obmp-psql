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

import java.util.Map;

/**
 * Consumer message object to be sent to writer
 */
public class ConsumerMessageObject {
    public String key;
    public Map<String, String> query;
    public ConsumerRunnable.ThreadType thread_type;
}

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

/**
 *
 */
public class RouterObject {
    public Integer connection_count;                // Count of connections

    /**
     * Constructor
     *
     */
    public RouterObject() {
         connection_count = new Integer(1);
    }

    /**
     * Check if the router is connected
     *
     * @return true if connected, false if not.
     */
    public boolean isConnected() {
        return (connection_count > 0) ? true : false;
    }
}

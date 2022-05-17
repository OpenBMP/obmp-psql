/*
 * Copyright (c) 2022 Cisco Systems, Inc. and others.  All rights reserved.
 */
package org.openbmp;

import java.util.Map;

/**
 * WriterRunnable Queue Message Object
 */
public class WriterQueueMsg {
    ///< Boolean to indicate if message can be bulk/batched or not
    Boolean bulk_ok;

    ///< Postgres insert prefix statement string
    String prefix;

    ///< Postgres insert suffix string
    String suffix;

    ///< Map of values (postgres bulk syntax)
    Map<String, String> values;

    WriterQueueMsg () {
        bulk_ok = Boolean.TRUE;
    }
}

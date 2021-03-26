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

import org.apache.logging.log4j.LogManager;
import org.apache.logging.log4j.Logger;

import java.lang.management.ManagementFactory;
import java.sql.*;
import java.util.*;


/**
 * PSQL handler class
 *
 * Connects and maintains connection to DB.
 * Provides various utility methods to interact with postgres.
 */
public class PSQLHandler {
    private static final Logger logger = LogManager.getFormatterLogger(PSQLHandler.class.getName());

    private Connection con;                                     // PSQL connection
    private Boolean dbConnected;                                // Indicates if DB is connected or not
    private Config cfg;
    private int pid;                                            // PID of process

    /**
     * Constructor
     *
     * @param cfg       Configuration - e.g. DB credentials
     */
    public PSQLHandler(Config cfg) {

        this.cfg = cfg;
        con = null;
    }

    public void disconnect() {
        if (dbConnected && con != null) {
            try {
                con.close();
                dbConnected = false;
            } catch (SQLException e) {
                e.printStackTrace();
            }
        }
    }

    public boolean connect() {
        dbConnected = false;

        if (con != null) {
            try {
                con.close();
            } catch (SQLException e) {
                e.printStackTrace();
            }
            con = null;
        }

        logger.info("Connecting to Postgres");
        try {
            Thread.sleep(1000);
        } catch (InterruptedException e1) {
            // ignore
        }

        /*
         * Establish connection to PSQL
         */
        try {
            // See https://jdbc.postgresql.org/documentation/head/ssl-client.html for ssl config

            String url = "jdbc:postgresql://" + cfg.getDbHost() + "/" + cfg.getDbName();

            Properties props = new Properties();
            props.setProperty("user", cfg.getDbUser());
            props.setProperty("password", cfg.getDbPw());
            props.setProperty("ssl", "true");
            props.setProperty("sslmode", "require");
            props.setProperty("sslfactory", "org.postgresql.ssl.NonValidatingFactory");
            props.setProperty("connectTimeout", "10" /* seconds */);
            props.setProperty("socketTimeout", "30" /* seconds */);
            props.setProperty("tcpKeepAlive", "true");
            props.setProperty("ApplicationName", "obmp-consumer");

            con = DriverManager.getConnection(url, props);

            con.setAutoCommit(true);

            logger.info("Writer connected to postgres");

            dbConnected = true;

        } catch (SQLException e) {
            e.printStackTrace();
            logger.warn("Writer thread failed to connect to psql", e);
        }

        return dbConnected;
    }

    /**
     * Run PSQL select query
     *
     * @param query         Select query string to run
     *
     * Returns List of rows.  Each row entry is a map where the key is the column name and the value is
     *       the string value.
     */
    public List<Map<String, String>> selectQuery(String query) {
        List<Map<String, String>> rows = new ArrayList<>();

        Statement stmt = null;
        ResultSet rs = null;

        try {
            stmt = con.createStatement();
            rs = stmt.executeQuery(query);

            ResultSetMetaData meta = rs.getMetaData();

            while (rs.next()) {
                Map<String, String> row = new HashMap();

                for (int i = 1; i <= meta.getColumnCount(); i++) {
                    row.put(meta.getColumnName(i), rs.getString(i));
                }

                rows.add(row);
            }

            rs.close();
            stmt.close();

        } catch (SQLException e) {
            e.printStackTrace();
        }

        return rows;
    }

    /**
     * Run PSQL update query
     *
     * @param query         Query string to run
     * @param retries       Number of times to retry, zero means no retries
     */
    public void updateQuery(String query, int retries) {
        Boolean success = Boolean.FALSE;

        if (!dbConnected) {
            connect();
        }

        // Loop the request if broken pipe, connection timed out, or deadlock
         for (int i = 0; i < retries; i++) {
            try {
                Statement stmt = con.createStatement();
                logger.trace("SQL Query retry = %d: %s", i, query);

                stmt.executeUpdate(query);
                stmt.close();

                i = retries;
                success = Boolean.TRUE;
                break;

            } catch (SQLException e) {
                // state 42804 can be invalid query, should not really retry for that.

                if (!e.getSQLState().equals("42601")  && i >= (retries - 1)) {
                    logger.info("SQL exception state " + i + " : " + e.getSQLState());
                    logger.info("SQL exception: " + e.getMessage());
                }

                if (e.getMessage().contains("connection") ||
                        e.getMessage().contains("Broken pipe")) {
                    logger.error("Not connected to psql: " + e.getMessage());

                    while (!connect()) {
                        try {
                            Thread.sleep(1000);
                        } catch (InterruptedException e1) {
                            // ignore
                        }
                    }
                } else if (e.getMessage().contains("deadlock") ) {
                    try {
                        Thread.sleep(150);
                    } catch (InterruptedException e2) {
                        // ignore
                    }
                }
            }
        }

        if (!success) {
            logger.warn("Failed to insert/update after %d max retires", retries);
            logger.debug("query: " + query);
        }
    }

     /**
     * Indicates if the DB is connected or not.
     *
     * @return True if DB is connected, False otherwise
     */
    public boolean isDbConnected() {
        boolean status;

        status = dbConnected;

        return status;
    }
}

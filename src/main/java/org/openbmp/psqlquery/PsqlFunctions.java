package org.openbmp.psqlquery;
/*
 * Copyright (c) 2020-2022 Cisco Systems, Inc. and others.  All rights reserved. *
 */


import java.util.List;

/**
 * Various functions to generate inserts/queries/etc for PSQL
 */
public class PsqlFunctions {

    public static String create_sql_string(Query query) {

        StringBuilder queryStr = new StringBuilder();

        String[] insertStmt = query.genInsertStatement();
        queryStr.append(insertStmt[0]);         // insert ... values

        boolean add_comma = false;
        for (String value: query.genValuesStatement().values()) {
            if (add_comma)
                queryStr.append(',');
            else
                add_comma = true;
            queryStr.append(value);

        }

        queryStr.append(insertStmt[1]);         // after values

        return queryStr.toString();
    }

    /**
     * Get PSQL values string from list of values
     *
     * @param values        List of values*
     * @return  String of values
     */
    public static String get_values_string(List<String> values) {
        StringBuilder sb = new StringBuilder();
        boolean first_value = true;

        for (String value: values) {
            if (!first_value)
                sb.append(',');
            else
                first_value = false;

            sb.append(value);
        }

        return sb.toString();
    }

    /**
     * create_psql_array from comma delimited string value of long values
     *
     * @param      items    Space delimited string of long values (32bit unsigned values)
     *
     * @return PSQL array string
     */
    public static String create_psql_array_long_string(String items) {
        StringBuilder sb = new StringBuilder();
        boolean first_item = true;

        sb.append("'{");
        for (String item: items.split(" ")) {
            try {
                if (item.length() <= 0 || item.equals("{") || item.equals("}"))
                    continue;

                if (!first_item)
                    sb.append(',');
                else
                    first_item = false;

                sb.append(item);

            } catch (Exception e) {
                continue;
            }
        }

        sb.append("}'");
        sb.append("::bigint[]");

        return sb.toString();
    }


    /**
     * create_psql_array from long array
     *
     * @param items     Long array of items
     *
     * @return PSQL array string
     */
    public static String create_psql_array(Long[] items) {
        StringBuilder sb = new StringBuilder();
        boolean first_item = true;

        sb.append("'{");
        for (Long item: items) {

            if (!first_item)
                sb.append(',');
            else
                first_item = false;

            sb.append(item);
        }

        sb.append("}'");

        return sb.toString();
    }


    /**
     * create_psql_array from long array
     *
     * @param items     Long array of items
     * @return PSQL array string
     */
    public static String create_psql_array(long[] items) {
        StringBuilder sb = new StringBuilder();
        boolean first_item = true;

        sb.append("'{");
        for (long item: items) {

            if (!first_item)
                sb.append(',');
            else
                first_item = false;

            sb.append(item);
        }

        sb.append("}'");

        return sb.toString();
    }

    /**
     * create_psql_array from string array
     *
     * @param items     String array of items
     * @return PSQL array string
     */
    public static String create_psql_array(String[] items) {
        return create_psql_array(items, false, false, false);
    }

    /**
     * create_psql_array from string array
     *
     * @param items         String array of items
     * @param makeNested    True if array should be created as nested value array
     * @param hasArrays     True if items are arrays
     * @param useNull       True to use null instead of empty string
     *
     * @return PSQL array string
     */
    public static String create_psql_array(String[] items, boolean makeNested, boolean hasArrays, boolean useNull) {
        StringBuilder sb = new StringBuilder();
        boolean first_item = true;

        if (!makeNested)
            sb.append('\'');

        sb.append('{');
        for (String item: items) {

            if (!first_item)
                sb.append(',');
            else
                first_item = false;

            if (useNull && (item == null || item.length() == 0)) {
                sb.append("null");

            } else {
                if (!hasArrays)
                    sb.append('"');

                if (item != null)
                    sb.append(item);

                if (!hasArrays)
                    sb.append('"');
            }
        }

        sb.append('}');

        if (!makeNested)
            sb.append('\'');

        sb.append("::varchar[]");
        return sb.toString();
    }

}

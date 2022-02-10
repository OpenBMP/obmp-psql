/*
 * Copyright (c) 2022 Tim Evens (tim@evensweb.com).  All rights reserved.
 *
 * This program and the accompanying materials are made available under the
 * terms of the Eclipse Public License v1.0 which accompanies this distribution,
 * and is available at http://www.eclipse.org/legal/epl-v10.html
 *
 */
package org.openbmp.psqlquery;

import java.util.List;

import org.openbmp.api.helpers.IpAddr;
import org.openbmp.api.parsed.message.L3VpnPrefixPojo;

import static org.openbmp.psqlquery.PsqlFunctions.create_psql_array;


public class L3VpnPrefixQuery extends Query {
    private final List<L3VpnPrefixPojo> records;

    public L3VpnPrefixQuery(List<L3VpnPrefixPojo> records){

        this.records = records;
    }


    /**
     * Generate insert/update statement, sans the values
     *
     * @return Two strings are returned
     *      0 = Insert statement string up to VALUES keyword
     *      1 = ON DUPLICATE KEY UPDATE ...  or empty if not used.
     */
    public String[] genInsertStatement() {
        String [] stmt = { " INSERT INTO l3vpn_rib (hash_id,peer_hash_id,base_attr_hash_id,isIPv4," +
                "origin_as,prefix,prefix_len,timestamp," +
                "isWithdrawn,path_id,labels,isPrePolicy,isAdjRibIn,rd,ext_community_list) " +

//                            " VALUES ",
                "SELECT DISTINCT ON (hash_id) * FROM ( VALUES ",

                ") t (hash_id,peer_hash_id,base_attr_hash_id,isIPv4," +
                        "origin_as,prefix,prefix_len,timestamp," +
                        "isWithdrawn,path_id,labels,isPrePolicy,isAdjRibIn,rd,ext_community_list) " +
                        " ORDER BY hash_id,timestamp desc" +
                        " ON CONFLICT (peer_hash_id,hash_id) DO UPDATE SET timestamp=excluded.timestamp," +
                        "base_attr_hash_id=CASE excluded.isWithdrawn WHEN true THEN l3vpn_rib.base_attr_hash_id ELSE excluded.base_attr_hash_id END," +
                        "origin_as=CASE excluded.isWithdrawn WHEN true THEN l3vpn_rib.origin_as ELSE excluded.origin_as END," +
                        "isWithdrawn=excluded.isWithdrawn," +
                        "path_id=excluded.path_id, labels=excluded.labels," +
                        "isPrePolicy=excluded.isPrePolicy, isAdjRibIn=excluded.isAdjRibIn," +
                        "rd=excluded.rd,ext_community_list=excluded.ext_community_list "
        };
        return stmt;
    }

    /**
     * Generate bulk values statement for SQL bulk insert.
     *
     * @return String in the format of (col1, col2, ...)[,...]
     */
    public String genValuesStatement() {
        StringBuilder sb = new StringBuilder();

        int i = 0;
        for (L3VpnPrefixPojo pojo: records) {

            if (i > 0)
                sb.append(',');

            i++;

            sb.append("('");
            sb.append(pojo.getHash()); sb.append("'::uuid,");
            sb.append('\''); sb.append(pojo.getPeer_hash()); sb.append("'::uuid,");

            if (pojo.getBase_attr_hash().length() != 0) {
                sb.append('\'');
                sb.append(pojo.getBase_attr_hash());
                sb.append("'::uuid,");
            } else {
                sb.append("null::uuid,");
            }

            sb.append(pojo.getIPv4()); sb.append("::boolean,");

            sb.append(pojo.getOrigin_asn()); sb.append(',');

            sb.append('\''); sb.append(pojo.getPrefix()); sb.append('/');
            sb.append(pojo.getPrefix_len());
            sb.append("'::inet,");

            sb.append(pojo.getPrefix_len()); sb.append(',');

            sb.append('\''); sb.append(pojo.getTimestamp()); sb.append("'::timestamp,");
            sb.append(pojo.getWithdrawn()); sb.append(',');
            sb.append(pojo.getPath_id()); sb.append(',');
            sb.append('\''); sb.append(pojo.getLabels()); sb.append("',");
            sb.append(pojo.getPrePolicy()); sb.append("::boolean,");
            sb.append(pojo.getAdjRibIn()); sb.append("::boolean,");

            sb.append('\''); sb.append(pojo.getRd()); sb.append("',");
            sb.append(create_psql_array(pojo.getExt_community_list().split(" ")));

            sb.append(')');
        }

        return sb.toString();
    }

}

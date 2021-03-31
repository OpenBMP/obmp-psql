/*
 * Copyright (c) 2018 Tim Evens (tim@evensweb.com).  All rights reserved.
 *
 * This program and the accompanying materials are made available under the
 * terms of the Eclipse Public License v1.0 which accompanies this distribution,
 * and is available at http://www.eclipse.org/legal/epl-v10.html
 *
 */

package org.openbmp.psqlquery;

import java.util.HashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;

import org.openbmp.api.parsed.message.BaseAttributePojo;
import org.openbmp.api.parsed.message.MsgBusFields;

public class BaseAttributeQuery extends Query{
	private final List<BaseAttributePojo> records;

	public BaseAttributeQuery(List<BaseAttributePojo> records){
		
		this.records = records;
	}
	
    /**
     * Generate MySQL insert/update statement, sans the values
     *
     * @return Two strings are returned
     *      0 = Insert statement string up to VALUES keyword
     *      1 = ON DUPLICATE KEY UPDATE ...  or empty if not used.
     */
    public String[] genInsertStatement() {
        final String [] stmt = { " INSERT INTO base_attrs (hash_id,peer_hash_id,origin,as_path,origin_as,next_hop,med,local_pref," +
                                 "isAtomicAgg,aggregator,community_list,ext_community_list,large_community_list," +
                                 "cluster_list,originator_id,as_path_count,nexthop_isIPv4,timestamp)" +
//                                  " VALUES ",
                                 "SELECT DISTINCT ON (hash_id) * FROM ( VALUES ",

                                 ") t(hash_id,peer_hash_id,origin,as_path,origin_as,next_hop,med,local_pref," +
                                      "isAtomicAgg,aggregator,community_list,ext_community_list,large_community_list," +
                                      "cluster_list,originator_id,as_path_count,nexthop_isIPv4,timestamp)" +
                                 " ORDER BY hash_id,timestamp desc" +
                                    " ON CONFLICT (peer_hash_id,hash_id) DO UPDATE SET " +
                                            "timestamp=excluded.timestamp" };
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
        for (BaseAttributePojo pojo: records) {
            if (i > 0)
                sb.append(',');

            i++;

            sb.append('(');
            sb.append('\''); sb.append(pojo.getHash()); sb.append("'::uuid,");
            sb.append('\''); sb.append(pojo.getPeer_hash()); sb.append("'::uuid,");
            sb.append('\''); sb.append(pojo.getOrigin()); sb.append("',");
            sb.append('\''); sb.append(pojo.getAs_path()); sb.append("',");
            sb.append(pojo.getOrigin_asn()); sb.append(',');
            sb.append('\''); sb.append(pojo.getNext_hop()); sb.append("'::inet,");
            sb.append(pojo.getMed()); sb.append(',');
            sb.append(pojo.getLocal_pref()); sb.append(',');
            sb.append(pojo.getAtomicAggregate()); sb.append("::boolean,");
            sb.append('\''); sb.append(pojo.getAggregator()); sb.append("',");
            sb.append('\''); sb.append(pojo.getCommunity_list()); sb.append("',");
            sb.append('\''); sb.append(pojo.getExt_community_list()); sb.append("',");
            sb.append('\''); sb.append(pojo.getLarge_community_list()); sb.append("',");
            sb.append('\''); sb.append(pojo.getCluster_list()); sb.append("',");


            if (pojo.getOriginator_id().length() > 0) {
                sb.append('\'');
                sb.append(pojo.getOriginator_id()); sb.append("'::inet,");
            } else {
                sb.append("null::inet,");
            }

            sb.append(pojo.getAs_path_len()); sb.append(',');
            sb.append(pojo.getNextHopIpv4()); sb.append("::boolean,");
            sb.append('\''); sb.append(pojo.getTimestamp()); sb.append("'::timestamp");
            sb.append(')');
        }

        return sb.toString();
    }

    /**
     * Generate MySQL insert/update statement, sans the values for as_path_analysis
     *
     * @return Two strings are returned
     *      0 = Insert statement string up to VALUES keyword
     *      1 = ON DUPLICATE KEY UPDATE ...  or empty if not used.
     */
    public String[] genAsPathAnalysisStatement() {
        final String [] stmt = {" INSERT INTO as_path_analysis (asn,asn_left,asn_right,asn_left_is_peering)" +
                                    " VALUES ",
                                " ON CONFLICT (asn,asn_left_is_peering,asn_left,asn_right) DO NOTHING" };
        return stmt;
    }

    /**
     * Generate bulk values statement for SQL bulk insert for as_path_analysis
     *
     * @return String in the format of (col1, col2, ...)[,...]
     */
    public String genAsPathAnalysisValuesStatement() {
        StringBuilder sb = new StringBuilder();
        Set<String> values = new HashSet<String>();

        /*
         * Iterate through the AS Path and extract out the left and right ASN for each AS within
         *     the AS PATH
         */
        for (BaseAttributePojo pojo: records) {

            String as_path_str = pojo.getAs_path().trim();
            as_path_str = as_path_str.replaceAll("[{}]", "");
            String[] as_path = as_path_str.split(" ");

            Long left_asn = 0L;
            Long right_asn = 0L;
            Long asn = 0L;

            for (int i=0; i < as_path.length; i++) {
                if (as_path[i].length() <= 0)
                    break;

                try {
                    asn = Long.valueOf(as_path[i]);
                } catch (NumberFormatException e) {
                    e.printStackTrace();
                    break;
                }

                if (asn > 0 ) {
                    if (i+1 < as_path.length) {

                        if (as_path[i + 1].length() <= 0)
                            break;

                        try {
                            right_asn = Long.valueOf(as_path[i + 1]);

                        } catch (NumberFormatException e) {
                            e.printStackTrace();
                            break;
                        }

                        if (right_asn.equals(asn)) {
                            continue;
                        }

                        String isPeeringAsn = (i == 0 || i == 1) ? "1" : "0";

                        StringBuilder vsb = new StringBuilder();
                        vsb.append('(');
                        vsb.append(asn); vsb.append(',');
                        vsb.append(left_asn); vsb.append(',');
                        vsb.append(right_asn); vsb.append(',');
                        vsb.append(isPeeringAsn); vsb.append("::boolean)");
                        values.add(vsb.toString());

                    } else {
                        // No more left in path - Origin ASN
                        StringBuilder vsb = new StringBuilder();
                        vsb.append('(');
                        vsb.append(asn); vsb.append(',');
                        vsb.append(left_asn);
                        vsb.append(",0,false)");
                        values.add(vsb.toString());

                        break;
                    }

                    left_asn = asn;
                }
            }
        }


        for (String value: values) {
            if (sb.length() > 0) {
                sb.append(',');
            }

            sb.append(value);
        }

        return sb.toString();
    }

}

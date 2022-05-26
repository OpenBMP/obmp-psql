/*
 * Copyright (c) 2018-2022 Cisco Systems, Inc. and others.  All rights reserved.
 */

package org.openbmp.psqlquery;

import java.util.*;

import org.openbmp.api.parsed.message.BaseAttributePojo;
import org.openbmp.api.parsed.message.MsgBusFields;

import static org.openbmp.psqlquery.PsqlFunctions.create_psql_array;
import static org.openbmp.psqlquery.PsqlFunctions.create_psql_array_long_string;

public class BaseAttributeQuery extends Query{
	private final List<BaseAttributePojo> records;

	public BaseAttributeQuery(List<BaseAttributePojo> records){
		
		this.records = records;
	}
	
    public String[] genInsertStatement() {
        final String [] stmt = { " INSERT INTO base_attrs (hash_id,peer_hash_id,origin,as_path,origin_as,next_hop,med,local_pref," +
                                 "isAtomicAgg,aggregator,community_list,ext_community_list,large_community_list," +
                                 "cluster_list,originator_id,as_path_count,nexthop_isIPv4,timestamp)" +
                                  " VALUES ",
//                                 "SELECT DISTINCT ON (hash_id) * FROM ( VALUES ",
//                                 ") t(hash_id,peer_hash_id,origin,as_path,origin_as,next_hop,med,local_pref," +
//                                      "isAtomicAgg,aggregator,community_list,ext_community_list,large_community_list," +
//                                      "cluster_list,originator_id,as_path_count,nexthop_isIPv4,timestamp)" +
//                                 " ORDER BY hash_id,timestamp desc" +
                                    " ON CONFLICT (hash_id) DO UPDATE SET " +
                                            "timestamp=excluded.timestamp" };
        return stmt;
    }

    public Map<String,String> genValuesStatement() {
        Map<String, String> values = new HashMap<>();

        for (BaseAttributePojo pojo: records) {
            StringBuilder sb = new StringBuilder();

            sb.append('(');
            sb.append('\''); sb.append(pojo.getHash()); sb.append("'::uuid,");
            sb.append('\''); sb.append(pojo.getPeer_hash()); sb.append("'::uuid,");
            sb.append('\''); sb.append(pojo.getOrigin()); sb.append("',");

            sb.append(create_psql_array_long_string(pojo.getAs_path())); sb.append(',');

            sb.append(pojo.getOrigin_asn()); sb.append(',');
            sb.append('\''); sb.append(pojo.getNext_hop()); sb.append("'::inet,");
            sb.append(pojo.getMed()); sb.append(',');
            sb.append(pojo.getLocal_pref()); sb.append(',');
            sb.append(pojo.getAtomicAggregate()); sb.append("::boolean,");
            sb.append('\''); sb.append(pojo.getAggregator()); sb.append("',");

            sb.append(create_psql_array(pojo.getCommunity_list().split(" "))); sb.append(',');
            sb.append(create_psql_array(pojo.getExt_community_list().split(" "))); sb.append(',');
            sb.append(create_psql_array(pojo.getLarge_community_list().split(" "))); sb.append(',');
            sb.append(create_psql_array(pojo.getCluster_list().split(" "))); sb.append(',');

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

            values.put(pojo.getHash(), sb.toString());
        }

        return values;
    }


}

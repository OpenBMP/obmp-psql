/*
 * Copyright (c) 2018-2022 Cisco Systems, Inc. and others.  All rights reserved.
 */
package org.openbmp.psqlquery;

import java.util.HashMap;
import java.util.List;
import java.util.Map;

import org.openbmp.api.parsed.message.MsgBusFields;

public class BmpStatQuery extends Query{
	
	public BmpStatQuery(List<Map<String, Object>> rowMap){
		
		this.rowMap = rowMap;
	}
	
    public String[] genInsertStatement() {
        String [] stmt = { " INSERT INTO stat_reports (peer_hash_id,timestamp,prefixes_rejected,known_dup_prefixes,known_dup_withdraws," +
                           "updates_invalid_by_cluster_list,updates_invalid_by_as_path_loop,updates_invalid_by_originagtor_id," +
                           "updates_invalid_by_as_confed_loop,num_routes_adj_rib_in,num_routes_local_rib) VALUES ",

                           " " };
        return stmt;
    }

    public Map<String, String> genValuesStatement() {
        Map<String, String> values = new HashMap<>();

        for (int i=0; i < rowMap.size(); i++) {
            StringBuilder sb = new StringBuilder();

            sb.append('(');
            sb.append("'" + lookupValue(MsgBusFields.PEER_HASH, i) + "',");
            sb.append("'" + lookupValue(MsgBusFields.TIMESTAMP, i) + "',");
            sb.append(lookupValue(MsgBusFields.REJECTED, i) + ",");
            sb.append(lookupValue(MsgBusFields.KNOWN_DUP_UPDATES, i) + ",");
            sb.append(lookupValue(MsgBusFields.KNOWN_DUP_WITHDRAWS, i) + ",");
            sb.append(lookupValue(MsgBusFields.INVALID_CLUSTER_LIST, i) + ",");
            sb.append(lookupValue(MsgBusFields.INVALID_AS_PATH, i) + ",");
            sb.append(lookupValue(MsgBusFields.INVALID_ORIGINATOR, i) + ",");
            sb.append(lookupValue(MsgBusFields.INVALID_AS_CONFED, i) + ",");
            sb.append(lookupValue(MsgBusFields.PRE_POLICY, i) + ",");
            sb.append(lookupValue(MsgBusFields.POST_POLICY, i) + "");

            sb.append(')');

            values.put(lookupValue(MsgBusFields.PEER_HASH, i).toString(), sb.toString());
        }

        return values;
    }


}

/*
 * Copyright (c) 2018-2022 Cisco Systems, Inc. and others.  All rights reserved.
 */
package org.openbmp.psqlquery;

import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;

import org.openbmp.RouterObject;
import org.openbmp.api.parsed.message.CollectorPojo;
import org.openbmp.api.parsed.message.MsgBusFields;

public class CollectorQuery extends Query{
    private final List<CollectorPojo> records;


    public CollectorQuery(List<CollectorPojo> records){
		
		this.records = records;
	}
	
    public String[] genInsertStatement() {
        String [] stmt = { " INSERT INTO collectors (hash_id,state,admin_id,routers,router_count,timestamp) " +
                                " VALUES ",

                                " ON CONFLICT (hash_id) DO UPDATE SET state=excluded.state,timestamp=excluded.timestamp," +
                                   "routers=excluded.routers,router_count=excluded.router_count" };
        return stmt;
    }

    public Map<String, String> genValuesStatement() {
        Map<String, String> values = new HashMap<>();

        for (CollectorPojo pojo : records) {
            StringBuilder sb = new StringBuilder();

            sb.append("('");
            sb.append(pojo.getHash()); sb.append("'::uuid,");
            sb.append(pojo.getAction().equalsIgnoreCase("stopped") ? "'down'::opstate," : "'up'::opstate,");
            sb.append('\''); sb.append(pojo.getAdmin_id()); sb.append("',");
            sb.append('\''); sb.append(pojo.getRouter_list()); sb.append("',");
            sb.append(pojo.getRouter_count()); sb.append(',');
            sb.append('\''); sb.append(pojo.getTimestamp()); sb.append("'::timestamp");
            sb.append(')');

            values.put(pojo.getHash(), sb.toString());
        }

        return values;
    }


    /**
     * Generate update statement to update routers
     *
     * @return Multi statement update is returned, such as update ...; update ...;
     */
    public String genRouterCollectorUpdate() {
        Boolean changed = Boolean.FALSE;
        StringBuilder sb = new StringBuilder();
        StringBuilder router_sql_in_list = new StringBuilder();
        router_sql_in_list.append("(");

        int i = 0;
        for (CollectorPojo pojo: records) {

            String action = (String) lookupValue(MsgBusFields.ACTION, i);

            if (i > 0 && sb.length() > 0)
                sb.append(';');

            i++;

            if (pojo.getAction().equalsIgnoreCase("started") || pojo.getAction().equalsIgnoreCase("stopped")) {
                sb.append("UPDATE routers SET state = 'down' WHERE collector_hash_id = '");
                sb.append(pojo.getHash()); sb.append('\'');
            }

            else { // heartbeat or changed
                // nothing
            }
        }

        return sb.toString();
    }


}

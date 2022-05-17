/*
 * Copyright (c) 2018-2022 Cisco Systems, Inc. and others.  All rights reserved.
 */
package org.openbmp.psqlquery;

import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;

import org.openbmp.RouterObject;
import org.openbmp.api.parsed.message.MsgBusFields;
import org.openbmp.api.parsed.message.Message;
import org.openbmp.api.parsed.message.RouterPojo;
import org.openbmp.api.parsed.message.UnicastPrefixPojo;

public class RouterQuery extends Query{
    private final List<RouterPojo> records;
    private String collector_hash;

	public RouterQuery(String collector_hash, List<RouterPojo> records){
        this.records = records;
        this.collector_hash = collector_hash;
	}

    public String[] genInsertStatement() {
        String [] stmt = { " INSERT INTO routers (hash_id,name,ip_address,timestamp,state,term_reason_code," +
                                  "term_reason_text,term_data,init_data,description,collector_hash_id,bgp_id) " +
                            " VALUES ",

                            " ON CONFLICT (hash_id) DO UPDATE SET timestamp=excluded.timestamp,state=excluded.state," +
                                   "name=CASE excluded.state WHEN 'up' THEN excluded.name ELSE routers.name END," +
                                   "description=CASE excluded.state WHEN 'up' THEN excluded.description ELSE routers.description END," +
                                   "bgp_id=excluded.bgp_id," +
                                   "init_data=CASE excluded.state WHEN 'up' THEN excluded.init_data ELSE routers.init_data END," +
                                   "term_reason_code=excluded.term_reason_code,term_reason_text=excluded.term_reason_text," +
                                   "collector_hash_id=excluded.collector_hash_id" };
        return stmt;
    }

    public Map<String, String> genValuesStatement() {
        Map<String, String> values = new HashMap<>();

        for (RouterPojo pojo : records) {
            StringBuilder sb = new StringBuilder();

            sb.append('(');

            sb.append('\''); sb.append(pojo.getHash()); sb.append("'::uuid,");
            sb.append('\''); sb.append(pojo.getName()); sb.append("',");
            sb.append('\''); sb.append(pojo.getIp_address()); sb.append("'::inet,");
            sb.append('\''); sb.append(pojo.getTimestamp()); sb.append("'::timestamp,");

            sb.append(pojo.getAction().equalsIgnoreCase("term") ? "'down'::opstate," : "'up'::opstate,");

            sb.append(pojo.getTerm_code()); sb.append(',');
            sb.append('\''); sb.append(pojo.getTerm_reason()); sb.append("',");
            sb.append('\''); sb.append(pojo.getTerm_data()); sb.append("',");
            sb.append('\''); sb.append(pojo.getInit_data()); sb.append("',");
            sb.append('\''); sb.append(pojo.getDescription()); sb.append("',");
            sb.append('\''); sb.append(collector_hash); sb.append("'::uuid,");

            if (pojo.getBgp_id().length() > 2) {
                sb.append('\'');
                sb.append(pojo.getBgp_id());
                sb.append("'::inet,");
            } else {
                sb.append("null");
            }

            sb.append(')');

            values.put(pojo.getHash(), sb.toString());
        }

        return values;
    }

    
    
    

    /**
     * Generate update statement to update peer status
     *
     * Avoids faulty report of peer status when router gets disconnected
     *
     * @param routerMap         Router tracking map
     *
     * @return Multi statement update is returned, such as update ...; update ...;
     */
    public String genPeerRouterUpdate(Map<String, RouterObject> routerMap) {

        StringBuilder sb = new StringBuilder();

        for (RouterPojo pojo : records) {

            // update router object
            RouterObject rObj;

            if (routerMap.containsKey(pojo.getHash())) {
                rObj = routerMap.get(pojo.getHash());

            } else {
                rObj = new RouterObject();
                routerMap.put(pojo.getHash(), rObj);
            }

            if (pojo.getAction().equalsIgnoreCase("first")
                    || pojo.getAction().equalsIgnoreCase("init")) {

                if (sb.length() > 0)
                    sb.append(";");

                if (rObj.connection_count <= 0) {
                    // Upon initial router message, we set the state of all peers to down since we will get peer UP's
                    //    multiple connections can exist, so this is only performed when this is the first connection
                    sb.append("UPDATE bgp_peers SET state = 'down' WHERE router_hash_id = '");
                    sb.append(pojo.getHash()); sb.append('\'');
                    sb.append(" AND timestamp < '"); sb.append(pojo.getTimestamp()); sb.append('\'');
                }

                // bump the connection count
                rObj.connection_count += 1;
            }

            else if (pojo.getAction().equalsIgnoreCase("term")) {

                if (rObj.connection_count > 0) {
                    rObj.connection_count -= 1;
                }

                //TODO: Considering updating peers with state = 0 on final term of router (connection_count == 0)
            }
        }

        return sb.toString();
    }

}

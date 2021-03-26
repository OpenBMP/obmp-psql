/*
 * Copyright (c) 2018 Tim Evens (tim@evensweb.com).  All rights reserved.
 *
 * This program and the accompanying materials are made available under the
 * terms of the Eclipse Public License v1.0 which accompanies this distribution,
 * and is available at http://www.eclipse.org/legal/epl-v10.html
 *
 */
package org.openbmp.psqlquery;

import java.util.ArrayList;
import java.util.List;
import java.util.Map;

import org.openbmp.api.parsed.message.MsgBusFields;
import org.openbmp.api.parsed.message.PeerPojo;

public class PeerQuery extends Query{
    private final List<PeerPojo> records;

    public PeerQuery(List<PeerPojo> records){
		
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
        String [] stmt = { " INSERT INTO bgp_peers (hash_id,router_hash_id,peer_rd,isIPv4,peer_addr,name,peer_bgp_id," +
                           "peer_as,state,isL3VPNpeer,timestamp,isPrePolicy,local_ip,local_bgp_id,local_port," +
                           "local_hold_time,local_asn,remote_port,remote_hold_time,sent_capabilities," +
                           "recv_capabilities,bmp_reason,bgp_err_code,bgp_err_subcode,error_text," +
                           "isLocRib,isLocRibFiltered,table_name) " +
                            " VALUES ",

                           " ON CONFLICT (hash_id) DO UPDATE SET name=excluded.name,state=excluded.state," +
                                   "timestamp=excluded.timestamp,local_port=excluded.local_port," +
                                   "local_hold_time=excluded.local_hold_time,remote_port=excluded.remote_port," +
                                   "remote_hold_time=excluded.remote_hold_time,sent_capabilities=excluded.sent_capabilities," +
                                   "recv_capabilities=excluded.recv_capabilities,bmp_reason=excluded.bmp_reason," +
                                   "bgp_err_code=excluded.bgp_err_code,bgp_err_subcode=excluded.bgp_err_subcode," +
                                   "error_text=excluded.error_text,table_name=excluded.table_name" };
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
        for (PeerPojo pojo : records) {
            if (i > 0)
                sb.append(',');

            i++;

            sb.append('(');

            sb.append('\''); sb.append(pojo.getHash()); sb.append("'::uuid,");
            sb.append('\''); sb.append(pojo.getRouter_hash()); sb.append("'::uuid,");
            sb.append('\''); sb.append(pojo.getPeer_rd()); sb.append("',");
            sb.append(pojo.getIPv4()); sb.append("::boolean,");
            sb.append('\''); sb.append(pojo.getPeer_ip()); sb.append("'::inet,");
            sb.append('\''); sb.append(pojo.getName()); sb.append("',");
            sb.append('\''); sb.append(pojo.getPeer_bgp_id()); sb.append("'::inet,");
            sb.append(pojo.getPeer_asn()); sb.append(',');

            sb.append(pojo.getAction().equalsIgnoreCase("up") ? "'up'" : "'down'"); sb.append(',');

            sb.append(pojo.getL3VPN()); sb.append("::boolean,");
            sb.append('\''); sb.append(pojo.getTimestamp()); sb.append("'::timestamp,");
            sb.append(pojo.getPrePolicy()); sb.append("::boolean,");

            if (pojo.getLocal_ip().length() > 2) {
                sb.append('\'');
                sb.append(pojo.getLocal_ip());
                sb.append("'::inet,");
            } else {
                sb.append("null,");
            }

            if (pojo.getLocal_bgp_id().length() > 2) {
                sb.append('\'');
                sb.append(pojo.getLocal_bgp_id());
                sb.append("'::inet,");
            } else {
                sb.append("null,");
            }

            sb.append(pojo.getLocal_port()); sb.append(',');
            sb.append(pojo.getLocal_holddown()); sb.append(',');
            sb.append(pojo.getLocal_asn()); sb.append(',');
            sb.append(pojo.getPeer_port()); sb.append(',');
            sb.append(pojo.getPeer_holddown()); sb.append(',');
            sb.append('\''); sb.append(pojo.getAdvertised_cap()); sb.append("',");
            sb.append('\''); sb.append(pojo.getReceived_cap()); sb.append("',");
            sb.append(pojo.getBmp_down_reason()); sb.append(',');
            sb.append(pojo.getBgp_error_code()); sb.append(',');
            sb.append(pojo.getBgp_error_subcode()); sb.append(',');
            sb.append('\''); sb.append(pojo.getBgp_error_text()); sb.append("',");
            sb.append(pojo.getLocRib()); sb.append("::boolean,");
            sb.append(pojo.getLocalRibFiltered()); sb.append("::boolean,");
            sb.append('\''); sb.append(pojo.getTable_name()); sb.append('\'');

            sb.append(')');
        }

        return sb.toString();
    }


    /**
     * Generate SQL RIB update statement to withdraw all rib entries
     *
     * Upon peer up or down, withdraw all RIB entries.  When the PEER is up all
     *   RIB entries will get updated.  Depending on how long the peer was down, some
     *   entries may not be present anymore, thus they are withdrawn.
     *
     * @return  List of query strings to execute
     */
    public List<String> genRibPeerUpdate() {
        List<String> result = new ArrayList<>();

        for (PeerPojo pojo : records) {
            StringBuilder sb = new StringBuilder();

            //sb.append("UPDATE ip_rib SET isWithdrawn = true WHERE peer_hash_id = '");
            sb.append("DELETE FROM ip_rib WHERE peer_hash_id = '");
            sb.append(pojo.getHash());
            sb.append("' AND timestamp < '");
            sb.append(pojo.getTimestamp()); sb.append('\'');

//            sb.append("; UPDATE ls_nodes SET isWithdrawn = True WHERE peer_hash_id = '");
//            sb.append(lookupValue(MsgBusFields.HASH, i));
//            sb.append("' AND timestamp < '");
//            sb.append(rowMap.get(i).get(MsgBusFields.TIMESTAMP.getName()) + "'");

//            sb.append("; UPDATE ls_links SET isWithdrawn = True WHERE peer_hash_id = '");
//            sb.append(lookupValue(MsgBusFields.HASH, i));
//            sb.append("' AND timestamp < '");
//            sb.append(rowMap.get(i).get(MsgBusFields.TIMESTAMP.getName()) + "'");
//
//            sb.append("; UPDATE ls_prefixes SET isWithdrawn = True WHERE peer_hash_id = '");
//            sb.append(lookupValue(MsgBusFields.HASH, i));
//            sb.append("' AND timestamp < '");
//            sb.append(rowMap.get(i).get(MsgBusFields.TIMESTAMP.getName()) + "'");

            result.add(sb.toString());
        }

        return result;
    }

}

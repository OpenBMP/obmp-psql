/*
 * Copyright (c) 2018-2022 Cisco Systems, Inc. and others.  All rights reserved.
 */

package org.openbmp.psqlquery;

import java.util.HashMap;
import java.util.List;
import java.util.Map;

import org.openbmp.api.parsed.message.LsNodePojo;


public class LsNodeQuery extends Query {
    private final List<LsNodePojo> records;

    public LsNodeQuery(List<LsNodePojo> records){

        this.records = records;
    }

    public String[] genInsertStatement() {
        String [] stmt = { " INSERT INTO ls_nodes (hash_id,peer_hash_id,base_attr_hash_id,seq," +
                "asn,bgp_ls_id,igp_router_id,ospf_area_id,protocol,router_id,isis_area_id," +
                "flags,name,mt_ids,sr_capabilities," +
                "isWithdrawn,timestamp) " +

                " VALUES ",
//                "SELECT DISTINCT ON (hash_id,peer_hash_id) * FROM ( VALUES ",
//
//                ") t(hash_id,peer_hash_id,base_attr_hash_id,seq," +
//                        "asn,bgp_ls_id,igp_router_id,ospf_area_id,protocol,router_id,isis_area_id" +
//                        "flags,name,mt_ids,sr_capabilities," +
//                        "isWithdrawn,timestamp) " +
//                    " ORDER BY hash_id,peer_hash_id,timestamp desc" +
                        " ON CONFLICT (hash_id,peer_hash_id) DO UPDATE SET timestamp=excluded.timestamp,seq=excluded.seq," +
                        "base_attr_hash_id=CASE excluded.isWithdrawn WHEN true THEN ls_nodes.base_attr_hash_id ELSE excluded.base_attr_hash_id END," +
                        "isWithdrawn=excluded.isWithdrawn," +
                        "sr_capabilities=CASE excluded.isWithdrawn WHEN true THEN ls_nodes.sr_capabilities ELSE excluded.sr_capabilities END"
        };
        return stmt;
    }

    public Map<String, String> genValuesStatement() {
        Map<String, String> values = new HashMap<>();

        for (LsNodePojo pojo: records) {
            StringBuilder sb = new StringBuilder();

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

            sb.append(pojo.getSequence()); sb.append(',');
            sb.append(pojo.getPeer_asn()); sb.append(',');

            sb.append(pojo.getLs_id()); sb.append(',');
            sb.append('\''); sb.append(pojo.getIgp_router_id()); sb.append("',");
            sb.append('\''); sb.append(pojo.getOspf_area_id()); sb.append("',");
            sb.append('\''); sb.append(pojo.getProtocol()); sb.append("'::ls_proto,");
            sb.append('\''); sb.append(pojo.getRouter_id()); sb.append("',");
            sb.append('\''); sb.append(pojo.getIsis_area_id()); sb.append("',");
            sb.append('\''); sb.append(pojo.getFlags()); sb.append("',");
            sb.append('\''); sb.append(pojo.getName()); sb.append("',");
            sb.append('\''); sb.append(pojo.getMt_ids()); sb.append("',");
            sb.append('\''); sb.append(pojo.getSr_capabilities()); sb.append("',");

            sb.append(pojo.getWithdrawn()); sb.append(',');
            sb.append('\''); sb.append(pojo.getTimestamp()); sb.append("'::timestamp");
            sb.append(')');

            values.put(pojo.getHash(), sb.toString());
        }

        return values;
    }

}

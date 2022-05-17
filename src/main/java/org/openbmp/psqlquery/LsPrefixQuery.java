/*
 * Copyright (c) 2018-2022 Cisco Systems, Inc. and others.  All rights reserved.
 */

package org.openbmp.psqlquery;

import org.openbmp.api.helpers.IpAddr;
import org.openbmp.api.parsed.message.LsPrefixPojo;

import java.util.HashMap;
import java.util.List;
import java.util.Map;


public class LsPrefixQuery extends Query {
    private final List<LsPrefixPojo> records;

    public LsPrefixQuery(List<LsPrefixPojo> records){

        this.records = records;
    }


    public String[] genInsertStatement() {
        String [] stmt = { " INSERT INTO ls_prefixes " +
                                "(hash_id,peer_hash_id,base_attr_hash_id,seq,local_node_hash_id," +
                                "mt_id,protocol,prefix,prefix_len,ospf_route_type," +
                                "igp_flags,isIPv4,route_tag,ext_route_tag,metric,ospf_fwd_addr,sr_prefix_sids," +
                                "isWithdrawn,timestamp)" +

                    " VALUES ",
//                    " SELECT DISTINCT ON (hash_id,peer_hash_id) * FROM ( VALUES ",
//
//                    ") t(hash_id,peer_hash_id,base_attr_hash_id,seq,local_node_hash_id," +
//                         "mt_id,protocol,prefix,prefix_len,ospf_route_type," +
//                         "igp_flags,isIPv4,route_tag,ext_route_tag,metric,ospf_fwd_addr,sr_prefix_sids" +
//                         "isWithdrawn,timestamp)" +
//                    " ORDER BY hash_id,peer_hash_id,timestamp desc" +
                        " ON CONFLICT (hash_id,peer_hash_id) DO UPDATE SET timestamp=excluded.timestamp,seq=excluded.seq," +
                            "base_attr_hash_id=CASE excluded.isWithdrawn WHEN true THEN ls_prefixes.base_attr_hash_id ELSE excluded.base_attr_hash_id END," +
                            "igp_flags=CASE excluded.isWithdrawn WHEN true THEN ls_prefixes.igp_flags ELSE excluded.igp_flags END," +
                            "route_tag=CASE excluded.isWithdrawn WHEN true THEN ls_prefixes.route_tag ELSE excluded.route_tag END," +
                            "ext_route_tag=CASE excluded.isWithdrawn WHEN true THEN ls_prefixes.ext_route_tag ELSE excluded.ext_route_tag END," +
                            "metric=CA" +
                            "SE excluded.isWithdrawn WHEN true THEN ls_prefixes.metric ELSE excluded.metric END," +
                            "sr_prefix_sids=CASE excluded.isWithdrawn WHEN true THEN ls_prefixes.sr_prefix_sids ELSE excluded.sr_prefix_sids END," +

                            "isWithdrawn=excluded.isWithdrawn"
        };
        return stmt;
    }

    public Map<String, String> genValuesStatement() {
        Map<String, String> values = new HashMap<>();

        for (LsPrefixPojo pojo: records) {
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
            sb.append('\''); sb.append(pojo.getLocal_node_hash()); sb.append("'::uuid,");
            sb.append(pojo.getMt_id()); sb.append(',');
            sb.append('\''); sb.append(pojo.getProtocol()); sb.append("'::ls_proto,");

            sb.append('\''); sb.append(pojo.getPrefix()); sb.append('/');
            sb.append(pojo.getPrefix_len()); sb.append("'::inet,");

            sb.append(pojo.getPrefix_len()); sb.append(',');
            sb.append('\''); sb.append(pojo.getOspf_route_type()); sb.append("'::ospf_route_type,");
            sb.append('\''); sb.append(pojo.getIgp_flags()); sb.append("',");
            sb.append(IpAddr.isIPv4(pojo.getPrefix())); sb.append("::boolean,");
            sb.append(pojo.getRoute_tag()); sb.append(',');
            sb.append(pojo.getExt_route_tag()); sb.append(',');
            sb.append(pojo.getIgp_metric()); sb.append(',');

            sb.append('\''); sb.append(pojo.getOspf_fwd_address()); sb.append("'::inet,");
            sb.append('\''); sb.append(pojo.getPrefix_sid_tlv()); sb.append("',");


            sb.append(pojo.getWithdrawn()); sb.append(',');
            sb.append('\''); sb.append(pojo.getTimestamp()); sb.append("'::timestamp");
            sb.append(')');

            values.put(pojo.getHash(), sb.toString());
        }

        return values;
    }

}

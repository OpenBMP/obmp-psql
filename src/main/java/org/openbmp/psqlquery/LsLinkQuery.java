/*
 * Copyright (c) 2018-2022 Cisco Systems, Inc. and others.  All rights reserved.
 */

package org.openbmp.psqlquery;

import org.openbmp.api.helpers.IpAddr;
import org.openbmp.api.parsed.message.LsLinkPojo;

import java.util.HashMap;
import java.util.List;
import java.util.Map;


public class LsLinkQuery extends Query {
    private final List<LsLinkPojo> records;

    public LsLinkQuery(List<LsLinkPojo> records){

        this.records = records;
    }


    public String[] genInsertStatement() {
        String [] stmt = { " INSERT INTO ls_links " +
                    "(hash_id,peer_hash_id,base_attr_hash_id,seq," +
                    "mt_id,interface_addr," +
                    "neighbor_addr,isIPv4,protocol,local_link_id,remote_link_id,local_node_hash_id,remote_node_hash_id," +
                    "admin_group,max_link_bw,max_resv_bw,unreserved_bw,te_def_metric,protection_type,mpls_proto_mask," +
                    "igp_metric,srlg,name,local_igp_router_id,local_router_id,remote_igp_router_id,remote_router_id,local_asn," +
                    "remote_asn,peer_node_sid,sr_adjacency_sids,iswithdrawn,timestamp)" +

                " VALUES ",
//                " SELECT DISTINCT ON (hash_id,peer_hash_id) * FROM ( VALUES ",

//                ") t(hash_id,peer_hash_id,base_attr_hash_id,seq," +
//                        "mt_id,interface_addr," +
//                        "neighbor_addr,isIPv4,protocol,local_link_id,remote_link_id,local_node_hash_id,remote_node_hash_id," +
//                        "admin_group,max_link_bw,max_resv_bw,unreserved_bw,te_def_metric,protection_type,mpls_proto_mask," +
//                        "igp_metric,srlg,name,local_igp_router_id,local_router_id,remote_igp_router_id,remote_router_id,local_asn," +
//                        "remote_asn,peer_node_sid,sr_adjacency_sids,iswithdrawn,timestamp)" +
//                    " ORDER BY hash_id,peer_hash_id,timestamp desc " +
                        " ON CONFLICT (hash_id,peer_hash_id) DO UPDATE SET timestamp=excluded.timestamp,isWithdrawn=excluded.isWithdrawn,seq=excluded.seq," +
                            "base_attr_hash_id=CASE excluded.isWithdrawn WHEN true THEN ls_links.base_attr_hash_id ELSE excluded.base_attr_hash_id END," +
                            "interface_addr=CASE excluded.isWithdrawn WHEN true THEN ls_links.interface_addr ELSE excluded.interface_addr END," +
                            "neighbor_addr=CASE excluded.isWithdrawn WHEN true THEN ls_links.neighbor_addr ELSE excluded.neighbor_addr END," +
                            "local_link_id=CASE excluded.isWithdrawn WHEN true THEN ls_links.local_link_id ELSE excluded.local_link_id END," +
                            "remote_link_id=CASE excluded.isWithdrawn WHEN true THEN ls_links.remote_link_id ELSE excluded.remote_link_id END," +
                            "admin_group=CASE excluded.isWithdrawn WHEN true THEN ls_links.admin_group ELSE excluded.admin_group END," +
                            "max_link_bw=CASE excluded.isWithdrawn WHEN true THEN ls_links.max_link_bw ELSE excluded.max_link_bw END," +
                            "max_resv_bw=CASE excluded.isWithdrawn WHEN true THEN ls_links.max_resv_bw ELSE excluded.max_resv_bw END," +
                            "unreserved_bw=CASE excluded.isWithdrawn WHEN true THEN ls_links.unreserved_bw ELSE excluded.unreserved_bw END," +
                            "te_def_metric=CASE excluded.isWithdrawn WHEN true THEN ls_links.te_def_metric ELSE excluded.te_def_metric END," +
                            "protection_type=CASE excluded.isWithdrawn WHEN true THEN ls_links.protection_type ELSE excluded.protection_type END," +
                            "mpls_proto_mask=CASE excluded.isWithdrawn WHEN true THEN ls_links.mpls_proto_mask ELSE excluded.mpls_proto_mask END," +
                            "igp_metric=CASE excluded.isWithdrawn WHEN true THEN ls_links.igp_metric ELSE excluded.igp_metric END," +
                            "srlg=CASE excluded.isWithdrawn WHEN true THEN ls_links.srlg ELSE excluded.srlg END," +
                            "name=CASE excluded.isWithdrawn WHEN true THEN ls_links.name ELSE excluded.name END," +
                            "peer_node_sid=CASE excluded.isWithdrawn WHEN true THEN ls_links.peer_node_sid ELSE excluded.peer_node_sid END," +
                            "sr_adjacency_sids=CASE excluded.isWithdrawn WHEN true THEN ls_links.sr_adjacency_sids ELSE excluded.sr_adjacency_sids END"
        };
        return stmt;
    }

    public Map<String, String> genValuesStatement() {
        Map<String, String> values = new HashMap<>();

        for (LsLinkPojo pojo: records) {
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
            sb.append(pojo.getMt_id()); sb.append(',');

            if (pojo.getInterface_ip() == null) {
                sb.append("null::inet,");
            } else {
                sb.append('\''); sb.append(pojo.getInterface_ip()); sb.append("'::inet,");
            }

            if (pojo.getNeighbor_ip() == null) {
                sb.append("null::inet,");
            } else {
                sb.append('\''); sb.append(pojo.getNeighbor_ip()); sb.append("'::inet,");
            }

            sb.append(IpAddr.isIPv4(pojo.getInterface_ip())); sb.append("::boolean,");
            sb.append('\''); sb.append(pojo.getProtocol()); sb.append("'::ls_proto,");
            sb.append(pojo.getLocal_link_id()); sb.append(',');
            sb.append(pojo.getRemote_link_id()); sb.append(',');
            sb.append('\''); sb.append(pojo.getLocal_node_hash()); sb.append("'::uuid,");
            sb.append('\''); sb.append(pojo.getRemote_node_hash()); sb.append("'::uuid,");
            sb.append(pojo.getAdmin_group()); sb.append("::bigint"); sb.append(',');
            sb.append(pojo.getMax_link_bw()); sb.append(',');
            sb.append(pojo.getMax_resv_bw()); sb.append(',');
            sb.append('\''); sb.append(pojo.getUnreserved_bw()); sb.append("',");
            sb.append(pojo.getTe_default_metric()); sb.append(',');
            sb.append('\''); sb.append(pojo.getLink_protection()); sb.append("',");
            sb.append('\''); sb.append(pojo.getMpls_proto_mask()); sb.append("'::ls_mpls_proto_mask,");
            sb.append(pojo.getIgp_metric()); sb.append(',');
            sb.append('\''); sb.append(pojo.getSrlg()); sb.append("',");
            sb.append('\''); sb.append(pojo.getLink_name()); sb.append("',");
            sb.append('\''); sb.append(pojo.getIgp_router_id()); sb.append("',");
            sb.append('\''); sb.append(pojo.getRouter_id()); sb.append("',");
            sb.append('\''); sb.append(pojo.getRemote_igp_router_id()); sb.append("',");
            sb.append('\''); sb.append(pojo.getRemote_router_id()); sb.append("',");
            sb.append(pojo.getLocal_node_asn()); sb.append(',');
            sb.append(pojo.getRemote_node_asn()); sb.append(',');
            sb.append('\''); sb.append(pojo.getEpe_peer_node_sid()); sb.append("',");
            sb.append('\''); sb.append(pojo.getAdjacency_segment_id()); sb.append("',");

            sb.append(pojo.getWithdrawn()); sb.append(',');
            sb.append('\''); sb.append(pojo.getTimestamp()); sb.append("'::timestamp");
            sb.append(')');

            values.put(pojo.getHash(), sb.toString());
        }

        return values;
    }

}

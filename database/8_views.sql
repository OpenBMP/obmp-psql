-- -----------------------------------------------------------------------
-- Copyright (c) 2018 Cisco Systems, Inc. and others.  All rights reserved.
-- Copyright (c) 2018 Tim Evens (tim@evensweb.com).  All rights reserved.
--
-- BEGIN Views Schema
-- -----------------------------------------------------------------------


drop view IF EXISTS v_peers CASCADE;
CREATE VIEW v_peers AS
SELECT CASE WHEN length(rtr.name) > 0 THEN rtr.name ELSE  host(rtr.ip_address) END AS RouterName, rtr.ip_address as RouterIP,
                p.local_ip as LocalIP, p.local_port as LocalPort, p.local_asn as LocalASN, p.local_bgp_id as LocalBGPId,
                CASE WHEN length(p.name) > 0 THEN p.name ELSE host(p.peer_addr) END AS PeerName,
                p.peer_addr as PeerIP, p.remote_port as PeerPort, p.peer_as as PeerASN,
                p.peer_bgp_id as PeerBGPId,
                p.local_hold_time as LocalHoldTime, p.remote_hold_time as PeerHoldTime,
                p.state as peer_state, rtr.state as router_state,
                p.isIPv4 as isPeerIPv4, p.isL3VPNpeer as isPeerVPN, p.isPrePolicy as isPrePolicy,
                p.timestamp as LastModified,
                p.bmp_reason as LastBMPReasonCode, p.bgp_err_code as LastDownCode,
                p.bgp_err_subcode as LastdownSubCode, p.error_text as LastDownMessage,
                p.timestamp as LastDownTimestamp,
                p.sent_capabilities as SentCapabilities, p.recv_capabilities as RecvCapabilities,
                w.as_name,
                p.isLocRib,p.isLocRibFiltered,p.table_name,
                p.hash_id as peer_hash_id, rtr.hash_id as router_hash_id,p.geo_ip_start

        FROM bgp_peers p JOIN routers rtr ON (p.router_hash_id = rtr.hash_id)
                                         LEFT JOIN info_asn w ON (p.peer_as = w.asn);

drop view IF EXISTS v_ip_routes CASCADE;
CREATE  VIEW v_ip_routes AS
       SELECT  CASE WHEN length(rtr.name) > 0 THEN rtr.name ELSE host(rtr.ip_address) END AS RouterName,
                CASE WHEN length(p.name) > 0 THEN p.name ELSE host(p.peer_addr) END AS PeerName,
                r.prefix AS Prefix,r.prefix_len AS PrefixLen,
                attr.origin AS Origin,r.origin_as AS Origin_AS,attr.med AS MED,
                attr.local_pref AS LocalPref,attr.next_hop AS NH,attr.as_path AS AS_Path,
                attr.as_path_count AS ASPath_Count,attr.community_list AS Communities,
                attr.ext_community_list AS ExtCommunities,attr.large_community_list AS LargeCommunities,
                attr.cluster_list AS ClusterList,
                attr.aggregator AS Aggregator,p.peer_addr AS PeerAddress, p.peer_as AS PeerASN,r.isIPv4 as isIPv4,
                p.isIPv4 as isPeerIPv4, p.isL3VPNpeer as isPeerVPN,
                r.timestamp AS LastModified, r.first_added_timestamp as FirstAddedTimestamp,
                r.path_id, r.labels,
                r.hash_id as rib_hash_id,
                r.base_attr_hash_id as base_hash_id, r.peer_hash_id, rtr.hash_id as router_hash_id,r.isWithdrawn,
                r.prefix_bits,r.isPrePolicy,r.isAdjRibIn
        FROM ip_rib r
            JOIN bgp_peers p ON (r.peer_hash_id = p.hash_id)
            JOIN base_attrs attr ON (attr.hash_id = r.base_attr_hash_id and attr.peer_hash_id = r.peer_hash_id)
            JOIN routers rtr ON (p.router_hash_id = rtr.hash_id);

drop view IF EXISTS v_ip_routes_geo CASCADE;
CREATE  VIEW v_ip_routes_geo AS
       SELECT  CASE WHEN length(rtr.name) > 0 THEN rtr.name ELSE host(rtr.ip_address) END AS RouterName,
                CASE WHEN length(p.name) > 0 THEN p.name ELSE host(p.peer_addr) END AS PeerName,
                r.prefix AS Prefix,r.prefix_len AS PrefixLen,
                attr.origin AS Origin,r.origin_as AS Origin_AS,attr.med AS MED,
                attr.local_pref AS LocalPref,attr.next_hop AS NH,attr.as_path AS AS_Path,
                attr.as_path_count AS ASPath_Count,attr.community_list AS Communities,
                attr.ext_community_list AS ExtCommunities,attr.large_community_list AS LargeCommunities,
                attr.cluster_list AS ClusterList,
                attr.aggregator AS Aggregator,p.peer_addr AS PeerAddress, p.peer_as AS PeerASN,r.isIPv4 as isIPv4,
                p.isIPv4 as isPeerIPv4, p.isL3VPNpeer as isPeerVPN,
                r.timestamp AS LastModified, r.first_added_timestamp as FirstAddedTimestamp,
                r.path_id, r.labels,
                r.hash_id as rib_hash_id,
                r.base_attr_hash_id as base_hash_id, r.peer_hash_id, rtr.hash_id as router_hash_id,r.isWithdrawn,
                r.prefix_bits,r.isPrePolicy,r.isAdjRibIn,
                g.ip as geo_ip,g.city as City, g.stateprov as stateprov, g.country as country,
                g.latitude as latitude, g.longitude as longitude
        FROM ip_rib r
            JOIN bgp_peers p ON (r.peer_hash_id = p.hash_id)
            JOIN base_attrs attr ON (attr.hash_id = r.base_attr_hash_id and attr.peer_hash_id = r.peer_hash_id)
            JOIN routers rtr ON (p.router_hash_id = rtr.hash_id)
            LEFT JOIN geo_ip g ON (g.ip && host(r.prefix)::inet)
        WHERE  r.isWithdrawn = false;


drop view IF EXISTS v_ip_routes_history CASCADE;
CREATE VIEW v_ip_routes_history AS
  SELECT
             CASE WHEN length(rtr.name) > 0 THEN rtr.name ELSE host(rtr.ip_address) END AS RouterName,
            rtr.ip_address as RouterAddress,
	        CASE WHEN length(p.name) > 0 THEN p.name ELSE host(p.peer_addr) END AS PeerName,
            log.prefix AS Prefix,log.prefix_len AS PrefixLen,
            attr.origin AS Origin,log.origin_as AS Origin_AS,
            attr.med AS MED,attr.local_pref AS LocalPref,attr.next_hop AS NH,
            attr.as_path AS AS_Path,attr.as_path_count AS ASPath_Count,attr.community_list AS Communities,
            attr.ext_community_list AS ExtCommunities,attr.large_community_list AS LargeCommunities,
            attr.cluster_list AS ClusterList,attr.aggregator AS Aggregator,p.peer_addr AS PeerIp,
            p.peer_as AS PeerASN,  p.isIPv4 as isPeerIPv4, p.isL3VPNpeer as isPeerVPN,
            log.id,log.timestamp AS LastModified,
            CASE WHEN log.iswithdrawn THEN 'Withdrawn' ELSE 'Advertised' END as event,
            log.base_attr_hash_id as base_attr_hash_id, log.peer_hash_id, rtr.hash_id as router_hash_id
        FROM ip_rib_log log
            JOIN base_attrs attr
                        ON (log.base_attr_hash_id = attr.hash_id AND
                            log.peer_hash_id = attr.peer_hash_id)
            JOIN bgp_peers p ON (log.peer_hash_id = p.hash_id)
            JOIN routers rtr ON (p.router_hash_id = rtr.hash_id);

---
--- Link State Views
---
drop view IF EXISTS v_ls_nodes CASCADE;
CREATE VIEW v_ls_nodes AS
SELECT r.name as RouterName,r.ip_address as RouterIP,
		p.name as PeerName, p.peer_addr as PeerIP,igp_router_id as IGP_RouterId,
		ls_nodes.name as NodeName,
		CASE WHEN ls_nodes.iswithdrawn THEN 'WITHDRAWN' ELSE 'ACTIVE' END as state,
        CASE WHEN ls_nodes.protocol in ('OSPFv2', 'OSPFv3') THEN router_id ELSE igp_router_id END as RouterId,
        ls_nodes.seq, ls_nodes.bgp_ls_id as bgpls_id, ls_nodes.ospf_area_id as OspfAreaId,
        ls_nodes.isis_area_id as ISISAreaId, ls_nodes.protocol, flags, ls_nodes.timestamp,
        ls_nodes.asn,base_attrs.as_path as AS_Path,base_attrs.local_pref as LocalPref,
        base_attrs.med as MED,base_attrs.next_hop as NH,ls_nodes.mt_ids as mt_ids,
        ls_nodes.hash_id,ls_nodes.base_attr_hash_id,ls_nodes.peer_hash_id,r.hash_id as router_hash_id
	FROM ls_nodes LEFT JOIN base_attrs ON (ls_nodes.base_attr_hash_id = base_attrs.hash_id AND ls_nodes.peer_hash_id = base_attrs.peer_hash_id)
		JOIN bgp_peers p on (p.hash_id = ls_nodes.peer_hash_id) JOIN
                             routers r on (p.router_hash_id = r.hash_id)
    WHERE not ls_nodes.igp_router_id ~ '\..[1-9A-F]00$' AND ls_nodes.igp_router_id not like '%]';


drop view IF EXISTS v_ls_links CASCADE;
CREATE VIEW v_ls_links AS
SELECT localn.name as Local_Router_Name,remoten.name as Remote_Router_Name,
        localn.igp_router_id as Local_IGP_RouterId,localn.router_id as Local_RouterId,
        remoten.igp_router_id Remote_IGP_RouterId, remoten.router_id as Remote_RouterId,
        localn.seq, localn.bgp_ls_id as bgpls_id,
        CASE WHEN ln.protocol in ('OSPFv2', 'OSPFv3') THEN localn.ospf_area_id ELSE localn.isis_area_id END as AreaId,
        ln.mt_id as MT_ID,interface_addr as InterfaceIP,neighbor_addr as NeighborIP,
        ln.isIPv4,ln.protocol,igp_metric,local_link_id,remote_link_id,admin_group,max_link_bw,max_resv_bw,
        unreserved_bw,te_def_metric,mpls_proto_mask,srlg,ln.name,ln.timestamp,local_node_hash_id,remote_node_hash_id,
        localn.igp_router_id as localn_igp_router_id,remoten.igp_router_id as remoten_igp_router_id,
        ln.base_attr_hash_id as base_attr_hash_id, ln.peer_hash_id as peer_hash_id,
		CASE WHEN ln.iswithdrawn THEN 'WITHDRAWN' ELSE 'ACTIVE' END as state
	FROM ls_links ln
	    JOIN ls_nodes localn ON (ln.local_node_hash_id = localn.hash_id
			AND ln.peer_hash_id = localn.peer_hash_id)
		JOIN ls_nodes remoten ON (ln.remote_node_hash_id = remoten.hash_id
			AND ln.peer_hash_id = remoten.peer_hash_id);


drop view IF EXISTS v_ls_prefixes CASCADE;
CREATE VIEW v_ls_prefixes AS
SELECT localn.name as Local_Router_Name,localn.igp_router_id as Local_IGP_RouterId,
         localn.router_id as Local_RouterId,
         lp.seq,lp.mt_id,prefix as Prefix, prefix_len,ospf_route_type,metric,lp.protocol,
         lp.timestamp,lp.peer_hash_id,lp.local_node_hash_id,
         CASE WHEN lp.iswithdrawn THEN 'WITHDRAWN' ELSE 'ACTIVE' END as state
    FROM ls_prefixes lp JOIN ls_nodes localn ON (localn.peer_hash_id = lp.peer_hash_id
                                                 AND lp.local_node_hash_id = localn.hash_id);


--
-- END
--

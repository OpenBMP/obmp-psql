-- -----------------------------------------------------------------------
-- Copyright (c) 2018 Cisco Systems, Inc. and others.  All rights reserved.
-- Copyright (c) 2018 Tim Evens (tim@evensweb.com).  All rights reserved.
--
-- BEGIN Triggers
-- -----------------------------------------------------------------------

-- -----------------------------------------------------------------------------------------------
-- Triggers and trigger functions for various tables
-- -----------------------------------------------------------------------------------------------

-- =========== Routers =====================
CREATE OR REPLACE FUNCTION t_routers_insert()
	RETURNS trigger AS $$
BEGIN
	SELECT find_geo_ip(new.ip_address) INTO new.geo_ip_start;

	RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION t_routers_update()
	RETURNS trigger AS $$
BEGIN
	SELECT find_geo_ip(new.ip_address) INTO new.geo_ip_start;

	RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS ins_routers ON routers;
CREATE TRIGGER ins_routers BEFORE INSERT ON routers
	FOR EACH ROW
		EXECUTE PROCEDURE t_routers_insert();


DROP TRIGGER IF EXISTS upd_routers ON routers;
CREATE TRIGGER upd_routers BEFORE UPDATE ON routers
	FOR EACH ROW
		EXECUTE PROCEDURE t_routers_update();

-- =========== BGP Peers =====================
CREATE OR REPLACE FUNCTION t_bgp_peers()
	RETURNS trigger AS $$
BEGIN
	IF (new.peer_addr = '0.0.0.0' AND new.peer_bgp_id = '0.0.0.0') THEN
		SELECT r.name,r.ip_address INTO new.name,new.peer_bgp_id
			FROM routers r WHERE r.hash_id = new.router_hash_id;
	END IF;

	SELECT find_geo_ip(new.peer_addr) INTO new.geo_ip_start;

	IF (new.state = 'up') THEN
		INSERT INTO peer_event_log (state,peer_hash_id,local_ip,local_bgp_id,local_port,local_hold_time,
                                    local_asn,remote_port,remote_hold_time,
                                    sent_capabilities,recv_capabilities,geo_ip_start,timestamp)
                VALUES (new.state,new.hash_id,new.local_ip,new.local_bgp_id,new.local_port,new.local_hold_time,
                        new.local_asn,new.remote_port,new.remote_hold_time,
                        new.sent_capabilities,new.recv_capabilities,new.geo_ip_start, new.timestamp);
	ELSE
		-- Updated using old values since those are not in the down state
		INSERT INTO peer_event_log (state,peer_hash_id,local_ip,local_bgp_id,local_port,local_hold_time,
                                    local_asn,remote_port,remote_hold_time,
                                    sent_capabilities,recv_capabilities,bmp_reason,bgp_err_code,
                                    bgp_err_subcode,error_text,timestamp)
                VALUES (new.state,new.hash_id,new.local_ip,new.local_bgp_id,new.local_port,new.local_hold_time,
                        new.local_asn,new.remote_port,new.remote_hold_time,
                        new.sent_capabilities,new.recv_capabilities,new.bmp_reason,new.bgp_err_code,
                        new.bgp_err_subcode,new.error_text,new.timestamp);

	END IF;

	RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS ins_bgp_peers ON bgp_peers;
CREATE TRIGGER ins_bgp_peers BEFORE INSERT ON bgp_peers
	FOR EACH ROW
		EXECUTE PROCEDURE t_bgp_peers();

DROP TRIGGER IF EXISTS upd_bgp_peers ON bgp_peers;
CREATE TRIGGER upd_bgp_peers BEFORE UPDATE ON bgp_peers
	FOR EACH ROW
		EXECUTE PROCEDURE t_bgp_peers();


-- =========== IP RIB =====================
-- CREATE OR REPLACE FUNCTION t_ip_rib_update()
-- 	RETURNS trigger AS $$
-- BEGIN
-- 	-- Only update
-- 	-- Add record to log table if there is a change
-- 	IF ((new.isWithdrawn <> old.isWithdrawn) OR (not new.isWithdrawn AND new.base_attr_hash_id <> old.base_attr_hash_id)) THEN
-- 		IF (new.isWithdrawn) THEN
-- 			INSERT INTO ip_rib_log (isWithdrawn,prefix,prefix_len,base_attr_hash_id,peer_hash_id,origin_as,timestamp)
-- 				VALUES (true,new.prefix,new.prefix_len,old.base_attr_hash_id,new.peer_hash_id,old.origin_as,new.timestamp);
-- 		ELSE
-- 			-- Update first added to DB when prefix has been withdrawn for too long
--             IF (old.isWithdrawn AND old.timestamp < (new.timestamp - interval '6 hours')) THEN
--                 SELECT current_timestamp(6) INTO new.first_added_timestamp;
--             END IF;
--
-- 			INSERT INTO ip_rib_log (isWithdrawn,prefix,prefix_len,base_attr_hash_id,peer_hash_id,origin_as,timestamp)
-- 				VALUES (false,new.prefix,new.prefix_len,new.base_attr_hash_id,new.peer_hash_id,new.origin_as,new.timestamp);
-- 		END IF;
-- 	END IF;
--
-- 	RETURN NEW;
-- END;
-- $$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION t_ip_rib_update()
	RETURNS trigger AS $$
BEGIN
	IF (new.isWithdrawn) THEN
		INSERT INTO ip_rib_log (isWithdrawn,prefix,prefix_len,base_attr_hash_id,peer_hash_id,origin_as,timestamp)
		VALUES (true,new.prefix,new.prefix_len,old.base_attr_hash_id,new.peer_hash_id,
		        old.origin_as,new.timestamp);
	ELSE
		INSERT INTO ip_rib_log (isWithdrawn,prefix,prefix_len,base_attr_hash_id,peer_hash_id,origin_as,timestamp)
		VALUES (false,new.prefix,new.prefix_len,new.base_attr_hash_id,new.peer_hash_id,
		        new.origin_as,new.timestamp);
	END IF;

	RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- CREATE OR REPLACE FUNCTION t_ip_rib_update()
-- 	RETURNS trigger AS $$
-- BEGIN
--
-- 	RETURN NEW;
-- END;
-- $$ LANGUAGE plpgsql;


-- ** not used **
-- CREATE OR REPLACE FUNCTION t_ip_rib_insert()
-- 	RETURNS trigger AS $$
-- BEGIN
--
-- 	-- not withdrawn, add record to global table
-- 	IF (not new.isWithdrawn) THEN
-- 		-- Update gen global ip rib  table
-- 		INSERT INTO global_ip_rib (prefix,prefix_len,recv_origin_as,rpki_origin_as,irr_origin_as,irr_source,prefix_bits,isIPv4)
--
-- 	      SELECT new.prefix,new.prefix_len,new.origin_as,
-- 	             rpki.origin_as, w.origin_as,w.source,new.prefix_bits,new.isIPv4
--
-- 	      FROM (SELECT new.prefix as prefix, new.prefix_len as prefix_len, new.origin_as as origin_as, new.prefix_bits,
-- 	              new.isIPv4) rib
-- 	        LEFT JOIN info_route w ON (new.prefix = w.prefix AND
-- 	                                        new.prefix_len = w.prefix_len)
-- 	        LEFT JOIN rpki_validator rpki ON (new.prefix = rpki.prefix AND
-- 	                                          new.prefix_len >= rpki.prefix_len and new.prefix_len <= rpki.prefix_len_max)
-- 	      LIMIT 1
--
-- 	    ON CONFLICT (prefix,prefix_len,recv_origin_as) DO UPDATE SET rpki_origin_as = excluded.rpki_origin_as,
-- 	                  irr_origin_as = excluded.irr_origin_as, irr_source=excluded.irr_source;
-- 	END IF;
--
-- 	RETURN NEW;
-- END;
-- $$ LANGUAGE plpgsql;

-- trigger applied on partitions
-- DROP TRIGGER IF EXISTS ins_ip_rib ON ip_rib;
-- CREATE TRIGGER ins_ip_rib AFTER INSERT ON ip_rib
-- 	FOR EACH ROW
-- 		EXECUTE PROCEDURE t_ip_rib_insert();

DROP TRIGGER IF EXISTS upd_ip_rib ON ip_rib;
CREATE TRIGGER upd_ip_rib AFTER UPDATE ON ip_rib
	FOR EACH ROW
	WHEN ((new.isWithdrawn <> old.isWithdrawn) OR
	      (not new.isWithdrawn AND new.base_attr_hash_id <> old.base_attr_hash_id))
	EXECUTE PROCEDURE t_ip_rib_update();


-- =========== LS_NODES =====================
CREATE OR REPLACE FUNCTION t_ls_nodes_update()
	RETURNS trigger AS $$
BEGIN
	-- Only update
	-- Add record to log table if there is a change
	IF ((new.isWithdrawn <> old.isWithdrawn) OR (not new.isWithdrawn AND new.base_attr_hash_id <> old.base_attr_hash_id)) THEN
		IF (new.isWithdrawn) THEN
			INSERT INTO ls_nodes_log (hash_id, peer_hash_id, base_attr_hash_id, seq, asn, bgp_ls_id, igp_router_id,
			        ospf_area_id, protocol, router_id, isis_area_id, flags, name, mt_ids, sr_capabilities,
			        iswithdrawn)
				VALUES (new.hash_id, new.peer_hash_id, old.base_attr_hash_id, new.seq, old.asn, old.bgp_ls_id, old.igp_router_id,
					old.ospf_area_id, old.protocol, old.router_id, old.isis_area_id, old.flags, old.name, old.mt_ids, old.sr_capabilities,
					true);
		ELSE
			INSERT INTO ls_nodes_log (hash_id, peer_hash_id, base_attr_hash_id, seq, asn, bgp_ls_id, igp_router_id,
			        ospf_area_id, protocol, router_id, isis_area_id, flags, name, mt_ids, sr_capabilities,
			        iswithdrawn)
				VALUES (new.hash_id, new.peer_hash_id, new.base_attr_hash_id, new.seq, old.asn, new.bgp_ls_id, new.igp_router_id,
					new.ospf_area_id, new.protocol, new.router_id, new.isis_area_id, new.flags, new.name, new.mt_ids, new.sr_capabilities,
					false);
		END IF;
	END IF;

	RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS upd_ls_nodes ON ls_nodes;
CREATE TRIGGER upd_ls_nodes BEFORE UPDATE ON ls_nodes
	FOR EACH ROW
		EXECUTE PROCEDURE t_ls_nodes_update();

-- =========== LS_LINKS =====================
CREATE OR REPLACE FUNCTION t_ls_links_update()
	RETURNS trigger AS $$
BEGIN
	-- Only update
	-- Add record to log table if there is a change
	IF ((new.isWithdrawn <> old.isWithdrawn) OR (not new.isWithdrawn AND new.base_attr_hash_id <> old.base_attr_hash_id)) THEN
		IF (new.isWithdrawn) THEN
			INSERT INTO ls_links_log (hash_id, peer_hash_id, base_attr_hash_id, seq, mt_id, interface_addr, neighbor_addr,
					isipv4, protocol, local_link_id, remote_link_id, local_node_hash_id, remote_node_hash_id, admin_group,
					max_link_bw, max_resv_bw, unreserved_bw, te_def_metric, protection_type,
					mpls_proto_mask, igp_metric, srlg, name, local_igp_router_id, local_router_id,
					remote_igp_router_id, remote_router_id, local_asn, remote_asn,
					peer_node_sid, sr_adjacency_sids,
					iswithdrawn)
				VALUES (new.hash_id, new.peer_hash_id, old.base_attr_hash_id, new.seq, old.mt_id, old.interface_addr, old.neighbor_addr,
					old.isipv4, old.protocol, old.local_link_id, old.remote_link_id, old.local_node_hash_id, old.remote_node_hash_id, old.admin_group,
					old.max_link_bw, old.max_resv_bw, old.unreserved_bw, old.te_def_metric, old.protection_type,
					old.mpls_proto_mask, old.igp_metric, old.srlg, old.name, old.local_igp_router_id, old.local_router_id,
					old.remote_igp_router_id, old.remote_router_id, old.local_asn, old.remote_asn,
					old.peer_node_sid, old.sr_adjacency_sids,
					true);
		ELSE
				INSERT INTO ls_links_log (hash_id, peer_hash_id, base_attr_hash_id, seq, mt_id, interface_addr, neighbor_addr,
					isipv4, protocol, local_link_id, remote_link_id, local_node_hash_id, remote_node_hash_id, admin_group,
					max_link_bw, max_resv_bw, unreserved_bw, te_def_metric, protection_type,
					mpls_proto_mask, igp_metric, srlg, name, local_igp_router_id, local_router_id,
					remote_igp_router_id, remote_router_id, local_asn, remote_asn,
					peer_node_sid, sr_adjacency_sids,
					iswithdrawn)
				VALUES (new.hash_id, new.peer_hash_id, new.base_attr_hash_id, new.seq, new.mt_id, new.interface_addr, new.neighbor_addr,
					new.isipv4, new.protocol, new.local_link_id, new.remote_link_id, new.local_node_hash_id, new.remote_node_hash_id, new.admin_group,
					new.max_link_bw, new.max_resv_bw, new.unreserved_bw, new.te_def_metric, new.protection_type,
					new.mpls_proto_mask, new.igp_metric, new.srlg, new.name, new.local_igp_router_id, new.local_router_id,
					new.remote_igp_router_id, new.remote_router_id, new.local_asn, new.remote_asn,
					new.peer_node_sid, new.sr_adjacency_sids,
					false);
		END IF;
	END IF;

	RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS upd_ls_links ON ls_links;
CREATE TRIGGER upd_ls_links BEFORE UPDATE ON ls_links
	FOR EACH ROW
		EXECUTE PROCEDURE t_ls_links_update();

-- =========== LS_PREFIXES =====================
CREATE OR REPLACE FUNCTION t_ls_prefixes_update()
	RETURNS trigger AS $$
BEGIN
	-- Only update
	-- Add record to log table if there is a change
	IF ((new.isWithdrawn <> old.isWithdrawn) OR (not new.isWithdrawn AND new.base_attr_hash_id <> old.base_attr_hash_id)) THEN
		IF (new.isWithdrawn) THEN
			INSERT INTO ls_prefixes_log (hash_id, peer_hash_id, base_attr_hash_id, seq,
					local_node_hash_id, mt_id, protocol, prefix, prefix_len, ospf_route_type,
					igp_flags, isipv4, route_tag, ext_route_tag, metric, ospf_fwd_addr,
					sr_prefix_sids, iswithdrawn)
				VALUES (new.hash_id, new.peer_hash_id, old.base_attr_hash_id, new.seq,
					old.local_node_hash_id, old.mt_id, old.protocol, old.prefix, old.prefix_len, old.ospf_route_type,
					old.igp_flags, old.isipv4, old.route_tag, old.ext_route_tag, old.metric, old.ospf_fwd_addr,
					old.sr_prefix_sids, true);
		ELSE
			INSERT INTO ls_prefixes_log (hash_id, peer_hash_id, base_attr_hash_id, seq,
					local_node_hash_id, mt_id, protocol, prefix, prefix_len, ospf_route_type,
					igp_flags, isipv4, route_tag, ext_route_tag, metric, ospf_fwd_addr,
					sr_prefix_sids, iswithdrawn)
				VALUES (new.hash_id, new.peer_hash_id, new.base_attr_hash_id, new.seq,
					new.local_node_hash_id, new.mt_id, new.protocol, new.prefix, new.prefix_len, new.ospf_route_type,
					new.igp_flags, new.isipv4, new.route_tag, new.ext_route_tag, new.metric, new.ospf_fwd_addr,
					new.sr_prefix_sids, false);

		END IF;
	END IF;

	RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS upd_ls_prefixes ON ls_prefixes;
CREATE TRIGGER upd_ls_prefixes BEFORE UPDATE ON ls_prefixes
	FOR EACH ROW
		EXECUTE PROCEDURE t_ls_prefixes_update();


---
--- L3VPN
---
CREATE OR REPLACE FUNCTION t_l3vpn_rib_update()
	RETURNS trigger AS $$
BEGIN
	IF (new.isWithdrawn) THEN
		INSERT INTO l3vpn_rib_log (isWithdrawn,prefix,prefix_len,base_attr_hash_id,peer_hash_id,origin_as,timestamp,
		                           rd,ext_community_list)
		VALUES (true,new.prefix,new.prefix_len,old.base_attr_hash_id,new.peer_hash_id,
		        old.origin_as,new.timestamp,old.rd,old.ext_community_list);
	ELSE
		INSERT INTO l3vpn_rib_log (isWithdrawn,prefix,prefix_len,base_attr_hash_id,peer_hash_id,origin_as,timestamp,
		                           rd,ext_community_list)
		VALUES (false,new.prefix,new.prefix_len,new.base_attr_hash_id,new.peer_hash_id,
		        new.origin_as,new.timestamp,new.rd,new.ext_community_list);
	END IF;

	RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS upd_l3vpn_rib ON l3vpn_rib;
CREATE TRIGGER upd_l3vpn_rib AFTER UPDATE ON l3vpn_rib
	FOR EACH ROW
	WHEN ((new.isWithdrawn <> old.isWithdrawn) OR
	      (not new.isWithdrawn AND new.base_attr_hash_id <> old.base_attr_hash_id))
EXECUTE PROCEDURE t_l3vpn_rib_update();
--
-- END
--

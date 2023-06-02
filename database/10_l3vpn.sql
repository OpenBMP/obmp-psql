-- -----------------------------------------------------------------------
-- Copyright (c) 2022 Cisco Systems, Inc. and others.  All rights reserved.
-- Copyright (c) 2022 Tim Evens (tim@evensweb.com).  All rights reserved.
-- -----------------------------------------------------------------------

--
-- Table structure for l3vpn rib
--    https://blog.dbi-services.com/hash-partitioning-in-postgresql-11/--
DROP TABLE IF EXISTS l3vpn_rib
CREATE TABLE l3vpn_rib (
	                       hash_id                 UUID,
	                       base_attr_hash_id       Nullable(UUID),
	                       peer_hash_id            UUID,
	                       isIPv4                  Bool,
	                       rd                      String,
	                       origin_as               Nullable(UInt32),
	                       prefix                  String,
	                       prefix_len              UInt16,
	                       timestamp               DateTime('UTC') CODEC(DoubleDelta, NONE),
	                       first_added_timestamp   DateTime('UTC') CODEC(DoubleDelta, NONE),
	                       isWithdrawn             Bool DEFAULT false,
	                       path_id                 UInt64,
	                       labels                  Nullable(String),
	                       ext_community_list      Nullable(String),
	                       isPrePolicy             Bool DEFAULT true,
	                       isAdjRibIn              Bool DEFAULT true,
	                       PRIMARY KEY (peer_hash_id, hash_id)
)
ENGINE = MergeTree
ORDER BY timestamp

-- Table structure for table ip_rib_log
DROP TABLE IF EXISTS l3vpn_rib_log
CREATE TABLE l3vpn_rib_log (
	                           id                      Float64 DEFAULT (toFloat64(toDateTime64(now64(), 3)) + toFloat64(timestamp)) - 3200000000 CODEC(Gorilla, Default),
	                           base_attr_hash_id       Nullable(UUID),
	                           timestamp               DateTime('UTC') CODEC(DoubleDelta, NONE),
	                           rd                      String,
	                           peer_hash_id            UUID,
	                           prefix                  String,
	                           prefix_len              UInt16,
	                           origin_as               UInt64,
	                           ext_community_list      Nullable(String),
	                           isPrePolicy             Bool DEFAULT true,
	                           isAdjRibIn              Bool DEFAULT true,
	                           isWithdrawn             Bool
)
ENGINE = MergeTree
PARTITION BY toStartOfDay(timestamp)
ORDER BY timestamp
TTL timestamp + toIntervalDay(60)


--
-- L3VPN Views
--
DROP VIEW IF EXISTS v_l3vpn_routes
CREATE  VIEW v_l3vpn_routes AS
SELECT  if(length(rtr.name) > 0, rtr.name, rtr.ip_address) AS RouterName,
        if(length(p.name) > 0, p.name, p.peer_addr) AS PeerName,
        r.rd, r.prefix AS Prefix, r.prefix_len AS PrefixLen,
        attr.origin AS Origin, r.origin_as AS Origin_AS, attr.med AS MED,
        attr.local_pref AS LocalPref, attr.next_hop AS NH, attr.as_path AS AS_Path,
        attr.as_path_count AS ASPath_Count, attr.community_list AS Communities,
        r.ext_community_list AS ExtCommunities, attr.large_community_list AS LargeCommunities,
        attr.cluster_list AS ClusterList, attr.aggregator AS Aggregator, 
		p.peer_addr AS PeerAddress, p.peer_as AS PeerASN, r.isIPv4 as isIPv4,
        p.isIPv4 as isPeerIPv4, p.isL3VPNpeer as isPeerVPN, r.timestamp AS LastModified,
		r.first_added_timestamp as FirstAddedTimestamp, r.path_id, r.labels,
        r.hash_id as rib_hash_id, r.base_attr_hash_id as base_hash_id, r.peer_hash_id,
		rtr.hash_id as router_hash_id,r.isWithdrawn, r.isPrePolicy,r.isAdjRibIn
FROM l3vpn_rib r
	     JOIN bgp_peers p ON (r.peer_hash_id = p.hash_id)
	     JOIN base_attrs attr ON (attr.hash_id = r.base_attr_hash_id and attr.peer_hash_id = r.peer_hash_id)
	     JOIN routers rtr ON (p.router_hash_id = rtr.hash_id)

DROP VIEW IF EXISTS v_l3vpn_routes_history
CREATE  VIEW v_l3vpn_routes_history AS
SELECT  r.id, if(length(rtr.name) > 0, rtr.name, rtr.ip_address) AS RouterName,
        if(length(p.name) > 0, p.name, p.peer_addr) AS PeerName,
        r.rd, r.prefix AS Prefix, r.prefix_len AS PrefixLen,
        attr.origin AS Origin, r.origin_as AS Origin_AS, attr.med AS MED,
        attr.local_pref AS LocalPref, attr.next_hop AS NH, attr.as_path AS AS_Path,
        attr.as_path_count AS ASPath_Count, attr.community_list AS Communities,
        r.ext_community_list AS ExtCommunities, attr.large_community_list AS LargeCommunities,
        attr.cluster_list AS ClusterList, attr.aggregator AS Aggregator, 
		p.peer_addr AS PeerAddress, p.peer_as AS PeerASN, p.isIPv4 as isPeerIPv4,
		p.isL3VPNpeer as isPeerVPN, r.timestamp AS LastModified,
		r.base_attr_hash_id as base_hash_id, r.peer_hash_id, rtr.hash_id as router_hash_id,
        if(r.iswithdrawn, 'Withdrawn', 'Advertised') as event, r.isPrePolicy, r.isAdjRibIn
FROM l3vpn_rib_log r
	     JOIN bgp_peers p ON (r.peer_hash_id = p.hash_id)
	     JOIN base_attrs attr ON (attr.hash_id = r.base_attr_hash_id and attr.peer_hash_id = r.peer_hash_id)
	     JOIN routers rtr ON (p.router_hash_id = rtr.hash_id);

---
--- L3VPN Triggers
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
-- L3VPN stat tables
--
DROP TABLE IF EXISTS stats_l3vpn_chg_bypeer
CREATE TABLE stats_l3vpn_chg_bypeer (
        interval_time           DateTime CODEC(DoubleDelta, NONE),
        peer_hash_id            UUID,
        updates                 UInt64 DEFAULT 0,
        withdraws               UInt64 DEFAULT 0
)
ENGINE = MergeTree
PARTITION BY toStartOfDay(interval_time)
ORDER BY interval_time
TTL interval_time + toIntervalDay(30)

-- advertisement and withdrawal changes by prefix
DROP TABLE IF EXISTS stats_l3vpn_chg_byprefix
CREATE TABLE stats_l3vpn_chg_byprefix (
          interval_time           DateTime CODEC(DoubleDelta, NONE),
          peer_hash_id            UUID,
          prefix                  String,
          prefix_len              UInt16,
          rd                      String,
          updates                 UInt64 DEFAULT 0,
          withdraws               UInt64 DEFAULT 0
)
ENGINE = MergeTree
PARTITION BY toStartOfDay(interval_time)
ORDER BY interval_time
TTL interval_time + toIntervalDay(30)

-- advertisement and withdrawal changes by rd
DROP TABLE IF EXISTS stats_l3vpn_chg_byrd
CREATE TABLE stats_l3vpn_chg_byrd (
	      interval_time           DateTime CODEC(DoubleDelta, NONE),
	      peer_hash_id            UUID,
	      rd                      String,
	      updates                 UInt64 DEFAULT 0,
	      withdraws               UInt64 DEFAULT 0
)
ENGINE = MergeTree
PARTITION BY toStartOfDay(interval_time)
ORDER BY interval_time
TTL interval_time + toIntervalDay(30)

--
-- Function to update the l3vpn change stats tables (bypeer, byasn, and byprefix).
--
CREATE OR REPLACE FUNCTION update_l3vpn_chg_stats(int_window interval)
	RETURNS void AS $$
BEGIN
	-- bypeer updates
	INSERT INTO stats_l3vpn_chg_bypeer (interval_time, peer_hash_id, withdraws,updates)
	SELECT
		time_bucket(int_window, now() - int_window) as IntervalTime,
		peer_hash_id,
		count(case WHEN l3vpn_rib_log.iswithdrawn = true THEN 1 ELSE null END) as withdraws,
		count(case WHEN l3vpn_rib_log.iswithdrawn = false THEN 1 ELSE null END) as updates
	FROM l3vpn_rib_log
	WHERE timestamp >= time_bucket(int_window, now() - int_window)
	  AND timestamp < time_bucket(int_window, now())
	GROUP BY IntervalTime,peer_hash_id
	ON CONFLICT (interval_time,peer_hash_id) DO UPDATE
		SET updates=excluded.updates, withdraws=excluded.withdraws;

	-- byrd updates
	INSERT INTO stats_l3vpn_chg_byrd (interval_time, peer_hash_id, rd,withdraws,updates)
	SELECT
		time_bucket(int_window, now() - int_window) as IntervalTime,
		peer_hash_id,rd,
		count(case WHEN l3vpn_rib_log.iswithdrawn = true THEN 1 ELSE null END) as withdraws,
		count(case WHEN l3vpn_rib_log.iswithdrawn = false THEN 1 ELSE null END) as updates
	FROM l3vpn_rib_log
	WHERE timestamp >= time_bucket(int_window, now() - int_window)
	  AND timestamp < time_bucket(int_window, now())
	GROUP BY IntervalTime,peer_hash_id,rd
	ON CONFLICT (interval_time,peer_hash_id,rd) DO UPDATE
		SET updates=excluded.updates, withdraws=excluded.withdraws;

	-- byprefix updates
	INSERT INTO stats_l3vpn_chg_byprefix (interval_time, peer_hash_id, prefix, prefix_len, rd, withdraws,updates)
	SELECT
		time_bucket(int_window, now() - int_window) as IntervalTime,
		peer_hash_id,prefix,prefix_len,rd,
		count(case WHEN l3vpn_rib_log.iswithdrawn = true THEN 1 ELSE null END) as withdraws,
		count(case WHEN l3vpn_rib_log.iswithdrawn = false THEN 1 ELSE null END) as updates
	FROM l3vpn_rib_log
	WHERE timestamp >= time_bucket(int_window, now() - int_window)
	  AND timestamp < time_bucket(int_window, now())
	GROUP BY IntervalTime,peer_hash_id,prefix,prefix_len,rd
	ON CONFLICT (interval_time,peer_hash_id,prefix,rd) DO UPDATE
		SET updates=excluded.updates, withdraws=excluded.withdraws;

END;
$$ LANGUAGE plpgsql;

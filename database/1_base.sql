-- -----------------------------------------------------------------------
-- Copyright (c) 2021 Cisco Systems, Inc. and Tim Evens.  All rights reserved.
--
-- BEGIN Base Schema
-- -----------------------------------------------------------------------

-- SET TIME ZONE 'UTC';

-- Enable https://www.postgresql.org/docs/10/pgtrgm.html type of indexes
CREATE EXTENSION IF NOT EXISTS pg_trgm;

-- btree_gist allows hash,prefix indexes, but this will cause normal gist
--    indexes to perform slower.
-- CREATE EXTENSION IF NOT EXISTS btree_gist;


-- -----------------------------------------------------
-- Tables and base, non dependant functions
-- -----------------------------------------------------

-- Table structure for table geo_ip
DROP TABLE IF EXISTS geo_ip
CREATE TABLE geo_ip (
  family                UInt16,
  ip                    String,
  country               String,
  stateprov             String,
  city                  String,
  latitude              Float32,
  longitude             Float32,
  timezone_offset       Float32,
  timezone_name         String,
  isp_name              String,
  connection_type       Nullable(String),
  organization_name     Nullable(String),
  PRIMARY KEY (ip)
)
ENGINE = MergeTree


INSERT INTO geo_ip VALUES
	(4, '0.0.0.0/0','US', 'WA', 'Seattle', 47.6129432, -122.4821472, 0, 'UTC', 'default', 'default', 'default'),
	(6, '::/0', 'US', 'WA', 'Seattle', 47.6129432, -122.4821472, 0, 'UTC', 'default', 'default', 'default');

CREATE OR REPLACE FUNCTION find_geo_ip(find_ip inet)
	RETURNS inet AS $$
	DECLARE
	        geo_ip_prefix inet := NULL;
	BEGIN

	    -- Use execute for better performance - http://blog.endpoint.com/2008/12/why-is-my-function-slow.html
	    EXECUTE 'SELECT ip
		    FROM geo_ip
	        WHERE ip && $1
	        ORDER BY ip desc
	        LIMIT 1' INTO geo_ip_prefix USING find_ip;

		RETURN geo_ip_prefix;
	END
$$ LANGUAGE plpgsql;

-- While the below LANGUAGE SQL works and is cleaner, it is slower than plpgsql
-- CREATE OR REPLACE FUNCTION find_geo_ip(find_ip inet)
-- 	RETURNS inet AS $$
-- 	    SELECT ip
-- 		    FROM geo_ip
-- 	        WHERE ip >>= find_ip
-- 	        ORDER BY ip desc
-- 	        LIMIT 1
-- 	$$ LANGUAGE SQL;


-- Table structure for table rpki_validator
DROP TABLE IF EXISTS rpki_validator
CREATE TABLE rpki_validator (
	prefix              String,
	prefix_len          UInt16 DEFAULT 0,
	prefix_len_max      UInt16 DEFAULT 0,
	origin_as           UInt64,
	timestamp           DateTime('UTC') CODEC(DoubleDelta, NONE),
	PRIMARY KEY (prefix, prefix_len_max, origin_as)
);
ENGINE = MergeTree
ORDER BY timestamp


-- Table structure for table users
--    note: change password to use crypt(), but change db_rest to support it
--
--    CREATE EXTENSION pgcrypto;
--             Create: crypt('new password', gen_salt('md5'));
--             Check:  select ...  WHERE password = crypt('user entered pw', password);
DROP TABLE IF EXISTS users
CREATE TABLE users (
	username            String,
	password            String,
	type                Enum8('admin' = 1, 'oper' = 2, '' = 3),
	PRIMARY KEY (username)
)
ENGINE = MergeTree
INSERT INTO users (username, password, type) VALUES ('openbmp', 'openbmp', 'admin');


-- Table structure for table collectors
DROP TABLE IF EXISTS collectors
CREATE TABLE collectors (
	hash_id             UUID,
	state               Enum8('up' = 1, 'down' = 2, '' = 3) DEFAULT 'down',
	admin_id            String,
	routers             Nullable(String),
	router_count        UInt16 DEFAULT 0,
	timestamp           DateTime('UTC') CODEC(DoubleDelta, NONE),
	name                Nullable(String),
	ip_address          Nullable(String),
	PRIMARY KEY (hash_id)
)
ENGINE = MergeTree
ORDER BY timestamp


-- Table structure for table routers
DROP TABLE IF EXISTS routers
CREATE TABLE routers (
	hash_id             UUID,
	name                String,
	ip_address          String,
	router_AS           Nullable(UInt64),
	timestamp           DateTime('UTC') CODEC(DoubleDelta, NONE),
	description         Nullable(String),
	state               Enum8('up' = 1, 'down' = 2, '' = 3) DEFAULT 'down',
	isPassive           Nullable(Bool) DEFAULT false,
	term_reason_code    Nullable(UInt32),
	term_reason_text    Nullable(String),
	term_data           Nullable(String),
	init_data           Nullable(String),
	geo_ip_start        Nullable(String),
	collector_hash_id   UUID,
	bgp_id              Nullable(String),
	PRIMARY KEY (hash_id)
)
ENGINE = MergeTree
ORDER BY timestamp


-- Table structure for table bgp_peers
DROP TABLE IF EXISTS bgp_peers CASCADE;
CREATE TABLE bgp_peers (
	hash_id                 UUID,
	router_hash_id          UUID,
	peer_rd                 String,
	isIPv4                  Bool DEFAULT true,
	peer_addr               String,
	name                    Nullable(String),
	peer_bgp_id             Nullable(String),
	peer_as                 UInt64
	state                   Enum8('up' = 1, 'down' = 2, '' = 3) DEFAULT 'down',
	isL3VPNpeer             Bool DEFAULT false,
	timestamp               DateTime('UTC') CODEC(DoubleDelta, NONE),
	isPrePolicy             Bool DEFAULT true,
	geo_ip_start            Nullable(String),
	local_ip                Nullable(String),
	local_bgp_id            Nullable(String),
	local_port              Nullable(UInt32),
	local_hold_time         Nullable(UInt16),
	local_asn               Nullable(UInt64),
	remote_port             Nullable(UInt32),
	remote_hold_time        Nullable(UInt16),
	sent_capabilities       Nullable(String),
	recv_capabilities       Nullable(String),
	bmp_reason              Nullable(UInt16),
	bgp_err_code            Nullable(UInt16),
	bgp_err_subcode         Nullable(UInt16),
	error_text              Nullable(String),
	isLocRib                Bool DEFAULT false,
	isLocRibFiltered        Bool DEFAULT false,
	table_name              Nullable(String),
	PRIMARY KEY (hash_id)
)
ENGINE = MergeTree
ORDER BY timestamp


-- Table structure for table peer_event_log
--     updated by bgp_peers trigger
DROP TABLE IF EXISTS peer_event_log
CREATE TABLE peer_event_log (
	id                  Float64 DEFAULT (toFloat64(toDateTime64(now64(), 3)) + toFloat64(timestamp)) - 3200000000 CODEC(Gorilla, Default),
	state               Enum8('up' = 1, 'down' = 2, '' = 3),
	peer_hash_id        UUID,
	local_ip            Nullable(String),
	local_bgp_id        Nullable(String),
	local_port          Nullable(UInt32),
	local_hold_time     Nullable(UInt32),
	geo_ip_start        Nullable(String),
	local_asn           Nullable(UInt64),
	remote_port         Nullable(UInt32),
	remote_hold_time    Nullable(UInt32),
	sent_capabilities   Nullable(String),
	recv_capabilities   Nullable(String),
	bmp_reason          Nullable(UInt16),
	bgp_err_code        Nullable(UInt16),
	bgp_err_subcode     Nullable(UInt16),
	error_text          Nullable(String),
	timestamp           DateTime('UTC') CODEC(DoubleDelta, NONE),
)
ENGINE = MergeTree
PARTITION BY toStartOfDay(timestamp)
ORDER BY timestamp
TTL timestamp + toIntervalDay(120)


-- Table structure for table stat_reports
--     TimescaleDB
DROP TABLE IF EXISTS stat_reports
CREATE TABLE stat_reports (
	id                                  Float64 DEFAULT (toFloat64(toDateTime64(now64(), 3)) + toFloat64(timestamp)) - 3200000000 CODEC(Gorilla, Default),
	peer_hash_id                        UUID,
	prefixes_rejected                   Nullable(UInt64),
	known_dup_prefixes                  Nullable(UInt64),
	known_dup_withdraws                 Nullable(UInt64),
    updates_invalid_by_cluster_list     Nullable(UInt64),
    updates_invalid_by_as_path_loop     Nullable(UInt64),
    updates_invalid_by_originagtor_id   Nullable(UInt64),
    updates_invalid_by_as_confed_loop   Nullable(UInt64),
    num_routes_adj_rib_in               Nullable(UInt64),
    num_routes_local_rib                Nullable(UInt64),
    timestamp timestamp(6)              DateTime('UTC') CODEC(DoubleDelta, NONE),
)
ENGINE = MergeTree
PARTITION BY toStartOfDay(timestamp)
ORDER BY timestamp
TTL timestamp + toIntervalDay(60)


-- Table structure for table base_attrs
--    https://blog.dbi-services.com/hash-partitioning-in-postgresql-11/
DROP TABLE IF EXISTS base_attrs
CREATE TABLE base_attrs (
	hash_id                 UUID,
	peer_hash_id            UUID,
	origin                  String,
	as_path                 UInt64,
	as_path_count           Nullable(UInt16) DEFAULT 0,
    origin_as               Nullable(UInt64),
    next_hop                Nullable(String),
    med                     Nullable(UInt64),
    local_pref              Nullable(UInt64),
    aggregator              Nullable(String),
    community_list          Nullable(String),
    ext_community_list      Nullable(String),
    large_community_list    Nullable(String),
    cluster_list            Nullable(String),
    isAtomicAgg             Nullable(Bool) DEFAULT false,
    nexthop_isIPv4          Nullable(Bool) DEFAULT true,
    timestamp               DateTime('UTC') CODEC(DoubleDelta, NONE),
    originator_id           Nullable(String),
    PRIMARY KEY (hash_id)
)
ENGINE = MergeTree
ORDER BY timestamp


-- Table structure for table rib
--    https://blog.dbi-services.com/hash-partitioning-in-postgresql-11/--
DROP TABLE IF EXISTS ip_rib
CREATE TABLE ip_rib (
	hash_id                 UUID,
    base_attr_hash_id       Nullable(UUID),
    peer_hash_id            UUID,
    isIPv4                  Bool,
    origin_as               Nullable(UInt64),
    prefix                  String,
    prefix_len              UInt16,
    timestamp               DateTime('UTC') CODEC(DoubleDelta, NONE),
    first_added_timestamp   DateTime('UTC') CODEC(DoubleDelta, NONE),
    isWithdrawn             Bool DEFAULT false,
    path_id                 Nullable(UInt64),
    labels                  Nullable(String),
    isPrePolicy             Bool DEFAULT true,
    isAdjRibIn              Bool DEFAULT true,
    PRIMARY KEY (peer_hash_id, hash_id)
)
ENGINE = MergeTree
ORDER BY timestamp


-- Table structure for table ip_rib_log
DROP TABLE IF EXISTS ip_rib_log
CREATE TABLE ip_rib_log (
    id                      Float64 DEFAULT (toFloat64(toDateTime64(now64(), 3)) + toFloat64(timestamp)) - 3200000000 CODEC(Gorilla, Default),
	base_attr_hash_id       UUID,
	timestamp               DateTime('UTC') CODEC(DoubleDelta, NONE),
    peer_hash_id            UUID,
    prefix                  String,
    prefix_len              UInt16,
    origin_as               UInt64,
    isWithdrawn             Bool
)
ENGINE = MergeTree
PARTITION BY toStartOfDay(timestamp)
ORDER BY timestamp
TTL timestamp + toIntervalDay(60)


-- Table structure for global ip rib
DROP TABLE IF EXISTS global_ip_rib
CREATE TABLE global_ip_rib (
    prefix                  String,
  	iswithdrawn             Bool DEFAULT false,
    prefix_len              UInt16 DEFAULT 0,
    recv_origin_as          UInt64,
    rpki_origin_as          Nullable(UInt64),
    irr_origin_as           Nullable(UInt64),
    irr_source              Nullable(String),
    irr_descr               Nullable(String),
    num_peers               Nullable(UInt64) DEFAULT 0,
    advertising_peers       Nullable(UInt64) DEFAULT 0,
    withdrawn_peers         Nullable(UInt64) DEFAULT 0,
    timestamp               DateTime('UTC') CODEC(DoubleDelta, NONE),
    first_added_timestamp   DateTime('UTC') CODEC(DoubleDelta, NONE),
    PRIMARY KEY (prefix, recv_origin_as)
)
ENGINE = MergeTree
ORDER BY timestamp


-- Table structure for table info_asn (based on whois)
DROP TABLE IF EXISTS info_asn
CREATE TABLE info_asn (
    asn                     UInt64,
    as_name                 Nullable(String),
    org_id                  Nullable(String),
    org_name                Nullable(String),
    remarks                 Nullable(String),
    address                 Nullable(String),
    city                    Nullable(String),
    state_prov              Nullable(String),
    postal_code             Nullable(String),
    country                 Nullable(String),
    raw_output              Nullable(String),
    timestamp               DateTime('UTC') CODEC(DoubleDelta, NONE),
    source                  Nullable(String),
    PRIMARY KEY (asn)
)
ENGINE = MergeTree
ORDER BY timestamp


-- Table structure for table info_route (based on whois)
DROP TABLE IF EXISTS info_route
CREATE TABLE info_route (
    prefix                  String,
    prefix_len              UInt16 DEFAULT 0,
    descr                   Nullable(String),
    origin_as               UInt64,
    source                  String,
    timestamp               DateTime('UTC') CODEC(DoubleDelta, NONE),
    PRIMARY KEY (prefix, prefix_len, origin_as)
)
ENGINE = MergeTree
ORDER BY timestamp


-- Table structure for table peering DB peerings by exchange
DROP TABLE IF EXISTS pdb_exchange_peers
CREATE TABLE pdb_exchange_peers (
    ix_id                   UInt32,
    ix_name                 String,
    ix_prefix_v4            Nullable(String),
    ix_prefix_v6            Nullable(String),
    ix_country              Nullable(String),
    ix_city                 Nullable(String),
    ix_region               Nullable(String),
    rs_peer                 Bool DEFAULT false,
    peer_name               String,
    peer_ipv4               String DEFAULT '0.0.0.0',
    peer_ipv6               String DEFAULT '::',
    peer_asn                UInt64,
    speed                   Nullable(UInt32),
	policy                  Nullable(String),
	poc_policy_email        Nullable(String),
	poc_noc_email           Nullable(String),
    timestamp               DateTime('UTC') CODEC(DoubleDelta, NONE),
    PRIMARY KEY (ix_id, peer_ipv4, peer_ipv6)
)
ENGINE = MergeTree
ORDER BY timestamp


-- Table structure for link state nodes
DROP TABLE IF EXISTS ls_nodes CASCADE;
CREATE TABLE ls_nodes (
    hash_id                 UUID,
    peer_hash_id            UUID,
    base_attr_hash_id       Nullable(UUID),
    seq                     UInt64 DEFAULT 0,
    asn                     UInt64,
    bgp_ls_id               UInt64 DEFAULT 0,
    igp_router_id           String,
    ospf_area_id            String,
    protocol                Enum8('IS-IS_L1' = 1, 'IS-IS_L2' = 2, 'OSPFv2' = 3, 'Direct' = 4, 'Static' = 5, 'OSPFv3' = 6, '' = 7) DEFAULT '',
    router_id               String,
    isis_area_id            Nullable(String),
    flags                   Nullable(String),
    name                    Nullable(String),
    mt_ids                  Nullable(String),
    sr_capabilities         Nullable(String),
    isWithdrawn             Bool DEFAULT false,
    timestamp               DateTime('UTC') CODEC(DoubleDelta, NONE),
    PRIMARY KEY (hash_id, peer_hash_id)
)
ENGINE = MergeTree
ORDER BY timestamp


-- Table structure for table ls_nodes_log
DROP TABLE IF EXISTS ls_nodes_log
CREATE TABLE ls_nodes_log (
    id                      Float64 DEFAULT (toFloat64(toDateTime64(now64(), 3)) + toFloat64(timestamp)) - 3200000000 CODEC(Gorilla, Default),
    hash_id                 UUID,
    peer_hash_id            UUID,
    base_attr_hash_id       Nullable(UUID),
    seq                     UInt64 DEFAULT 0,
    asn                     UInt64,
    bgp_ls_id               UInt64 DEFAULT 0,
    igp_router_id           String,
    ospf_area_id            String,
    protocol                Enum8('IS-IS_L1' = 1, 'IS-IS_L2' = 2, 'OSPFv2' = 3, 'Direct' = 4, 'Static' = 5, 'OSPFv3' = 6, '') DEFAULT '',
    router_id               String,
    isis_area_id            Nullable(String),
    flags                   Nullable(String),
    name                    Nullable(String),
    mt_ids                  Nullable(String),
    sr_capabilities         Nullable(String),
    isWithdrawn             Bool DEFAULT false,
    timestamp               DateTime('UTC') CODEC(DoubleDelta, NONE),
)
ENGINE = MergeTree
PARTITION BY toStartOfDay(timestamp)
ORDER BY timestamp
TTL timestamp + toIntervalDay(60)


-- Table structure for link state links
DROP TABLE IF EXISTS ls_links
CREATE TABLE ls_links (
	  hash_id                 UUID,
	  peer_hash_id            UUID,
	  base_attr_hash_id       Nullable(UUID),
	  seq                     UInt64 DEFAULT 0,
	  mt_id                   UInt32 DEFAULT 0,
	  interface_addr          Nullable(String),
	  neighbor_addr           Nullable(String),
	  isIPv4                  Bool DEFAULT true,
	  protocol                Enum8('IS-IS_L1' = 1, 'IS-IS_L2' = 2, 'OSPFv2' = 3, 'Direct' = 4, 'Static' = 5, 'OSPFv3' = 6, '') DEFAULT '',
	  local_link_id           Nullable(UInt64),
	  remote_link_id          Nullable(UInt64),
	  local_node_hash_id      UUID,
	  remote_node_hash_id     UUID,
	  admin_group             UInt64,
	  max_link_bw             Nullable(UInt64),
	  max_resv_bw             Nullable(UInt64),
	  unreserved_bw           Nullable(String),
	  te_def_metric           Nullable(UInt64),
	  protection_type         Nullable(String),
	  mpls_proto_mask         Enum8('LDP' = 1, 'RSVP-TE' = 2, '' = 3),
	  igp_metric              UInt64 DEFAULT 0,
	  srlg                    Nullable(String),
	  name                    Nullable(String),
	  local_igp_router_id     String,
	  local_router_id         String,
	  remote_igp_router_id    String,
	  remote_router_id        String,
	  local_asn               UInt64 DEFAULT 0,
	  remote_asn              UInt64 DEFAULT 0,
	  peer_node_sid           Nullable(String),
	  sr_adjacency_sids       Nullable(String),
	  isWithdrawn             Bool DEFAULT false,
	  timestamp               DateTime('UTC') CODEC(DoubleDelta, NONE),
	  PRIMARY KEY (hash_id,peer_hash_id)
)
ENGINE = MergeTree
ORDER BY timestamp


-- Table structure for table ls_links_log
DROP TABLE IF EXISTS ls_links_log
CREATE TABLE ls_links_log (
	  id                      Float64 DEFAULT (toFloat64(toDateTime64(now64(), 3)) + toFloat64(timestamp)) - 3200000000 CODEC(Gorilla, Default),
	  hash_id                 UUID,
	  peer_hash_id            UUID,
	  base_attr_hash_id       Nullable(UUID),
	  seq                     UInt64 DEFAULT 0,
	  mt_id                   UInt32 DEFAULT 0,
	  interface_addr          Nullable(String),
	  neighbor_addr           Nullable(String),
	  isIPv4                  Bool DEFAULT true,
	  protocol                Enum8('IS-IS_L1' = 1, 'IS-IS_L2' = 2, 'OSPFv2' = 3, 'Direct' = 4, 'Static' = 5, 'OSPFv3' = 6, '') DEFAULT '',
	  local_link_id           Nullable(UInt64),
	  remote_link_id          Nullable(UInt64),
	  local_node_hash_id      UUID,
	  remote_node_hash_id     UUID,
	  admin_group             UInt64,
	  max_link_bw             Nullable(UInt64),
	  max_resv_bw             Nullable(UInt64),
	  unreserved_bw           Nullable(String),
	  te_def_metric           Nullable(UInt64),
	  protection_type         Nullable(String),
	  mpls_proto_mask         Enum8('LDP' = 1, 'RSVP-TE' = 2, '' = 3),
	  igp_metric              UInt64 DEFAULT 0,
	  srlg                    Nullable(String),
	  name                    Nullable(String),
	  local_igp_router_id     String,
	  local_router_id         String,
	  remote_igp_router_id    String,
	  remote_router_id        String,
	  local_asn               UInt64 DEFAULT 0,
	  remote_asn              UInt64 DEFAULT 0,
	  peer_node_sid           Nullable(String),
	  sr_adjacency_sids       Nullable(String),
	  isWithdrawn             Bool DEFAULT false,
	  timestamp               DateTime('UTC') CODEC(DoubleDelta, NONE),
)
ENGINE = MergeTree
PARTITION BY toStartOfDay(timestamp)
ORDER BY timestamp
TTL timestamp + toIntervalDay(60)


-- Table structure for link state prefixes
DROP TABLE IF EXISTS ls_prefixes
CREATE TABLE ls_prefixes (
      hash_id                 UUID,
      peer_hash_id            UUID,
      base_attr_hash_id       Nullable(UUID),
      seq                     UInt64 DEFAULT 0,
      local_node_hash_id      UUID,
      mt_id                   UInt32 DEFAULT 0,
      protocol                Enum8('IS-IS_L1' = 1, 'IS-IS_L2' = 2, 'OSPFv2' = 3, 'Direct' = 4, 'Static' = 5, 'OSPFv3' = 6, '') DEFAULT '',
	  prefix                  String,
      prefix_len              UInt16,
	  ospf_route_type         Enum8('Intra' = 1, 'Inter' = 2, 'Ext-1' = 3, 'Ext-2' = 4, 'NSSA-1' = 5, 'NSSA-2' = 6, '' = 7) DEFAULT '',
	  igp_flags               Nullable(String),
      isIPv4                  Bool DEFAULT true,
	  route_tag               UInt64 DEFAULT 0,
	  ext_route_tag           UInt64 DEFAULT 0,
	  metric                  UInt64 DEFAULT 0,
	  ospf_fwd_addr           Nullable(String),
	  sr_prefix_sids          Nullable(String),
      isWithdrawn             Bool DEFAULT false,
      timestamp               DateTime('UTC') CODEC(DoubleDelta, NONE),
      PRIMARY KEY (hash_id,peer_hash_id)
)
ENGINE = MergeTree
ORDER BY timestamp


-- Table structure for table ls_nodes_log
DROP TABLE IF EXISTS ls_prefixes_log
CREATE TABLE ls_prefixes_log (
      id                      Float64 DEFAULT (toFloat64(toDateTime64(now64(), 3)) + toFloat64(timestamp)) - 3200000000 CODEC(Gorilla, Default),
      hash_id                 UUID,
      peer_hash_id            UUID,
      base_attr_hash_id       Nullable(UUID),
      seq                     UInt64 DEFAULT 0,
      local_node_hash_id      UUID,
      mt_id                   UInt32 DEFAULT 0,
      protocol                Enum8('IS-IS_L1' = 1, 'IS-IS_L2' = 2, 'OSPFv2' = 3, 'Direct' = 4, 'Static' = 5, 'OSPFv3' = 6, '') DEFAULT '',
	  prefix                  String,
      prefix_len              UInt16,
	  ospf_route_type         Enum8('Intra' = 1, 'Inter' = 2, 'Ext-1' = 3, 'Ext-2' = 4, 'NSSA-1' = 5, 'NSSA-2' = 6, '' = 7) DEFAULT '',
	  igp_flags               Nullable(String),
      isIPv4                  Bool DEFAULT true,
	  route_tag               UInt16 DEFAULT 0,
	  ext_route_tag           UInt16 DEFAULT 0,
	  metric                  UInt16 DEFAULT 0,
	  ospf_fwd_addr           Nullable(String),
	  sr_prefix_sids          Nullable(String),
      isWithdrawn             Bool DEFAULT false,
      timestamp               DateTime('UTC') CODEC(DoubleDelta, NONE),
)
ENGINE = MergeTree
PARTITION BY toStartOfDay(timestamp)
ORDER BY timestamp
TTL timestamp + toIntervalDay(60)


--
-- END
--

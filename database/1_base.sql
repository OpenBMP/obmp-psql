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


-- enable timescale DB
CREATE EXTENSION IF NOT EXISTS timescaledb CASCADE;

-- Use different disk for history/log/time series
-- CREATE TABLESPACE timeseries LOCATION '/var/lib/postgresql/ts';


-- -----------------------------------------------------
-- Enums used in tables
-- -----------------------------------------------------
-- DROP TYPE  IF EXISTS opState CASCADE;
CREATE TYPE opState as enum ('up', 'down', '');
CREATE TYPE user_role as enum ('admin', 'oper', '');
CREATE TYPE ls_proto as enum ('IS-IS_L1', 'IS-IS_L2', 'OSPFv2', 'Direct', 'Static', 'OSPFv3', '');
CREATE TYPE ospf_route_type as enum ('Intra','Inter','Ext-1','Ext-2','NSSA-1','NSSA-2','');
CREATE TYPE ls_mpls_proto_mask as enum('LDP', 'RSVP-TE', '');

-- -----------------------------------------------------
-- Tables and base, non dependant functions
-- -----------------------------------------------------

-- Table structure for table geo_ip
DROP TABLE IF EXISTS geo_ip CASCADE;
CREATE TABLE geo_ip (
  family                smallint        NOT NULL,
  ip                    inet            NOT NULL,
  country               char(2)         NOT NULL,
  stateprov             varchar(80)     NOT NULL,
  city                  varchar(80)     NOT NULL,
  latitude              float           NOT NULL,
  longitude             float           NOT NULL,
  timezone_offset       float           NOT NULL,
  timezone_name         varchar(64)     NOT NULL,
  isp_name              varchar(128)    NOT NULL,
  connection_type       varchar(64),
  organization_name     varchar(128),
  PRIMARY KEY (ip)
);
CREATE INDEX ON geo_ip (stateprov);
CREATE INDEX ON geo_ip (country);
CREATE INDEX ON geo_ip (family);
CREATE INDEX ON geo_ip USING GIST (ip inet_ops);
create index on geo_ip using HASH (ip);


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
DROP TABLE IF EXISTS rpki_validator CASCADE;
CREATE TABLE rpki_validator (
	prefix              inet            NOT NULL,
	prefix_len          smallint        NOT NULL DEFAULT 0,
	prefix_len_max      smallint        NOT NULL DEFAULT 0,
	origin_as           bigint          NOT NULL,
	timestamp           timestamp       without time zone default (now() at time zone 'utc') NOT NULL,
	PRIMARY KEY (prefix,prefix_len_max,origin_as)
);
CREATE INDEX ON rpki_validator (origin_as);
CREATE INDEX ON rpki_validator USING gist (prefix inet_ops);



-- Table structure for table users
--    note: change password to use crypt(), but change db_rest to support it
--
--    CREATE EXTENSION pgcrypto;
--             Create: crypt('new password', gen_salt('md5'));
--             Check:  select ...  WHERE password = crypt('user entered pw', password);
DROP TABLE IF EXISTS users CASCADE;
CREATE TABLE users (
	username            varchar(50)     NOT NULL,
	password            varchar(50)     NOT NULL,
	type                user_role       NOT NULL,
	PRIMARY KEY (username)
);
INSERT INTO users (username,password,type) VALUES ('openbmp', 'openbmp', 'admin');


-- Table structure for table collectors
DROP TABLE IF EXISTS collectors CASCADE;
CREATE TABLE collectors (
	hash_id             uuid                NOT NULL,
	state               opState             DEFAULT 'down',
	admin_id            varchar(64)         NOT NULL,
	routers             varchar(4096),
	router_count        smallint            NOT NULL DEFAULT 0,
	timestamp           timestamp(6)        without time zone default (now() at time zone 'utc') NOT NULL,
	name                varchar(200),
	ip_address          varchar(40),
	PRIMARY KEY (hash_id)
);


-- Table structure for table routers
DROP TABLE IF EXISTS routers CASCADE;
CREATE TABLE routers (
	hash_id             uuid                NOT NULL,
	name                varchar(200)        NOT NULL,
	ip_address          inet                NOT NULL,
	router_AS           bigint,
	timestamp           timestamp(6)        without time zone default (now() at time zone 'utc') NOT NULL,
	description         varchar(255),
	state               opState             DEFAULT 'down',
	isPassive           boolean             DEFAULT false,
	term_reason_code    int,
	term_reason_text    varchar(255),
	term_data           text,
	init_data           text,
	geo_ip_start        inet,
	collector_hash_id   uuid                NOT NULL,
	bgp_id              inet,
	PRIMARY KEY (hash_id)
);


CREATE INDEX ON routers (name);
CREATE INDEX ON routers (ip_address);


-- Table structure for table bgp_peers
DROP TABLE IF EXISTS bgp_peers CASCADE;
CREATE TABLE bgp_peers (
	hash_id                 uuid                NOT NULL,
	router_hash_id          uuid                NOT NULL,
	peer_rd                 varchar(32)         NOT NULL,
	isIPv4                  boolean             NOT NULL DEFAULT true,
	peer_addr               inet                NOT NULL,
	name                    varchar(200),
	peer_bgp_id             inet,
	peer_as                 bigint              NOT NULL,
	state                   opState             NOT NULL DEFAULT 'down',
	isL3VPNpeer             boolean             NOT NULL DEFAULT false,
	timestamp               timestamp(6)        without time zone default (now() at time zone 'utc') NOT NULL,
	isPrePolicy             boolean             DEFAULT true,
	geo_ip_start            inet,
	local_ip                inet,
	local_bgp_id            inet,
	local_port              int,
	local_hold_time         smallint,
	local_asn               bigint,
	remote_port             int,
	remote_hold_time        smallint,
	sent_capabilities       varchar(4096),
	recv_capabilities       varchar(4096),
	bmp_reason              smallint,
	bgp_err_code            smallint,
	bgp_err_subcode         smallint,
	error_text              varchar(255),
	isLocRib                boolean             NOT NULL DEFAULT false,
	isLocRibFiltered        boolean             NOT NULL DEFAULT false,
	table_name              varchar(255),
	PRIMARY KEY (hash_id)
);

CREATE INDEX ON bgp_peers (peer_addr);
CREATE INDEX ON bgp_peers (name);
CREATE INDEX ON bgp_peers (peer_as);
CREATE INDEX ON bgp_peers (router_hash_id);


-- Table structure for table peer_event_log
--     updated by bgp_peers trigger
DROP TABLE IF EXISTS peer_event_log CASCADE;
CREATE TABLE peer_event_log (
	id                  bigserial               NOT NULL,
	state               opState                 NOT NULL,
	peer_hash_id        uuid                    NOT NULL,
	local_ip            inet,
	local_bgp_id        inet,
	local_port          int,
	local_hold_time     int,
	geo_ip_start        inet,
	local_asn           bigint,
	remote_port         int,
	remote_hold_time    int,
	sent_capabilities   varchar(4096),
	recv_capabilities   varchar(4096),
	bmp_reason          smallint,
	bgp_err_code        smallint,
	bgp_err_subcode     smallint,
	error_text          varchar(255),
	timestamp           timestamp(6)            without time zone default (now() at time zone 'utc') NOT NULL
) TABLESPACE timeseries;
CREATE INDEX ON peer_event_log (peer_hash_id);
CREATE INDEX ON peer_event_log (local_ip);
CREATE INDEX ON peer_event_log (local_asn);

-- convert to timescaledb
SELECT create_hypertable('peer_event_log', 'timestamp');
SELECT add_retention_policy('peer_event_log', INTERVAL '4 months');


-- Table structure for table stat_reports
--     TimescaleDB
DROP TABLE IF EXISTS stat_reports CASCADE;
CREATE TABLE stat_reports (
	id                                  bigserial               NOT NULL,
	peer_hash_id                        uuid                    NOT NULL,
	prefixes_rejected                   bigint,
	known_dup_prefixes                  bigint,
	known_dup_withdraws                 bigint,
    updates_invalid_by_cluster_list     bigint,
    updates_invalid_by_as_path_loop     bigint,
    updates_invalid_by_originagtor_id   bigint,
    updates_invalid_by_as_confed_loop   bigint,
    num_routes_adj_rib_in               bigint,
    num_routes_local_rib                bigint,
    timestamp timestamp(6)              without time zone default (now() at time zone 'utc') NOT NULL
) TABLESPACE timeseries;
CREATE INDEX ON stat_reports (peer_hash_id);


-- convert to timescaledb
SELECT create_hypertable('stat_reports', 'timestamp', chunk_time_interval => interval '30 day');
SELECT add_retention_policy('stat_reports', INTERVAL '8 weeks');


-- Table structure for table base_attrs
--    https://blog.dbi-services.com/hash-partitioning-in-postgresql-11/
DROP TABLE IF EXISTS base_attrs CASCADE;
CREATE TABLE base_attrs (
	hash_id                 uuid                NOT NULL,
	peer_hash_id            uuid                NOT NULL,
	origin                  varchar(16)         NOT NULL,
	as_path                 bigint[]            NOT NULL,
	as_path_count           smallint            DEFAULT 0,
    origin_as               bigint,
    next_hop                inet,
    med                     bigint,
    local_pref              bigint,
    aggregator              varchar(64),
    community_list          varchar(15)[],
    ext_community_list      varchar(50)[],
    large_community_list    varchar(40)[],
    cluster_list            varchar(40)[],
    isAtomicAgg             boolean             DEFAULT false,
    nexthop_isIPv4          boolean             DEFAULT true,
    timestamp               timestamp(6)        without time zone default (now() at time zone 'utc') NOT NULL,
    originator_id           inet,
    PRIMARY KEY (hash_id)
);

--CREATE UNIQUE INDEX ON base_attrs USING BTREE  (timestamp,hash_id);
--CREATE INDEX ON base_attrs (origin_as);
--CREATE INDEX ON base_attrs (as_path_count);
CREATE INDEX ON base_attrs USING GIN  (as_path array_ops);
CREATE INDEX ON base_attrs USING GIN  (community_list array_ops);
CREATE INDEX ON base_attrs USING GIN  (ext_community_list array_ops);
CREATE INDEX ON base_attrs USING GIN  (large_community_list array_ops);
CREATE INDEX ON base_attrs (peer_hash_id);
CREATE INDEX ON base_attrs (next_hop);


ALTER TABLE base_attrs SET (autovacuum_analyze_threshold = 1000);
ALTER TABLE base_attrs SET (autovacuum_vacuum_threshold = 2000);
ALTER TABLE base_attrs SET (autovacuum_vacuum_cost_limit = 200);
ALTER TABLE base_attrs SET (autovacuum_vacuum_cost_delay = 10);




-- Table structure for table rib
--    https://blog.dbi-services.com/hash-partitioning-in-postgresql-11/--
DROP TABLE IF EXISTS ip_rib CASCADE;
CREATE TABLE ip_rib (
	hash_id                 uuid                NOT NULL,
    base_attr_hash_id       uuid,
    peer_hash_id            uuid                NOT NULL,
    isIPv4                  boolean             NOT NULL,
    origin_as               bigint,
    prefix                  inet                NOT NULL,
    prefix_len              smallint            NOT NULL,
    timestamp               timestamp(6)        without time zone default (now() at time zone 'utc') NOT NULL,
    first_added_timestamp   timestamp(6)        without time zone default (now() at time zone 'utc') NOT NULL,
    isWithdrawn             boolean             NOT NULL DEFAULT false,
    path_id                 bigint,
    labels                  varchar(255),
    isPrePolicy             boolean             NOT NULL DEFAULT true,
    isAdjRibIn              boolean             NOT NULL DEFAULT true,
    PRIMARY KEY (peer_hash_id, hash_id)
);

CREATE INDEX ON ip_rib (hash_id);
CREATE INDEX ON ip_rib (timestamp DESC);
CREATE INDEX ON ip_rib (first_added_timestamp DESC);
--CREATE INDEX ON ip_rib USING HASH (peer_hash_id);
-- Brin apparently requires a lot of memory and changes psql to prefer this index
-- CREATE INDEX ON ip_rib using brin (peer_hash_id,timestamp);
CREATE INDEX ON ip_rib (base_attr_hash_id);
CREATE INDEX ON ip_rib USING GIST (prefix inet_ops);
CREATE INDEX ON ip_rib (prefix);
CREATE INDEX ON ip_rib (origin_as);
CREATE INDEX ON ip_rib (peer_hash_id,origin_as);

ALTER TABLE ip_rib SET (autovacuum_analyze_threshold = 100);
ALTER TABLE ip_rib SET (autovacuum_vacuum_threshold =  200);
ALTER TABLE ip_rib SET (autovacuum_vacuum_cost_limit = 200);
ALTER TABLE ip_rib SET (autovacuum_vacuum_cost_delay = 10);


-- Table structure for table ip_rib_log
DROP TABLE IF EXISTS ip_rib_log CASCADE;
CREATE TABLE ip_rib_log (
    id                      bigserial           NOT NULL,
	base_attr_hash_id       uuid                NOT NULL,
	timestamp               timestamp(6)        without time zone default (now() at time zone 'utc') NOT NULL,
    peer_hash_id            uuid                NOT NULL,
    prefix                  inet                NOT NULL,
    prefix_len              smallint            NOT NULL,
    origin_as               bigint              NOT NULL,
    isWithdrawn             boolean             NOT NULL
) TABLESPACE timeseries;
--CREATE INDEX ON ip_rib_log USING HASH  (peer_hash_id);
CREATE INDEX ON ip_rib_log USING GIST (prefix inet_ops);
CREATE INDEX ON ip_rib_log (origin_as);
CREATE INDEX ON ip_rib_log (peer_hash_id);
CREATE INDEX ON ip_rib_log (base_attr_hash_id);
CREATE INDEX ON ip_rib_log (peer_hash_id,base_attr_hash_id);

-- convert to timescaledb
SELECT create_hypertable('ip_rib_log', 'timestamp', chunk_time_interval => interval '1 hours');

SELECT add_retention_policy('ip_rib_log', INTERVAL '2 months');


ALTER TABLE ip_rib_log SET (
	timescaledb.compress,
	timescaledb.compress_segmentby = 'peer_hash_id,prefix,origin_as'
	);

SELECT add_compression_policy('ip_rib_log', INTERVAL '2 days');

-- To see compression details
-- SELECT pg_size_pretty(before_compression_total_bytes) as "before compression",
--       pg_size_pretty(after_compression_total_bytes) as "after compression"
-- FROM hypertable_compression_stats('ip_rib_log');




-- Table structure for global ip rib
DROP TABLE IF EXISTS global_ip_rib CASCADE;
CREATE TABLE global_ip_rib (
    prefix                  inet                NOT NULL,
  	iswithdrawn             boolean             NOT NULL DEFAULT false,
    prefix_len              smallint            NOT NULL DEFAULT 0,
    recv_origin_as          bigint              NOT NULL,
    rpki_origin_as          bigint,
    irr_origin_as           bigint,
    irr_source              varchar(32),
    irr_descr               varchar(255),
    num_peers               int                 DEFAULT 0,
    advertising_peers       int                 DEFAULT 0,
    withdrawn_peers         int                 DEFAULT 0,
    timestamp               timestamp           without time zone default (now() at time zone 'utc') NOT NULL,
    first_added_timestamp   timestamp(6)        without time zone default (now() at time zone 'utc') NOT NULL,

    PRIMARY KEY (prefix,recv_origin_as)
);
CREATE INDEX ON global_ip_rib (recv_origin_as);
CREATE INDEX ON global_ip_rib USING GIST (prefix inet_ops);
CREATE INDEX ON global_ip_rib (rpki_origin_as);
CREATE INDEX ON global_ip_rib (irr_origin_as);
CREATE INDEX ON global_ip_rib (timestamp DESC);
CREATE INDEX ON global_ip_rib (iswithdrawn,timestamp DESC);


-- Table structure for table info_asn (based on whois)
DROP TABLE IF EXISTS info_asn CASCADE;
CREATE TABLE info_asn (
    asn                     bigint              NOT NULL,
    as_name                 varchar(255),
    org_id                  varchar(255),
    org_name                varchar(255),
    remarks                 text,
    address                 varchar(255),
    city                    varchar(255),
    state_prov              varchar(255),
    postal_code             varchar(255),
    country                 varchar(255),
    raw_output              text,
    timestamp               timestamp           without time zone default (now() at time zone 'utc') NOT NULL,
    source                  varchar(64)         DEFAULT NULL,
    PRIMARY KEY (asn)
);


-- Table structure for table info_route (based on whois)
DROP TABLE IF EXISTS info_route CASCADE;
CREATE TABLE info_route (
    prefix                  inet                NOT NULL,
    prefix_len              smallint            NOT NULL DEFAULT 0,
    descr                   text,
    origin_as               bigint              NOT NULL,
    source                  varchar(32)         NOT NULL,
    timestamp               timestamp           without time zone default (now() at time zone 'utc') NOT NULL,
    PRIMARY KEY (prefix,prefix_len,origin_as)
);
CREATE INDEX ON info_route (origin_as);
CREATE INDEX ON info_route USING GIST (prefix inet_ops);
CREATE INDEX ON info_route (prefix inet_ops);

-- Table structure for table peering DB peerings by exchange
DROP TABLE IF EXISTS pdb_exchange_peers CASCADE;
CREATE TABLE pdb_exchange_peers (
    ix_id                   int                 NOT NULL,
    ix_name                 varchar(128)        NOT NULL,
    ix_prefix_v4            inet,
    ix_prefix_v6            inet,
    ix_country              varchar(12),
    ix_city                 varchar(128),
    ix_region               varchar(128),
    rs_peer                 boolean             NOT NULL DEFAULT false,
    peer_name               varchar(255)        NOT NULL,
    peer_ipv4               inet                NOT NULL DEFAULT '0.0.0.0',
    peer_ipv6               inet                NOT NULL DEFAULT '::',
    peer_asn                bigint              NOT NULL,
    speed                   int,
	policy                  varchar(64),
	poc_policy_email        varchar(255),
	poc_noc_email           varchar(255),
    timestamp               timestamp           without time zone default (now() at time zone 'utc') NOT NULL,
    PRIMARY KEY (ix_id,peer_ipv4,peer_ipv6)
);
CREATE INDEX ON pdb_exchange_peers (ix_id);
CREATE INDEX ON pdb_exchange_peers (ix_region);
CREATE INDEX ON pdb_exchange_peers (ix_country);
CREATE INDEX ON pdb_exchange_peers USING GIST (peer_ipv4 inet_ops);
CREATE INDEX ON pdb_exchange_peers USING GIST (ix_prefix_v4 inet_ops);
CREATE INDEX ON pdb_exchange_peers USING gin (peer_name gin_trgm_ops);
CREATE INDEX ON pdb_exchange_peers (peer_asn);

-- Table structure for link state nodes
DROP TABLE IF EXISTS ls_nodes CASCADE;
CREATE TABLE ls_nodes (
    hash_id                 uuid                NOT NULL,
    peer_hash_id            uuid                NOT NULL,
    base_attr_hash_id       uuid,
    seq                     bigint              NOT NULL DEFAULT 0,
    asn                     bigint              NOT NULL,
    bgp_ls_id               bigint              NOT NULL DEFAULT 0,
    igp_router_id           varchar(46)         NOT NULL,
    ospf_area_id            varchar(16)         NOT NULL,
    protocol                ls_proto            DEFAULT '',
    router_id               varchar(46)         NOT NULL,
    isis_area_id            varchar(46),
    flags                   varchar(20),
    name                    varchar(255),
    mt_ids                  varchar(128),
    sr_capabilities         varchar(255),
    isWithdrawn             boolean             NOT NULL DEFAULT false,
    timestamp               timestamp(6)        without time zone default (now() at time zone 'utc') NOT NULL,
    PRIMARY KEY (hash_id,peer_hash_id)
);

-- CREATE UNIQUE INDEX ON ip_rib (hash_id);
CREATE INDEX ON ls_nodes (router_id);
CREATE INDEX ON ls_nodes (base_attr_hash_id);
CREATE INDEX ON ls_nodes (igp_router_id);
CREATE INDEX ON ls_nodes (peer_hash_id);
CREATE INDEX ON ls_nodes (hash_id);
CREATE INDEX ON ls_nodes (hash_id, peer_hash_id);

-- Table structure for table ls_nodes_log
DROP TABLE IF EXISTS ls_nodes_log CASCADE;
CREATE TABLE ls_nodes_log (
    id                      bigserial           NOT NULL,
    hash_id                 uuid                NOT NULL,
    peer_hash_id            uuid                NOT NULL,
    base_attr_hash_id       uuid,
    seq                     bigint              NOT NULL DEFAULT 0,
    asn                     bigint              NOT NULL,
    bgp_ls_id               bigint              NOT NULL DEFAULT 0,
    igp_router_id           varchar(46)         NOT NULL,
    ospf_area_id            varchar(16)         NOT NULL,
    protocol                ls_proto            DEFAULT '',
    router_id               varchar(46)         NOT NULL,
    isis_area_id            varchar(46),
    flags                   varchar(20),
    name                    varchar(255),
    mt_ids                  varchar(128),
    sr_capabilities         varchar(255),
    isWithdrawn             boolean             NOT NULL DEFAULT false,
    timestamp               timestamp(6)        without time zone default (now() at time zone 'utc') NOT NULL
) TABLESPACE timeseries;
CREATE INDEX ON ls_nodes_log USING HASH (peer_hash_id);
CREATE INDEX ON ls_nodes_log USING HASH (hash_id);
CREATE INDEX ON ls_nodes_log (igp_router_id);
CREATE INDEX ON ls_nodes_log (name);

-- convert to timescaledb
SELECT create_hypertable('ls_nodes_log', 'timestamp', chunk_time_interval => interval '30 day');
SELECT add_retention_policy('ls_nodes_log', INTERVAL '8 weeks');


-- Table structure for link state links
DROP TABLE IF EXISTS ls_links CASCADE;
CREATE TABLE ls_links (
	  hash_id                 uuid                NOT NULL,
	  peer_hash_id            uuid                NOT NULL,
	  base_attr_hash_id       uuid,
	  seq                     bigint              NOT NULL DEFAULT 0,
	  mt_id                   int                 NOT NULL DEFAULT 0,
	  interface_addr          inet,
	  neighbor_addr           inet,
	  isIPv4                  boolean             NOT NULL DEFAULT true,
	  protocol                ls_proto            DEFAULT '',
	  local_link_id           bigint,
	  remote_link_id          bigint,
	  local_node_hash_id      uuid                NOT NULL,
	  remote_node_hash_id     uuid                NOT NULL,
	  admin_group             bigint              NOT NULL,
	  max_link_bw             bigint,
	  max_resv_bw             bigint,
	  unreserved_bw           varchar(128),
	  te_def_metric           bigint,
	  protection_type         varchar(60),
	  mpls_proto_mask         ls_mpls_proto_mask,
	  igp_metric              bigint             NOT NULL DEFAULT 0,
	  srlg                    varchar(128),
	  name                    varchar(255),
	  local_igp_router_id     varchar(46)        NOT NULL,
	  local_router_id         varchar(46)        NOT NULL,
	  remote_igp_router_id    varchar(46)        NOT NULL,
	  remote_router_id        varchar(46)        NOT NULL,
	  local_asn               bigint             NOT NULL DEFAULT 0,
	  remote_asn              bigint             NOT NULL DEFAULT 0,
	  peer_node_sid           varchar(128),
	  sr_adjacency_sids       varchar(255),
	  isWithdrawn             boolean            NOT NULL DEFAULT false,
	  timestamp               timestamp(6)       without time zone default (now() at time zone 'utc') NOT NULL,
	  PRIMARY KEY (hash_id,peer_hash_id)
);

CREATE INDEX ON ls_links (local_router_id);
CREATE INDEX ON ls_links (local_node_hash_id);
CREATE INDEX ON ls_links (remote_node_hash_id);
CREATE INDEX ON ls_links (base_attr_hash_id);
CREATE INDEX ON ls_links (remote_router_id);
CREATE INDEX ON ls_links (local_node_hash_id, peer_hash_id);

-- Table structure for table ls_links_log
DROP TABLE IF EXISTS ls_links_log CASCADE;
CREATE TABLE ls_links_log (
	  id                      bigserial           NOT NULL,
	  hash_id                 uuid                NOT NULL,
	  peer_hash_id            uuid                NOT NULL,
	  base_attr_hash_id       uuid,
	  seq                     bigint              NOT NULL DEFAULT 0,
	  mt_id                   int                 NOT NULL DEFAULT 0,
	  interface_addr          inet,
	  neighbor_addr           inet,
	  isIPv4                  boolean             NOT NULL DEFAULT true,
	  protocol                ls_proto            DEFAULT '',
	  local_link_id           bigint,
	  remote_link_id          bigint,
	  local_node_hash_id      uuid                NOT NULL,
	  remote_node_hash_id     uuid                NOT NULL,
	  admin_group             bigint              NOT NULL,
	  max_link_bw             bigint,
	  max_resv_bw             bigint,
	  unreserved_bw           varchar(128),
	  te_def_metric           bigint,
	  protection_type         varchar(60),
	  mpls_proto_mask         ls_mpls_proto_mask,
	  igp_metric              bigint             NOT NULL DEFAULT 0,
	  srlg                    varchar(128),
	  name                    varchar(255),
	  local_igp_router_id     varchar(46)        NOT NULL,
	  local_router_id         varchar(46)        NOT NULL,
	  remote_igp_router_id    varchar(46)        NOT NULL,
	  remote_router_id        varchar(46)        NOT NULL,
	  local_asn               bigint             NOT NULL DEFAULT 0,
	  remote_asn              bigint             NOT NULL DEFAULT 0,
	  peer_node_sid           varchar(128),
	  sr_adjacency_sids       varchar(255),
	  isWithdrawn             boolean            NOT NULL DEFAULT false,
	  timestamp               timestamp(6)       without time zone default (now() at time zone 'utc') NOT NULL
) TABLESPACE timeseries;
CREATE INDEX ON ls_links_log USING HASH (peer_hash_id);
CREATE INDEX ON ls_links_log USING HASH (hash_id);
CREATE INDEX ON ls_links_log (local_igp_router_id);
CREATE INDEX ON ls_links_log USING HASH (local_node_hash_id);
CREATE INDEX ON ls_links_log USING HASH (remote_node_hash_id);
CREATE INDEX ON ls_links_log (remote_igp_router_id);

-- convert to timescaledb
SELECT create_hypertable('ls_links_log', 'timestamp', chunk_time_interval => interval '30 day');
SELECT add_retention_policy('ls_links_log', INTERVAL '8 weeks');


-- Table structure for link state prefixes
DROP TABLE IF EXISTS ls_prefixes CASCADE;
CREATE TABLE ls_prefixes (
      hash_id                 uuid                NOT NULL,
      peer_hash_id            uuid                NOT NULL,
      base_attr_hash_id       uuid,
      seq                     bigint              NOT NULL DEFAULT 0,
      local_node_hash_id      uuid                NOT NULL,
      mt_id                   int                 NOT NULL DEFAULT 0,
      protocol                ls_proto            DEFAULT '',
	  prefix                  inet                NOT NULL,
      prefix_len              smallint            NOT NULL,
	  ospf_route_type         ospf_route_type     NOT NULL DEFAULT '',
	  igp_flags               varchar(20),
      isIPv4                  boolean             NOT NULL DEFAULT true,
	  route_tag               bigint              NOT NULL DEFAULT 0,
	  ext_route_tag           bigint              NOT NULL DEFAULT 0,
	  metric                  bigint              NOT NULL DEFAULT 0,
	  ospf_fwd_addr           inet,
	  sr_prefix_sids          varchar(255),
      isWithdrawn             boolean            NOT NULL DEFAULT false,
      timestamp               timestamp(6)       without time zone default (now() at time zone 'utc') NOT NULL,
      PRIMARY KEY (hash_id,peer_hash_id)
);

CREATE INDEX ON ls_prefixes USING HASH (local_node_hash_id);
CREATE INDEX ON ls_prefixes USING HASH (base_attr_hash_id);
CREATE INDEX ON ls_prefixes USING GIST (prefix inet_ops);

-- Table structure for table ls_nodes_log
DROP TABLE IF EXISTS ls_prefixes_log CASCADE;
CREATE TABLE ls_prefixes_log (
      id                      bigserial           NOT NULL,
      hash_id                 uuid                NOT NULL,
      peer_hash_id            uuid                NOT NULL,
      base_attr_hash_id       uuid,
      seq                     bigint              NOT NULL DEFAULT 0,
      local_node_hash_id      uuid                NOT NULL,
      mt_id                   int                 NOT NULL DEFAULT 0,
      protocol                ls_proto            DEFAULT '',
	  prefix                  inet                NOT NULL,
      prefix_len              smallint            NOT NULL,
	  ospf_route_type         ospf_route_type     NOT NULL DEFAULT '',
	  igp_flags               varchar(20),
      isIPv4                  boolean             NOT NULL DEFAULT true,
	  route_tag               bigint              NOT NULL DEFAULT 0,
	  ext_route_tag           bigint              NOT NULL DEFAULT 0,
	  metric                  bigint              NOT NULL DEFAULT 0,
	  ospf_fwd_addr           inet,
	  sr_prefix_sids          varchar(255),
      isWithdrawn             boolean            NOT NULL DEFAULT false,
      timestamp               timestamp(6)       without time zone default (now() at time zone 'utc') NOT NULL
) TABLESPACE timeseries;
CREATE INDEX ON ls_prefixes_log USING HASH (peer_hash_id);
CREATE INDEX ON ls_prefixes_log USING HASH (hash_id);
CREATE INDEX ON ls_prefixes_log USING HASH (local_node_hash_id);
CREATE INDEX ON ls_prefixes_log USING GIST (prefix inet_ops);

-- convert to timescaledb
SELECT create_hypertable('ls_prefixes_log', 'timestamp', chunk_time_interval => interval '30 day');
SELECT add_retention_policy('ls_prefixes_log', INTERVAL '8 weeks');



--
-- END
--

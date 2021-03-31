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
CREATE TYPE opState as enum ('up', 'down', '');
CREATE TYPE user_role as enum ('admin', 'oper', '');
CREATE TYPE ls_proto as enum ('IS-IS_L1', 'IS-IS_L2', 'OSPFv2', 'Direct', 'Static', 'OSPFv3', '');
CREATE TYPE ospf_route_type as enum ('Intra','Inter','Ext-1','Ext-2','NSSA-1','NSSA-2','');
CREATE TYPE ls_mpls_proto_mask as enum('LDP', 'RSVP-TE', '');

-- -----------------------------------------------------
-- Tables and base, non dependant functions
-- -----------------------------------------------------

-- Table structure for table geo_ip
DROP TABLE IF EXISTS geo_ip;
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
DROP TABLE IF EXISTS rpki_validator;
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
DROP TABLE IF EXISTS users;
CREATE TABLE users (
	username            varchar(50)     NOT NULL,
	password            varchar(50)     NOT NULL,
	type                user_role       NOT NULL,
	PRIMARY KEY (username)
);
INSERT INTO users (username,password,type) VALUES ('openbmp', 'openbmp', 'admin');


-- Table structure for table collectors
DROP TABLE IF EXISTS collectors;
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

ALTER TABLE collectors SET (autovacuum_analyze_threshold = 50);
ALTER TABLE collectors SET (autovacuum_vacuum_threshold = 50);


-- Table structure for table routers
DROP TABLE IF EXISTS routers;
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

ALTER TABLE routers SET (autovacuum_analyze_threshold = 50);
ALTER TABLE routers SET (autovacuum_vacuum_threshold = 50);


-- Table structure for table bgp_peers
DROP TABLE IF EXISTS bgp_peers;
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

ALTER TABLE bgp_peers SET (autovacuum_analyze_threshold = 50);
ALTER TABLE bgp_peers SET (autovacuum_vacuum_threshold = 50);


-- Table structure for table peer_event_log
--     updated by bgp_peers trigger
DROP TABLE IF EXISTS peer_event_log;
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


-- Table structure for table stat_reports
--     TimescaleDB
DROP TABLE IF EXISTS stat_reports;
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

-- Table structure for table base_attrs
--    https://blog.dbi-services.com/hash-partitioning-in-postgresql-11/
DROP TABLE IF EXISTS base_attrs;
CREATE TABLE base_attrs (
	hash_id                 uuid                NOT NULL,
	peer_hash_id            uuid                NOT NULL,
	origin                  varchar(16)         NOT NULL,
	as_path                 varchar(8192)       NOT NULL,
	as_path_count           smallint            DEFAULT 0,
    origin_as               bigint,
    next_hop                inet,
    med                     bigint,
    local_pref              bigint,
    aggregator              varchar(64),
    community_list          varchar(6000),
    ext_community_list      varchar(2048),
    large_community_list    varchar(3000),
    cluster_list            varchar(2048),
    isAtomicAgg             boolean             DEFAULT false,
    nexthop_isIPv4          boolean             DEFAULT true,
    timestamp               timestamp(6)        without time zone default (now() at time zone 'utc') NOT NULL,
    originator_id           inet,
    PRIMARY KEY (peer_hash_id,hash_id)
) PARTITION BY HASH (peer_hash_id);

CREATE INDEX ON base_attrs USING HASH  (hash_id);
--CREATE INDEX ON base_attrs (origin_as);
--CREATE INDEX ON base_attrs (as_path_count);
CREATE INDEX ON base_attrs USING gin (as_path gin_trgm_ops);
CREATE INDEX ON base_attrs USING gin (community_list gin_trgm_ops);
CREATE INDEX ON base_attrs USING HASH  (peer_hash_id);
CREATE INDEX ON base_attrs (peer_hash_id, hash_id);

CREATE TABLE base_attrs_p1 PARTITION OF base_attrs
	FOR VALUES WITH (modulus 40, remainder 0)
	WITH (autovacuum_vacuum_cost_limit = 1000, autovacuum_vacuum_cost_delay = 5);
CREATE TABLE base_attrs_p2 PARTITION OF base_attrs
	FOR VALUES WITH (modulus 40, remainder 1)
	WITH (autovacuum_vacuum_cost_limit = 1000, autovacuum_vacuum_cost_delay = 5);
CREATE TABLE base_attrs_p3 PARTITION OF base_attrs
	FOR VALUES WITH (modulus 40, remainder 2)
	WITH (autovacuum_vacuum_cost_limit = 1000, autovacuum_vacuum_cost_delay = 5);
CREATE TABLE base_attrs_p4 PARTITION OF base_attrs
	FOR VALUES WITH (modulus 40, remainder 3)
	WITH (autovacuum_vacuum_cost_limit = 1000, autovacuum_vacuum_cost_delay = 5);
CREATE TABLE base_attrs_p5 PARTITION OF base_attrs
	FOR VALUES WITH (modulus 40, remainder 4)
	WITH (autovacuum_vacuum_cost_limit = 1000, autovacuum_vacuum_cost_delay = 5);
CREATE TABLE base_attrs_p6 PARTITION OF base_attrs
	FOR VALUES WITH (modulus 40, remainder 5)
	WITH (autovacuum_vacuum_cost_limit = 1000, autovacuum_vacuum_cost_delay = 5);
CREATE TABLE base_attrs_p7 PARTITION OF base_attrs
	FOR VALUES WITH (modulus 40, remainder 6)
	WITH (autovacuum_vacuum_cost_limit = 1000, autovacuum_vacuum_cost_delay = 5);
CREATE TABLE base_attrs_p8 PARTITION OF base_attrs
	FOR VALUES WITH (modulus 40, remainder 7)
	WITH (autovacuum_vacuum_cost_limit = 1000, autovacuum_vacuum_cost_delay = 5);
CREATE TABLE base_attrs_p9 PARTITION OF base_attrs
	FOR VALUES WITH (modulus 40, remainder 8)
	WITH (autovacuum_vacuum_cost_limit = 1000, autovacuum_vacuum_cost_delay = 5);
CREATE TABLE base_attrs_p10 PARTITION OF base_attrs
	FOR VALUES WITH (modulus 40, remainder 9)
	WITH (autovacuum_vacuum_cost_limit = 1000, autovacuum_vacuum_cost_delay = 5);
CREATE TABLE base_attrs_p11 PARTITION OF base_attrs
	FOR VALUES WITH (modulus 40, remainder 10)
	WITH (autovacuum_vacuum_cost_limit = 1000, autovacuum_vacuum_cost_delay = 5);
CREATE TABLE base_attrs_p12 PARTITION OF base_attrs
	FOR VALUES WITH (modulus 40, remainder 11)
	WITH (autovacuum_vacuum_cost_limit = 1000, autovacuum_vacuum_cost_delay = 5);
CREATE TABLE base_attrs_p13 PARTITION OF base_attrs
	FOR VALUES WITH (modulus 40, remainder 12)
	WITH (autovacuum_vacuum_cost_limit = 1000, autovacuum_vacuum_cost_delay = 5);
CREATE TABLE base_attrs_p14 PARTITION OF base_attrs
	FOR VALUES WITH (modulus 40, remainder 13)
	WITH (autovacuum_vacuum_cost_limit = 1000, autovacuum_vacuum_cost_delay = 5);
CREATE TABLE base_attrs_p15 PARTITION OF base_attrs
	FOR VALUES WITH (modulus 40, remainder 14)
	WITH (autovacuum_vacuum_cost_limit = 1000, autovacuum_vacuum_cost_delay = 5);
CREATE TABLE base_attrs_p16 PARTITION OF base_attrs
	FOR VALUES WITH (modulus 40, remainder 15)
	WITH (autovacuum_vacuum_cost_limit = 1000, autovacuum_vacuum_cost_delay = 5);
CREATE TABLE base_attrs_p17 PARTITION OF base_attrs
	FOR VALUES WITH (modulus 40, remainder 16)
	WITH (autovacuum_vacuum_cost_limit = 1000, autovacuum_vacuum_cost_delay = 5);
CREATE TABLE base_attrs_p18 PARTITION OF base_attrs
	FOR VALUES WITH (modulus 40, remainder 17)
	WITH (autovacuum_vacuum_cost_limit = 1000, autovacuum_vacuum_cost_delay = 5);
CREATE TABLE base_attrs_p19 PARTITION OF base_attrs
	FOR VALUES WITH (modulus 40, remainder 18)
	WITH (autovacuum_vacuum_cost_limit = 1000, autovacuum_vacuum_cost_delay = 5);
CREATE TABLE base_attrs_p20 PARTITION OF base_attrs
	FOR VALUES WITH (modulus 40, remainder 19)
	WITH (autovacuum_vacuum_cost_limit = 1000, autovacuum_vacuum_cost_delay = 5);
CREATE TABLE base_attrs_p21 PARTITION OF base_attrs
	FOR VALUES WITH (modulus 40, remainder 20)
	WITH (autovacuum_vacuum_cost_limit = 1000, autovacuum_vacuum_cost_delay = 5);
CREATE TABLE base_attrs_p22 PARTITION OF base_attrs
	FOR VALUES WITH (modulus 40, remainder 21)
	WITH (autovacuum_vacuum_cost_limit = 1000, autovacuum_vacuum_cost_delay = 5);
CREATE TABLE base_attrs_p23 PARTITION OF base_attrs
	FOR VALUES WITH (modulus 40, remainder 22)
	WITH (autovacuum_vacuum_cost_limit = 1000, autovacuum_vacuum_cost_delay = 5);
CREATE TABLE base_attrs_p24 PARTITION OF base_attrs
	FOR VALUES WITH (modulus 40, remainder 23)
	WITH (autovacuum_vacuum_cost_limit = 1000, autovacuum_vacuum_cost_delay = 5);
CREATE TABLE base_attrs_p25 PARTITION OF base_attrs
	FOR VALUES WITH (modulus 40, remainder 24)
	WITH (autovacuum_vacuum_cost_limit = 1000, autovacuum_vacuum_cost_delay = 5);
CREATE TABLE base_attrs_p26 PARTITION OF base_attrs
	FOR VALUES WITH (modulus 40, remainder 25)
	WITH (autovacuum_vacuum_cost_limit = 1000, autovacuum_vacuum_cost_delay = 5);
CREATE TABLE base_attrs_p27 PARTITION OF base_attrs
	FOR VALUES WITH (modulus 40, remainder 26)
	WITH (autovacuum_vacuum_cost_limit = 1000, autovacuum_vacuum_cost_delay = 5);
CREATE TABLE base_attrs_p28 PARTITION OF base_attrs
	FOR VALUES WITH (modulus 40, remainder 27)
	WITH (autovacuum_vacuum_cost_limit = 1000, autovacuum_vacuum_cost_delay = 5);
CREATE TABLE base_attrs_p29 PARTITION OF base_attrs
	FOR VALUES WITH (modulus 40, remainder 28)
	WITH (autovacuum_vacuum_cost_limit = 1000, autovacuum_vacuum_cost_delay = 5);
CREATE TABLE base_attrs_p30 PARTITION OF base_attrs
	FOR VALUES WITH (modulus 40, remainder 29)
	WITH (autovacuum_vacuum_cost_limit = 1000, autovacuum_vacuum_cost_delay = 5);
CREATE TABLE base_attrs_p31 PARTITION OF base_attrs
	FOR VALUES WITH (modulus 40, remainder 30)
	WITH (autovacuum_vacuum_cost_limit = 1000, autovacuum_vacuum_cost_delay = 5);
CREATE TABLE base_attrs_p32 PARTITION OF base_attrs
	FOR VALUES WITH (modulus 40, remainder 31)
	WITH (autovacuum_vacuum_cost_limit = 1000, autovacuum_vacuum_cost_delay = 5);
CREATE TABLE base_attrs_p33 PARTITION OF base_attrs
	FOR VALUES WITH (modulus 40, remainder 32)
	WITH (autovacuum_vacuum_cost_limit = 1000, autovacuum_vacuum_cost_delay = 5);
CREATE TABLE base_attrs_p34 PARTITION OF base_attrs
	FOR VALUES WITH (modulus 40, remainder 33)
	WITH (autovacuum_vacuum_cost_limit = 1000, autovacuum_vacuum_cost_delay = 5);
CREATE TABLE base_attrs_p35 PARTITION OF base_attrs
	FOR VALUES WITH (modulus 40, remainder 34)
	WITH (autovacuum_vacuum_cost_limit = 1000, autovacuum_vacuum_cost_delay = 5);
CREATE TABLE base_attrs_p36 PARTITION OF base_attrs
	FOR VALUES WITH (modulus 40, remainder 35)
	WITH (autovacuum_vacuum_cost_limit = 1000, autovacuum_vacuum_cost_delay = 5);
CREATE TABLE base_attrs_p37 PARTITION OF base_attrs
	FOR VALUES WITH (modulus 40, remainder 36)
	WITH (autovacuum_vacuum_cost_limit = 1000, autovacuum_vacuum_cost_delay = 5);
CREATE TABLE base_attrs_p38 PARTITION OF base_attrs
	FOR VALUES WITH (modulus 40, remainder 37)
	WITH (autovacuum_vacuum_cost_limit = 1000, autovacuum_vacuum_cost_delay = 5);
CREATE TABLE base_attrs_p39 PARTITION OF base_attrs
	FOR VALUES WITH (modulus 40, remainder 38)
	WITH (autovacuum_vacuum_cost_limit = 1000, autovacuum_vacuum_cost_delay = 5);
CREATE TABLE base_attrs_p40 PARTITION OF base_attrs
	FOR VALUES WITH (modulus 40, remainder 39)
	WITH (autovacuum_vacuum_cost_limit = 1000, autovacuum_vacuum_cost_delay = 5);


-- Table structure for table rib
--    https://blog.dbi-services.com/hash-partitioning-in-postgresql-11/--
DROP TABLE IF EXISTS ip_rib;
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
    prefix_bits             varchar(128),
    path_id                 bigint,
    labels                  varchar(255),
    isPrePolicy             boolean             NOT NULL DEFAULT true,
    isAdjRibIn              boolean             NOT NULL DEFAULT true,
    PRIMARY KEY (peer_hash_id, hash_id)
) PARTITION BY HASH (peer_hash_id);

CREATE INDEX ON ip_rib USING HASH (hash_id);
--CREATE INDEX ON ip_rib USING HASH (peer_hash_id);
-- Brin apparently requires a lot of memory and changes psql to prefer this index
-- CREATE INDEX ON ip_rib using brin (peer_hash_id,timestamp);
CREATE INDEX ON ip_rib USING HASH (base_attr_hash_id);
CREATE INDEX ON ip_rib USING GIST (prefix inet_ops);
CREATE INDEX ON ip_rib (origin_as);
CREATE INDEX ON ip_rib (peer_hash_id,origin_as);

CREATE TABLE ip_rib_p1 PARTITION OF ip_rib
	FOR VALUES WITH (modulus 40, remainder 0)
	WITH (autovacuum_vacuum_cost_limit = 1000, autovacuum_vacuum_cost_delay = 5);
CREATE TABLE ip_rib_p2 PARTITION OF ip_rib
	FOR VALUES WITH (modulus 40, remainder 1)
	WITH (autovacuum_vacuum_cost_limit = 1000, autovacuum_vacuum_cost_delay = 5);
CREATE TABLE ip_rib_p3 PARTITION OF ip_rib
	FOR VALUES WITH (modulus 40, remainder 2)
	WITH (autovacuum_vacuum_cost_limit = 1000, autovacuum_vacuum_cost_delay = 5);
CREATE TABLE ip_rib_p4 PARTITION OF ip_rib
	FOR VALUES WITH (modulus 40, remainder 3)
	WITH (autovacuum_vacuum_cost_limit = 1000, autovacuum_vacuum_cost_delay = 5);
CREATE TABLE ip_rib_p5 PARTITION OF ip_rib
	FOR VALUES WITH (modulus 40, remainder 4)
	WITH (autovacuum_vacuum_cost_limit = 1000, autovacuum_vacuum_cost_delay = 5);
CREATE TABLE ip_rib_p6 PARTITION OF ip_rib
	FOR VALUES WITH (modulus 40, remainder 5)
	WITH (autovacuum_vacuum_cost_limit = 1000, autovacuum_vacuum_cost_delay = 5);
CREATE TABLE ip_rib_p7 PARTITION OF ip_rib
	FOR VALUES WITH (modulus 40, remainder 6)
	WITH (autovacuum_vacuum_cost_limit = 1000, autovacuum_vacuum_cost_delay = 5);
CREATE TABLE ip_rib_p8 PARTITION OF ip_rib
	FOR VALUES WITH (modulus 40, remainder 7)
	WITH (autovacuum_vacuum_cost_limit = 1000, autovacuum_vacuum_cost_delay = 5);
CREATE TABLE ip_rib_p9 PARTITION OF ip_rib
	FOR VALUES WITH (modulus 40, remainder 8)
	WITH (autovacuum_vacuum_cost_limit = 1000, autovacuum_vacuum_cost_delay = 5);
CREATE TABLE ip_rib_p10 PARTITION OF ip_rib
	FOR VALUES WITH (modulus 40, remainder 9)
	WITH (autovacuum_vacuum_cost_limit = 1000, autovacuum_vacuum_cost_delay = 5);
CREATE TABLE ip_rib_p11 PARTITION OF ip_rib
	FOR VALUES WITH (modulus 40, remainder 10)
	WITH (autovacuum_vacuum_cost_limit = 1000, autovacuum_vacuum_cost_delay = 5);
CREATE TABLE ip_rib_p12 PARTITION OF ip_rib
	FOR VALUES WITH (modulus 40, remainder 11)
	WITH (autovacuum_vacuum_cost_limit = 1000, autovacuum_vacuum_cost_delay = 5);
CREATE TABLE ip_rib_p13 PARTITION OF ip_rib
	FOR VALUES WITH (modulus 40, remainder 12)
	WITH (autovacuum_vacuum_cost_limit = 1000, autovacuum_vacuum_cost_delay = 5);
CREATE TABLE ip_rib_p14 PARTITION OF ip_rib
	FOR VALUES WITH (modulus 40, remainder 13)
	WITH (autovacuum_vacuum_cost_limit = 1000, autovacuum_vacuum_cost_delay = 5);
CREATE TABLE ip_rib_p15 PARTITION OF ip_rib
	FOR VALUES WITH (modulus 40, remainder 14)
	WITH (autovacuum_vacuum_cost_limit = 1000, autovacuum_vacuum_cost_delay = 5);
CREATE TABLE ip_rib_p16 PARTITION OF ip_rib
	FOR VALUES WITH (modulus 40, remainder 15)
	WITH (autovacuum_vacuum_cost_limit = 1000, autovacuum_vacuum_cost_delay = 5);
CREATE TABLE ip_rib_p17 PARTITION OF ip_rib
	FOR VALUES WITH (modulus 40, remainder 16)
	WITH (autovacuum_vacuum_cost_limit = 1000, autovacuum_vacuum_cost_delay = 5);
CREATE TABLE ip_rib_p18 PARTITION OF ip_rib
	FOR VALUES WITH (modulus 40, remainder 17)
	WITH (autovacuum_vacuum_cost_limit = 1000, autovacuum_vacuum_cost_delay = 5);
CREATE TABLE ip_rib_p19 PARTITION OF ip_rib
	FOR VALUES WITH (modulus 40, remainder 18)
	WITH (autovacuum_vacuum_cost_limit = 1000, autovacuum_vacuum_cost_delay = 5);
CREATE TABLE ip_rib_p20 PARTITION OF ip_rib
	FOR VALUES WITH (modulus 40, remainder 19)
	WITH (autovacuum_vacuum_cost_limit = 1000, autovacuum_vacuum_cost_delay = 5);
CREATE TABLE ip_rib_p21 PARTITION OF ip_rib
	FOR VALUES WITH (modulus 40, remainder 20)
	WITH (autovacuum_vacuum_cost_limit = 1000, autovacuum_vacuum_cost_delay = 5);
CREATE TABLE ip_rib_p22 PARTITION OF ip_rib
	FOR VALUES WITH (modulus 40, remainder 21)
	WITH (autovacuum_vacuum_cost_limit = 1000, autovacuum_vacuum_cost_delay = 5);
CREATE TABLE ip_rib_p23 PARTITION OF ip_rib
	FOR VALUES WITH (modulus 40, remainder 22)
	WITH (autovacuum_vacuum_cost_limit = 1000, autovacuum_vacuum_cost_delay = 5);
CREATE TABLE ip_rib_p24 PARTITION OF ip_rib
	FOR VALUES WITH (modulus 40, remainder 23)
	WITH (autovacuum_vacuum_cost_limit = 1000, autovacuum_vacuum_cost_delay = 5);
CREATE TABLE ip_rib_p25 PARTITION OF ip_rib
	FOR VALUES WITH (modulus 40, remainder 24)
	WITH (autovacuum_vacuum_cost_limit = 1000, autovacuum_vacuum_cost_delay = 5);
CREATE TABLE ip_rib_p26 PARTITION OF ip_rib
	FOR VALUES WITH (modulus 40, remainder 25)
	WITH (autovacuum_vacuum_cost_limit = 1000, autovacuum_vacuum_cost_delay = 5);
CREATE TABLE ip_rib_p27 PARTITION OF ip_rib
	FOR VALUES WITH (modulus 40, remainder 26)
	WITH (autovacuum_vacuum_cost_limit = 1000, autovacuum_vacuum_cost_delay = 5);
CREATE TABLE ip_rib_p28 PARTITION OF ip_rib
	FOR VALUES WITH (modulus 40, remainder 27)
	WITH (autovacuum_vacuum_cost_limit = 1000, autovacuum_vacuum_cost_delay = 5);
CREATE TABLE ip_rib_p29 PARTITION OF ip_rib
	FOR VALUES WITH (modulus 40, remainder 28)
	WITH (autovacuum_vacuum_cost_limit = 1000, autovacuum_vacuum_cost_delay = 5);
CREATE TABLE ip_rib_p30 PARTITION OF ip_rib
	FOR VALUES WITH (modulus 40, remainder 29)
	WITH (autovacuum_vacuum_cost_limit = 1000, autovacuum_vacuum_cost_delay = 5);
CREATE TABLE ip_rib_p31 PARTITION OF ip_rib
	FOR VALUES WITH (modulus 40, remainder 30)
	WITH (autovacuum_vacuum_cost_limit = 1000, autovacuum_vacuum_cost_delay = 5);
CREATE TABLE ip_rib_p32 PARTITION OF ip_rib
	FOR VALUES WITH (modulus 40, remainder 31)
	WITH (autovacuum_vacuum_cost_limit = 1000, autovacuum_vacuum_cost_delay = 5);
CREATE TABLE ip_rib_p33 PARTITION OF ip_rib
	FOR VALUES WITH (modulus 40, remainder 32)
	WITH (autovacuum_vacuum_cost_limit = 1000, autovacuum_vacuum_cost_delay = 5);
CREATE TABLE ip_rib_p34 PARTITION OF ip_rib
	FOR VALUES WITH (modulus 40, remainder 33)
	WITH (autovacuum_vacuum_cost_limit = 1000, autovacuum_vacuum_cost_delay = 5);
CREATE TABLE ip_rib_p35 PARTITION OF ip_rib
	FOR VALUES WITH (modulus 40, remainder 34)
	WITH (autovacuum_vacuum_cost_limit = 1000, autovacuum_vacuum_cost_delay = 5);
CREATE TABLE ip_rib_p36 PARTITION OF ip_rib
	FOR VALUES WITH (modulus 40, remainder 35)
	WITH (autovacuum_vacuum_cost_limit = 1000, autovacuum_vacuum_cost_delay = 5);
CREATE TABLE ip_rib_p37 PARTITION OF ip_rib
	FOR VALUES WITH (modulus 40, remainder 36)
	WITH (autovacuum_vacuum_cost_limit = 1000, autovacuum_vacuum_cost_delay = 5);
CREATE TABLE ip_rib_p38 PARTITION OF ip_rib
	FOR VALUES WITH (modulus 40, remainder 37)
	WITH (autovacuum_vacuum_cost_limit = 1000, autovacuum_vacuum_cost_delay = 5);
CREATE TABLE ip_rib_p39 PARTITION OF ip_rib
	FOR VALUES WITH (modulus 40, remainder 38)
	WITH (autovacuum_vacuum_cost_limit = 1000, autovacuum_vacuum_cost_delay = 5);
CREATE TABLE ip_rib_p40 PARTITION OF ip_rib
	FOR VALUES WITH (modulus 40, remainder 39)
	WITH (autovacuum_vacuum_cost_limit = 1000, autovacuum_vacuum_cost_delay = 5);


-- Table structure for table ip_rib_log
DROP TABLE IF EXISTS ip_rib_log;
CREATE TABLE ip_rib_log (
    id                      bigserial           NOT NULL,
	base_attr_hash_id       uuid                NOT NULL,
	timestamp               timestamp(6)        without time zone default (now() at time zone 'utc') NOT NULL,
    peer_hash_id            uuid                NOT NULL,
    prefix                  inet                NOT NULL,
    prefix_len              smallint            NOT NULL,
    origin_as               bigint              NOT NULL,
    isWithdrawn             boolean             NOT NULL
) WITH (autovacuum_enabled = false) TABLESPACE timeseries;
--CREATE INDEX ON ip_rib_log USING HASH  (peer_hash_id);
CREATE INDEX ON ip_rib_log USING GIST (prefix inet_ops);
CREATE INDEX ON ip_rib_log (origin_as);

-- convert to timescaledb
SELECT create_hypertable('ip_rib_log', 'timestamp', chunk_time_interval => interval '1 hours');

-- Table structure for global ip rib
DROP TABLE IF EXISTS global_ip_rib;
CREATE TABLE global_ip_rib (
    prefix                  inet                NOT NULL,
  	should_delete           boolean             NOT NULL DEFAULT false,
    prefix_len              smallint            NOT NULL DEFAULT 0,
    recv_origin_as          bigint              NOT NULL,
    rpki_origin_as          bigint,
    irr_origin_as           bigint,
    irr_source              varchar(32),
    num_peers               int                 DEFAULT 0,
    timestamp               timestamp           without time zone default (now() at time zone 'utc') NOT NULL,

    PRIMARY KEY (prefix,recv_origin_as)
);
CREATE INDEX ON global_ip_rib (recv_origin_as);
CREATE INDEX ON global_ip_rib USING GIST (prefix inet_ops);
CREATE INDEX ON global_ip_rib (should_delete);
CREATE INDEX ON global_ip_rib (rpki_origin_as);
CREATE INDEX ON global_ip_rib (irr_origin_as);

ALTER TABLE global_ip_rib SET (autovacuum_vacuum_cost_limit = 1000);
ALTER TABLE global_ip_rib SET (autovacuum_vacuum_cost_delay = 5);


-- Table structure for table info_asn (based on whois)
DROP TABLE IF EXISTS info_asn;
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


ALTER TABLE info_asn SET (autovacuum_analyze_threshold = 50);
ALTER TABLE info_asn SET (autovacuum_vacuum_threshold = 50);

-- Table structure for table info_route (based on whois)
DROP TABLE IF EXISTS info_route;
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

ALTER TABLE info_route SET (autovacuum_analyze_threshold = 50);
ALTER TABLE info_route SET (autovacuum_vacuum_threshold = 50);


-- Table structure for table as_path_analysis
--     Optionally enabled table to index AS paths
DROP TABLE IF EXISTS as_path_analysis;
CREATE TABLE as_path_analysis (
    asn                     bigint              NOT NULL,
    asn_left                bigint              NOT NULL DEFAULT 0,
    asn_right               bigint              NOT NULL DEFAULT 0,
    asn_left_is_peering     boolean             DEFAULT false,
    timestamp               timestamp(6)        without time zone default (now() at time zone 'utc') NOT NULL,
    PRIMARY KEY (asn,asn_left_is_peering,asn_left,asn_right)
);

CREATE INDEX ON as_path_analysis (asn_left);
CREATE INDEX ON as_path_analysis (asn_right);

ALTER TABLE as_path_analysis SET (autovacuum_vacuum_cost_limit = 1000);
ALTER TABLE as_path_analysis SET (autovacuum_vacuum_cost_delay = 5);


-- Alerts table for security monitoring
DROP TABLE IF EXISTS alerts;
CREATE TABLE alerts (
	id                      bigserial           NOT NULL,
    type                    varchar(128)        NOT NULL,
	message                 text                NOT NULL,
    monitored_asn           bigint,
    offending_asn           bigint,
    monitored_asname        varchar(200),
    offending_asname        varchar(200),
	affected_prefix         inet,
	history_url             varchar(512),
	event_json              jsonb,
    timestamp               timestamp(6)        without time zone default (now() at time zone 'utc') NOT NULL
) TABLESPACE timeseries;

CREATE INDEX ON alerts (monitored_asn);
CREATE INDEX ON alerts (offending_asn);
CREATE INDEX ON alerts (type);
CREATE INDEX ON alerts using gist (affected_prefix inet_ops);

-- convert to timescaledb
SELECT create_hypertable('alerts', 'timestamp');


-- Table structure for link state nodes
DROP TABLE IF EXISTS ls_nodes;
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
    PRIMARY KEY (hash_id)
);

-- CREATE UNIQUE INDEX ON ip_rib (hash_id);
CREATE INDEX ON ls_nodes (router_id);
CREATE INDEX ON ls_nodes (base_attr_hash_id);
CREATE INDEX ON ls_nodes (igp_router_id);
CREATE INDEX ON ls_nodes (peer_hash_id);
CREATE INDEX ON ls_nodes (hash_id);
CREATE INDEX ON ls_nodes (hash_id, peer_hash_id);

ALTER TABLE ls_nodes SET (autovacuum_vacuum_cost_limit = 1000);
ALTER TABLE ls_nodes SET (autovacuum_vacuum_cost_delay = 5);

-- Table structure for table ls_nodes_log
DROP TABLE IF EXISTS ls_nodes_log;
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

-- Table structure for link state links
DROP TABLE IF EXISTS ls_links;
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
	  admin_group             int                 NOT NULL,
	  max_link_bw             bigint,
	  max_resv_bw             bigint,
	  unreserved_bw           varchar(60),
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
	  PRIMARY KEY (hash_id)
);

CREATE INDEX ON ls_links (local_router_id);
CREATE INDEX ON ls_links (local_node_hash_id);
CREATE INDEX ON ls_links (remote_node_hash_id);
CREATE INDEX ON ls_links (base_attr_hash_id);
CREATE INDEX ON ls_links (remote_router_id);
CREATE INDEX ON ls_links (local_node_hash_id, peer_hash_id);

ALTER TABLE ls_links SET (autovacuum_vacuum_cost_limit = 1000);
ALTER TABLE ls_links SET (autovacuum_vacuum_cost_delay = 5);

-- Table structure for table ls_links_log
DROP TABLE IF EXISTS ls_links_log;
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
	  admin_group             int                 NOT NULL,
	  max_link_bw             bigint,
	  max_resv_bw             bigint,
	  unreserved_bw           varchar(60),
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

-- Table structure for link state prefixes
DROP TABLE IF EXISTS ls_prefixes;
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
      PRIMARY KEY (hash_id)
);

CREATE INDEX ON ls_prefixes USING HASH (local_node_hash_id);
CREATE INDEX ON ls_prefixes USING HASH (base_attr_hash_id);
CREATE INDEX ON ls_prefixes USING GIST (prefix inet_ops);

ALTER TABLE ls_prefixes SET (autovacuum_vacuum_cost_limit = 1000);
ALTER TABLE ls_prefixes SET (autovacuum_vacuum_cost_delay = 5);

-- Table structure for table ls_nodes_log
DROP TABLE IF EXISTS ls_prefixes_log;
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

--
-- END
--

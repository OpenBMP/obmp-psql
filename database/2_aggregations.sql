-- -----------------------------------------------------------------------
-- Copyright (c) 2018 Cisco Systems, Inc. and others.  All rights reserved.
-- Copyright (c) 2018 Tim Evens (tim@evensweb.com).  All rights reserved.
--
-- BEGIN Aggregation/Statistics Schema
-- -----------------------------------------------------------------------

-- advertisement and withdrawal changes by peer
DROP TABLE IF EXISTS stats_chg_bypeer;
CREATE TABLE stats_chg_bypeer (
	interval_time           timestamp(6)        without time zone NOT NULL,
	peer_hash_id            uuid                NOT NULL,
	updates                 bigint              NOT NULL DEFAULT 0,
	withdraws               bigint              NOT NULL DEFAULT 0
) WITH (autovacuum_enabled = false) TABLESPACE timeseries;

CREATE UNIQUE INDEX ON stats_chg_bypeer (interval_time,peer_hash_id);
CREATE INDEX ON stats_chg_bypeer (peer_hash_id);

-- convert to timescaledb
SELECT create_hypertable('stats_chg_bypeer', 'interval_time', chunk_time_interval => interval '6 hours');

-- advertisement and withdrawal changes by asn
DROP TABLE IF EXISTS stats_chg_byasn;
CREATE TABLE stats_chg_byasn (
	interval_time           timestamp(6)        without time zone NOT NULL,
	peer_hash_id            uuid                NOT NULL,
	origin_as               bigint              NOT NULL,
	updates                 bigint              NOT NULL DEFAULT 0,
	withdraws               bigint              NOT NULL DEFAULT 0
) WITH (autovacuum_enabled = false) TABLESPACE timeseries ;

CREATE UNIQUE INDEX ON stats_chg_byasn (interval_time,peer_hash_id,origin_as);
CREATE INDEX ON stats_chg_byasn (peer_hash_id);
CREATE INDEX ON stats_chg_byasn (origin_as);

-- convert to timescaledb
SELECT create_hypertable('stats_chg_byasn', 'interval_time', chunk_time_interval => interval '6 hours');

-- advertisement and withdrawal changes by prefix
DROP TABLE IF EXISTS stats_chg_byprefix;
CREATE TABLE stats_chg_byprefix (
	interval_time           timestamp(6)        without time zone NOT NULL,
	peer_hash_id            uuid                NOT NULL,
	prefix                  inet                NOT NULL,
	prefix_len              smallint            NOT NULL,
	updates                 bigint              NOT NULL DEFAULT 0,
	withdraws               bigint              NOT NULL DEFAULT 0
) WITH (autovacuum_enabled = false) TABLESPACE timeseries;

CREATE UNIQUE INDEX ON stats_chg_byprefix (interval_time,peer_hash_id,prefix);
CREATE INDEX ON stats_chg_byprefix (peer_hash_id);
CREATE INDEX ON stats_chg_byprefix (prefix);


-- convert to timescaledb
SELECT create_hypertable('stats_chg_byprefix', 'interval_time', chunk_time_interval => interval '6 hours');

--
-- Function to update the change stats tables (bypeer, byasn, and byprefix).
--    Will update the tables based on the last 5 minutes, not counting current minute.
--
CREATE OR REPLACE FUNCTION update_chg_stats(int_window interval)
	RETURNS void AS $$
BEGIN
  -- bypeer updates
  INSERT INTO stats_chg_bypeer (interval_time, peer_hash_id, withdraws,updates)
	SELECT
	       to_timestamp((extract(epoch from timestamp)::bigint / 60)::bigint * 60) at time zone 'utc' as IntervalTime,
	       peer_hash_id,
	       count(case WHEN ip_rib_log.iswithdrawn = true THEN 1 ELSE null END) as withdraws,
	       count(case WHEN ip_rib_log.iswithdrawn = false THEN 1 ELSE null END) as updates
	     FROM ip_rib_log
	     WHERE timestamp >= to_timestamp((extract(epoch from now())::bigint / 60)::bigint * 60) at time zone 'utc' - int_window
	           AND timestamp < to_timestamp((extract(epoch from now())::bigint / 60)::bigint * 60) at time zone 'utc'    -- current minute
	     GROUP BY IntervalTime,peer_hash_id
	ON CONFLICT (interval_time,peer_hash_id) DO UPDATE
		SET updates=excluded.updates, withdraws=excluded.withdraws;

  -- byasn updates
  INSERT INTO stats_chg_byasn (interval_time, peer_hash_id, origin_as,withdraws,updates)
	SELECT
	       to_timestamp((extract(epoch from timestamp)::bigint / 60)::bigint * 60) at time zone 'utc' as IntervalTime,
	       peer_hash_id,origin_as,
	       count(case WHEN ip_rib_log.iswithdrawn = true THEN 1 ELSE null END) as withdraws,
	       count(case WHEN ip_rib_log.iswithdrawn = false THEN 1 ELSE null END) as updates
	     FROM ip_rib_log
	     WHERE timestamp >= to_timestamp((extract(epoch from now())::bigint / 60)::bigint * 60) at time zone 'utc' - int_window
	           AND timestamp < to_timestamp((extract(epoch from now())::bigint / 60)::bigint * 60) at time zone 'utc'   -- current minute
	     GROUP BY IntervalTime,peer_hash_id,origin_as
	ON CONFLICT (interval_time,peer_hash_id,origin_as) DO UPDATE
		SET updates=excluded.updates, withdraws=excluded.withdraws;

  -- byprefix updates
  INSERT INTO stats_chg_byprefix (interval_time, peer_hash_id, prefix, prefix_len, withdraws,updates)
	SELECT
	       to_timestamp((extract(epoch from timestamp)::bigint / 120)::bigint * 120) at time zone 'utc' as IntervalTime,
	       peer_hash_id,prefix,prefix_len,
	       count(case WHEN ip_rib_log.iswithdrawn = true THEN 1 ELSE null END) as withdraws,
	       count(case WHEN ip_rib_log.iswithdrawn = false THEN 1 ELSE null END) as updates
	     FROM ip_rib_log
	     WHERE timestamp >= to_timestamp((extract(epoch from now())::bigint / 120)::bigint * 120) at time zone 'utc' - int_window
	           AND timestamp < to_timestamp((extract(epoch from now())::bigint / 120)::bigint * 120) at time zone 'utc'   -- current minute
	     GROUP BY IntervalTime,peer_hash_id,prefix,prefix_len
	ON CONFLICT (interval_time,peer_hash_id,prefix) DO UPDATE
		SET updates=excluded.updates, withdraws=excluded.withdraws;

END;
$$ LANGUAGE plpgsql;

-- Origin ASN stats
DROP TABLE IF EXISTS stats_ip_origins;
CREATE TABLE stats_ip_origins (
	id                      bigserial           NOT NULL,
	interval_time           timestamp(6)        without time zone NOT NULL,
	asn                     bigint              NOT NULL,
	v4_prefixes             int                 NOT NULL DEFAULT 0,
	v6_prefixes             int                 NOT NULL DEFAULT 0,
	v4_with_rpki            int                 NOT NULL DEFAULT 0,
	v6_with_rpki            int                 NOT NULL DEFAULT 0,
	v4_with_irr             int                 NOT NULL DEFAULT 0,
	v6_with_irr             int                 NOT NULL DEFAULT 0
) TABLESPACE timeseries;

CREATE UNIQUE INDEX ON stats_ip_origins (interval_time,asn);


-- convert to timescaledb
SELECT create_hypertable('stats_ip_origins', 'interval_time', chunk_time_interval => interval '1 month');

--
-- Function to update the global IP rib and the prefix counts by origin stats. This includes RPKI and IRR counts
--
CREATE OR REPLACE FUNCTION update_global_ip_rib()
	RETURNS void AS $$
BEGIN

	-- mark existing records to be deleted
	UPDATE global_ip_rib SET should_delete = true;

    -- Load the global rib with the current state rib
    INSERT INTO global_ip_rib (prefix,prefix_len,recv_origin_as,timestamp,num_peers)
        SELECT prefix,prefix_len,origin_as,max(timestamp),count(peer_hash_id)
          FROM ip_rib
          WHERE origin_as != 0 AND origin_as != 23456 AND iswithdrawn = false
          GROUP BY prefix,prefix_len,origin_as
      ON CONFLICT (prefix,recv_origin_as)
        DO UPDATE SET should_delete=false, num_peers=excluded.num_peers;

    -- purge older records marked for deletion and if they are older than 2 hours
    DELETE FROM global_ip_rib where should_delete = true and timestamp < now () - interval '2 hours';

    -- Update IRR
    UPDATE global_ip_rib r SET irr_origin_as=i.origin_as,irr_source=i.source
        FROM info_route i
        WHERE  r.timestamp >= now() - interval '2 hour' and i.prefix = r.prefix;

    -- Update RPKI entries - Limit query to only update what has changed in the last 2 hours
    --    NOTE: The global_ip_rib table should have current times when first run (new table).
    --          This will result in this query taking a while. After first run, it shouldn't take
    --          as long.
     UPDATE global_ip_rib r SET rpki_origin_as=p.origin_as
         FROM rpki_validator p
 		WHERE r.timestamp >= now() - interval '2 hour' AND p.prefix >>= r.prefix AND r.prefix_len >= p.prefix_len
 		    AND r.prefix_len <= p.prefix_len_max;

	-- Update again with exact match if possible
	UPDATE global_ip_rib r SET rpki_origin_as=p.origin_as
	FROM rpki_validator p
	WHERE r.timestamp >= now() - interval '2 hour'
	  AND p.prefix >>= r.prefix AND r.prefix_len >= p.prefix_len
	  AND r.prefix_len <= p.prefix_len_max
	  AND r.recv_origin_as = p.origin_as;

     -- Origin stats (originated v4/v6 with IRR and RPKI counts)
     INSERT INTO stats_ip_origins (interval_time,asn,v4_prefixes,v6_prefixes,
               v4_with_rpki,v6_with_rpki,v4_with_irr,v6_with_irr)
       SELECT to_timestamp((extract(epoch from now())::bigint / 3600)::bigint * 3600),
             recv_origin_as,
             sum(case when family(prefix) = 4 THEN 1 ELSE 0 END) as v4_prefixes,
             sum(case when family(prefix) = 6 THEN 1 ELSE 0 END) as v6_prefixes,
             sum(case when rpki_origin_as > 0 and family(prefix) = 4 THEN 1 ELSE 0 END) as v4_with_rpki,
             sum(case when rpki_origin_as > 0 and family(prefix) = 6 THEN 1 ELSE 0 END) as v6_with_rpki,
             sum(case when irr_origin_as > 0 and family(prefix) = 4 THEN 1 ELSE 0 END) as v4_with_irr,
             sum(case when irr_origin_as > 0 and family(prefix) = 6 THEN 1 ELSE 0 END) as v6_with_irr
         FROM global_ip_rib
         GROUP BY recv_origin_as
       ON CONFLICT (interval_time,asn) DO UPDATE SET v4_prefixes=excluded.v4_prefixes,
             v6_prefixes=excluded.v6_prefixes,
             v4_with_rpki=excluded.v4_with_rpki,
             v6_with_rpki=excluded.v6_with_rpki,
             v4_with_irr=excluded.v4_with_irr,
             v6_with_irr=excluded.v6_with_irr;


END;
$$ LANGUAGE plpgsql;


-- Peer rib counts
DROP TABLE IF EXISTS stats_peer_rib;
CREATE TABLE stats_peer_rib (
	interval_time           timestamp(6)        without time zone NOT NULL,
	peer_hash_id            uuid                NOT NULL,
	v4_prefixes             int                 NOT NULL DEFAULT 0,
	v6_prefixes             int                 NOT NULL DEFAULT 0
) TABLESPACE timeseries;

CREATE UNIQUE INDEX ON stats_peer_rib (interval_time,peer_hash_id);
CREATE INDEX ON stats_peer_rib (peer_hash_id);


-- convert to timescaledb
SELECT create_hypertable('stats_peer_rib', 'interval_time', chunk_time_interval => interval '1 month');

--
-- Function to update the per-peer RIB prefix counts
--    This currently is only counting unicast IPv4/Ipv6
--
CREATE OR REPLACE FUNCTION update_peer_rib_counts()
	RETURNS void AS $$
BEGIN
     -- Per peer rib counts - every 15 minutes
     INSERT INTO stats_peer_rib (interval_time,peer_hash_id,v4_prefixes,v6_prefixes)
       SELECT to_timestamp((extract(epoch from now())::bigint / 900)::bigint * 900),
             peer_hash_id,
             sum(CASE WHEN isIPv4 = true THEN 1 ELSE 0 END) AS v4_prefixes,
             sum(CASE WHEN isIPv4 = false THEN 1 ELSE 0 END) as v6_prefixes
         FROM ip_rib
         WHERE isWithdrawn = false
         GROUP BY peer_hash_id
       ON CONFLICT (interval_time,peer_hash_id) DO UPDATE SET v4_prefixes=excluded.v4_prefixes,
             v6_prefixes=excluded.v6_prefixes;
END;
$$ LANGUAGE plpgsql;

-- Peer past updates counts
DROP TABLE IF EXISTS stats_peer_update_counts;
CREATE TABLE stats_peer_update_counts (
	interval_time           timestamp(6)        without time zone NOT NULL,
	peer_hash_id            uuid                NOT NULL,
	advertise_avg           int                 NOT NULL DEFAULT 0,
	advertise_min           int                 NOT NULL DEFAULT 0,
	advertise_max           int                 NOT NULL DEFAULT 0,
	withdraw_avg            int                 NOT NULL DEFAULT 0,
	withdraw_min            int                 NOT NULL DEFAULT 0,
	withdraw_max            int                 NOT NULL DEFAULT 0
) TABLESPACE timeseries;

CREATE UNIQUE INDEX ON stats_peer_update_counts (interval_time,peer_hash_id);
CREATE INDEX ON stats_peer_update_counts (peer_hash_id);


-- convert to timescaledb
SELECT create_hypertable('stats_peer_update_counts', 'interval_time', chunk_time_interval => interval '1 month');

--
-- Function snapshots the avg/min/max advertisements and withdrawals for each peer
--    for the given interval in seconds
--
CREATE OR REPLACE FUNCTION update_peer_update_counts(interval_secs int)
	RETURNS void AS $$
BEGIN
     -- Per peer update counts for interval
     INSERT INTO stats_peer_update_counts (interval_time,peer_hash_id,
                        advertise_avg,advertise_min,advertise_max,
                        withdraw_avg,withdraw_min,withdraw_max)
       SELECT to_timestamp((extract(epoch from now())::bigint / interval_secs)::bigint * interval_secs),
             peer_hash_id,
             avg(updates), min(updates), max(updates),
             avg(withdraws), min(withdraws), max(withdraws)
         FROM stats_chg_bypeer
         WHERE interval_time >= now() - (interval_secs::text || ' seconds')::interval
         GROUP BY peer_hash_id
       ON CONFLICT (interval_time,peer_hash_id) DO UPDATE SET advertise_avg=excluded.advertise_avg,
             advertise_min=excluded.advertise_min,
             advertise_max=excluded.advertise_max,
             withdraw_avg=excluded.withdraw_avg,
             withdraw_min=excluded.withdraw_min,
             withdraw_max=excluded.withdraw_max;
END;
$$ LANGUAGE plpgsql;
--
-- END
--
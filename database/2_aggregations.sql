-- -----------------------------------------------------------------------
-- Copyright (c) 2018 Cisco Systems, Inc. and others.  All rights reserved.
-- Copyright (c) 2018 Tim Evens (tim@evensweb.com).  All rights reserved.
--
-- BEGIN Aggregation/Statistics Schema
-- -----------------------------------------------------------------------

-- advertisement and withdrawal changes by peer
DROP TABLE IF EXISTS stats_chg_bypeer
CREATE TABLE stats_chg_bypeer (
	interval_time           DateTime CODEC(DoubleDelta, NONE),
	peer_hash_id            UUID,
	updates                 UInt64 DEFAULT 0,
	withdraws               UInt64 DEFAULT 0
)
ENGINE = MergeTree
PARTITION BY toStartOfDay(interval_time)
ORDER BY interval_time
TTL interval_time + toIntervalDay(30)


-- advertisement and withdrawal changes by asn
DROP TABLE IF EXISTS stats_chg_byasn
CREATE TABLE stats_chg_byasn (
	interval_time           DateTime CODEC(DoubleDelta, NONE),
	peer_hash_id            UUID,
	origin_as               UInt64,
	updates                 UInt64 DEFAULT 0,
	withdraws               UInt64 DEFAULT 0
)
ENGINE = MergeTree
PARTITION BY toStartOfDay(interval_time)
ORDER BY interval_time
TTL interval_time + toIntervalDay(30)


-- advertisement and withdrawal changes by prefix
DROP TABLE IF EXISTS stats_chg_byprefix
CREATE TABLE stats_chg_byprefix (
	interval_time           DateTime CODEC(DoubleDelta, NONE),
	peer_hash_id            UUID,
	prefix                  String,
	prefix_len              UInt16,
	updates                 UInt64 DEFAULT 0,
	withdraws               UInt64 DEFAULT 0
)
ENGINE = MergeTree
PARTITION BY toStartOfDay(interval_time)
ORDER BY interval_time
TTL interval_time + toIntervalDay(30)


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
DROP TABLE IF EXISTS stats_ip_origins
CREATE TABLE stats_ip_origins (
	id                      Float64 DEFAULT (toFloat64(toDateTime64(now64(), 3)) + toFloat64(timestamp)) - 3200000000 CODEC(Gorilla, Default),
	interval_time           DateTime CODEC(DoubleDelta, NONE),
	asn                     UInt64,
	v4_prefixes             UInt32 DEFAULT 0,
	v6_prefixes             UInt32 DEFAULT 0,
	v4_with_rpki            UInt32 DEFAULT 0,
	v6_with_rpki            UInt32 DEFAULT 0,
	v4_with_irr             UInt32 DEFAULT 0,
	v6_with_irr             UInt32 DEFAULT 0
)
ENGINE = MergeTree
PARTITION BY toStartOfDay(interval_time)
ORDER BY interval_time
TTL interval_time + toIntervalDay(30)


--
-- Function to purge old withdrawn prefixes
--
CREATE OR REPLACE FUNCTION purge_global_ip_rib(
	older_than_time interval DEFAULT '4 hours'
)
	RETURNS void AS $$
BEGIN
	-- delete old withdrawn prefixes that we don't want to track anymore
	DELETE FROM global_ip_rib where iswithdrawn = true and timestamp < now () - older_than_time;

END;
$$ LANGUAGE plpgsql;

--
-- Function to update the global IP rib and the prefix counts by origin stats. This includes RPKI and IRR counts
--      max_interval            Max last query time interval to allow.  This is the duration that the function will go back to.
--
CREATE OR REPLACE FUNCTION update_global_ip_rib(max_interval interval DEFAULT '2 hour')
	RETURNS void AS $$
DECLARE
	execution_start timestamptz  := clock_timestamp();
	insert_count    int;
	start_time timestamptz := now();
BEGIN

	select time_bucket('5 minutes', timestamp - interval '5 minute') INTO start_time
	FROM global_ip_rib order by timestamp desc limit 1;

	IF start_time is null THEN
		start_time = time_bucket('5 minutes', now() - max_interval);
		raise INFO '-> Last query time is null, setting last query time within %', max_interval;
	ELSIF start_time < now() - max_interval THEN
	    start_time = time_bucket('5 minutes', now() - max_interval);
	    raise INFO '-> Last query time is greater than max % time, setting last query time', max_interval;
	ELSIF start_time > now() THEN
		start_time = time_bucket('5 minutes', now() - interval '15 minutes');
		raise INFO '-> Last query time is greater than current time, setting last query time to past 15 minutes';
	END IF;

	raise INFO 'Start time       : %', execution_start;
	raise INFO 'Last Query Time  : %', start_time;

	raise INFO '-> Updating changed prefixes ...';

	insert_count = 0;

	INSERT INTO global_ip_rib (prefix,prefix_len,recv_origin_as,
	                           iswithdrawn,timestamp,first_added_timestamp,num_peers,advertising_peers,withdrawn_peers)

			SELECT r.prefix,
			       max(r.prefix_len),
			       r.origin_as,
			       bool_and(r.iswithdrawn)                                             as isWithdrawn,
			       max(r.timestamp),
			       min(r.first_added_timestamp),
			       count(distinct r.peer_hash_id)                                      as total_peers,
			       count(distinct r.peer_hash_id) FILTER (WHERE r.iswithdrawn = False) as advertising_peers,
			       count(distinct r.peer_hash_id) FILTER (WHERE r.iswithdrawn = True)  as withdrawn_peers
			FROM ip_rib r
			WHERE
			  (timestamp >= start_time OR first_added_timestamp >= start_time)
			  AND origin_as != 23456
			GROUP BY r.prefix, r.origin_as
			ON CONFLICT (prefix,recv_origin_as)
				DO UPDATE SET timestamp=excluded.timestamp,
				              first_added_timestamp=excluded.first_added_timestamp,
				              iswithdrawn=excluded.iswithdrawn,
				              num_peers=excluded.num_peers,
				              advertising_peers=excluded.advertising_peers,
				              withdrawn_peers=excluded.withdrawn_peers;

	GET DIAGNOSTICS insert_count = row_count;
	raise INFO 'Rows updated   : %', insert_count;
	raise INFO 'Duration       : %', clock_timestamp() - execution_start;
	raise INFO 'Completion time: %', clock_timestamp();

	-- Update IRR
	raise INFO '-> Updating IRR info';
	UPDATE global_ip_rib r SET
		                       irr_origin_as=i.origin_as,
		                       irr_source=i.source,
		                       irr_descr=i.descr
	FROM info_route i
	WHERE  r.timestamp >= start_time and i.prefix = r.prefix;

	GET DIAGNOSTICS insert_count = row_count;
	raise INFO 'Rows updated   : %', insert_count;
	raise INFO 'Duration       : %', clock_timestamp() - execution_start;
	raise INFO 'Completion time: %', clock_timestamp();


	-- Update RPKI entries - Limit query to only update what has changed in interval time
	--    NOTE: The global_ip_rib table should have current times when first run (new table).
	--          This will result in this query taking a while. After first run, it shouldn't take
	--          as long.
	raise INFO '-> Updating RPKI info';
	UPDATE global_ip_rib r SET rpki_origin_as=p.origin_as
	FROM rpki_validator p
	WHERE r.timestamp >= start_time
	  AND p.prefix >>= r.prefix
	  AND r.prefix_len >= p.prefix_len
	  AND r.prefix_len <= p.prefix_len_max;

	GET DIAGNOSTICS insert_count = row_count;
	raise INFO 'Rows updated   : %', insert_count;
	raise INFO 'Duration       : %', clock_timestamp() - execution_start;


	raise INFO 'Completion time: %', clock_timestamp();

END;
$$ LANGUAGE plpgsql;

--
-- Function to to sync the global rib
--
CREATE OR REPLACE FUNCTION sync_global_ip_rib()
	RETURNS void AS $$
DECLARE
	execution_start timestamptz  := clock_timestamp();
	insert_count    int;
	start_time timestamptz := now();
BEGIN

	raise INFO 'Start time       : %', execution_start;

	INSERT INTO global_ip_rib (prefix,prefix_len,recv_origin_as,
	                           iswithdrawn,timestamp,first_added_timestamp,num_peers,advertising_peers,withdrawn_peers)

	SELECT r.prefix,
	       max(r.prefix_len),
	       r.origin_as,
	       bool_and(r.iswithdrawn)                                             as isWithdrawn,
	       max(r.timestamp),
	       min(r.first_added_timestamp),
	       count(distinct r.peer_hash_id)                                      as total_peers,
	       count(distinct r.peer_hash_id) FILTER (WHERE r.iswithdrawn = False) as advertising_peers,
	       count(distinct r.peer_hash_id) FILTER (WHERE r.iswithdrawn = True)  as withdrawn_peers
	FROM ip_rib r
	WHERE origin_as != 23456
	GROUP BY r.prefix, r.origin_as
	ON CONFLICT (prefix,recv_origin_as)
		DO UPDATE SET timestamp=excluded.timestamp,
		              first_added_timestamp=excluded.first_added_timestamp,
		              iswithdrawn=excluded.iswithdrawn,
		              num_peers=excluded.num_peers,
		              advertising_peers=excluded.advertising_peers,
		              withdrawn_peers=excluded.withdrawn_peers;

	GET DIAGNOSTICS insert_count = row_count;
	raise INFO 'Rows updated   : %', insert_count;
	raise INFO 'Duration       : %', clock_timestamp() - execution_start;
	raise INFO 'Completion time: %', clock_timestamp();

	-- Update IRR
	raise INFO '-> Updating IRR info';
	UPDATE global_ip_rib r SET
		                       irr_origin_as=i.origin_as,
		                       irr_source=i.source,
		                       irr_descr=i.descr
	FROM info_route i
	WHERE  i.prefix = r.prefix;

	GET DIAGNOSTICS insert_count = row_count;
	raise INFO 'Rows updated   : %', insert_count;
	raise INFO 'Duration       : %', clock_timestamp() - execution_start;
	raise INFO 'Completion time: %', clock_timestamp();


	-- Update RPKI entries - Limit query to only update what has changed in interval time
	--    NOTE: The global_ip_rib table should have current times when first run (new table).
	--          This will result in this query taking a while. After first run, it shouldn't take
	--          as long.
	raise INFO '-> Updating RPKI info';
	UPDATE global_ip_rib r SET rpki_origin_as=p.origin_as
	FROM rpki_validator p
	WHERE
	  p.prefix >>= r.prefix
	  AND r.prefix_len >= p.prefix_len
	  AND r.prefix_len <= p.prefix_len_max;

	GET DIAGNOSTICS insert_count = row_count;
	raise INFO 'Rows updated   : %', insert_count;
	raise INFO 'Duration       : %', clock_timestamp() - execution_start;


	raise INFO 'Completion time: %', clock_timestamp();

END;
$$ LANGUAGE plpgsql;


--
-- Function to update the origin stats.
--      int_time                Interval/window time to check for changed RIB entries.
--
CREATE OR REPLACE FUNCTION update_origin_stats(
	int_time interval DEFAULT '30 minutes'
)
	RETURNS void AS $$
BEGIN

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
DROP TABLE IF EXISTS stats_peer_rib
CREATE TABLE stats_peer_rib (
	interval_time           DateTime CODEC(DoubleDelta, NONE),
	peer_hash_id            UUID,
	v4_prefixes             UInt32 DEFAULT 0,
	v6_prefixes             UInt32 DEFAULT 0
)
ENGINE = MergeTree
PARTITION BY toStartOfDay(interval_time)
ORDER BY interval_time
TTL interval_time + toIntervalDay(30)


--
-- Function to update the per-peer RIB prefix counts
--    This currently is only counting unicast IPv4/Ipv6
--
CREATE OR REPLACE FUNCTION update_peer_rib_counts()
	RETURNS void AS $$
BEGIN
     -- Per peer rib counts - every 15 minutes
     INSERT INTO stats_peer_rib (interval_time,peer_hash_id,v4_prefixes,v6_prefixes)
       SELECT  time_bucket('15 minutes', now()),
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
DROP TABLE IF EXISTS stats_peer_update_counts
CREATE TABLE stats_peer_update_counts (
	interval_time           DateTime CODEC(DoubleDelta, NONE),
	peer_hash_id            UUID,
	advertise_avg           UInt32 DEFAULT 0,
	advertise_min           UInt32 DEFAULT 0,
	advertise_max           UInt32 DEFAULT 0,
	withdraw_avg            UInt32 DEFAULT 0,
	withdraw_min            UInt32 DEFAULT 0,
	withdraw_max            UInt32 DEFAULT 0
)
ENGINE = MergeTree
PARTITION BY toStartOfDay(interval_time)
ORDER BY interval_time
TTL interval_time + toIntervalDay(30)


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

--
-- Peer kpi's, used for ranking internet peers
--
DROP VIEW IF EXISTS v_peers_kpi;
CREATE VIEW v_peers_kpi AS
  SELECT p.peer_hash_id,max(p.peerbgpid),
      CASE last(ispeeripv4, lastmodified) WHEN true THEN 'IPv4' ELSE 'IPv6' END as peer_ipv,
      max(RouterName) as "RouterName",
      max(PeerName) as "PeerName",
      max(PeerIP) as "PeerIP",
      max(PeerASN) as "PeerASN",
      max(left(as_name, 28)) as "AS Name",
      max(peer_state) as "State",
      CASE last(isPeerIPv4, LastModified) WHEN true THEN
        CASE WHEN last(v4_prefixes,interval_time) > 700000
              THEN 1000
            WHEN last(v4_prefixes, interval_time) > 300000
              THEN 500
            WHEN last(v4_prefixes, interval_time) > 100000
              THEN 100
            WHEN last(v4_prefixes, interval_time) > 9000
              THEN 10
            ELSE 1
          END
        ELSE
            CASE WHEN last(v6_prefixes, interval_time) > 50000
              THEN 1000
            WHEN last(v6_prefixes, interval_time) > 20000
              THEN 500
            WHEN last(v6_prefixes, interval_time) > 10000
              THEN 100
            WHEN last(v6_prefixes, interval_time) > 1000
              THEN 10
            ELSE 1
          END
        END as rib_score,
      CASE WHEN last(p.ispeeripv4,LastModified) THEN last(v4_prefixes, interval_time) ELSE last(v6_prefixes, interval_time) END as "Prefixes",
      CASE last(isPeerIPv4, LastModified) WHEN true THEN
            CASE WHEN max(avg_updates) > 1200 THEN -500
                WHEN max(avg_updates) > 100 THEN 1000
                ELSE -100 END
        ELSE
            CASE WHEN max(avg_updates) > 1200 THEN -500
                WHEN max(avg_updates) >= 10 THEN 1000
                ELSE -100 END

      END as advertisements_score,

      CASE last(isPeerIPv4, LastModified) WHEN true THEN
             CASE WHEN max(avg_withdraws) > 150 THEN -500
                WHEN max(avg_withdraws) > 10 THEN 1000
                ELSE -100 END
          ELSE
             CASE WHEN max(avg_withdraws) > 100 THEN -100
                WHEN max(avg_withdraws) >= 1 THEN 1000
                ELSE -100 END

       END as withdraws_score,

      (SELECT count(distinct asn_right)
        FROM as_path_analysis
        where asn = max(p.peerasn) and asn_left = 0) as connections,
      (select count(distinct asn_right)
        FROM as_path_analysis
        where asn = max(p.peerasn) and asn_left > 0 and asn_right > 0
            and timestamp >= now() - interval '2 weeks') as transit_connections,
      max(avg_withdraws) as withdraw_avg, max(avg_updates) as updates_avg,
      max(LastModified) as "LastModified",

      -- This column finds the longest matched prefix for the source and returns the origin_as for it
      (select origin_as from ip_rib
            WHERE peer_hash_id in ('a7dbc2e9-6a25-1993-4eb5-1facbf440258',
                                   '0015eb77-a338-65e9-5458-d6b6f01816bc',
                                   '309b2a71-1611-702e-bf2b-ca6ea98967e7')
                AND isipv4 = last(p.ispeeripv4, p.lastmodified)
                AND prefix >>= last(p.peerip, p.lastmodified)
            ORDER BY prefix_len desc limit 1) as expected_origin_as,

      CASE WHEN max(peer_state) = 'up' THEN 1 ELSE 0 END as stateBool
  FROM v_peers p
    LEFT JOIN stats_peer_rib s ON (p.peer_hash_id = s.peer_hash_id
            AND s.interval_time >= now() - interval '40 minutes')
    LEFT JOIN (SELECT
            peer_hash_id,avg(advertise_avg)::int as avg_updates,avg(withdraw_avg)::int as avg_withdraws
        FROM stats_peer_update_counts
        WHERE interval_time >= now() - interval '2 day'
        GROUP BY peer_hash_id
      ) u ON (u.peer_hash_id = p.peer_hash_id)
  GROUP BY p.peer_hash_id;

--
-- Peer rank table
--
DROP TABLE IF EXISTS peer_rank;
CREATE TABLE peer_rank (
  	peer_hash_id            uuid                NOT NULL,
    rank                    int                 NOT NULL DEFAULT 0,
    peer_ip_ver             varchar(8),
    router_name             varchar(256),
    peer_name               varchar(256),
    peer_asn                bigint,
    peer_as_name            varchar(256),
    peer_ip                 inet,
    expected_peer_asn       bigint,
    state                   varchar(8),
    rib_weight              int                 DEFAULT 0,
    advertisements_weight   int                 DEFAULT 0,
    withdraws_weight        int                 DEFAULT 0,
    connections             int,
    transit_connections     int,
    should_delete           boolean              DEFAULT false
);
CREATE UNIQUE INDEX ON peer_rank (peer_hash_id);
ALTER TABLE routers SET (autovacuum_analyze_threshold = 50);

--
-- Get list of peers by ordered by rank in terms of best to use for security monitoring
--
CREATE OR REPLACE FUNCTION update_peer_ranks()
    RETURNS void AS $$
BEGIN
    UPDATE peer_rank SET should_delete = true;
    INSERT INTO peer_rank (peer_hash_id,rank,peer_ip_ver,router_name,peer_name,peer_asn,
                           peer_as_name,peer_ip,expected_peer_asn,state,
                           rib_score,advertisements_score,withdraws_score,connections,transit_connections)
        SELECT peer_hash_id,
               DENSE_RANK() OVER (PARTITION BY peer_ipv
                                  ORDER BY ((transit_connections * 100) + connections + (rib_score * 10)
                                            + (advertisements_score * 100) + (withdraws_score * 100) +
                                            (CASE WHEN "PeerASN" = expected_origin_as THEN 1000 ELSE 0 END) +
                                            (CASE WHEN "State"='down' THEN -1000000 ELSE 1000000 END )) desc) as rank,
               peer_ipv, "RouterName","PeerName","PeerASN","AS Name","PeerIP", expected_origin_as, "State",
              rib_score,advertisements_score,withdraws_score,connections,transit_connections
          FROM v_peers_kpi
    ON CONFLICT (peer_hash_id) DO UPDATE
      SET rank=excluded.rank,state=excluded.state, expected_peer_asn=excluded.expected_peer_asn,
           rib_score=excluded.rib_score,advertisements_score=excluded.advertisements_score,withdraws_score=excluded.withdraws_score,
           connections=excluded.connections,transit_connections=excluded.transit_connections,
           should_delete=false;

    DELETE FROM peer_rank where should_delete = true;
END;
$$ LANGUAGE plpgsql;

-- SELECT update_peer_ranks();

-- select rank,peer_ip_ver,router_name,peer_name,peer_as_name,peer_ip,
--         CASE WHEN expected_peer_asn = peer_asn THEN 'Match' ELSE 'No Match' END as peer_asn_match,
--       state,rib_score,advertisements_score,withdraws_score,connections,transit_connections
--     from peer_rank where peer_ip_ver = 'IPv4' order by rank ;
--
-- Per peer class based on past stats
--
DROP VIEW IF EXISTS v_peers_class;
DROP VIEW IF EXISTS v_peers_kpi;
CREATE VIEW v_peers_kpi AS
  SELECT p.peer_hash_id,max(p.peerbgpid),
      CASE last(ispeeripv4, lastmodified) WHEN true THEN 'IPv4' ELSE 'IPv6' END as peer_ipv,
      max(RouterName) as "RouterName",
      max(PeerName) as "PeerName",
      max(PeerIP) as "PeerIP",
      max(PeerASN) as "PeerASN",
      max(left(as_name, 28)) as "AS Name",
      max(peer_state) as "State",
      CASE last(isPeerIPv4, LastModified) WHEN true THEN
        CASE WHEN last(v4_prefixes,interval_time) > 700000
              THEN 10000
            WHEN last(v4_prefixes, interval_time) > 300000
              THEN 5000
            WHEN last(v4_prefixes, interval_time) > 100000
              THEN 1000
            WHEN last(v4_prefixes, interval_time) > 9000
              THEN 100
            ELSE 10
          END
        ELSE
            CASE WHEN last(v6_prefixes, interval_time) > 50000
              THEN 10000
            WHEN last(v6_prefixes, interval_time) > 20000
              THEN 5000
            WHEN last(v6_prefixes, interval_time) > 10000
              THEN 1000
            WHEN last(v6_prefixes, interval_time) > 1000
              THEN 100
            ELSE 10
          END
        END as rib_weight,
      CASE WHEN last(p.ispeeripv4,LastModified) THEN last(v4_prefixes, interval_time) ELSE last(v6_prefixes, interval_time) END as "Prefixes",
      CASE last(isPeerIPv4, LastModified) WHEN true THEN
            CASE WHEN max(avg_updates) > 1200 THEN -500
                WHEN max(avg_updates) > 100 THEN 1000
                ELSE -100 END
        ELSE
            CASE WHEN max(avg_updates) > 1200 THEN -500
                WHEN max(avg_updates) >= 10 THEN 1000
                ELSE -100 END

      END as advertisements_weight,

      CASE last(isPeerIPv4, LastModified) WHEN true THEN
             CASE WHEN max(avg_withdraws) > 150 THEN -500
                WHEN max(avg_withdraws) > 10 THEN 1000
                ELSE -100 END
          ELSE
             CASE WHEN max(avg_withdraws) > 100 THEN -100
                WHEN max(avg_withdraws) >= 1 THEN 1000
                ELSE -100 END

       END as withdraws_weight,

      (SELECT count(distinct asn_right)
        FROM as_path_analysis
        where asn = max(p.peerasn) and asn_left = 0) as connections,
      (select count(distinct asn_right)
        FROM as_path_analysis
        where asn = max(p.peerasn) and asn_left > 0 and asn_right > 0
            and timestamp >= now() - interval '2 weeks') as transit_connections,
      max(avg_withdraws) as withdraw_avg, max(avg_updates) as updates_avg,
      max(LastModified) as "LastModified",

      -- This column finds the longest matched prefix for the source and returns the origin_as for it
      (select origin_as from ip_rib
            WHERE peer_hash_id in ('a7dbc2e9-6a25-1993-4eb5-1facbf440258',
                                   '0015eb77-a338-65e9-5458-d6b6f01816bc',
                                   '309b2a71-1611-702e-bf2b-ca6ea98967e7')
                AND isipv4 = last(p.ispeeripv4, p.lastmodified)
                AND prefix >>= last(p.peerip, p.lastmodified)
            ORDER BY prefix_len desc limit 1) as expected_origin_as,

      CASE WHEN max(peer_state) = 'up' THEN 1 ELSE 0 END as stateBool
  FROM v_peers p
    LEFT JOIN stats_peer_rib s ON (p.peer_hash_id = s.peer_hash_id
            AND s.interval_time >= now() - interval '40 minutes')
    LEFT JOIN (SELECT
            peer_hash_id,avg(advertise_avg)::int as avg_updates,avg(withdraw_avg)::int as avg_withdraws
        FROM stats_peer_update_counts
        WHERE interval_time >= now() - interval '2 day'
        GROUP BY peer_hash_id
      ) u ON (u.peer_hash_id = p.peer_hash_id)
  GROUP BY p.peer_hash_id;

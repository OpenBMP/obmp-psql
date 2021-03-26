-- -----------------------------------------------------------------------
-- Copyright (c) 2020 Cisco Systems, Inc. and others.  All rights reserved.
-- -----------------------------------------------------------------------

-- -----------------------------------------------------
-- Tables and base, non dependant functions
-- -----------------------------------------------------

-- Table structure for webex communities
DROP TABLE IF EXISTS wbx_communities;
CREATE TABLE wbx_communities (
	community       varchar(100)          NOT NULL,
	role            varchar(100)          NOT NULL,
	description     varchar(255)          NOT NULL,
  PRIMARY KEY (community)
);
CREATE INDEX ON wbx_communities (community);
CREATE INDEX ON wbx_communities (role);

INSERT INTO wbx_communities VALUES
	('13445:120', 'Special Action', 'LP assignment = 120'),
	('13445:170', 'Special Action', 'LP assignment = 170'),
	('13445:200', 'Special Action', 'LP assignment = 200'),
	('13445:300', 'Special Action', 'LP assignment = 300'),
	('13445:400', 'Special Action', 'LP assignment = 400'),
	('13445:500', 'Special Action', 'LP assignment = 500'),
	('13445:600', 'Special Action', 'LP assignment = 600'),
	('13445:700', 'Special Action', 'LP assignment = 700'),
    ('13445:800', 'Special Action', 'LP assignment = 800'),
    ('13445:900', 'Special Action', 'LP assignment = 900'),
	('13445:666', 'Special Action', 'Destination black hole'),
	('13445:677', 'Special Action', 'Drop - Theater only'),
	('13445:777', 'Special Action', 'Pass'),

	('13445:1000', 'Externals', 'SFI'),
	('13445:1010', 'Externals', 'Transit'),
	('13445:1020', 'Externals', 'Customer'),
	('13445:1021', 'Externals', 'Enterprise Peering'),
	('13445:1040', 'Externals', 'Connected'),
	('13445:1050', 'Externals', 'Static'),
	('13445:1060', 'Externals', 'Cloud Provider'),
	('13445:21534', 'Externals', 'Broadsoft'),
	('13445:1090', 'Externals', 'SIP Provider'),
	('13445:30000', 'Externals', 'Cisco corp (ASN 109)'),
	('64535:7224', 'Externals', 'AWS Private VPC'),

	('13445:20030', 'Service', 'SIP'),
	('13445:20040', 'Service', 'Ext Auth DNS A'),
	('13445:20041', 'Service', 'Ext Auth DNS B'),

	('65535:22001', 'WebEx Services', 'Network Monitoring (1000 Eyes) - Internal'),
	('13445:22001', 'WebEx Services', 'Network Monitoring (1000 Eyes) - External'),
	('65535:22010', 'WebEx Services', 'CCA legacy - Internal'),
	('13445:22010', 'WebEx Services', 'CCA legacy - External'),
	('65535:22011', 'WebEx Services', 'CCA UCRE - Internal'),
	('13445:22011', 'WebEx Services', 'CCA UCRE - External'),
	('65535:22012', 'WebEx Services', 'CCA Fedramp - Internal'),
    ('13445:22012', 'WebEx Services', 'CCA Fedramp - External'),
   	('65535:22020', 'WebEx Services', 'CMR Video - Internal'),
    ('13445:22020', 'WebEx Services', 'CMR Video - External'),
	('65535:22030', 'WebEx Services', 'PMP - Internal'),
    ('13445:22030', 'WebEx Services', 'PMP - External'),
  	('65535:22040', 'WebEx Services', 'Meeting/Jabber - Internal'),
    ('13445:22040', 'WebEx Services', 'Meeting/Jabber - External'),
  	('65535:22050', 'WebEx Services', 'Internet UCRE - Internal'),
    ('13445:22050', 'WebEx Services', 'Internet UCRE - External'),
	('65535:22060', 'WebEx Services', 'PSTN UCRE - Internal'),
    ('13445:22060', 'WebEx Services', 'PSTN UCRE - External'),
	('65535:22070', 'WebEx Services', 'Spark - Internal'),
    ('13445:22070', 'WebEx Services', 'Spark - External'),
	('65535:22999', 'WebEx Services', 'BTS/ATS - Internal'),
    ('13445:22999', 'WebEx Services', 'BTS/ATS - External'),

    ('13445:10000', 'Theater', 'US'),
    ('13445:10010', 'Theater', 'EU'),
	('13445:10020', 'Theater', 'Asia'),
	('13445:10030', 'Theater', 'IND'),
	('13445:10200', 'Theater', 'Australia'),

	('13445:2020', 'POP', 'AMS01'),
	('13445:2000', 'POP', 'AMS10'),
	('13445:2010', 'POP', 'BLR03'),
	('13445:2190', 'POP', 'DFW01'),
	('13445:2200', 'POP', 'DFW02'),
	('13445:2050', 'POP', 'DFW10'),
	('13445:2170', 'POP', 'HKG10'),
	('13445:2060', 'POP', 'IAD02'),
	('13445:2160', 'POP', 'JFK01'),
	('13445:2070', 'POP', 'JFK10'),
	('13445:2080', 'POP', 'LAX10'),
	('13445:2090', 'POP', 'LHR03'),
	('13445:2120', 'POP', 'NRT02'),
	('13445:2110', 'POP', 'NRT03'),
	('13445:2030', 'POP', 'ORD10'),
	('13445:2130', 'POP', 'SIN01'),
	('13445:2140', 'POP', 'SJC02'),
	('13445:2150', 'POP', 'SJC10'),
	('13445:2180', 'POP', 'SYD10'),
	('13445:2210', 'POP', 'SYD01'),
	('13445:2040', 'POP', 'YYZ01');

-- Peering aggreation table
DROP TABLE IF EXISTS wbx_peering;
CREATE TABLE wbx_peering (
     timestamp               timestamp(6)        without time zone default (now() at time zone 'utc') NOT NULL,
     peering_as             bigint,
     received_origins       int                 DEFAULT 0,
     received_prefixes      int                 DEFAULT 0,
     peering_type           varchar(40)         DEFAULT 'Direct',
	 datacenter             varchar(10),
	 router_name            varchar(128),
     nh                     inet                NOT NULL,

	 PRIMARY KEY (nh,peering_as)
);
CREATE INDEX ON wbx_peering (peering_as);

CREATE OR REPLACE FUNCTION update_wbx_peering()
	RETURNS void AS $$
DECLARE
	start_time TIMESTAMP(6) := now();
BEGIN
	INSERT INTO wbx_peering (peering_as,received_prefixes,received_origins,peering_type,datacenter,router_name,nh)

		SELECT peering_as,received_prefixes,received_origins,peering_type,
		       substring(l.local_router_name from 1 for 3) as DataCenter,l.local_router_name,nh

		FROM (SELECT  r.nh,
		              peering_as,
		              count(distinct r.prefix) as received_prefixes,
		              count(distinct r.origin_as) as received_origins,
		              CASE WHEN count(distinct r.origin_as) > 1 THEN 'Transit' ELSE 'Direct' END as peering_type
		      FROM (
			           SELECT nh,
			                  i.prefix,origin_as,
			                  cast(split_part(as_path, ' ', 2) AS int) as peering_as
			           FROM v_ip_routes i
			           WHERE iswithdrawn = FALSE
				         AND origin_as != 0
			             AND NOT (origin_as >= 64512 AND origin_as <= 65535)
				         AND communities ~ '( |^)13445:10[02][01]( |$)'
		           ) r
		      GROUP BY nh,peering_as) p
		    LEFT JOIN v_ls_prefixes l ON (l.prefix && p.nh)
		    LEFT JOIN info_asn a ON (a.asn = p.peering_as)
			WHERE not (l.local_router_name ~ '.*-(PE|CRT).*' AND l.prefix_len = 32)
		ORDER BY peering_as,dataCenter
	ON CONFLICT (nh,peering_as) DO UPDATE
		SET timestamp = start_time, peering_as = excluded.peering_as,
		    received_prefixes = excluded.received_prefixes, received_origins = excluded.received_origins,
		    peering_type = excluded.peering_type,datacenter = excluded.datacenter,
		    router_name = excluded.router_name, nh = excluded.nh;

	DELETE from wbx_peering where timestamp < start_time;
END;
$$ LANGUAGE plpgsql;


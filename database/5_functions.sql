-- -----------------------------------------------------------------------
-- Copyright (c) 2018 Cisco Systems, Inc. and others.  All rights reserved.
-- Copyright (c) 2018 Tim Evens (tim@evensweb.com).  All rights reserved.
--
-- BEGIN Functions
-- -----------------------------------------------------------------------

-- -----------------------------------------------------------------------------------------------
-- Utility functions
-- -----------------------------------------------------------------------------------------------

-- Function to display the size of tables
CREATE OR REPLACE FUNCTION show_table_info()
	RETURNS TABLE( oid oid,table_schema name,table_name name,row_estimate real,
				   total_bytes bigint,index_bytes bigint,
	               toast_bytes bigint,table_bytes bigint,total varchar(32),index varchar(32),
	               toast varchar(32),table_value varchar(32)
	              ) AS $$
	    SELECT *, pg_size_pretty(total_bytes) AS total,
                pg_size_pretty(index_bytes) AS INDEX,
                pg_size_pretty(toast_bytes) AS toast,
                pg_size_pretty(table_bytes) AS table_value
		  FROM (
			  SELECT *, total_bytes-index_bytes-COALESCE(toast_bytes,0) AS table_bytes FROM (
			      SELECT c.oid,nspname AS table_schema, relname AS TABLE_NAME,
			              c.reltuples AS row_estimate,
			              pg_total_relation_size(c.oid) AS total_bytes,
			              pg_indexes_size(c.oid) AS index_bytes,
			              pg_total_relation_size(reltoastrelid) AS toast_bytes
			          FROM pg_class c
			          LEFT JOIN pg_namespace n ON n.oid = c.relnamespace
			          WHERE relkind = 'r'
			  ) a
		) a;
	$$ LANGUAGE SQL;


-- Function to add partitions based on routers index
--    A new partition will be added to each table (currently ip_rib)
--    The routers index check constrain will be updated
-- CREATE OR REPLACE FUNCTION add_routers_partition()
-- 	RETURNS smallint AS $$
-- DECLARE
-- 	_parts smallint := 0;
-- BEGIN
--
-- 	select count(i.inhrelid) INTO _parts
--         from pg_catalog.pg_inherits i
--             join pg_catalog.pg_class cl on i.inhparent = cl.oid
--             join pg_catalog.pg_namespace nsp on cl.relnamespace = nsp.oid
--         where nsp.nspname = 'public'
--             and cl.relname = 'ip_rib';
--
-- 	-- Adjust the max as needed - right now a good default is 500
-- 	IF (_parts < 500) THEN
-- 		_parts := _parts + 1;
-- 		EXECUTE format('CREATE TABLE ip_rib_p%s PARTITION OF ip_rib
-- 		                    FOR VALUES IN (%s)', _parts, _parts);
--
-- 		EXECUTE format('CREATE UNIQUE INDEX ON ip_rib_p%s (hash_id)', _parts);
-- 		EXECUTE format('CREATE INDEX ON ip_rib_p%s (peer_hash_id)', _parts);
-- 		EXECUTE format('CREATE INDEX ON ip_rib_p%s (base_attr_hash_id)', _parts);
-- 		EXECUTE format('CREATE INDEX ON ip_rib_p%s (prefix)', _parts);
-- 		EXECUTE format('CREATE INDEX ON ip_rib_p%s (isWithdrawn)', _parts);
-- 		EXECUTE format('CREATE INDEX ON ip_rib_p%s (origin_as)', _parts);
-- 		EXECUTE format('CREATE INDEX ON ip_rib_p%s (prefix_bits)', _parts);
--
-- 		EXECUTE format('ALTER TABLE routers drop constraint routers_index_check, add CONSTRAINT routers_index_check CHECK (index <= %s)', _parts);
--
-- 		EXECUTE format('DROP TRIGGER IF EXISTS ins_ip_rib_p%s ON ip_rib_p%s',_parts,_parts);
--
-- 		EXECUTE format('CREATE TRIGGER ins_ip_rib_p%s AFTER INSERT ON ip_rib_p%s FOR EACH ROW EXECUTE PROCEDURE t_ip_rib_insert();',_parts, _parts);
--
-- 		EXECUTE format('DROP TRIGGER IF EXISTS upd_ip_rib_p%s ON ip_rib_p%s',_parts,_parts);
--
-- 		EXECUTE format('CREATE TRIGGER upd_ip_rib_p%s BEFORE UPDATE ON ip_rib_p%s FOR EACH ROW EXECUTE PROCEDURE t_ip_rib_update();',_parts, _parts);
--
-- 	END IF;
--
-- 	RETURN _parts;
-- END;
-- $$ LANGUAGE plpgsql;
--
-- add partitions
-- select add_routers_partition();
-- select add_routers_partition();
-- select add_routers_partition();
-- select add_routers_partition();
-- select add_routers_partition();
-- select add_routers_partition();
-- select add_routers_partition();
-- select add_routers_partition();
-- select add_routers_partition();
-- select add_routers_partition();


-- Function to find the next available router index
CREATE OR REPLACE FUNCTION get_next_router_index()
	RETURNS smallint AS $$
DECLARE
	_idx smallint := 0;
	_prev_idx smallint := 0;
BEGIN

	FOR _idx IN SELECT index FROM routers ORDER BY index LOOP
		IF (_prev_idx = 0) THEN
			_prev_idx := _idx;
			CONTINUE;

		ELSIF ( (_prev_idx + 1) != _idx) THEN
			-- Found available index
			RETURN _prev_idx + 1;
		END IF;

		_prev_idx := _idx;
	END LOOP;

	RETURN _prev_idx + 1;
END;
$$ LANGUAGE plpgsql;


--
-- END
--

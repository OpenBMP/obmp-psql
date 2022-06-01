#!/usr/bin/env python3
"""
  Copyright (c) 2020-2022 Cisco Systems, Inc. and others.  All rights reserved.

  .. moduleauthor:: Tim Evens <tievens@cisco.com>

    This script can be used to import either DB-IP City Lite CSV or MaxMind GeoIP2 City Lite CSV
    into OBMP postgres DB.

    Ref: DB-IP CSV Lite      - https://db-ip.com/db/download/ip-to-city-lite
         MaxMind Geo2IP Lite - https://dev.maxmind.com/geoip/geolocate-an-ip/databases?lang=en

    NOTE: MaxMind requires a login in order to download the CSV file.  DB-IP does not. DB-IP is therefore
         the default since it doesn't require a login.

  sudo apt install libpq-dev postgresql-common
  sudo pip3 install psycopg2
  sudo pip3 install netaddr
  sudo pip3 install click
"""
import logging
import click
import netaddr
import csv
import os.path
import psycopg2 as py
from time import time

# Set logger
logging.basicConfig(format='%(asctime)s | %(levelname)-8s | %(name)s[%(lineno)s] | %(message)s', level=logging.INFO)
LOG = logging.getLogger("geo-csv-to-psql")

SQL_INSERT = ("INSERT INTO geo_ip (family,ip,city,stateprov,country,latitude,longitude,"
              "timezone_offset, timezone_name, isp_name) VALUES ")

SQL_CONFLICT = (" ON CONFLICT (ip) DO UPDATE SET "
                " city=excluded.city, stateprov=excluded.stateprov,"
                " country=excluded.country, latitude=excluded.latitude, longitude=excluded.longitude;")


class dbHandler:
    """ Database handler class

        This class handles the database access methods.
    """

    #: Connection handle
    conn = None

    #: Cursor handle
    cursor = None

    #: Last query time in seconds (floating point)
    last_query_time = 0

    def __init__(self):
        pass

    def connectDb(self, user, pw, host, database):
        """
         Connect to database
        """
        try:
            self.conn = py.connect(user=user, password=pw,
                                   host=host,
                                   database=database)

            self.cursor = self.conn.cursor()

        except py.ProgrammingError as err:
            LOG.error("Connect failed: %s", str(err))
            raise err

    def close(self):
        """ Close the database connection """
        if (self.cursor):
            self.cursor.close()
            self.cursor = None

        if (self.conn):
            self.conn.close()
            self.conn = None

    def createTable(self, tableName, tableSchema, dropIfExists = True):
        """ Create table schema

            :param tablename:    The table name that is being created
            :param tableSchema:  Create table syntax as it would be to create it in SQL
            :param dropIfExists: True to drop the table, false to not drop it.

            :return: True if the table successfully was created, false otherwise
        """
        if (not self.cursor):
            LOG.error("Looks like psql is not connected, try to reconnect.")
            return False

        try:
            if (dropIfExists == True):
                self.cursor.execute("DROP TABLE IF EXISTS %s" % tableName)

            self.cursor.execute(tableSchema)

        except py.ProgrammingError as err:
            LOG.error("Failed to create table - %s", str(err))
            #raise err


        return True

    def createTable(self, tableName, tableSchema, dropIfExists = True):
        """ Create table schema

            :param tablename:    The table name that is being created
            :param tableSchema:  Create table syntax as it would be to create it in SQL
            :param dropIfExists: True to drop the table, false to not drop it.

            :return: True if the table successfully was created, false otherwise
        """
        if (not self.cursor):
            LOG.error("Looks like psql is not connected, try to reconnect.")
            return False

        try:
            if (dropIfExists == True):
                self.cursor.execute("DROP TABLE IF EXISTS %s" % tableName)

            self.cursor.execute(tableSchema)

        except py.ProgrammingError as err:
            LOG.error("Failed to create table - %s", str(err))
            #raise err
            return False

        return True

    def query(self, query, queryParams=None):
        """ Run a query and return the result set back

            :param query:       The query to run - should be a working SELECT statement
            :param queryParams: Dictionary of parameters to supply to the query for
                                variable substitution

            :return: Returns "None" if error, otherwise array list of rows
        """
        if (not self.cursor):
            LOG.error("Looks like psql is not connected, try to reconnect")
            return None

        try:
            startTime = time()

            if (queryParams):
                self.cursor.execute(query % queryParams)
            else:
                self.cursor.execute(query)

            self.last_query_time = time() - startTime

            rows = []

            while (True):
                result = self.cursor.fetchmany(size=10000)
                if (len(result) > 0):
                    rows += result
                else:
                    break

            return rows

        except py.ProgrammingError as err:
            LOG.error("query failed - %s", str(err))
            return None

    def queryNoResults(self, query, queryParams=None):
        """ Runs a query that would normally not have any results, such as insert, update, delete

            :param query:       The query to run - should be a working INSERT or UPDATE statement
            :param queryParams: Dictionary of parameters to supply to the query for
                                variable substitution

            :return: Returns True if successful, false if not.
        """
        if (not self.cursor):
            LOG.error("Looks like psql is not connected, try to reconnect")
            return None

        try:
            startTime = time()

            if (queryParams):
                self.cursor.execute(query % queryParams)
            else:
                self.cursor.execute(query)

            self.conn.commit()

            self.last_query_time = time() - startTime

            return True

        except py.ProgrammingError as err:
            LOG.error("query failed - %s", str(err))
            #print("   QUERY: %s", query)
            return None


def import_maxmind_csv(db, mm_loc, mm_ipv4, mm_ipv6):
    """
    import MaxMind City CSV Lite into OBMP postgres DB

    :param db:          Connected DB handler
    :param mm_loc:      GeoLite2-City-Locations-en.csv
    :param mm_ipv4:     GeoLite2-City-Blocks-IPv4.csv
    :param mm_ipv6:     GeoLite2-City-Blocks-IPv6.csv

    :return: True if success, False on Error
    """
    locations = {}

    if not mm_ipv4 and mm_ipv6:
        LOG.error("Missing at least one GeoLite2-City-Blocks-* CSV file names, need one or both.")
        return False

    elif mm_ipv4 and not os.path.isfile(mm_ipv4):
        LOG.error(f"IPv4 file '{mm_ipv4}' does not exist, cannot continue")
        return False

    elif mm_ipv6 and not os.path.isfile(mm_ipv6):
        LOG.error(f"IPv6 file '{mm_ipv6}' does not exist, cannot continue")
        return False

    # Load locations into memory
    # geoname_id,locale_code,continent_code,continent_name,country_iso_code,country_name,subdivision_1_iso_code,subdivision_1_name,subdivision_2_iso_code,subdivision_2_name,city_name,metro_code,time_zone,is_in_european_union
    with open(mm_loc, "r") as lf:
        lf.readline()
        line=lf.readline()
        while line and len(line) > 0:
            stripped_line=line.rstrip('\n').replace("'", "")
            r = [ '{}'.format(x) for x in list(csv.reader([stripped_line], delimiter=',', quotechar='"'))[0] ]

            key = r[0] # geoname_id
            entry = {
                "country": r[4],
                "stateprov": r[7],
                "city": r[10],
                #"metro": r[11],
                "tz_name": r[12]
            }

            locations[key] = entry

            line=lf.readline()

    for f in [ mm_ipv4, mm_ipv6 ]:
        LOG.info(f"Processing {f}")
        count = 0
        sql_values=""
        line_count = 0

        with open(f, "r") as ib:
            ib.readline()
            line=ib.readline()
            while line and len(line) > 0:
                stripped_line=line.rstrip('\n').replace("'", "")
                r = [ '{}'.format(x) for x in list(csv.reader([stripped_line], delimiter=',', quotechar='"'))[0] ]

                try:
                    loc = locations[r[1]]
                except KeyError as e:
                    LOG.warning(f"Prefix missing geoname_id '{r[1]}': {r}")
                    line=ib.readline()
                    line_count += 1
                    continue

                if count:
                    sql_values += ','

                sql_values += f"({4 if '.' in r[0] else 6},"
                sql_values += f"'{r[0]}','{loc['city']}','{loc['stateprov']}','{loc['country']}',"
                sql_values += f"{r[7]},{r[8]},0,'{loc['tz_name']}','')"
                count += 1

                line=ib.readline()
                line_count += 1

                # bulk insert
                if count >= 3000:
                    LOG.info(f"Inserting {count} records, line count {line_count}")

                    try:
                        db.queryNoResults(SQL_INSERT + sql_values + SQL_CONFLICT)
                    except:
                        LOG.error("Trying to insert again due to exception")
                        db.queryNoResults(SQL_INSERT + sql_values + SQL_CONFLICT)

                    sql_values = ""
                    count = 0

            # insert the last batch
            if len(sql_values) > 0:
                try:
                    LOG.info(f"Inserting last batch, count {count}, line count {line_count}")
                    db.queryNoResults(SQL_INSERT + sql_values + SQL_CONFLICT)
                except:
                    LOG.error("Trying to insert again due to exception")
                    db.queryNoResults(SQL_INSERT + sql_values + SQL_CONFLICT)

    return True


def import_dbip_csv(db, in_file):
    """
    import DB-IP CSV Lite Format - https://db-ip.com/db/download/ip-to-city-lite into OBMP Postgres DB

    :param db:          Connected DB handler
    :param in_file:     DB-IP File to load

    :return: True if success, False on Error
    """
    total_count = 0
    count=0
    line_count=1
    sql_values=""

    with open(in_file, "r") as inf:
        line=inf.readline()
        while line and len(line) > 0:
            stripped_line=line.rstrip('\n').replace("'", "")
            r = [ '{}'.format(x) for x in list(csv.reader([stripped_line], delimiter=',', quotechar='"'))[0] ]
            ip_list=netaddr.iprange_to_cidrs(r[0], r[1])
            addr_type = 4 if '.' in r[0] else 6

            # DB-IP specifies ranges like 1.1.1.18 - 1.1.1.50.  ip_list will be the specific CIDRs that includes
            #   all the IPs in the range.  This is why a single entry will end up being multiple CIDRs.
            for ip in ip_list:
                if count:
                    sql_values += ','

                sql_values += "(%d, '%s', '%s', '%s', '%s', %s, %s," % (addr_type,
                                                                        ip,
                                                                        r[5].encode('ascii', 'ignore').decode('ascii'),
                                                                        r[4].encode('ascii', 'ignore').decode('ascii'),
                                                                        r[3],
                                                                        r[6], r[7]);
                sql_values += "0, 'UTC', '') "
                count += 1

            line=inf.readline()
            line_count += 1

            # bulk insert
            if count >= 4000:
                total_count += count
                LOG.info(f"Inserting {count} records, total {total_count}, line count {line_count}")

                try:
                    db.queryNoResults(SQL_INSERT + sql_values + SQL_CONFLICT)
                except:
                    LOG.error("Trying to insert again due to exception")
                    db.queryNoResults(SQL_INSERT + sql_values + SQL_CONFLICT)

                sql_values = ""
                count = 0

        # insert the last batch
        if len(sql_values) > 0:
            total_count += count
            try:
                LOG.info(f"Inserting last batch, count {count}, total {total_count}, line count {line_count}")
                db.queryNoResults(SQL_INSERT + sql_values + SQL_CONFLICT)
            except:
                LOG.error("Trying to insert again due to exception")
                db.queryNoResults(SQL_INSERT + sql_values + SQL_CONFLICT)

    return True

@click.command(context_settings=dict(help_option_names=['--help'], max_content_width=200))
@click.option('-h', '--pghost', 'pghost', envvar='PGHOST',
              help="Postgres hostname",
              metavar="<string>", default="localhost")
@click.option('-u', '--pguser', 'pguser', envvar='PGUSER',
              help="Postgres User",
              metavar="<string>", default="openbmp")
@click.option('-p', '--pgpassword', 'pgpassword', envvar='PGPASSWORD',
              help="Postgres Password",
              metavar="<string>", default="openbmp")
@click.option('-d', '--pgdatabase', 'pgdatabase', envvar='PGDATABASE',
              help="Postgres Database name",
              metavar="<string>", default="openbmp")
@click.option('--db_ip_file', 'db_ip_file',
              help="DB-IP CSV DB-IP City Lite filename",
              metavar="<string>", default=None)
@click.option('--maxmind_loc_file', 'mm_loc_file',
              help="MaxMind GeoLite2-City-Locations CSV filename",
              metavar="<string>", default=None)
@click.option('--maxmind_ipv4_file', 'mm_ipv4_file',
              help="MaxMind GeoLite2-City-Blocks-IPv4 CSV filename",
              metavar="<string>", default=None)
@click.option('--maxmind_ipv6_file', 'mm_ipv6_file',
              help="MaxMind GeoLite2-City-Blocks-IPv6 CSV filename",
              metavar="<string>", default=None)
# @click.option('-f', '--flush', 'flush_routes',
#               help="Flush routing table(s) at startup",
#               is_flag=True, default=False)
def main(pghost, pguser, pgpassword, pgdatabase, db_ip_file, mm_loc_file, mm_ipv4_file, mm_ipv6_file):
    db = dbHandler()

    success = True

    if db_ip_file:
        LOG.info(f"Importing DB-IP City Lite {db_ip_file}...")

        if not os.path.isfile(db_ip_file):
            LOG.fatal(f"CSV file '{db_ip_file}' does not exist, cannot continue")
            exit(1)

        db.connectDb(pguser, pgpassword, pghost, pgdatabase)

        success = import_dbip_csv(db, db_ip_file)

        db.close()

    else:
        if not mm_loc_file:
            LOG.fatal("Missing --maxmind_loc_file. Locations file is required in order to import.")
            exit(1)
        elif not os.path.isfile(mm_loc_file):
            LOG.error(f"Locations file '{mm_loc_file}' doesn't exist, cannot proceed.")
            exit(2)

        if not mm_ipv4_file and not mm_ipv6_file:
            LOG.fatal("Missing --maxmind_ipv4_file and --maxmind_ipv6_file. At least one of them must defined.")

        LOG.info("Importing MaxMind GeoIP2 City Lite files ...")

        db.connectDb(pguser, pgpassword, pghost, pgdatabase)

        success = import_maxmind_csv(db, mm_loc_file, mm_ipv4_file, mm_ipv6_file)

        db.close()

    if not success:
        LOG.error("import failed")
        exit(3)

if __name__ == '__main__':
    main()

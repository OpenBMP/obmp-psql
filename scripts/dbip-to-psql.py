#!/usr/bin/env python3
"""
  Copyright (c) 2020 Cisco Systems, Inc. and others.  All rights reserved.

  .. moduleauthor:: Tim Evens <tievens@cisco.com>

  sudo apt install libpq-dev postgresql-common
  sudo pip3 install psycopg2
  sudo pip3 install netaddr
  sudo pip3 install click

 After import, sync geo_ip with the RIB

 INSERT INTO geo_ip (family, ip, country, stateprov,city,latitude,longitude,
				    timezone_offset, timezone_name, isp_name)
	select 4,prefix,country,stateprov,city,latitude,longitude,0,'UTC','RIB_SYNC'
		FROM (
			select distinct prefix
				from ip_rib
				where peer_hash_id = 'd46b7950-5eb0-a864-be53-16e4247c68f0'
					and prefix != '0.0.0.0/0'
		) r
		JOIN geo_ip g ON (ip >>= host(prefix)::inet and ip != '0.0.0.0/0')
	ON CONFLICT (ip) DO NOTHING;

"""
import logging
import click
import netaddr
import csv
import psycopg2 as py
from time import time

# Set logger
logging.basicConfig(format='%(asctime)s | %(levelname)-8s | %(name)s[%(lineno)s] | %(message)s', level=logging.INFO)
LOG = logging.getLogger("dbip-to-psql")


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


@click.command(context_settings=dict(help_option_names=['-h', '--help'], max_content_width=200))
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
@click.option('-i', '--in_file', 'in_file',
              help="DB-IP input file (Lite CSV format)",
              metavar="<string>", default="")

# @click.option('-f', '--flush', 'flush_routes',
#               help="Flush routing table(s) at startup",
#               is_flag=True, default=False)
def main(pghost, pguser, pgpassword, pgdatabase, in_file):

    db = dbHandler()
    db.connectDb(pguser, pgpassword, pghost, pgdatabase)

    with open(in_file, "r") as inf:
        line=inf.readline()
        while line:
            #r=line.rstrip('\n').replace("'", "").split(',')
            stripped_line=line.rstrip('\n').replace("'", "")
            r = [ '{}'.format(x) for x in list(csv.reader([stripped_line], delimiter=',', quotechar='"'))[0] ]
            ip_list=netaddr.iprange_to_cidrs(r[0], r[1])
            addr_type = 4 if '.' in r[0] else 6
            for ip in ip_list:
                sql = "INSERT INTO geo_ip (family,ip,city,stateprov,country,latitude,longitude,"
                sql += "timezone_offset, timezone_name, isp_name) "
                sql += "values (%d, '%s', '%s', '%s', '%s', %s, %s," % (addr_type,
                                                                        ip,
                                                                        r[5].encode('ascii', 'ignore').decode('ascii'),
                                                                        r[4].encode('ascii', 'ignore').decode('ascii'),
                                                                        r[3],
                                                                        r[6], r[7]);
                sql += "0, 'UTC', '') "
                sql += "ON CONFLICT (ip) DO UPDATE SET "
                sql += "city=excluded.city, stateprov=excluded.stateprov,"
                sql += "country=excluded.country, latitude=excluded.latitude, longitude=excluded.longitude;"

                #LOG.info(sql)
                db.queryNoResults(sql)

            line=inf.readline()

    db.close()


if __name__ == '__main__':
    main()
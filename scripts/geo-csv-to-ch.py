#!/usr/bin/env python3
"""
  Copyright (c) 2020-2022 Cisco Systems, Inc. and others.  All rights reserved.

  .. moduleauthor:: Tim Evens <tievens@cisco.com>

    This script can be used to import either DB-IP City Lite CSV or MaxMind GeoIP2 City Lite CSV
    into OBMP clickhouse DB.

    Ref: DB-IP CSV Lite      - https://db-ip.com/db/download/ip-to-city-lite
         MaxMind Geo2IP Lite - https://dev.maxmind.com/geoip/geolocate-an-ip/databases?lang=en

    NOTE: MaxMind requires a login in order to download the CSV file.  DB-IP does not. DB-IP is therefore
         the default since it doesn't require a login.

  sudo apt install python3-{click,clickhouse-driver,netaddr}
"""
import logging
import click
import netaddr
import csv
import os.path
from time import time

import dbHandler

# Set logger
logging.basicConfig(format='%(asctime)s | %(levelname)-8s | %(name)s[%(lineno)s] | %(message)s', level=logging.INFO)
LOG = logging.getLogger("geo-csv-to-ch")

SQL_INSERT = ("INSERT INTO geo_ip (family, cidr, cidr_len, city, stateprov, country, latitude, longitude, "
              "timezone_offset, timezone_name, isp_name) VALUES ")


def import_maxmind_csv(db, mm_loc, mm_ipv4, mm_ipv6):
    """
    import MaxMind City CSV Lite into OBMP clickhouse DB

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
                        db.queryNoResults(SQL_INSERT + sql_values)
                    except:
                        LOG.error("Trying to insert again due to exception")
                        db.queryNoResults(SQL_INSERT + sql_values)

                    sql_values = ""
                    count = 0

            # insert the last batch
            if len(sql_values) > 0:
                try:
                    LOG.info(f"Inserting last batch, count {count}, line count {line_count}")
                    db.queryNoResults(SQL_INSERT + sql_values)
                except:
                    LOG.error("Trying to insert again due to exception")
                    db.queryNoResults(SQL_INSERT + sql_values)

    return True


def import_dbip_csv(db, in_file):
    """
    import DB-IP CSV Lite Format - https://db-ip.com/db/download/ip-to-city-lite into OBMP Clickhouse DB

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

                sql_values += "(%d, '%s', %d, '%s', '%s', '%s', %s, %s," % (addr_type,
                                                                        str(ip.split('/', 1)[0]),
                                                                        int(ip.split('/', 1)[1]),
                                                                        r[5].encode('ascii', 'ignore').decode('ascii'),
                                                                        r[4].encode('ascii', 'ignore').decode('ascii'),
                                                                        r[3],
                                                                        r[6], r[7]);
                sql_values += "0, 'UTC', '') "
                count += 1

            line=inf.readline()
            line_count += 1

            # bulk insert
            if count >= 100000:
                total_count += count
                LOG.info(f"Inserting {count} records, total {total_count}, line count {line_count}")

                try:
                    db.queryNoResults(SQL_INSERT + sql_values)
                except:
                    LOG.error("Trying to insert again due to exception")
                    db.queryNoResults(SQL_INSERT + sql_values)

                sql_values = ""
                count = 0

        # insert the last batch
        if len(sql_values) > 0:
            total_count += count
            try:
                LOG.info(f"Inserting last batch, count {count}, total {total_count}, line count {line_count}")
                db.queryNoResults(SQL_INSERT + sql_values)
            except:
                LOG.error("Trying to insert again due to exception")
                db.queryNoResults(SQL_INSERT + sql_values)

    return True

@click.command(context_settings=dict(help_option_names=['--help'], max_content_width=200))
@click.option('-h', '--host', 'host', envvar='HOST',
              help="Clickhouse hostname",
              metavar="<string>", default="localhost")
@click.option('-u', '--user', 'user', envvar='USER',
              help="Clickhouse User",
              metavar="<string>", default="openbmp")
@click.option('-p', '--password', 'password', envvar='PASSWORD',
              help="Clickhouse Password",
              metavar="<string>", default="openbmp")
@click.option('-d', '--database', 'database', envvar='DATABASE',
              help="Clickhouse Database name",
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
def main(host, user, password, database, db_ip_file, mm_loc_file, mm_ipv4_file, mm_ipv6_file):
    db = dbHandler.dbHandler()

    success = True

    if db_ip_file:
        LOG.info(f"Importing DB-IP City Lite {db_ip_file}...")

        if not os.path.isfile(db_ip_file):
            LOG.fatal(f"CSV file '{db_ip_file}' does not exist, cannot continue")
            exit(1)

        db.connectDb(user, password, host, database)

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

        db.connectDb(user, password, host, database)

        success = import_maxmind_csv(db, mm_loc_file, mm_ipv4_file, mm_ipv6_file)

        db.close()

    if not success:
        LOG.error("import failed")
        exit(3)

if __name__ == '__main__':
    main()

#!/usr/bin/env python
"""
  Copyright (c) 2018 Cisco Systems, Inc. and others.  All rights reserved.
  Copyright (c) 2018 Tim Evens (tim@evensweb.com).  All rights reserved.

  This program and the accompanying materials are made available under the
  terms of the Eclipse Public License v1.0 which accompanies this distribution,
  and is available at http://www.eclipse.org/legal/epl-v10.html

  .. moduleauthor:: Tim Evens <tim@evensweb.com>
"""
import getopt
import gzip
import os
import sys
from collections import OrderedDict, deque
from ftplib import FTP
from shutil import rmtree
import traceback

import dbHandler

# ----------------------------------------------------------------
# RR Database download sites
# ----------------------------------------------------------------
RR_DB_FTP = OrderedDict()
#RR_DB_FTP['nttcom'] = {'site': 'rr1.ntt.net', 'path': '/nttcomRR/', 'filename': 'nttcom.db.gz'}
#RR_DB_FTP['level3'] = {'site': 'ftp.radb.net', 'path': '/radb/dbase/', 'filename': 'level3.db.gz'}
#RR_DB_FTP['radb'] = {'site': 'ftp.radb.net', 'path': '/radb/dbase/', 'filename': 'radb.db.gz'}
#RR_DB_FTP['arin'] = {'site': 'ftp.arin.net', 'path': '/pub/rr/', 'filename': 'arin.db'}
RR_DB_FTP['afrinic'] = {'site': 'ftp.afrinic.net', 'path': '/pub/dbase/', 'filename': 'afrinic.db.gz'}
RR_DB_FTP['apnic'] = {'site': 'ftp.apnic.net', 'path': '/pub/apnic/whois/', 'filename': 'apnic.db.route.gz'}
#RR_DB_FTP['jpirr'] = {'site': 'ftp.radb.net', 'path': '/radb/dbase/', 'filename': 'jpirr.db.gz'}
RR_DB_FTP['apnic_v6'] = {'site': 'ftp.apnic.net', 'path': '/pub/apnic/whois/', 'filename': 'apnic.db.route6.gz'}
RR_DB_FTP['ripe'] = {'site': 'ftp.ripe.net', 'path': '/ripe/dbase/split/', 'filename': 'ripe.db.route.gz'}
RR_DB_FTP['ripe_v6'] = {'site': 'ftp.ripe.net', 'path': '/ripe/dbase/split/', 'filename': 'ripe.db.route6.gz'}


RR_DB_FILES = OrderedDict()
RR_DB_FILES['nttcom'] = {'filename': 'nttcom.db.gz'}
RR_DB_FILES['level3'] = {'filename': 'level3.db.gz'}
RR_DB_FILES['radb'] = {'filename': 'radb.db.gz'}
RR_DB_FILES['arin'] = {'filename': 'arin.db.gz'}
#RR_DB_FILES['afrinic'] = {'filename': 'afrinic.db.gz'}
#RR_DB_FILES['apnic'] = {'filename': 'apnic.db.route.gz'}
RR_DB_FILES['jpirr'] = {'filename': 'jpirr.db.gz'}
#RR_DB_FILES['apnic_v6'] = {'filename': 'apnic.db.route6.gz'}
#RR_DB_FILES['ripe'] = {'filename': 'ripe.db.route.gz'}
#RR_DB_FILES['ripe_v6'] = {'filename': 'ripe.db.route6.gz'}

# ----------------------------------------------------------------
# Whois mapping
# ----------------------------------------------------------------
WHOIS_ATTR_MAP = {
    # RADB
    'route': 'prefix',
    'route6': 'prefix',
    'descr': 'descr',
    'origin': 'origin_as',
}

#: Bulk insert queue
bulk_insert_queue = deque()
MAX_BULK_INSERT_QUEUE_SIZE = 2000

#: Temp directory
TMP_DIR = '/tmp/rr_dbase'


# ----------------------------------------------------------------


def import_rr_db_file(db, source, db_filename):
    """ Reads RR DB file and imports into database

    ..see: http://irr.net/docs/list.html for details of RR FTP/DB files

    :param db:              DbAccess reference
    :param source:          Source of the data (i.e. key value of RR_DB_FTP dict)
    :param db_filename:     Filename of DB file to import
    """
    record = {'source': source}
    inf = None

    print "Parsing %s" % db_filename
    if (db_filename.endswith(".gz")):
        inf = gzip.open(db_filename, 'rb')
    else:
        inf = open(db_filename, 'r')

    if (inf != None):
        recordComplete = False
        prev_attr = ""

        for line in inf:
            line = line.rstrip('\n')
            line = line.replace("\t", " ")

            # empty line means record is complete
            if len(line) == 0:
                recordComplete = True

            # Skip lines with a comment
            elif line[0] == '#' or line[0] == '%':
                continue

            elif line[0] == ' ':
                if prev_attr == 'descr':
                    #print "continuation: (%s) '%s'\n\t\t%r" % (prev_attr, line, record)
                    # Line is a continuation of previous attribute
                    try:
                        value = line.strip()
                        value = value.replace("'", "")
                        value = value.replace("\\", "")

                        record[WHOIS_ATTR_MAP[prev_attr]] += "\n" + value

                    except:
                        print "problem with continuation: (%s) '%s'\n\t\t%r" % (prev_attr, line, record)
                        pass

            elif ': ' in line:
                # Parse the attributes and build record
                (attr, value) = line.split(': ', 1)
                attr = attr.strip()
                value = value.strip()
                value = value.replace("'", "")
                value = value.replace("\\", "")

                if (attr == 'origin'):
                    # Strip off characters 'AS'
                    value = value[2:]

                    if ' ' in value:
                        value = value.split(' ', 1)[0]

                    # Convert from dot notiation back to numeric
                    if "." in value:
                        a = value.split('.', 1)
                        record[WHOIS_ATTR_MAP[attr]] = (int(a[0]) << 16) + int(a[1])

                    else:
                        record[WHOIS_ATTR_MAP[attr]] = int(value)

                elif (attr == 'route' or attr == 'route6'):
                    # Extract out the prefix_len
                    a = value.split('/')
                    record['prefix_len'] = int(a[1])
                    record[WHOIS_ATTR_MAP[attr]] = a[0]

                # allow appending duplicate attributes
                elif (attr == 'descr' and WHOIS_ATTR_MAP[attr] in record):
                    record[WHOIS_ATTR_MAP[attr]] += ' \n' + value

                elif (attr in WHOIS_ATTR_MAP):
                    record[WHOIS_ATTR_MAP[attr]] = value

                prev_attr = attr

            if recordComplete:
                recordComplete = False

                if 'prefix' in record:
                    add_route_to_db(db, record)

                record = {'source': source}

        # Commit any pending items
        add_route_to_db(db, {}, commit=True)

        # Close the file
        inf.close()


def add_route_to_db(db, record, commit=False):
    """ Adds/updates route in DB

    :param db:          DbAccess reference
    :param record:      Dictionary of column names and values
    :param commit:      True to flush/commit the queue and this record, False to queue
                        and perform bulk insert.

    :return: True if updated, False if error
    """
    # Add entry to queue
    if (len(record) > 4):
        bulk_insert_queue.append("('%s/%d'::inet,%d,%u,'%s', '%s')" % (record['prefix'], record['prefix_len'],
                                                                       record['prefix_len'],
                                                                       record['origin_as'],
                                                                       unicode(record['descr'], errors="ignore")[:254],
                                                                       record['source']))

    # Insert/commit the queue if commit is True or if reached max queue size
    if ((commit == True or len(bulk_insert_queue) > MAX_BULK_INSERT_QUEUE_SIZE) and
            len(bulk_insert_queue)):
        query = "INSERT INTO info_route (prefix,prefix_len,origin_as,descr,source) "
        query += " SELECT DISTINCT ON (prefix,prefix_len,origin_as) * FROM ( VALUES "


        # try:
        while bulk_insert_queue:
            query += "%s," % bulk_insert_queue.popleft()

        # except IndexError:
        #     # No more entries
        #     pass

        # Remove the last comma if present
        if (query.endswith(',')):
            query = query[:-1]

        query += " ) t(prefix,prefix_len,origin_as,descr,source) " # add order by if needed
        query += " ON CONFLICT (prefix,prefix_len,origin_as) DO UPDATE SET "
        query += "   descr=excluded.descr, source=excluded.source, timestamp=now()"

        # print "QUERY = %s" % query
        # print "----------------------------------------------------------------"
        db.queryNoResults(query)


def download_data_file():
    """ Download the RR data files
    """
    if (not os.path.exists(TMP_DIR)):
        os.makedirs(TMP_DIR)

    for source in RR_DB_FTP:
        try:
            print "Downloading %s..." % source
            ftp = FTP(RR_DB_FTP[source]['site'])
            ftp.login()
            ftp.cwd(RR_DB_FTP[source]['path'])
            ftp.retrbinary("RETR %s" % RR_DB_FTP[source]['filename'],
                           open("%s/%s" % (TMP_DIR, RR_DB_FTP[source]['filename']), 'wb').write)
            ftp.quit()
            print "      Done downloading %s" % source
        except:
            print "Error processing %s, skipping" % source
            traceback.print_exc()


def script_exit(status=0):
    """ Simple wrapper to exit the script cleanly """
    exit(status)


def parseCmdArgs(argv):
    """ Parse commandline arguments

        Usage is printed and program is terminated if there is an error.

        :param argv:   ARGV as provided by sys.argv.  Arg 0 is the program name

        :returns:  dictionary defined as::
                {
                    user:       <username>,
                    password:   <password>,
                    db_host:    <database host>
                }
    """
    REQUIRED_ARGS = 3
    found_req_args = 0
    cmd_args = {'user': None,
                'password': None,
                'db_host': None,
                'db_name': "openbmp"}

    if (len(argv) < 3):
        usage(argv[0])
        sys.exit(1)

    try:
        (opts, args) = getopt.getopt(argv[1:], "hu:p:d:",
                                     ["help", "user=", "password=", "dbName="])

        for o, a in opts:
            if o in ("-h", "--help"):
                usage(argv[0])
                sys.exit(0)

            elif o in ("-u", "--user"):
                found_req_args += 1
                cmd_args['user'] = a

            elif o in ("-p", "--password"):
                found_req_args += 1
                cmd_args['password'] = a

            elif o in ("-d", "--dbName"):
                found_req_args += 1
                cmd_args['db_name'] = a

            else:
                usage(argv[0])
                sys.exit(1)

        # The last arg should be the command
        if (len(args) <= 0):
            print "ERROR: Missing the database host/IP"
            usage(argv[0])
            sys.exit(1)

        else:
            found_req_args += 1
            cmd_args['db_host'] = args[0]

        # The last arg should be the command
        if (found_req_args < REQUIRED_ARGS):
            print "ERROR: Missing required args, found %d required %d" % (found_req_args, REQUIRED_ARGS)
            usage(argv[0])
            sys.exit(1)

        return cmd_args

    except (getopt.GetoptError, TypeError), err:
        print str(err)  # will print something like "option -a not recognized"
        usage(argv[0])
        sys.exit(2)


def usage(prog):
    """ Usage - Prints the usage for this program.

        :param prog:  Program name
    """
    print ""
    print "Usage: %s [OPTIONS] <database host/ip address>" % prog
    print ""
    print "  -u, --user".ljust(30) + "Database username"
    print "  -p, --password".ljust(30) + "Database password"
    print ""

    print "OPTIONAL OPTIONS:"
    print "  -h, --help".ljust(30) + "Print this help menu"
    print "  -d, --dbName".ljust(30) + "Database name, default is 'openbmp'"


def main():
    """
    """
    cfg = parseCmdArgs(sys.argv)

    # Download the RR data files
    #download_data_file()

    db = dbHandler.dbHandler()
    db.connectDb(cfg['user'], cfg['password'], cfg['db_host'], cfg['db_name'])

    for source in RR_DB_FILES:
        try:
            import_rr_db_file(db, source, "%s/%s" % (TMP_DIR, RR_DB_FILES[source]['filename']))
        except:
            traceback.print_exc()


    #rmtree(TMP_DIR)

    db.close()


if __name__ == '__main__':
    main()
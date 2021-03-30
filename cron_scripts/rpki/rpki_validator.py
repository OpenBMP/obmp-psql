#!/usr/bin/env python3
"""
  Copyright (c) 2021 Cisco Systems, Inc. and Tim Evens.  All rights reserved.

  .. moduleauthor:: Tim Evens <tim@evensweb.com>
"""

import sys
import getopt
import dbHandler
import urllib2, json
import ipaddr
from time import time

# ----------------------------------------------------------------
# Global variables
# ----------------------------------------------------------------


# ----------------------------------------------------------------
# Functions
# ----------------------------------------------------------------
def load_export(db, server, api="api/export.json"):
    query_begin = 'INSERT INTO rpki_validator (prefix, prefix_len, prefix_len_max, origin_as) VALUES '
    query_end = ' ON CONFLICT (prefix,prefix_len_max,origin_as) DO UPDATE SET timestamp=now()'

    # get json data
    data = []

    try:
        req = urllib2.Request(url='http://' + server + '/' + api,
                              headers={ 'Accept': 'application/json'})
        json_response = json.load(urllib2.urlopen(req))
        data = json_response['roas'] # json

    except urllib2.URLError as err:
       print ("Error connecting to rpki server: %r") % err
       return

    query = query_begin
    count = 0
    for line in data:

        if count > 0:
            query += ','

        asn, prefix_full, max_length = line['asn'], line['prefix'], line['maxLength']
        prefix, prefix_len = prefix_full.split('/')[0], prefix_full.split('/')[1]

        query += "('%s'::inet, %d, %d, %d)" % (prefix_full, int(prefix_len), int(max_length), int(asn))
        count += 1

        if (count > 200):    # Bulk insert/upset
            db.queryNoResults(query + query_end)
            query = query_begin
            count = 0

    # process remaining items in the query
    if query.endswith(','):
        query = query[:-1]
        db.queryNoResults(query + query_end)


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
    REQUIRED_ARGS = 4
    found_req_args = 0
    cmd_args = { 'user': None,
                 'password': None,
                 'db_host': None,
                 'db_name': "openbmp",
                 'server': None,
                 'api': None }

    if (len(argv) < 5):
        usage(argv[0])
        sys.exit(1)

    try:
        (opts, args) = getopt.getopt(argv[1:], "hu:p:d:s:a:",
                                       ["help", "user=", "password=", "dbName=", "server=", 'api='])

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

            elif o in ("-s", "--server"):
                found_req_args += 1
                cmd_args['server'] = a

            else:
                usage(argv[0])
                sys.exit(1)

        # The last arg should be the command
        if (len(args) <= 0):
            print ("ERROR: Missing the database host/IP")
            usage(argv[0])
            sys.exit(1)

        else:
            found_req_args += 1
            cmd_args['db_host'] = args[0]


        # The last arg should be the command
        if (found_req_args < REQUIRED_ARGS):
            print ("ERROR: Missing required args, found %d required %d" % (found_req_args, REQUIRED_ARGS))
            usage(argv[0])
            sys.exit(1)

        return cmd_args

    except (getopt.GetoptError, TypeError) as err:
        print (str(err))  # will print something like "option -a not recognized"
        usage(argv[0])
        sys.exit(2)


def usage(prog):
    """ Usage - Prints the usage for this program.

        :param prog:  Program name
    """
    print ("")
    print ("Usage: %s [OPTIONS] <database host/ip address>" % prog)
    print ("")
    print ("  -u, --user".ljust(30) + "Database username")
    print ("  -p, --password".ljust(30) + "Database password")
    print ("  -s, --server".ljust(30) + "RPKI Validator server address")
    print ("")

    print ("OPTIONAL OPTIONS:")
    print ("  -h, --help".ljust(30) + "Print this help menu")
    print ("  -d, --dbName".ljust(30) + "Database name, default is 'openbmp'")

    print ("NOTES:")
    print ("   RPKI validator http://server/export.json is used to populate the DB")


def main():
    cfg = parseCmdArgs(sys.argv)

    db = dbHandler.dbHandler()
    db.connectDb(cfg['user'], cfg['password'], cfg['db_host'], cfg['db_name'])
    print('connected to db')

    server = cfg['server']
    load_export(db, server);
    print ("Loaded rpki roas")

    # Purge old entries that didn't get updated
    db.queryNoResults("DELETE FROM rpki_validator WHERE timestamp < now() - interval '1 hour'")
    print("purged old roas")

    print("Done")


if __name__ == '__main__':
    main()

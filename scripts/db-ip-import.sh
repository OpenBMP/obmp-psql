#!/bin/bash
# Cron script to import DB-IP into OBMP geo_ip
#
#  Copyright (c) 2022 Cisco Systems, Inc. and others.  All rights reserved.
#
# Author: Tim Evens <tievens@cisco.com>
#
source /usr/local/openbmp/pg_profile

rm -f /tmp/dbip.csv.gz /tmp/dbip.csv

echo "INFO: Downloading dbip-city-lite-$(date "+%Y-%m").csv.gz"
wget -O /tmp/dbip.csv.gz https://download.db-ip.com/free/dbip-city-lite-$(date "+%Y-%m").csv.gz
echo $?

if [[ $? == 0 ]]; then
    echo "decompress db-ip CSV"
    gzip -d /tmp/dbip.csv.gz

    echo "Running geo csv import script"
    /usr/local/openbmp/geo-csv-to-psql.py --db_ip_file /tmp/dbip.csv
else
    echo "ERROR: Failed to download dbip-city-lite-2022-06.csv.gz"
    exit 1
fi

rm -f /tmp/dbip.csv.gz /tmp/dbip.csv

#!/usr/bin/env python3
"""
  Copyright (c) 2022 Cisco Systems, Inc. and others.  All rights reserved.

  .. moduleauthor:: Chi Durbin <chdurbin@cisco.com>
  .. moduleauthor:: Tim Evens <tievens@cisco.com>
"""
import click
import psycopg2 # postgres connector
import requests
import json
import time # time the sync
import logging
from random import randint


# setup logging
log_format = ('[%(asctime)s] %(levelname)-8s %(name)-12s %(message)s')

# Define basic configuration
logging.basicConfig(
    # Define logging level
    level=logging.INFO,
    # Declare the object  created to format the log messages
    format=log_format,
    # Declare handlers
    handlers=[
        logging.StreamHandler()
    ])

logger = logging.getLogger("OBMP peeringDB:: ")


# Max bulk values to insert at once
MAX_BULK = 1000

# Upsert bulk query
UPSERT_INFO_ASN = {
    "insert": "INSERT INTO info_asn (asn, as_name, org_id, org_name, remarks, address, city, state_prov, postal_code, country, source)",
    "values":  "VALUES ",
    "conflict": (" ON CONFLICT (asn) DO UPDATE SET "
                 "   as_name=excluded.as_name,org_id=excluded.org_id,org_name=excluded.org_name,remarks=excluded.remarks,"
                 "   address=excluded.address,city=excluded.city,state_prov=excluded.state_prov,postal_code=excluded.postal_code,"
                 "   country=excluded.country,source=excluded.source,timestamp=excluded.timestamp"
                )
}

UPSERT_PDB_IX_PEERS = {
    "insert": ("INSERT INTO pdb_exchange_peers (ix_id,ix_name,ix_prefix_v4,ix_prefix_v6,rs_peer,peer_name,peer_ipv4,peer_ipv6,peer_asn,"
               "speed,policy,poc_policy_email,poc_noc_email,ix_city,ix_country,ix_region) "),
    "values": "VALUES ",
    "conflict": (" ON CONFLICT (ix_id,peer_ipv4,peer_ipv6) DO UPDATE SET "
                 "   ix_name=excluded.ix_name, ix_prefix_v4=excluded.ix_prefix_v4,ix_prefix_v6=excluded.ix_prefix_v6,"
                 "   rs_peer=excluded.rs_peer,peer_name=excluded.peer_name,peer_asn=excluded.peer_asn,"
                 "   speed=excluded.speed,policy=excluded.policy,"
                 "   ix_city=excluded.ix_city,ix_country=excluded.ix_country,ix_region=excluded.ix_region,"
                 "   timestamp=excluded.timestamp"
                )
}


class apiDb:
    """ Peering DB API class to import data from Peering DB to OBMP postgres
    """

    #: Connection handle
    conn = None

    #: Cursor handle
    cursor = None

    #: PeeringDB ORGs as dictionary
    pdb_orgs = None

    #: PeeringDB Networks as dictionary
    pdb_nets = None

    #: PeeringDB Network IX LAN info (e.g., peerings)
    pdb_netixlan = None

    #: PeeringDB Point of contacts. This is a nested dictionary where the first key is either
    #:    'noc' or 'policy'.  The second key is the net_id.
    pdb_pocs = None

    #: PeeringDB IX Prefixes. This is a nested dictionary where the first key is 'v4' or 'v6'.
    #:    The second key is ixlan_id.
    pdb_ix_pfxs = None

    #: PeeringDB IXs.
    pdb_ix = None

    def __init__(self, pghost, pguser, pgpassword, pgdatabase):
        self.pghost = pghost
        self.pguser = pguser
        self.pgpassword = pgpassword
        self.pgdatabase = pgdatabase

        self.connect_db()

    def connect_db(self):
        logger.info(f"Connecting to postgres {self.pghost}/{self.pgdatabase}")
        # setup DB connection
        self.conn = psycopg2.connect(database=self.pgdatabase, user=self.pguser,
                                     password=self.pgpassword, host=self.pghost)
        self.cursor = self.conn.cursor()

        logger.info(f"Connected to postgres {self.pghost}/{self.pgdatabase}")

    def close_db(self, error=None, query=None):
        if error:
            logger.error(f"DB error: {error}")
            logger.info(f"DB query: {query}")

        if self.conn:
            logger.info("Close DB")
            self.conn.close()

    def api_get(self, url):
        """ Gets JSON from URL response and returns dictionary of result

            :param url:         Peering DB URL
            :returns: None if error, otherwise JSON dictionary of result
        """
        try:
            req = requests.get(url)

            if not req or req.status_code != 200:
                logger.error(f"Unable to GET {url}")
                return None

            raw_dict = json.loads(req.text)

            # Strip off data and store in dict using ID as the key
            resp_dict = {}
            for entry in raw_dict['data']:
                resp_dict[entry['id']] = entry

            return resp_dict

        except requests.exceptions.ConnectionError as err:
            logger.error(f"Failed to connect to peeirngdb.com: {err}")
            return None

    def get_nets(self):
        """ Get the nets from peering DB and load into dictionary

            :returns: True if successful or False if not
        """
        url = "https://www.peeringdb.com/api/net"

        logger.info("Retrieving networks")
        self.pdb_nets = self.api_get(url)
        logger.info(f"Retrieved {len(self.pdb_nets)} networks")

        return True if self.pdb_nets else False

    def get_ixs(self):
        """ Get the IXs from peering DB and load into dictionary

            :returns: True if successful or False if not
        """
        url = "https://www.peeringdb.com/api/ix"

        logger.info("Retrieving Exchanges")
        self.pdb_ixs = self.api_get(url)
        logger.info(f"Retrieved {len(self.pdb_ixs)} exchanges")

        return True if self.pdb_ixs else False


    def get_orgs(self):
        """ Get the orgs from peering DB and load into dictionary

            :returns: True if successful or False if not
        """
        url = "https://www.peeringdb.com/api/org"

        logger.info("Retrieving orgs")
        self.pdb_orgs = self.api_get(url)
        logger.info(f"Retrieved {len(self.pdb_orgs)} orgs")

        return True if self.pdb_orgs else False

    def get_netixlan(self):
        """ Get the IX peering info from peering DB and load into dictionary

            :returns: True if successful or False if not
        """
        url = "https://www.peeringdb.com/api/netixlan"

        logger.info("Retrieving IX peering")
        self.pdb_netixlan = self.api_get(url)
        logger.info(f"Retrieved {len(self.pdb_netixlan)} peers")

        return True if self.pdb_netixlan else False

    def get_pocs(self):
        """ Get the POCs from peering DB and load into dictionary

            :returns: True if successful or False if not
        """
        url = "https://www.peeringdb.com/api/poc"

        logger.info("Retrieving POCs")
        pocs = self.api_get(url)

        # Create nested dictionary keyed by ROLE then by net_id
        self.pdb_pocs = { "noc": {}, "policy": {} }
        for value in pocs.values():
            if value['role'] == "NOC":
                self.pdb_pocs['noc'][value['net_id']] = value
            elif value['role'] == 'Policy':
                self.pdb_pocs['policy'][value['net_id']] = value


        logger.info(f"Retrieved {len(pocs)} pocs")

        return True if self.pdb_pocs else False

    def get_ixpfxs(self):
        """ Get the IX prefixes from peering DB and load into dictionary

            :returns: True if successful or False if not
        """
        url = "https://www.peeringdb.com/api/ixpfx"

        logger.info("Retrieving IX Prefixes")
        ix_pfxs = self.api_get(url)

        # Create nested dictionary for IX prefixes
        self.pdb_ix_pfxs = { "v4": {}, "v6": {} }
        for value in ix_pfxs.values():
            if value['protocol'] == "IPv6":
                self.pdb_ix_pfxs['v6'][value['ixlan_id']] = value
            elif value['protocol'] == 'IPv4':
                self.pdb_ix_pfxs['v4'][value['ixlan_id']] = value

        logger.info(f"Retrieved {len(ix_pfxs)} IX prefixes")

        return True if self.pdb_ix_pfxs else False

    def load_pdb_data(self):
        """ Gets and loads peeirng DB data into memory to be used by other functions

            :returns: True if successful, False if not
        """
        if not self.get_nets():
            logger.error("Failed to get peeringdb networks")
            return False

        if not self.get_ixs():
            logger.error("Failed to get peeringdb exchanges")
            return False


        if not self.get_orgs():
            logger.error("Failed to get peeringdb orgs")
            return False

        if not self.get_netixlan():
            logger.error("Failed to get peeringdb IX peerings")
            return False

        if not self.get_pocs():
            logger.error("Failed to get peeringdb POCs")
            return False

        if not self.get_ixpfxs():
            logger.error("Failed to get peeringdb IX prefixes")
            return False

        return True

    def import_ix_peering(self):
        """ Import into Postgres the peering inforamtion for each IX """
        logger.info("Begin IX peering import")

        if not self.pdb_netixlan or not self.pdb_nets or not self.pdb_pocs or not self.pdb_ix_pfxs:
            logger.error("Missing peering DB data.  Run load_pdb_data() first.")
            return False

        # start time
        t1=time.time()

        values_list = []
        for entry in self.pdb_netixlan.values():

            if not entry['operational']:
                logger.debug(f"Skipping non operational: {entry}")
                continue

            ix_name = entry['name'].replace("'", "''")
            ix_id = entry['ix_id']
            peer_ipv4 = f"'{entry['ipaddr4']}'" if entry['ipaddr4'] else "'0.0.0.0'"
            peer_ipv6 = f"'{entry['ipaddr6']}'" if entry['ipaddr6'] else "'::'"

            # If both ipv4 and ipv6 are null/empty peer IPs, then skip
            if peer_ipv4 == "'0.0.0.0'" and peer_ipv6 == "'::'":
                logger.debug(f"Skipping null IPs: {entry}")
                continue

            peer_asn = entry['asn']
            speed = entry['speed']
            rs_peer = entry['is_rs_peer']

            ix_city = self.pdb_ixs[entry['ix_id']]['city'].replace("'", "''")
            ix_country = self.pdb_ixs[entry['ix_id']]['country']
            ix_region = self.pdb_ixs[entry['ix_id']]['region_continent'].replace("'", "''")

            ix_prefix_v4 = "null"
            ix_prefix_v6 = "null"
            poc_noc_email = ""
            poc_policy_email = ""

            try:
                ix_prefix_v4 = f"'{self.pdb_ix_pfxs['v4'][entry['ixlan_id']]['prefix']}'"
            except:
                pass

            try:
                ix_prefix_v6 = f"'{self.pdb_ix_pfxs['v6'][entry['ixlan_id']]['prefix']}'"
            except:
                pass

            try:
                poc_policy_email = self.pdb_pocs['policy'][entry['net_id']]['email']
            except:
                pass

            try:
                poc_noc_email = self.pdb_pocs['noc'][entry['net_id']]['email']
            except:
                pass

            peer_name = f"{self.pdb_nets[entry['net_id']]['name']} | {self.pdb_nets[entry['net_id']]['aka']}".replace("'", "")
            policy = self.pdb_nets[entry['net_id']]['policy_general']

            # bulk update
            if len(values_list) >= MAX_BULK:
                processed=len(values_list)
                self.upsert(UPSERT_PDB_IX_PEERS, values_list)
                values_list = []
                t2=(time.time()-t1)
                logger.info(f"IX Peer Time: {t2}, number of peers processed: {processed}")

            # Append value to bulk update
            value=(f"({ix_id}, '{ix_name}', {ix_prefix_v4}::inet, {ix_prefix_v6}::inet, {rs_peer}, '{peer_name[:254]}',"
                   f"{peer_ipv4}::inet, {peer_ipv6}::inet, '{peer_asn}', '{speed}', '{policy}',"
                   f"'{poc_policy_email}','{poc_noc_email}','{ix_city[:128]}','{ix_country}','{ix_region[:128]}')")

            values_list.append(value)

        # Insert last entries
        if len(values_list) > 0:
            self.upsert(UPSERT_PDB_IX_PEERS, values_list)
            processed=len(values_list)
            t2=(time.time()-t1)
            logger.info(f"Time: {t2}, number of peers processed: {processed}")

        logger.info(f"Peering Import from PeeringDB successful: processed: {len(self.pdb_nets)}, time: {t2}")

    def import_asn_info(self):
        """ Import into Postgres the ASN information """
        logger.info("Begin ASN import")

        if not self.pdb_orgs or not self.pdb_nets:
            logger.error("No peering DB data.  Run load_pdb_data() first.")
            return False

        # start time
        t1=time.time()        

        # go through each AS and and grab data
        values_list = []
        for entry in self.pdb_nets.values():
            asn = entry['asn']
            as_name=entry['name'][:240].replace("'", "''")
            aka=entry['aka'][:240].replace("'", "''")
            org_name=f"{as_name} - {aka}"[:240].replace("'", "''")

            route_server=entry['route_server'][:240].replace("'", "''")
            looking_glass=entry['looking_glass'][:240].replace("'", "''")
            notes=entry['notes'][:1500]

            remarks = f"route_server: {route_server}\n" if len(route_server) > 1 else ""
            remarks += f"looking_glass: {looking_glass}" if len(looking_glass) > 1 else ""
            remarks += f"{notes}"
            remarks = remarks.replace("'", "''")

            # pull out Org_ID
            org_id = entry['org_id']

            if org_id not in self.pdb_orgs:
                logger.error(f"{org_id} not in orgs dictionary, skipping")
                continue

            address1 = self.pdb_orgs[org_id]['address1'][:250]
            address2 = self.pdb_orgs[org_id]['address2'][:250]
            address = f"{address1}, {address2}"[:240].replace("'", "''") # need to join address1 and 2 for DB
            city = self.pdb_orgs[org_id]['city'][:240].replace("'", "''")
            state_prov = self.pdb_orgs[org_id]['state'][:240].replace("'", "''")
            country = self.pdb_orgs[org_id]['country'][:240].replace("'", "''")
            postal_code = self.pdb_orgs[org_id]['zipcode'][:200]

            # bulk update
            if len(values_list) >= MAX_BULK:
                processed=len(values_list)
                self.upsert(UPSERT_INFO_ASN, values_list)
                values_list = []
                t2=(time.time()-t1)
                logger.info(f"Time: {t2}, number of AS processed: {processed}")

            # Append value to bulk update
            value=(f"({asn}, '{as_name}', '{org_id}', '{org_name}', '{remarks}', '{address}',"
                   f"'{city}', '{state_prov}', '{postal_code}', '{country}', 'peeringdb')")
            values_list.append(value)

        # Insert last entries
        if len(values_list) > 0:
            self.upsert(UPSERT_INFO_ASN, values_list)
            processed=len(values_list)
            t2=(time.time()-t1)
            logger.info(f"ASN Time: {t2}, number of AS processed: {processed}")

        logger.info(f"ASN Import from PeeringDB successful: processed: {len(self.pdb_nets)}, time: {t2}")

    def upsert(self, upsert, values_list):
        try:
            values = ','.join(values_list)
            upsert_stmt= upsert['insert'] + upsert['values'] + values + upsert['conflict']

            logger.debug(f"sql: {upsert_stmt}")

            self.cursor.execute (upsert_stmt)
            self.conn.commit()
        
        except (Exception, psycopg2.IntegrityError) as error:
            self.conn.rollback()
            logger.error(f"PSQL error: {error}")
            logger.debug(upsert_stmt)

        except (Exception, psycopg2.DatabaseError) as error:
            self.conn.rollback()
            logger.error(f"PSQL error: {error}")
            logger.debug(upsert_stmt)


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
@click.option('-s', '--sleep', 'sleep_secs',
              help="Randomly sleep to delay connections to peeringdb (default 600)",
              metavar="<int>", default="600")
def main(pghost, pguser, pgpassword, pgdatabase, sleep_secs):

    # Add a sleep before connecting to peeringDB
    sleep_rand = randint(10, int(sleep_secs))
    logger.info(f"Random sleep for {sleep_rand} seconds")
    time.sleep(sleep_rand)

    pdb_api = apiDb(pghost, pguser, pgpassword, pgdatabase)   # PeeringDB API

    # Load peering DB data
    if pdb_api.load_pdb_data():

        # Perform imports into postgres
        pdb_api.import_asn_info()
        pdb_api.import_ix_peering()

    pdb_api.close_db()


if __name__=='__main__':
    main()

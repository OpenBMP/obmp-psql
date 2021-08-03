#!/usr/bin/env python3

"""
  Copyright (c) 2021 Cisco Systems, Inc. and others.  All rights reserved.
  .. moduleauthor:: Chi Durbin <chdurbin@cisco.com>
"""

 
import psycopg2 # postgres connector
import requests
import json
import configdb # DB config and credentials
import time # time the sync
import logging

# Max bulk values to insert at once
MAX_BULK = 1000

# Upsert bulk query
UPSERT_PSQL= { "insert": "INSERT INTO info_asn (asn, as_name, org_id, org_name, remarks, address, city, state_prov, postal_code, country, source)",
               "values":  "VALUES ",
               "conflict": (" ON CONFLICT (asn) DO UPDATE SET "
                "   as_name=excluded.as_name,org_id=excluded.org_id,org_name=excluded.org_name,remarks=excluded.remarks,"
                "   address=excluded.address,city=excluded.city,state_prov=excluded.state_prov,postal_code=excluded.postal_code,"
                "   country=excluded.country,source=excluded.source")
             }

class apiDb: 
    
    # setup DB connection
    conn = psycopg2.connect(database=configdb.postgresDb, user=configdb.dbUser, password=configdb.dbPassword, host=configdb.dbHost, port=configdb.dbPort)    
    cur = conn.cursor()
    
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

    logger = logging.getLogger("CNIS peeringDB logger:: ")

    def create_org_dict(self, orgs_json):
        """ Creates a dictionary of orgs based from peeringDB orgs JSON output.
            Key is the org ID, value is the entry dict.
        """
        org_dict = {}
        orgs=json.loads(orgs_json)
        for entry in orgs['data']:
            org_dict[entry['id']] = entry

        return org_dict


    def bulk_as_from_api(self):
        ## go through every ASN and org pull out/parse details,  update DB

        # start time
        t1=time.time()        
        
        api_asn= "https://www.peeringdb.com/api/net"
        org="https://www.peeringdb.com/api/org"
        # make request
        r_asn=requests.get(api_asn)
        r_org=requests.get(org)

        #if asn and org URLs are ok
        if r_asn.status_code == 200 and r_org.status_code == 200:
            
            # convert to JSON
            j_asn=json.loads(r_asn.text)

            # Load orgs into memory dictionary
            orgs = self.create_org_dict(r_org.text)

            # go through each AS and and grab data
            values_list = []
            for entry in j_asn['data']:
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

                if org_id not in orgs:
                    self.logger.error(f"{org_id} not in orgs dictionary, skipping")
                    continue

                address1 = orgs[org_id]['address1'][:250]
                address2 = orgs[org_id]['address2'][:250]
                address = f"{address1}, {address2}"[:240].replace("'", "''") # need to join address1 and 2 for DB
                city = orgs[org_id]['city'][:240].replace("'", "''")
                state_prov = orgs[org_id]['state'][:240].replace("'", "''")
                country = orgs[org_id]['country'][:240].replace("'", "''")
                postal_code = orgs[org_id]['zipcode'][:200]

                # bulk update
                if len(values_list) >= MAX_BULK:
                    processed=len(values_list)
                    self.upsert_db(values_list)
                    values_list = []
                    t2=(time.time()-t1)
                    self.logger.info(f"Time: {t2}, number of AS processed: {processed}")

                # Append value to bulk update
                value=(f"({asn}, '{as_name}', '{org_id}', '{org_name}', '{remarks}', '{address}',"
                       f"'{city}', '{state_prov}', '{postal_code}', '{country}', 'peeringdb')")
                values_list.append(value)

            # Insert last entries
            if len(values_list) > 0:
                self.upsert_db(values_list)
                processed=len(values_list)
                t2=(time.time()-t1)
                self.logger.info(f"Time: {t2}, number of AS processed: {processed}")

        # asn or org http status != 200
        else:
            conn_error="Error connecting to PeeringDB"
            self.logger.error(conn_error)#"Error connecting to PeeringDB")    

        self.logger.info(f"Sync from PeeringDB successful: total number of AS: {len(j_asn['data'])}, time: {t2}")

    def upsert_db(self, values_list):
        try:
            values = ','.join(values_list)
            upsert_stmt=UPSERT_PSQL['insert'] + UPSERT_PSQL['values'] + values + UPSERT_PSQL['conflict']

            self.logger.debug(f"sql: {upsert_stmt}")

            self.cur.execute (upsert_stmt)
            self.conn.commit()
        
        except (Exception, psycopg2.IntegrityError) as error:
            self.close_db(error, upsert_stmt) # move exception handle to function to cut down of duplicate code

        except (Exception, psycopg2.DatabaseError) as error:
            self.close_db(error, upsert_stmt)


    def close_db(self, error, upsert_stmt):
    # send notifications and close DB
        self.logger.error("DB error: {}".format(error))
        self.logger.info("DB error: {}".format(upsert_stmt))

        if self.conn is not None:
            self.logger.info("Close DB")
            self.conn.close()     
       
        quit() # it's all gone wrong, quit out of the app


def main():
    getData = apiDb() # instaniate class

    getData.bulk_as_from_api()

if __name__=='__main__':main()

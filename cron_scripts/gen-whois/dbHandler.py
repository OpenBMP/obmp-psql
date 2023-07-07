#!/usr/bin/env python3
"""
  Copyright (c) 2021 Cisco Systems, Inc. and Tim Evens.  All rights reserved.

  This program and the accompanying materials are made available under the
  terms of the Eclipse Public License v1.0 which accompanies this distribution,
  and is available at http://www.eclipse.org/legal/epl-v10.html

  .. moduleauthor:: Tim Evens <tim@evensweb.com>
"""
import clickhouse_driver as py
from time import time

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
        self.user = user
        self.pw = pw
        self.host = host
        self.database = database

        try:
            self.conn = py.connect(f"clickhouse://{self.user}:{self.pw}@{self.host}/{self.database}?max_query_size=1048576"
            self.cursor = self.conn.cursor()

        except (py.ProgrammingError) as err:
            print("ERROR: Connect failed: " + str(err))
            raise err

    def close(self):
        """ Close the database connection """
        if (self.cursor):
            self.cursor.close()
            self.cursor = None

        if (self.conn):
            self.conn.close()
            self.conn = None

    def dropTable(self, tableName, tableSchema, dropIfExists = True):
        """ Drop table schema

            :param tablename:    The table name that is being created
            :param tableSchema:  Drop table syntax as it would be to drop it in SQL
            :param dropIfExists: True to drop the table, false to not drop it.

            :return: True if the table successfully was created, false otherwise
        """
        if (not self.cursor):
            print("ERROR: Looks like clickhouse-client is not connected, try to reconnect.")
            return False

        try:
            if (dropIfExists == True):
               self.cursor.execute("DROP TABLE IF EXISTS %s" % tableName)

            self.cursor.execute(tableSchema)

        except py.ProgrammingError as err:
            print("ERROR: Failed to drop table - " + str(err))
            #raise err


        return True

    def createTable(self, tableName, tableSchema, createIfExists = True):
        """ Create table schema

            :param tablename:    The table name that is being created
            :param tableSchema:  Create table syntax as it would be to create it in SQL
            :param createIfExists: True to drop the table, false to not drop it.

            :return: True if the table successfully was created, false otherwise
        """
        if (not self.cursor):
            print("ERROR: Looks like clickhouse-client is not connected, try to reconnect.")
            return False

        try:
            if (createIfExists == True):
               self.cursor.execute("CREATE TABLE IF EXISTS %s" % tableName)

            self.cursor.execute(tableSchema)

        except py.ProgrammingError as err:
            print("ERROR: Failed to create table - " + str(err))
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
            print("ERROR: Looks like clickhouse-client is not connected, try to reconnect")
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
            print("ERROR: query failed - " + str(err))
            return None

    def queryNoResults(self, query, queryParams=None):
        """ Runs a query that would normally not have any results, such as insert, update, delete

            :param query:       The query to run - should be a working INSERT or UPDATE statement
            :param queryParams: Dictionary of parameters to supply to the query for
                                variable substitution

            :return: Returns True if successful, false if not.
        """
        if (not self.cursor):
            print("ERROR: Looks like clickhouse-client is not connected, try to reconnect")
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
            print("ERROR: query failed - " + str(err))
            #print("   QUERY: %s", query)
            return None

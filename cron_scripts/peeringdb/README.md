
# PeeringDB - AS syncing

## Intro

PeeringDB is a community database of (among other things) AS and organisation details. This application pulls AS and organisation information from different API calls, parses the data and pushes the result to a local (to Webex) database for use in CNIS.

## Contents 

peeringdb.py - main Python application that makes the API call and pushes to Postgres.
configdb.py - grabs the DB connection settings (host, port, DB name, user, password) for environment variables.
Dockerfile - instructions for containerising the application.
requirements.txt - PIP requirements file

### Execution 

Deploy as a container:
`docker run --name peeringdb -d -e "PGDATABASE=x" -e "PGUSER=x" -e "PGPASSWORD=x" -e "PGHOST=x" -e "PGPORT=5432" openbmp/peeringdb`


Run manually:
 `PGDATABASE=x PGUSER=x PGPASSWORD=x PGHOST=x PGPORT=5432 python3 ./peeringdb.py`

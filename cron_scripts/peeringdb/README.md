
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
`docker run --name peeringdb -d -e "POSTGRES_DB=x" -e "DB_USER=x" -e "DB_PASSWORD=x" -e "DB_HOST=x" -e "DB_PORT=5432" cnis/peeringdb`


Run manually:
 `POSTGRES_DB=x DB_USER=x DB_PASSWORD=x DB_HOST=x DB_PORT=5432 python3 ./peeringdb.py`

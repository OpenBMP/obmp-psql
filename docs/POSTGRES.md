# OpenBMP PostgreSQL


> Consult the OpenBMP docker postgres [INSTALL](https://github.com/OpenBMP/docker/blob/master/postgres/scripts/install) and
[RUN](https://github.com/OpenBMP/docker/blob/master/postgres/scripts/run) scripts for
end-to-end install and run automation details. 

Postgres Install
----------------
You will need a postgres server.  You **MUST** use PostgreSQL **10.x** or greater.  

Follow the install intructions under [PostgreSQL Download](https://www.postgresql.org/download/) to install.


#### Example Installing Postgres 10.x on Ubuntu 10.x

```sh
echo "deb http://apt.postgresql.org/pub/repos/apt/ xenial-pgdg main" > /etc/apt/sources.list.d/pgdg.list

wget --quiet -O - https://www.postgresql.org/media/keys/ACCC4CF8.asc | sudo apt-key add -

sudo apt-get update

sudo apt-get install postgresql-10
```

Storage
-------
You will need to dedicate space for the postgres instance.  Normally two partitions are used.  A good
starting size for postgres main is 500GB and postgres ts (timescaleDB) is 1TB.  Both disks
should be fast SSD. ZFS can be used on either of them to add compression. The size you need will depend
on the number of NLRI's and updates per second.


Memory & CPU
------------
The size of memory will depend on the type of queries and number of NLRI's.   A good starting point for
memory is a server with more than 48GB RAM.

The number of vCPU's also varies by the number of concurrent connections and how many threads you use for
the postgres consumer.  A good starting point is at least 8 vCPU's.   

Postgres and Linux OOM
---------------------- 

Postgres can be killed by the Linux OOM-Killer. This is very bad as it causes Postgres to restart.
This will happen because postgres uses a large shared buffer, which causes the OOM to believe
it's using a lot of VM.     

It is suggested to run the postgres server with the following Linux settings:

    # Update runtime
    sysctl -w vm.vfs_cache_pressure=500
    sysctl -w vm.swappiness=10
    sysctl -w vm.min_free_kbytes=1000000
    sysctl -w vm.overcommit_memory=2
    sysctl -w vm.overcommit_ratio=95   

    # Update startup    
    echo "vm.vfs_cache_pressure=500" >> /etc/sysctl.conf
    echo "vm.min_free_kbytes=1000000" >> /etc/sysctl.conf
    echo "vm.swappiness=10" >> /etc/sysctl.conf
    echo "vm.overcommit_memory=2" >> /etc/sysctl.conf
    echo "vm.overcommit_ratio=95" >> /etc/sysctl.conf


See Postgres [hugepages](https://www.postgresql.org/docs/current/static/kernel-resources.html#LINUX-HUGE-PAGES) for
details on how to enable and use hugepages.   Some Linux distributions enable **transparent hugepages** which
will prevent the ability to configure ```vm.nr_hugepages```. If you find that you cannot set ```vm.nr_hugepages```,
then try the below:

    echo never > /sys/kernel/mm/transparent_hugepage/enabled
    echo never > /sys/kernel/mm/transparent_hugepage/defrag
    sync && echo 3 > /proc/sys/vm/drop_caches

TimescaleDB
-----------
Install [TimescaleDB](https://docs.timescale.com/v0.11/getting-started/installation/linux/installation-yum) per their
instructions. 


Postgres Configuration
----------------------
Configure ```postgresql.conf``` and ```pg_hba.conf``` after postgresql is install.  

    MEM=<GB value>

    # configure memory
    sed -i -e "s/^\#*shared_buffers.*=.*/shared_buffers = ${MEM}GB/" /etc/postgresql/10/main/postgresql.conf


    if [[ $MEM -ge 40 ]]; then
        # Use 5 percent memory if there's enough
        #WORK_MEM=$(((MEM * 1024) * 5 / 100))
        WORK_MEM=1024

    elif [[ $MEM -ge 4 ]]; then
        WORK_MEM=256
    else
        WORK_MEM=16
    fi

    sed -i -e "s/^\#*work_mem.*=.*/work_mem = ${WORK_MEM}MB/" /etc/postgresql/10/main/postgresql.conf
    
    # Configure access from any IPv4 address using SSL and a login password
    egrep -q -e '^hostssl( |\t)+all' /etc/postgresql/10/main/pg_hba.conf || \
            echo 'hostssl    all        all        0.0.0.0/0        md5' >> /etc/postgresql/10/main/pg_hba.conf

    # Configure server to listen to all interfaces/IP addresses on port 5432
    sed -i -e "s/^\#*listen_addresses.*=.*/listen_addresses = '*'/" /etc/postgresql/10/main/postgresql.conf
    sed -i -e "s/^\#*port.*=.*/port = 5432/" /etc/postgresql/10/main/postgresql.conf

    # Tune performance
    sed -i -e "s/^\#*synchronous_commit.*=.*/synchronous_commit = off/" /etc/postgresql/10/main/postgresql.conf
    sed -i -e "s/^\#*wal_compression.*=.*/wal_compression = on/" /etc/postgresql/10/main/postgresql.conf
    sed -i -e "s/^\#*max_wal_size.*=.*/max_wal_size = 16GB/" /etc/postgresql/10/main/postgresql.conf


Make any other needed customizations.

Init the database
-----------------
If the database has not been initialized, initialize using the following:

```
   DATA_DIR=/data/postgres
   su -c "/usr/lib/postgresql/10/bin/initdb -D $DATA_DIR" postgres

    # Start postgres
    service postgresql start
```

Load the OpenBMP Schema
-----------------------


#### Download the schema files first

```
mkdir -p /tmp/obmp_db_schema
cd /tmp/obmp_db_schema
wget -q https://raw.githubusercontent.com/OpenBMP/obmp-postgres/master/database/1_base.sql
wget -q https://raw.githubusercontent.com/OpenBMP/obmp-postgres/master/database/2_aggregations.sql
wget -q https://raw.githubusercontent.com/OpenBMP/obmp-postgres/master/database/5_functions.sql
wget -q https://raw.githubusercontent.com/OpenBMP/obmp-postgres/master/database/8_views.sql
wget -q https://raw.githubusercontent.com/OpenBMP/obmp-postgres/master/database/9_triggers.sql
wget -q https://raw.githubusercontent.com/OpenBMP/obmp-postgres/master/database/schema-version
```


#### Setup some ENV

```
export PGDATABASE=openbmp
export PGUSER=openbmp
export PGPASSWORD=openbmp
```

#### Create the DB and default user

```
su - -c "createdb $PGDATABASE" postgres
su - -c "psql -c \"CREATE ROLE $PGUSER WITH LOGIN SUPERUSER PASSWORD '$PGPASSWORD'\"" postgres
```

#### Load the schema files

```
su - -c "psql $PGDATABASE < /tmp/obmp_db_schema/1_base.sql" postgres
su - -c "psql $PGDATABASE < /tmp/obmp_db_schema/2_aggregations.sql" postgres
su - -c "psql $PGDATABASE < /tmp/obmp_db_schema/5_functions.sql" postgres
su - -c "psql $PGDATABASE < /tmp/obmp_db_schema/8_views.sql" postgres
su - -c "psql $PGDATABASE < /tmp/obmp_db_schema/db_schema/9_triggers.sql" postgres
```


Run Postgres
------------

Normally you can do a ```service postgresql start```


DB Maintenance
--------------
The DB is primarily maintained using cron jobs.

#### Download cron scripts

```
mkdir -p /usr/local/openbmp
cd /usr/local/openbmp
wget -q https://raw.githubusercontent.com/OpenBMP/obmp-postgres/master/cron_scripts/gen-whois/dbHandler.py
wget -q https://raw.githubusercontent.com/OpenBMP/obmp-postgres/master/cron_scripts/gen-whois/gen_whois_asn.py
wget -q https://raw.githubusercontent.com/OpenBMP/obmp-postgres/master/cron_scripts/gen-whois/gen_whois_route.py
wget -q https://raw.githubusercontent.com/OpenBMP/obmp-postgres/master/cron_scripts/rpki/rpki_validator.py
```

#### Add/update the following based on your PG settings. 

```
cat > /etc/cron.d/openbmp <<SETVAR

PGUSER=openbmp
PGPASSWORD=openbmp
PGHOST=127.0.0.1
PGDATABASE=openbmp

# Update ASN info
6 1 * * *	root  /usr/local/openbmp/gen_whois_asn.py -u $PGUSER -p $PGPASSWORD 127.0.0.1 >> /var/log/asn_load.log

# Update aggregation table stats
*/3 * * * *  root   psql -c "select update_chg_stats('26 minute')"

# Update peer rib counts
*/15 * * * *	root   psql -c "select update_peer_rib_counts()"

# Update origin stats
21 * * * *	root  psql -c "select update_global_ip_rib();"

# Purge time series data that is older than desired retention
0 * 1,15 * *     root  psql -c "SELECT drop_chunks(interval '2 weeks');"

# Update RPKI
31 */2 * * *	root  /usr/local/rpki_validator.py -u $PGUSER -p $PGPASSWORD -s 127.0.0.1:8080 127.0.0.1

# Update IRR
1 1 * * *	root  /usr/local/openbmp/gen_whois_route.py -u $PGUSER -p $PGPASSWORD 127.0.0.1 > /var/log/irr_load.log

SETVAR
```

> #### NOTE:
> You will need to install RPKI validator if you plan to use RPKI. 

# OpenBMP PostgreSQL Backend

[![Join the chat at https://gitter.im/OpenBMP/obmp-postgres](https://badges.gitter.im/OpenBMP/obmp-postgres.svg)](https://gitter.im/OpenBMP/obmp-postgres?utm_source=badge&utm_medium=badge&utm_campaign=pr-badge&utm_content=badge)
![Build Status](http://build-jenkins.openbmp.org/buildStatus/icon?job=obmp-psql)



The PostgreSQL (PSQL) consumer implements the OpenBMP [Message Bus API](https://github.com/OpenBMP/openbmp/blob/master/docs/MESSAGE_BUS_API.md) **parsed**
messages to collect and store BMP/BGP data from all collectors, routers, and peers in real-time. 

> #### IMPORTANT
> Migration to this consumer is being done in phases.  Currently the below address families are included:
> - Unicast IPv4
> - Unicast IPv6
> - Labeled Unicast IPv4
> - Labeled Unicast IPv6

## PostgreSQL will replace MySQL

MySQL will remain for a while with fixes, but new features will only be in PSQL.

#### MySQL/MariaDB has served well for the past few years but it has the following shortcomings

- **Manual partition management for time series data**:   Partition management of the time
 series tables has been a problem for operators.  While MySQL does support partitions, you have to
 keep on top of dropping old partitions and repartition the **pOther** partition for upcoming date ranges. 
 This has proven to be a challenge for operators. More often than not, disk space runs out before
 the partitions have been maintained.  If disk space runs out, a MySQL recovery is needed. [TimescaleDB](http://www.timescale.com)
 addresses this problem.  
 
- **InnoDB recovery is horrible**: When disk space runs out, recovering can take hours.  If not
performed correctly, data loss results.  Postgres recovers quickly without requiring a manual configuration
of recovery mode. Based on testing, the postgres WAL recovery out performs InnoDB.  

- **InnoDB requires a ton of memory**: In order to perform well, InnoDB requires a lot of memory. Postgres
has better performance with half the amount of memory.  

- **InnoDB data (e.g. ibdata) grows over time even with per-file tables**:  InnoDB stores various
information in ibdata. This includes pending transactions. This results in the **ibdata**
files growing in size over time.  Stopping MariaDB without a graceful shutdown results in this
file growing. We have seen the ibdata file, even with per-file tables, grow to over 100+ GB.   What
makes things worse is that the ibdata files cannot be truncated without having to drop/create the
tables again.  This basically results in huge amount of disk space that gets wasted over time. Postgres
does not have this issue.     

- **Difficultly in using multiple disks**: Often multiple disks are used to spread the load of writes/reads.
InnoDB supports a DATA DIRECTORY configuation, but it has to be configured per table.  What is worse is that it
needs to be configured per partition.  This increaes the operator complexity to maintain partitions. Postgres solves
this using **tablespaces** and makes it really easy to use one or more disks. 
   


#### PostgreSQL and TimescaleDB add the following new features

In addition to resolving the above shotcomings... 

- **Aggregation tables are back**: Aggregation tables are where we track and record history of changes over time. This
 includes prefix counts by peer and family, advertisements and withdrawals by router/peer/asn/prefix, originating ASN
 prefix counts by family, etc.  These tables were disabled by default in MySQL because the performance with more than
 60,000,000 prefixes resulted in very poor InnoDB performance on full-table scans.  In other words, it would take
 more than 30 minutes to generate the aggregations.  We can now do this in just a few minutes with Postgres.
 
 
- **Better scale**: The current RouteViews data set (demo) has over **141,000,000** prefixes being monitored and over 
  **175,600,000** advertisements/withdrawals logged per day.  Postgres and TimescaleDB
  perform well enough to keep up with this scale while supporting the complex aggregations. 
 
  
- **Customizable retention policies**: TimescaleDB provides a simple method to purge old data, such as ```SELECT drop_chunks(interval '3 months', 'conditions');```. 
This enables simple cron or pg_agent events to maintain the desired retention.


- **Array datatype**: Postgres supports an array datatype to enable AS PATH and communities to be arrays 
instead of a string. 


- **INET datatype**: This is far better than the mysql **varbinary** type used to store the ip address. **GIST**
indexing supports prefix aware queries (e.g. find prefix 10.10.10.10) that would otherwise not be possible in MySQL. 


- **Better JSON support**: While MySQL has minimal support, Postgres has better support of native JSON. JSON datatypes
can be indexed on the JSON field if/when needed. This makes it possible to store JSON within a single field/column
supporting extraction and indexing on individual JSON objects. 
 

#### PostgreSQL and TimescaleDB add the following fixes

- **Peer states**: If the router does not support/implement a delay (**initial delay**) between router INIT and PEER UP messages,
 the MySQL consumer could process the PEER UP after the updates.  This results in
some peers showing incorrect states.   This has been fixed with the Postgres consumer. 


- **Prefix History**: The MySQL consumer logged history to ```path_attr_log``` and ```withdrawn_log``` tables.  ```path_attr_log```
log table only contained history if the prefix had an atribute change.  While this saved on some space, it resulted
in confusion with tracking withdrawal and subsequent advertisements.   This has changed with the Postgres consumer.
There is now a signle table ```ip_rib_log``` that contains both advertisements and withdrawals.  Duplicate advertisements with
the same attributes will be suppressed only if the previous was not a withdrawal.  This results in a natural
log of prefix history by suppressing route-refresh noise while maintaining high fidelity (microsecond granularity).

- **Table/Schema Changes**: Many any of the tables have been modified for postgres datatypes.   Some of the tables have been renamed
for better clarity.  
 


Implementation
--------------
The consumer implements all the **parsed message bus API's** to store all data.  The data is stored for real-time
and historical reporting. 

### Consumer Resume/Restart
Apache Kafka implements a rotating log approach for the message bus stream.  The default retention is large enough
to handle hundreds of peers with full internet routing tables for hours.  The consumer tracks where it is within the
log/stream by using offsets (via Apache Kafka API's).  This enables the consumer to resume where it left off in the event the consumer is restarted.    

The consumer offset is tracked by the client id/group id.  You can shutdown one consumer on host A and then start a
new consumer on host B using the same id's to enable host B to resume where host A left off.  In other words, the
consumer is portable since it does not maintain state locally. 

> #### Important
> Try to keep the consumer running at all times. While it is supported to stop/start the consumer without having
> to touch the collector, long durations of downtime can result in the consumer taking a while to catch-up.  
> 
> When the MySQL connection is running slow or when the consumer is catching up, you will see an INFO log message
> that reports that the queue size is above 500.  This will repeat every 10 seconds if it stays above 500.  Lack of
> these messages indicates that the consumer is running real-time. 

### Threading and PSQL Connections
The current threading model has one PSQL connection per thread.  Number of threads are configured in
[obmp-psql.yml](src/main/resources/obmp-psql.yml).  When the consumer starts, all threads will be initialized (running).

The consumer will dynamically map peers to threads using a **least queue size distribution**.  When all peers
are similar, this works well.  If a thread becomes congested, it will be **rebalanced** based on the rebalance
time interval in seconds. A rebalance can be slow as it requires that all messages in the thread queue be flushed
before peers can be rebalanced (redistributed).  Normally after one or two rebalances, the distribution should
be sufficient for an even load over all PSQL connections.

Threads will be dynamically terminated if they are not needed.  This is controlled by the scale back configuration. 
  

#### Thread/Writer Configuration
```yaml
  # Number of writer threads per processing type.
  #     The number of threads and psql connections are
  #     [types * writer_max_threads_per_type]. Each writer makes
  #     a connection to psql in order to execute SQL statements in parallel.
  #     The number of threads are auto-scaled up and down based on partition
  #     load.  If there is high load, additional threads will be added, up
  #     to the writer_max_threads_per_type.
  #
  #  Following types are implemented.
  #   - Default
  #   - as_path_analysis
  #   - base attributes
  writer_max_threads_per_type: 3

  # Number of consecutive times the writer queue (per type) can sustain over
  #    the high threshold mark.  If queue is above threshold for a consecutive
  #    writer_allowed_over_queue_times value, a new thread will be added for
  #    the writer type, providing it isn't already at max threads (per type).
  writer_allowed_over_queue_times: 2

  # Number of seconds the writer needs to sustain below the low queue threshold mark
  #     in order to trigger scaling back the number of threads in use.  Only one thread
  #     is scaled back a time.  It can take
  #     [writer_seconds_thread_scale_back * writer_max_threads_per_type - 1] time to scale
  #     back to one 1 (per type).
  writer_seconds_thread_scale_back: 7200

  # Number of seconds between rebalacing of writer threads
  #    Rebalance will drain writer queues at this interval if at least one writer is above threshold
  writer_rebalance_seconds: 1800

  # By default AS Path indexing is enabled.  This can be very resource intensive to psql
  #    and disk.   You can disable updating the psql 'as_path_analysis' table if
  #    this analysis is not needed/used.  Disabling this will effect the gen_asn_stats table,
  #    which will also effect anything that uses that table.
  disable_as_path_indexing: false

```

#### Load balancing/Redundancy
Unlike the MySQL consumer, the PSQL consumer is more efficent and should not require more than one PSQL instance per
PostgreSQL DB. Multiple consumers can be run.  When mutiple consumers are run, Kafka will balance the consumers
by Kafka partition.  The consumers will work fine with this. If one consumer stops working, the other will
take over.  Fault tolerance is ensured when 2 or more consumers are running.  

### RIB Dump Handling
When a collector is started, routers will make connections and start a RIB dump for each peer. This produces
an initial heavy load on the PSQL consumer. This is normal and should not cause for concern.  The consumer rate
varies by many factors, but normally 10M + prefixes can be consumed and handled within an hour.  After the RIB
dump, only incremental updates are sent (standard BGP here) allowing the consumer to be real-time without a delay.
It is expected that after RIB DUMP with stable routers/peers, BGP updates will be
in the DB in less than 100ms from when the router transmits the BMP message. 

Documentation
-------------

- [Postgres Server Setup](docs/POSTGRES.md)
- [Build and Install](docs/BUILD.md)
- [Running App](docs/RUN.md)




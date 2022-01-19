# OpenBMP PostgreSQL Backend

The PostgreSQL (PSQL) consumer implements the OpenBMP [Message Bus API](https://github.com/OpenBMP/OpenBMP.github.io/blob/main/api/kafka_message_schema.md) **parsed**
messages to collect and store BMP/BGP data from all collectors, routers, and peers in real-time. 

> **IMPORTANT**
> Migration to this consumer is being done in phases.  Currently the below address families are included:
> - Unicast IPv4
> - Unicast IPv6
> - Labeled Unicast IPv4
> - Labeled Unicast IPv6
> - Link-State (ISIS, OSPF, ...)



Implementation
--------------
The consumer implements all the **parsed message bus API's** to store all data.  The data is stored for real-time and historical reporting. 



### Consumer Resume/Restart

Kafka implements a rotating log approach for the message bus stream.  The default retention is large enough to handle hundreds of peers with full internet routing tables for hours.  The consume tracks where it is within the log/stream by using offsets (via Kafka API's).  This enables the consumer to resume where it left off in the event the consumer is restarted.    

The consumer offset is tracked by the client id/group id.  You can shutdown one consumer on host A and then start a new consumer on host B using the same id's to enable host B to resume where host A left off.  

In other words, the consumer is portable since it does not maintain state locally. 



> **Important**
> Try to keep the consumer running at all times. While it is supported to stop/start the consumer without having to touch the collector, long durations of downtime can result in the consumer taking a while to catch-up.  



The current threading model has one PSQL connection per thread.  Number of threads are configured in
[obmp-psql.yml](src/main/resources/obmp-psql.yml).  When the consumer starts, all threads will be initialized (running).

The consumer will dynamically map peers to threads using a **least queue size distribution**.  When all peers are similar, this works well.  If a thread becomes congested, it will be **rebalanced** based on the rebalance time interval in seconds. A rebalance can be slow as it requires that all messages in the thread queue be flushed before peers can be rebalanced (redistributed).  Normally after one or two rebalances, the distribution should be sufficient for an even load over all PSQL connections.

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
  #     [writer_seconds_thread_scale_back * writer_max_threads_per_type - 1] time
  #     to scale back to one 1 (per type).
  writer_seconds_thread_scale_back: 7200

  # Number of seconds between rebalacing of writer threads
  #    Rebalance will drain writer queues at this interval if at least one writer
  #    is above threshold
  writer_rebalance_seconds: 1800

```



#### Load balancing/Redundancy

Multiple consumers can be run.  When mutiple consumers are run, Kafka will balance the consumers
by Kafka partition.  The consumers will work fine with this. If one consumer stops working, the other will
take over.  Fault tolerance is ensured when 2 or more consumers are running.  

### RIB Dump Handling
When a collector is started, routers will make connections and start a RIB dump for each peer. This produces an initial heavy load on the PSQL consumer. This is normal and should not cause for concern.  The consumer rate varies by many factors, but normally 10M + prefixes can be consumed and handled within an hour.  After the RIB dump, only incremental updates are sent (standard BGP here) allowing the consumer to be real-time without a delay.
It is expected that after RIB DUMP with stable routers/peers, BGP updates will be
in the DB in less than 100ms from when the router transmits the BMP message. 

Documentation
-------------

- [Build and Install](docs/BUILD.md)
- [Running App](docs/RUN.md)




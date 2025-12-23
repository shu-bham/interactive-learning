# Increment 05: Replication Internals (PSYNC2 & Failover)

Redis replication is the cornerstone of High Availability (HA). As a Staff Engineer, you must understand the difference between "I'm copying data" and "I'm staying in sync."

---

## 1. The Replication Handshake

When a Replica connects to a Primary:
1. **Handshake**: Authenticate and exchange capabilities.
2. **Synchronization**: The Primary decides whether to do a **Full Sync** or a **Partial Sync**.

---

## 2. Full Sync vs. Partial Sync (The PSYNC Secret)

### Full Sync (The Heavy Lift)
If the Replica is new or has been offline too long, the Primary:
1. Forks a child (BGSAVE) to create an RDB.
2. Streams the RDB to the Replica.
3. Buffers all new incoming writes during the RDB transfer.
4. Once the RDB is loaded, the Replica applies the buffered writes.

### Partial Sync (PSYNC / PSYNC2)
If the Replica was only gone for a few seconds, it can request a Partial Sync. 
- **Replication ID**: Every Primary has a unique ID and an **Offset**.
- **Replication Backlog**: A circular buffer on the Primary that stores recent writes.
- If the Replica's offset is still within the backlog, the Primary just sends the missing bytes. **Zero disk IO required.**

---

## 3. PSYNC2 (Redis 4.0+)
In older versions, if a Replica was promoted to Primary during a failover, all other Replicas had to do a Full Resync because the Master ID changed.
**PSYNC2** allows Replicas to keep their synchronization status even after a failover, by preserving the Replication ID and Offset of the previous Primary.

---

## 4. Diskless Replication
By default, the Primary writes the RDB to disk before sending it.
With `repl-diskless-sync yes`, the Primary skips the disk and sends the RDB directly over the network socket.
- **When to use?** Fast network, slow disks (common in cloud environments).

---

## 5. Hands-on Exercise: Observing Slave Lag

### Step 1: Check Replication Status
On your `redis-primary`:
```redis
INFO replication
```
Observe the `connected_slaves` count and the `master_repl_offset`.

### Step 2: Simulate Load and Watch Offset
Run a variety of writes on the Primary:
```bash
# Seeding Strings
docker exec -it redis-primary redis-cli "EVAL" "for i=1,10000 do redis.call('SET', 'repl_s_'..i, i) end" 0

# Seeding Hashes
docker exec -it redis-primary redis-cli "EVAL" "for i=1,1000 do redis.call('HSET', 'repl_h_'..i, 'field1', i, 'field2', i*2) end" 0
```

Watch the offsets on both nodes to see the lag catch up:
```bash
# On primary
docker exec -it redis-primary redis-cli INFO replication | grep offset
# On replica
docker exec -it redis-replica redis-cli INFO replication | grep offset
```

---

## Your Task
1. What is the default size of the `repl-backlog-size`? (Found in `redis.conf`).
2. If you have 10GB of write traffic per hour and the backlog is 1MB, what happens to a Replica that disconnects for 5 minutes?
3. Find the `min-slaves-to-write` setting. Why would a Staff Engineer enable this?

---

## Solutions & Staff Level Insights

### Task 1: Backlog Size
Default is usually **1MB**. 

### Task 2: The Resync Trap
If the write traffic is high and the backlog is small, the offset will "fall off" the buffer quickly.
- In this scenario, a 5-minute disconnect will almost certainly trigger a **Full Resync**.
- **Staff Level**: For big production clusters, we often increase `repl-backlog-size` to several hundred MBs (or GBs) to allow for network blips without triggering heavy Full Syncs.

### Task 3: `min-replicas-to-write` (formerly `min-slaves-to-write`)
This setting prevents the Primary from accepting writes if it doesn't have at least $N$ replicas healthy and within $M$ seconds of lag.
- **Why?**: It prevents the "Split Brain" scenario where a Primary is isolated from its replicas but still taking writes that will be lost once it re-joins and becomes a replica itself.

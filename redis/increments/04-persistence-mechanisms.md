# Increment 04: RDB vs AOF (The Durability Trade-offs)

In standard production environments, Redis is not just a cache; it often acts as a primary data store or a critical state manager. As a Staff Engineer, you must decide how to balance **Durability** (not losing data) against **Performance** (latency spikes).

---

## 1. RDB (Redis Database) - The Snapshot

RDB performs point-in-time snapshots of your dataset at specified intervals.

### How it works:
1. Redis calls `fork()`.
2. The child process writes the entire dataset to a temporary RDB file.
3. Once finished, it replaces the old RDB file.

### Staff Level Insight: The `fork()` Cost
While the child process saves data, it uses **Copy-on-Write (CoW)**. 
- **The Catch**: If you have a 32GB Redis instance and your write rate is high, `fork()` can take 100ms+, causing a visible "STW" (Stop-The-World) pause for clients.
- **RDB Binary Format**: It is extremely compact and fast to load, making it ideal for backups and disaster recovery.

---

## 2. AOF (Append Only File) - The Transaction Log

AOF records every write operation received by the server. These operations are appended to a log file.

### Fsync Policies:
1. `appendfsync always`: `fsync()` after every write. Extremely slow, but safest.
2. `appendfsync everysec`: (Default) `fsync()` in a background thread every second. Compromise between speed and safety.
3. `appendfsync no`: Let the OS decide when to flush. Fastest, but risky.

### The AOF Rewrite (`BGREWRITEAOF`)
As the log grows, it becomes inefficient. Redis periodically "rewrites" it by creating a new file that only contains the *minimum* commands needed to reconstruct the current memory state.

---

## 3. Hybrid Persistence (Redis 4.0+)

Most modern deployments use **Hybrid Persistence**. 
- The AOF file is prefixed with an RDB snapshot.
- The remaining "tail" of the file contains the standard AOF command log.
- **Benefit**: Fast loading (from RDB) + Granular recovery (from AOF).

---

## 4. Hands-on Exercise: Observing Persistence

### Step 1: Triggering a Snapshot (RDB)
Connect to your `redis-primary` and run:
```redis
SET persistence_test "snapshot_me"
BGSAVE
```
Check the output of `LASTSAVE` or look inside the `data/primary` directory for `dump.rdb`.

### Step 2: Enabling AOF
By default, AOF is often disabled in base configs. Let's enable it live:
```redis
CONFIG SET appendonly yes
```
Now, perform some writes and check the `appendonly.aof` (or `.aof.manifest` in v7) file in the `data/` directory.

### Step 3: Performance Impact
Notice how the `INFO persistence` command gives you the duration of the last RDB/AOF save.

---

## Your Task
1. Look at `redis.conf`. What is the default `save` configuration? (e.g., `save 900 1`). What does it mean?
2. Research `aof-use-rdb-preamble`. Is it enabled by default in Redis 7?
3. **Staff Challenge**: If you have a write-heavy workload (100k OPS) and a 16GB dataset, would you prefer RDB or AOF for minimum latency impact? Why?

---

## Solutions & Staff Level Insights

### Task 1: Default Save
`save 900 1` means "Save if at least 1 key changed in 900 seconds (15 mins)". 
Redis usually has multiple tiers, e.g., `save 300 10` and `save 60 10000`. This allows for faster snapshots during high-traffic periods.

### Task 2: Preamble
Yes, `aof-use-rdb-preamble` is default `yes` in recent versions. It makes AOF files look like binary RDB data at the start.

### Task 3: The Write-Heavy Conflict
- **RDB**: High latency spikes during `fork()`.
- **AOF**: Constant small CPU/IO overhead due to flushing.
- **Staff Solution**: For minimum latency at scale, many engineers disable persistence on the **Primary** and only enable AOF/RDB on **Replicas**. This protects the Primary's CPU and memory from the `fork()` overhead while still having a durable backup.

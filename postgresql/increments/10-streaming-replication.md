# 🎯 Increment 10: Streaming Replication (vs MySQL Replication)

**Duration**: 60 minutes  
**Difficulty**: ⭐⭐⭐⭐ Deep Dive

## 📋 Quick Summary

PostgreSQL changed the game with **Physical Streaming Replication**. Unlike MySQL's traditional binary log replication (which replays SQL or Row changes), PostgreSQL replication streams the **exact disk blocks** (WAL) as they are written to the primary.

**Key Concepts**:
- **Physical Replication**: Byte-for-byte copy of the primary's disk state.
- **Streaming**: Data flows over a network socket in real-time.
- **Asynchronous**: Primary commits immediately (default, faster).
- **Synchronous**: Primary waits for at least one replica to acknowledge (safer).
- **Hot Standby**: The replica is open for read-only queries.

---

## 🎓 Theory (25 minutes)

### 1. Physical vs MySQL (Logical) Replication

| Feature | MySQL (Binlog) | PostgreSQL (Streaming) |
|---------|---------------|-----------------------|
| Type | Logical (SQL or Rows) | Physical (Disk Blocks/WAL) |
| Fragility| Moderate (Data drift possible) | Extremely Robust (Exact copy) |
| Flexibility| Can replicate specific tables | Replicates the **whole instance** |
| Performance| Single-threaded (usually) | Very low overhead |

> [!IMPORTANT]
> Because Physical Replication is byte-for-byte, the Primary and Replica **must be the same major version** and usually the same OS/architecture. You cannot easily replicate from PG 15 to PG 16 using Physical Replication (unlike MySQL).

### 2. How it works

1. **WalWriter** on Primary writes to WAL.
2. **WalSender** on Primary reads from WAL and sends to Replica.
3. **WalReceiver** on Replica receives WAL.
4. **Startup Process** on Replica replays WAL into its data files.

### 3. Synchronous Replication

You can choose exactly how "durable" your replication is:
- `synchronous_commit = off`: Fastest, no waiting.
- `synchronous_commit = local`: Wait for primary flush.
- `synchronous_commit = on`: Wait for replica to receive WAL.
- `synchronous_commit = remote_apply`: Wait for replica to actually *see* the data.

---

## 🧪 Hands-On Exercises (25 minutes)

### Exercise 1: Setting up the Streaming Replica (Hands-on)

Follow these steps to initialize your replica. Since we are using Docker, we'll use `pg_basebackup` to clone the primary's data directory.

#### Step 1: Create a Replication User on the Primary
Connect to your primary database and create a user with replication privileges.

```bash
./scripts/connect-primary.sh
```

Inside `psql`:
```sql
-- Create a dedicated user for replication
CREATE ROLE replicator WITH REPLICATION PASSWORD 'replpass' LOGIN;
```

#### Step 2: Prepare the Replica
We need to "wipe" the replica's data directory and fill it with a fresh backup from the primary. 

```bash
# 1. Stop the replica container if it's running
docker stop postgresql-replica

# 2. Use a temporary container to wipe the replica volume and run pg_basebackup
# Note: We use 'postgresql_pg-network' as the default compose network name
docker run --rm \
  --network postgresql_pg-network \
  -v postgresql_pg-replica-data:/var/lib/postgresql/data \
  postgres:16 \
  bash -c "rm -rf /var/lib/postgresql/data/* && \
           PGPASSWORD=replpass pg_basebackup -h postgresql-primary -D /var/lib/postgresql/data -U replicator -Fp -Xs -P -R"
```

> [!TIP]
> If the command above fails with a "network not found" error, run `docker network ls` to find the exact name of the network created by your docker-compose (usually `[folder]_pg-network`). If it fails with an "HBA" error, ensure you have restarted your primary after editing the config files!

**What do these flags mean?**
- `-h`: Host (Primary)
- `-D`: Data directory
- `-U`: User
- `-P`: Progress bar
- `-R`: **CRITICAL** - Generates the `standby.signal` and connection settings automatically.

#### Step 3: Start the Replica
Now start the container back up. It will detect the `standby.signal` and start in Hot Standby mode.

```bash
docker start postgresql-replica
```

#### Step 4: Verify Connection
Check the logs of the replica to see it successfully connected to the primary.

```bash
docker logs postgresql-replica
```
*Look for: "database system is ready to accept read-only connections"*

#### Step 5: Test the Replica
Once the replica is ready, you can connect to it using our new helper script.

```bash
./scripts/connect-replica.sh
```

Try running a `SELECT` on the users table. Then try an `INSERT`—it should fail because the replica is read-only!

---

### Exercise 2: Checking Replication Status

Run this on the **Primary**:

```sql
SELECT * FROM pg_stat_replication;
```

**What to look for**:
- `state`: Should be `streaming`.
- `sync_state`: `async` (default) or `sync`.
- `replay_lag`: The delay between Primary and Replica.

### Exercise 3: Promoting a Replica (Failover)

If the primary dies, you "promote" the replica:

```bash
# Hypothetical command on the replica server
docker exec -it postgresql-replica pg_ctl promote -D /var/lib/postgresql/data
```

---

## 🎤 Interview Question Practice

**Q1**: "What is the biggest downside of Physical Streaming Replication?"

**Answer**: Physical replication is "all or nothing"—it replicates the entire database cluster (every database inside the instance). You cannot choose to replicate only one specific table or database. Also, the primary and replica must be on the same major version and architecture. If you need more flexibility, you must use **Logical Replication**.

**Q2**: "What happens to a replica if the network between it and the primary goes down for an hour?"

**Answer**: The replica will stop receiving new data. However, as soon as the network returns, it will attempt to reconnect. If the primary still has the missing WAL files (controlled by `max_wal_size` or **Replication Slots**), the replica will catch up. If the WAL files have been deleted, the replica will fail and must be rebuilt.

---

## ✅ Completion Checklist

- [ ] Explain the difference between Physical and Logical replication
- [ ] List 4 `synchronous_commit` levels
- [ ] Understand how to check for replication lag
- [ ] Know that "Hot Standby" must be enabled to query a replica

## 🔗 Next: Increment 11 - Logical Replication & Partitioning
Ready to replicate only specific tables or upgrade across versions? Let's master **Logical Replication**.

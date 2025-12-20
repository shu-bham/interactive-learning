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

### Exercise 1: Expanding the Lab (Adding a Replica)

We need to update our `docker-compose.yml` to add a secondary node. 

> [!NOTE]
> For this exercise, I've prepared a specialized setup. We'll simulate a replica connection.

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

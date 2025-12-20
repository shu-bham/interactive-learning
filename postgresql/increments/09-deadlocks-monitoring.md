# 🎯 Increment 09: Deadlocks & Lock Monitoring

**Duration**: 40 minutes  
**Difficulty**: ⭐⭐⭐⭐ Deep Dive

## 📋 Quick Summary

In a high-concurrency senior backend role, you'll eventually face the mystery of "Why is this simple update taking 10 seconds?". The answer is almost always **Lock Contention**. PostgreSQL gives you surgical tools to find the culprit.

**Key Concepts**:
- **pg_locks**: The master view of every lock currently held or waited for.
- **deadlock_timeout**: How long PostgreSQL waits before checking for a circular lock dependency.
- **pg_stat_activity**: Link locked processes to actual SQL queries.
- **Terminating Backends**: Safely stopping a rogue process.

---

## 🎓 Theory (15 minutes)

### 1. The Lock Manager

PostgreSQL stores all locks in a shared memory region.
- `pg_locks` contains: `pid`, `mode` (Exclusive, Share, etc.), `granted` (True/False).
- If `granted = false`, that process is **blocked**.

### 2. Deadlock Detection

A **Deadlock** happens when T1 waits for T2, and T2 waits for T1. 
- PostgreSQL doesn't check for this constantly (too expensive).
- It waits for `deadlock_timeout` (default 1 second).
- If the block persists, it runs a "Deadlock Search" and kills one of the transactions.

### 3. Killing Connections

| Function | Action | MySQL Equivalent |
|----------|--------|------------------|
| `pg_cancel_backend(pid)` | Stop the current query | `KILL QUERY <id>` |
| `pg_terminate_backend(pid)`| Kill the connection | `KILL <id>` |

---

## 🧪 Hands-On Exercises (20 minutes)

### Exercise 1: Simulate a Lock Block

```sql
-- Terminal 1
BEGIN;
UPDATE users SET age = age + 1 WHERE user_id = 1;
-- (Keep open)

-- Terminal 2
UPDATE users SET age = age + 5 WHERE user_id = 1;
-- (This will hang/wait)
```

### Exercise 2: Find the Blocker (The "Senior" Query)

Open **Terminal 3** and run this critical query:

```sql
SELECT
    blocking_locks.pid  AS blocking_pid,
    blocking_activity.usename AS blocking_user,
    blocking_activity.query AS blocking_query,
    blocked_locks.pid AS blocked_pid,
    blocked_activity.usename AS blocked_user,
    blocked_activity.query AS blocked_query
FROM pg_catalog.pg_locks blocked_locks
JOIN pg_catalog.pg_stat_activity blocked_activity ON blocked_locks.pid = blocked_activity.pid
JOIN pg_catalog.pg_locks blocking_locks 
    ON blocking_locks.locktype = blocked_locks.locktype
    AND blocking_locks.DATABASE IS NOT DISTINCT FROM blocked_locks.DATABASE
    AND blocking_locks.relation IS NOT DISTINCT FROM blocked_locks.relation
    AND blocking_locks.page IS NOT DISTINCT FROM blocked_locks.page
    AND blocking_locks.tuple IS NOT DISTINCT FROM blocked_locks.tuple
    AND blocking_locks.virtualxid IS NOT DISTINCT FROM blocked_locks.virtualxid
    AND blocking_locks.transactionid IS NOT DISTINCT FROM blocked_locks.transactionid
    AND blocking_locks.classid IS NOT DISTINCT FROM blocked_locks.classid
    AND blocking_locks.objid IS NOT DISTINCT FROM blocked_locks.objid
    AND blocking_locks.objsubid IS NOT DISTINCT FROM blocked_locks.objsubid
    AND blocking_locks.pid != blocked_locks.pid
JOIN pg_catalog.pg_stat_activity blocking_activity ON blocking_locks.pid = blocking_activity.pid
WHERE NOT blocked_locks.granted;
```

### Exercise 3: Resolve the Block

```sql
-- Kill the blocking process from Terminal 3
SELECT pg_terminate_backend(<BLOCKING_PID>);
```
Verify that Terminal 2 now either completes or fails.

---

## 🎤 Interview Question Practice

**Q1**: "What's the difference between `pg_cancel_backend` and `pg_terminate_backend`?"

**Answer**: `pg_cancel_backend` sends a SIGINT signal, which attempts to stop the current query but keeps the connection alive. `pg_terminate_backend` sends a SIGTERM, which kills the entire backend process and the client's connection. Always try `cancel` first before `terminate`.

**Q2**: "How do you prevent deadlocks in your application code?"

**Answer**: 
1. Always acquire locks in the same order (e.g., sort IDs before updating).
2. Keep transactions as short as possible.
3. Use `SELECT ... FOR UPDATE NOWAIT` or `SKIP LOCKED` if the application can handle a failure or skip a busy row.

---

## ✅ Completion Checklist

- [ ] Explain how to detect a blocked query in PostgreSQL
- [ ] Use `pg_stat_activity` to see how long a query has been running
- [ ] Successfully find and kill a blocking process
- [ ] Understand the purpose of `deadlock_timeout`

## 🔗 Next Phase: Replication & Extensions
You've mastered the single-node performance and safety. Now let's see how PostgreSQL scales out with **Streaming and Logical Replication**.

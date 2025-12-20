# 🎯 Increment 13: pg_stat Views & Performance Monitoring

**Duration**: 50 minutes  
**Difficulty**: ⭐⭐⭐⭐ Deep Dive

## 📋 Quick Summary

MySQL has the performance schema. PostgreSQL has **pg_stat views**. These internal views track every tuple read, every index scanned, and every millisecond spent waiting for I/O. For a senior dev, these views are your "dashboard" for DB health.

**Key Concepts**:
- **pg_stat_activity**: Who is doing what right now?
- **pg_stat_user_tables**: Which tables need indexes? (Seq scan vs Index scan).
- **pg_stat_user_indexes**: Which indexes are unused and eating space?
- **Wait Events**: Is the CPU waiting for Disk, Network, or Locks?

---

## 🎓 Theory (20 minutes)

### 1. Table & Index Health

| View | Metric to Watch | Meaning |
|------|-----------------|---------|
| `pg_stat_user_tables` | `seq_scan` vs `idx_scan` | High `seq_scan` on big tables = missing index. |
| `pg_stat_user_tables` | `n_dead_tup` | High count = Autovacuum needs tuning. |
| `pg_stat_user_indexes`| `idx_scan` | `0` scans = Unused index (safe to delete). |

### 2. Wait Events (The "Why is it slow?" Tool)

In `pg_stat_activity`, look at `wait_event_type` and `wait_event`:
- `IO`: Waiting for disk (Slow disk or memory pressure).
- `Lock`: Waiting for another transaction.
- `CPU`: Busy processing (Good, usually).

### 3. Checkpoint & BGWriter Health

The `pg_stat_bgwriter` view tells you if your `shared_buffers` are big enough. If the `checkpointer` is doing all the work, you're fine. If `backends` are forced to write to disk themselves (`buffers_backend`), your memory settings are too low.

---

## 🧪 Hands-On Exercises (20 minutes)

### Exercise 1: Finding Unused Indexes

```sql
-- Find indexes that haven't been used since the last stats reset
SELECT 
    schemaname, relname, indexrelname, 
    idx_scan, 
    pg_size_pretty(pg_relation_size(indexrelid)) as index_size
FROM pg_stat_user_indexes 
WHERE idx_scan = 0 
AND idx_unique = false;
```

### Exercise 2: Detecting Index-Missing Queries

```sql
-- List tables with highest sequential scan volume
SELECT 
    relname, 
    seq_scan, 
    seq_tup_read, 
    idx_scan, 
    n_live_tup
FROM pg_stat_user_tables 
WHERE seq_scan > 0 
ORDER BY seq_tup_read DESC;
```

### Exercise 3: Real-time Wait Event Analysis

```sql
-- See what current active queries are waiting for
SELECT pid, usename, state, wait_event_type, wait_event, query
FROM pg_stat_activity
WHERE state = 'active';
```

---

## 🎤 Interview Question Practice

**Q1**: "How do you know if your `shared_buffers` are undersized?"

**Answer**: Monitor `pg_stat_bgwriter`. If you see a high number of `buffers_backend` (buffers written directly by backend processes instead of the background writer or checkpointer), it means backend processes aren't finding free buffers and are forced to perform I/O themselves. Increasing `shared_buffers` or tuning `bgwriter_delay` is usually the fix.

**Q2**: "How do you identify 'Deadlock' potential before it happens?"

**Answer**: By monitoring `pg_stat_activity` for transactions in a `waiting` state for an extended period. Also, analyzing `pg_locks` for many ungranted locks on the same relation is a red flag for future deadlocks or severe contention.

---

## ✅ Completion Checklist

- [ ] Explain the difference between `seq_tup_read` and `idx_tup_fetch`
- [ ] Identify an unused index and justify its removal
- [ ] List 3 common `wait_event` categories
- [ ] Use `pg_stat_user_tables` to check if autovacuum has run recently

## 🔗 Next: Increment 14 - Interview Preparation & Cheat Sheet
The final step! Let's consolidate everything into a **Senior Developer Cheat Sheet** for your upcoming interviews.

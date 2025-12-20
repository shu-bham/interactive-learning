# 🎯 Increment 07: Table Bloat, VACUUM & Autovacuum

**Duration**: 60 minutes  
**Difficulty**: ⭐⭐⭐⭐⭐ Expert

## 📋 Quick Summary

Because PostgreSQL's MVCC creates new row versions instead of overwriting, tables naturally "bloat". **VACUUM** is the garbage collector that reclaims this space. If it fails, your database will eventually stop working.

**Key Concepts**:
- **VACUUM**: Marks dead tuples as "free space" for future inserts.
- **VACUUM FULL**: Physically rewrites the table to disk (Exclusive Lock!).
- **Autovacuum**: The background daemon that handles this automatically.
- **Transaction ID Wraparound**: A critical "stop-the-world" risk if vacuuming is neglected.

---

## 🎓 Theory (25 minutes)

### 1. Why VACUUM is necessary

Recall Increment 04: `UPDATE` = `DELETE` + `INSERT`.
Without VACUUM, the "deleted" rows would sit on disk forever, eating space and slowing down scans.

### 2. The Visibility Map (VM)

PostgreSQL keeps a bit for every page: "Is every row in this page visible to everyone?". 
- If yes, **Index Only Scans** can skip the heap.
- VACUUM updates this map.

### 3. VACUUM vs VACUUM FULL

| Feature | Standard `VACUUM` | `VACUUM FULL` |
|---------|------------------|---------------|
| Locking | Concurrent (No block) | **Exclusive Lock** (Blocks all) |
| Strategy| Mark space as reusable | Rewrite table from scratch |
| Result  | Doesn't shrink file size | Shrinks file size |

> [!WARNING]
> Never run `VACUUM FULL` on a production table during peak hours. It will lock the table completely until it finishes. Use `pg_repack` or `extension` for online bloat removal.

### 4. Transaction ID (XID) Wraparound

Transaction IDs are 32-bit (4 billion). After 2 billion, they "wrap around". To PostgreSQL, a new transaction ID `3` might look "older" than `2,000,000,000`. 
**VACUUM FREEZE** converts old XIDs to a special `FrozenXID` to prevent data loss.

---

## 🧪 Hands-On Exercises (25 minutes)

### Exercise 1: Manual Vacuuming

```sql
-- 1. Check dead tuples (from our earlier bloat exercise)
SELECT relname, n_dead_tup FROM pg_stat_user_tables WHERE relname = 'users';

-- 2. Run a standard vacuum
VACUUM users;

-- 3. Check again
SELECT relname, n_dead_tup FROM pg_stat_user_tables WHERE relname = 'users';
-- Dead tuples should be 0, but the file size did NOT shrink.
```

### Exercise 2: Observing Autovacuum Settings

```sql
-- See the triggers for autovacuum
SELECT name, setting, unit FROM pg_settings WHERE name LIKE 'autovacuum%';
```

**Key setting**: `autovacuum_vacuum_scale_factor` (default 0.2). This means start vacuuming when 20% of the table is dead tuples. For a 1TB table, 200GB of bloat is too much! Senior devs set this to 0.01 or 0.05.

### Exercise 3: Bloat Analysis (The "Senior" Query)

```sql
-- This query estimates bloat percentage (simplified)
SELECT
    current_database(), schemaname, relname, 
    n_dead_tup, 
    n_live_tup,
    ROUND(n_dead_tup::float / GREATEST(n_live_tup, 1)::float * 100, 2) as bloat_ratio
FROM pg_stat_all_tables
WHERE n_live_tup > 0
ORDER BY bloat_ratio DESC;
```

---

## 🎤 Interview Question Practice

**Q1**: "Why shouldn't I just turn off Autovacuum?"

**Answer**: Turning off Autovacuum is one of the most dangerous things you can do in PostgreSQL. It will lead to:
1. Massive table and index bloat (killing performance).
2. Out-of-date statistics (causing the query planner to pick bad plans).
3. Eventually, **Transaction ID Wraparound**, which will force the database into read-only mode to prevent data corruption.

**Q2**: "How do you reduce table bloat without locking the table?"

**Answer**: 
1. Tune Autovacuum to be more aggressive (lower scale factors).
2. Use the `pg_repack` or `pg_squeeze` extensions, which rewrite the table in the background using triggers/logs without an exclusive lock.
3. If only a small amount of bloat is present, sometimes a `VACUUM ANALYZE` is enough to reclaim space for future inserts.

---

## ✅ Completion Checklist

- [ ] Explain why standard `VACUUM` doesn't shrink file size
- [ ] Understand the difference between Live and Dead tuples
- [ ] List 2 risks of XID Wraparound
- [ ] Know how to find the "last autovacuum" time for a table

## 🔗 Next Phase: Transactions & Concurrency
You've mastered storage and performance! Now let's dive into **Locking, Deadlocks, and Isolation Levels**.

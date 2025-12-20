# 🎯 Increment 14: Senior PostgreSQL Interview Cheat Sheet

**Duration**: 60 minutes  
**Difficulty**: ⭐⭐⭐⭐⭐ Expert

## 📋 Quick Summary

This final increment is your "Senior Dev" mental model. We'll consolidate every major technical concept into a fast-access cheat sheet that helps you talk like a PostgreSQL expert in your upcoming interviews.

---

## 🎓 The PostgreSQL vs MySQL Comparison Matrix

| Topic | MySQL (InnoDB) | PostgreSQL | WHY it matters (Interview) |
|-------|---------------|------------|----------------------------|
| **Arch** | Threads | Processes | Scaling (Concurrency vs Memory) |
| **Locking** | Pessimistic | Optimistic (SSI) | How app handles serialization errors. |
| **Updates** | In-place | Append-only (MVCC) | Explaining Bloat & VACUUM theory. |
| **Memory** | Buffer Pool (80%) | Shared Buffers (25%) + OS | Understanding double-buffering. |
| **Indices** | B+Tree | B-Tree, GIN, GiST, BRIN | Choosing the right tool for the data. |
| **DDL** | Implicit Commit | Transactional DDL | Zero-downtime migration safety. |

---

## 🧠 High-Level Interview Patterns

### 1. How would you design a High Availability (HA) stack?
**Your Answer**: "I would use **Streaming Replication** for the data layer, **Patroni** with **etcd** for leader election and failover management, and **PgBouncer** for connection pooling to handle the process-per-connection overhead."

### 2. How do you handle zero-downtime schema changes?
**Your Answer**: "PostgreSQL's **Transactional DDL** is a base. For indexes, I use `CREATE INDEX CONCURRENTLY`. For column additions, I ensure a default value isn't applied to existing rows in a single heavy lock (though modern PG handles this better). For complex changes, I use **Logical Replication** to sync to a new schema and then cut over."

### 3. What is your troubleshooting workflow for a slow query?
**Your Answer**: 
1. `EXPLAIN (ANALYZE, BUFFERS)` to see actual costs and IO.
2. Check `pg_stat_statements` for execution frequency and mean time.
3. Verify table statistics (`pg_stats`) and run `ANALYZE` if needed.
4. Check for **Table Bloat** using `pg_stat_user_tables`.
5. Check for **Wait Events** using `pg_stat_activity`.

---

## 🛠️ The "Senior" Troubleshooting Toolkit

| Problem | Command / View | First Fix |
|---------|---------------|-----------|
| **Blocked Query** | `pg_locks` + `pg_stat_activity` | Kill the blocker |
| **Slow Disk IO** | `pg_stat_bgwriter` | Increase `shared_buffers` |
| **Missing Index** | `pg_stat_user_tables` | Add Index (CONCURRENTLY) |
| **Storage Growth**| `n_dead_tup` | Aggressive Autovacuum tuning |

---

## 🎤 Top 5 "Hard" Interview Questions

1. **"Explain the visibility rules of MVCC using xmin/xmax."**
   - *Key words*: Transaction ID, Committed, Snapshot, Tuple.

2. **"What is the 'Double Buffering' problem and how do you mitigate it?"**
   - *Key words*: OS Page Cache, shared_buffers, 25% RAM rule.

3. **"How does a B-Tree index differ from a GIN index on a JSONB column?"**
   - *Key words*: Equality/Range (B-Tree) vs Contains (GIN), Internal tree structure.

4. **"What is the 'HOT' (Heap Only Tuple) optimization?"**
   - *Key words*: Update, Index Pointer, Same Page, Vacuum.

5. **"Why should you avoid extremely long-running transactions in PostgreSQL?"**
   - *Key words*: Prevent Vacuum, XID wraparound risk, Table bloat.

---

## ✅ Course Graduation Checklist

- [x] Successfully set up and managed a PostgreSQL cluster via Docker
- [x] Understood the physical storage and process model
- [x] Mastered the query planner and advanced indexing
- [x] Learned how to troubleshoot locks and performance bottlenecks
- [x] Built the mental models to pass a Senior Backend Interview

## 🏆 Final Words
PostgreSQL is a deep, professional database. By completing this hands-on course, you've moved past "just writing SQL" to understanding the systems architecture that powers $100B+ companies.

**Good luck with your interviews!**

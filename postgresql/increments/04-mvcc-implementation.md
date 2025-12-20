# 🎯 Increment 04: MVCC Implementation in PostgreSQL

**Duration**: 60 minutes  
**Difficulty**: ⭐⭐⭐⭐⭐ Expert

## 📋 Quick Summary

PostgreSQL's **Multi-Version Concurrency Control (MVCC)** is brilliant but controversial. Unlike MySQL (InnoDB), which uses an **Undo Log** to reconstruct old versions, PostgreSQL stores multiple versions of the same row **directly in the table** (the heap).

**Key Concepts**:
- **xmin**: Transaction ID that created the row version (tuple).
- **xmax**: Transaction ID that deleted or updated the row version.
- **Dead Tuples**: Old row versions that are no longer visible to any transaction.
- **Bloat**: The physical growth of a table due to accumulated dead tuples.

---

## 🎓 Theory (25 minutes)

### 1. The Big Difference: PostgreSQL vs InnoDB

| Feature | MySQL (InnoDB) | PostgreSQL |
|---------|---------------|------------|
| Storage | 1 version in table + N in Undo Log | All versions in the table (Heap) |
| Update | In-place (usually) | Delete + Insert (always) |
| Read | Reconstruct old version from Undo | Find visible version in the table |
| Cleanup | Purge thread cleans Undo Log | VACUUM marks dead tuples for reuse |

> [!CAUTION]
> **Because every UPDATE is a DELETE + INSERT**, updating a row in PostgreSQL is significantly more expensive on IO and disk space than in MySQL. This leads to the infamous "Table Bloat".

### 2. Hidden Columns (The Version Trackers)

Every row (tuple) in PostgreSQL has internal columns you can see if you ask:

- **xmin**: The `txid` that inserted this row.
- **xmax**: If `0`, the row is alive. If `>0`, the `txid` that deleted/updated it.

### 3. Visibility Rule (Simplified)

A row is visible to your transaction if:
1. `xmin` is **committed** and was started before your snapshot.
2. `xmax` is **0** (not deleted) or was started **after** your snapshot.

---

## 🧪 Hands-On Exercises (25 minutes)

### Exercise 1: Peeking behind the curtain (xmin/xmax)

```sql
-- 1. Look at the hidden columns
SELECT xmin, xmax, user_id, username FROM users;

-- 2. Open a new transaction (don't commit)
BEGIN;
UPDATE users SET age = age + 1 WHERE username = 'john_doe';

-- 3. In the same transaction, see the change
SELECT xmin, xmax, user_id, username, age FROM users WHERE username = 'john_doe';
-- Note the new xmin and xmax!

-- 4. In a DIFFERENT terminal, check the same row
-- SELECT xmin, xmax, age FROM users WHERE username = 'john_doe';
-- You'll see the OLD xmin and original age.

ROLLBACK;
```

### Exercise 2: Observing Bloat (The hard way)

```sql
-- 1. Check current size of users table
SELECT pg_size_pretty(pg_total_relation_size('users'));

-- 2. Hammer the table with updates
DO $$
BEGIN
   FOR i IN 1..1000 LOOP
      UPDATE users SET age = age + 1;
   END LOOP;
END $$;

-- 3. Check size again
SELECT pg_size_pretty(pg_total_relation_size('users'));
-- It grew, even though the number of rows is the same!
```

### Exercise 3: Counting Dead Tuples

PostgreSQL provides a view to track how "dirty" a table is.

```sql
SELECT 
    relname, 
    n_live_tup, 
    n_dead_tup, 
    last_vacuum, 
    last_autovacuum
FROM pg_stat_user_tables
WHERE relname = 'users';
```

---

## 🎤 Interview Question Practice

**Q1**: "Why does an `UPDATE` in PostgreSQL increase the table size on disk?"

**Answer**: PostgreSQL uses an append-only MVCC architecture. An `UPDATE` does not overwrite the existing row; it creates a new version of the row with a new `xmin` and marks the old row with an `xmax`. The old version (dead tuple) remains on disk until it is cleaned up by `VACUUM`.

**Q2**: "What is the 'HOT' (Heap Only Tuple) optimization?"

**Answer**: Since every `UPDATE` creates a new row, it normally requires updating all indexes to point to the new physical location. **HOT** allows PostgreSQL to skip the index update if the indexed columns didn't change and the new row fits on the same page as the old one, creating a "chain" from the old tuple to the new one. This is a critical performance win.

---

## ✅ Completion Checklist

- [ ] Explain the difference between `xmin` and `xmax`
- [ ] Understand why PostgreSQL doesn't have an "Undo Log" like MySQL
- [ ] Connect the concept of "Dead Tuples" to "Table Bloat"
- [ ] Successfully query a table's `n_dead_tup` count

## 🔗 Next Phase: Query & Indexing Internals
Now that we know how data is stored, let's see how PostgreSQL finds it quickly using the **Query Planner** and **Index Types**.

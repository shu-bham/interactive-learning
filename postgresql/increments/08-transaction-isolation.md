# 🎯 Increment 08: Transaction Isolation & Locking (vs MySQL)

**Duration**: 50 minutes  
**Difficulty**: ⭐⭐⭐⭐ Deep Dive

## 📋 Quick Summary

PostgreSQL's isolation levels and locking mechanisms are more granular and standard-compliant than MySQL's. Understanding the difference in **Defaults** is the #1 thing to know before migration or interviewing.

**Key Concepts**:
- **Default Isolation**: PostgreSQL defaults to **READ COMMITTED** (MySQL defaults to Repeatable Read).
- **SSI (Serializable Snapshot Isolation)**: The only DB that provides "true" serializability without locking the whole table.
- **FOR NO KEY UPDATE**: A specialized lock that allows higher concurrency than a standard `FOR UPDATE`.
- **Advisory Locks**: Application-level locks managed by the database.

---

## 🎓 Theory (20 minutes)

### 1. Isolation Levels Comparison

| Level | MySQL (InnoDB) | PostgreSQL |
|-------|---------------|------------|
| **Read Uncommitted**| Supported (Dirty reads) | Treated as Read Committed |
| **Read Committed** | Standard | **The Default**. No dirty reads. |
| **Repeatable Read** | **The Default**. Prevents Phantoms. | Prevents Phantoms, but throws error on concurrent update. |
| **Serializable** | Pessimistic Locking | **SSI (Optimistic)**. Best in class. |

### 2. The "Update" Conflict Risk

In `REPEATABLE READ`:
- **MySQL**: If T1 and T2 update the same row, T2 waits.
- **PostgreSQL**: If T2 tries to update a row that T1 modified after T2's snapshot, T2 fails with: `could not serialize access due to concurrent update`. You must retry the transaction.

### 3. Row-Level Locks

| Lock Type | Purpose | Permission |
|-----------|---------|------------|
| `FOR UPDATE` | Modifying the row | Most restrictive |
| `FOR NO KEY UPDATE`| Modifying non-PK columns | Allows concurrent `FOR SHARE` |
| `FOR SHARE` | Reading but pinning the row | Prevents others from `FOR UPDATE` |
| `FOR KEY SHARE` | Foreign Keys use this | Highly concurrent |

---

## 🧪 Hands-On Exercises (25 minutes)

### Exercise 1: Observing Read Committed (Default)

```sql
-- Terminal 1
BEGIN;
UPDATE users SET age = 50 WHERE username = 'john_doe';

-- Terminal 2
SELECT age FROM users WHERE username = 'john_doe';
-- Shows OLD value (Normal MVCC)

-- Terminal 1
COMMIT;

-- Terminal 1 / Terminal 2
SELECT age FROM users WHERE username = 'john_doe';
-- Shows 50 (Read Committed in action)
```

### Exercise 2: Advisory Locks (Great for Senior Interviews)

Need a distributed lock for a cron job? Use PostgreSQL.

```sql
-- 1. Try to acquire a lock (Fast, non-blocking)
SELECT pg_try_advisory_lock(12345); 
-- Returns true (1)

-- 2. In another terminal, try the same
SELECT pg_try_advisory_lock(12345);
-- Returns false (0)

-- 3. Release
SELECT pg_advisory_unlock(12345);
```

### Exercise 3: FOR UPDATE vs FOR NO KEY UPDATE

```sql
-- Terminal 1
BEGIN;
SELECT * FROM users WHERE user_id = 1 FOR NO KEY UPDATE;

-- Terminal 2
BEGIN;
-- This would normally be blocked by FOR UPDATE, 
-- but FOR NO KEY UPDATE might allow some concurrent interactions 
-- if they don't impact keys. 
-- (Actually, most DML is still blocked, but this is a key internal optimization for FKs).
```

---

## 🎤 Interview Question Practice

**Q1**: "My application worked fine on MySQL but started throwing 'could not serialize access' errors on PostgreSQL. Why?"

**Answer**: This usually happens when switching to `REPEATABLE READ` or `SERIALIZABLE`. PostgreSQL uses optimistic concurrency control for these levels. If two transactions try to update the same row, PostgreSQL doesn't always make one wait; it may abort the second one to maintain the snapshot's integrity. The application must be designed to **retry** transactions on serialization errors.

**Q2**: "What are Advisory Locks and when would you use them?"

**Answer**: Advisory locks are application-defined locks that have no meaning to the database's integrity but are managed by the database's lock manager. They are excellent for application-level synchronization, like ensuring only one instance of a background worker runs at a time, without needing a separate system like Redis or Zookeeper.

---

## ✅ Completion Checklist

- [ ] Explain why PostgreSQL defaults to `READ COMMITTED`
- [ ] Successfully acquire and release an advisory lock
- [ ] Understand when to use `FOR UPDATE`
- [ ] Explain the difference between pessimistic (MySQL) and optimistic (PG) serialization

## 🔗 Next: Increment 09 - Deadlocks & Lock Monitoring
Ready to find out who's blocking who? Let's master the **Lock Monitoring** views.

# 🎯 Increment 5: MVCC & Transaction Isolation Levels

**Duration**: 50 minutes  
**Difficulty**: ⭐⭐⭐⭐⭐ Expert

## 📋 Quick Summary

**What you'll master**: Multi-Version Concurrency Control (MVCC) - the mechanism that allows readers and writers to work concurrently without blocking each other.

**Key concepts**: 
- **Read View** = Snapshot of database state for a transaction
- **Row versioning** = Multiple versions of same row exist simultaneously
- **Hidden columns** = DB_TRX_ID, DB_ROLL_PTR for version tracking
- **Isolation levels** = READ COMMITTED vs REPEATABLE READ implementation

**Why it matters**: 
- **Core concurrency mechanism** - enables high-throughput systems
- **Interview favorite** - "Explain how MVCC works" is a classic question
- **Production debugging** - understand why transactions see different data
- **Performance tuning** - long transactions cause undo log growth

---

## What You'll Learn

- Understand MVCC implementation in InnoDB
- Explain how read views work
- Master transaction isolation level differences
- Identify and fix MVCC-related performance issues
- Handle phantom reads and consistent reads

## 🎓 Theory (20 minutes)

### The Concurrency Problem

**Without MVCC**:
```
T1: BEGIN
T1: SELECT balance FROM accounts WHERE id = 1;  -- balance = 100
                                                 
T2: BEGIN                                        
T2: UPDATE accounts SET balance = 200 WHERE id = 1;
T2: COMMIT                                       
                                                 
T1: SELECT balance FROM accounts WHERE id = 1;  -- What do we see?
```

**Options**:
1. **Lock-based**: T2 waits for T1 to finish → Low concurrency
2. **MVCC**: T1 sees old version (100), T2 creates new version (200) → High concurrency ✅

### MVCC Implementation

**Every row has hidden columns**:
```
Visible columns: [id=1, balance=200]
Hidden columns:  [DB_TRX_ID=102, DB_ROLL_PTR=→undo_log, DB_ROW_ID=...]
```

- **DB_TRX_ID**: Transaction ID that last modified this row
- **DB_ROLL_PTR**: Pointer to undo log (previous version)
- **DB_ROW_ID**: Auto-generated row ID (if no PK)

**Version Chain**:
```
Current Row:  [id=1, balance=200, TRX_ID=102, ROLL_PTR→]
                                                       ↓
Undo Log:     [id=1, balance=150, TRX_ID=100, ROLL_PTR→]
                                                       ↓
Undo Log:     [id=1, balance=100, TRX_ID=95, ROLL_PTR=NULL]
```

### Read View

When a transaction starts (REPEATABLE READ) or executes a query (READ COMMITTED), it creates a **read view**:

```
Read View contains:
- m_ids: List of active transaction IDs
- min_trx_id: Smallest active transaction ID
- max_trx_id: Next transaction ID to be assigned
- creator_trx_id: This transaction's ID
```

**Visibility Rules**:
```
For each row version with DB_TRX_ID = trx_id:

1. If trx_id < min_trx_id → VISIBLE (committed before read view)
2. If trx_id >= max_trx_id → NOT VISIBLE (started after read view)
3. If trx_id in m_ids → NOT VISIBLE (still active)
4. Otherwise → VISIBLE (committed before read view)
```

### Isolation Levels

| Level | Read View Created | Behavior |
|-------|-------------------|----------|
| **READ UNCOMMITTED** | No read view | Sees uncommitted changes (dirty reads) |
| **READ COMMITTED** | **Per query** | Fresh snapshot each SELECT |
| **REPEATABLE READ** | **Per transaction** | Consistent snapshot entire transaction |
| **SERIALIZABLE** | Per transaction + locks | No concurrent modifications |

---

## 🧪 Hands-On Exercises (25 minutes)

### Exercise 1: Observing MVCC (10 min)

**Open 3 terminal sessions to MySQL**

**Session 1 - Long transaction**:
```sql
SET SESSION TRANSACTION ISOLATION LEVEL REPEATABLE READ;
START TRANSACTION;

-- Create a read view
SELECT user_id, username, age FROM users WHERE user_id = 1;
-- Note the age value

-- Keep transaction open!
```

**Session 2 - Make updates**:
```sql
-- Update the same row
UPDATE users SET age = 99 WHERE user_id = 1;
COMMIT;

-- Verify update
SELECT user_id, username, age FROM users WHERE user_id = 1;
-- Shows age = 99
```

**Session 3 - New transaction**:
```sql
START TRANSACTION;
SELECT user_id, username, age FROM users WHERE user_id = 1;
-- Shows age = 99 (sees committed version)
COMMIT;
```

**Back to Session 1**:
```sql
-- Read again - still sees OLD value!
SELECT user_id, username, age FROM users WHERE user_id = 1;
-- Still shows original age (MVCC in action!)

-- Check undo log activity
SHOW ENGINE INNODB STATUS\G
-- Look for "History list length"

COMMIT;

-- Now sees new value
SELECT user_id, username, age FROM users WHERE user_id = 1;
-- Shows age = 99
```

### Exercise 2: READ COMMITTED vs REPEATABLE READ (10 min)

**Session 1 - READ COMMITTED**:
```sql
SET SESSION TRANSACTION ISOLATION LEVEL READ COMMITTED;
START TRANSACTION;

SELECT user_id, age FROM users WHERE user_id = 2;
-- Note the age
```

**Session 2**:
```sql
UPDATE users SET age = 88 WHERE user_id = 2;
COMMIT;
```

**Session 1**:
```sql
-- Read again - sees NEW value (non-repeatable read)
SELECT user_id, age FROM users WHERE user_id = 2;
-- Shows age = 88

COMMIT;
```

**Now try REPEATABLE READ**:

**Session 1**:
```sql
SET SESSION TRANSACTION ISOLATION LEVEL REPEATABLE READ;
START TRANSACTION;

SELECT user_id, age FROM users WHERE user_id = 2;
-- Note the age
```

**Session 2**:
```sql
UPDATE users SET age = 77 WHERE user_id = 2;
COMMIT;
```

**Session 1**:
```sql
-- Read again - sees OLD value (repeatable read)
SELECT user_id, age FROM users WHERE user_id = 2;
-- Still shows original age

COMMIT;
```

### Exercise 3: Phantom Reads (5 min)

**Session 1**:
```sql
SET SESSION TRANSACTION ISOLATION LEVEL REPEATABLE READ;
START TRANSACTION;

SELECT COUNT(*) FROM users WHERE age > 30;
-- Note the count
```

**Session 2**:
```sql
INSERT INTO users (username, email, first_name, last_name, age)
VALUES ('phantom', 'phantom@test.com', 'Phantom', 'User', 35);
COMMIT;
```

**Session 1**:
```sql
-- Count again - same result (phantom prevented by MVCC)
SELECT COUNT(*) FROM users WHERE age > 30;
-- Count unchanged

-- But if you try to UPDATE...
UPDATE users SET status = 'active' WHERE age > 30;
-- This WILL update the new row! (semi-consistent read)

SELECT ROW_COUNT();
-- Shows one more row updated than expected

COMMIT;
```

## 🎯 Challenge: Undo Log Growth

```sql
-- Monitor undo log size
SELECT 
    TABLESPACE_NAME,
    (TOTAL_EXTENTS * EXTENT_SIZE) / 1024 / 1024 AS size_mb
FROM information_schema.FILES
WHERE TABLESPACE_NAME LIKE 'innodb_undo%';

-- Session 1: Start long transaction
START TRANSACTION;
SELECT * FROM users LIMIT 1;
-- Don't commit!

-- Session 2: Make many updates
UPDATE users SET age = age + 1;
COMMIT;

-- Session 3: Check history list length
SHOW ENGINE INNODB STATUS\G
-- Look for "History list length" - should be high

-- Session 1: Commit to allow purge
COMMIT;

-- Wait a few seconds, then check again
SHOW ENGINE INNODB STATUS\G
-- History list length should decrease
```

---

## 📝 Key Takeaways

1. **MVCC enables non-blocking reads** - readers don't block writers
2. **Read view determines visibility** - created per transaction or per query
3. **REPEATABLE READ** = snapshot per transaction
4. **READ COMMITTED** = fresh snapshot per query
5. **Long transactions prevent undo log purging** - causes growth
6. **Phantom reads mostly prevented** by MVCC in REPEATABLE READ

---

## 🎤 Interview Questions

### Q1: How does InnoDB implement MVCC?

**Answer**:
- Each row has hidden columns: DB_TRX_ID, DB_ROLL_PTR
- Undo logs store old row versions
- Read view determines which version is visible
- Visibility based on transaction ID comparison
- Purge thread cleans old versions when no longer needed

### Q2: What's the trade-off between READ COMMITTED and REPEATABLE READ?

**Answer**:

**REPEATABLE READ**:
- ✅ Consistent snapshot entire transaction
- ✅ Prevents non-repeatable reads
- ❌ Longer undo log retention
- ❌ Potential for lost updates

**READ COMMITTED**:
- ✅ Shorter undo log retention
- ✅ Sees latest committed data
- ❌ Non-repeatable reads possible
- ❌ Less consistent within transaction

**Use REPEATABLE READ when**: Need consistent snapshot (reports, analytics)  
**Use READ COMMITTED when**: Need latest data, short transactions

### Q3: Why do long transactions cause performance issues?

**Answer**:
- Prevent undo log purging (old versions needed for MVCC)
- History list length grows
- Undo tablespace grows
- More versions to check during reads
- Increased memory usage

**Solution**: Keep transactions short, commit frequently

---

## ✅ Completion Checklist

- [ ] Understand MVCC implementation with undo logs
- [ ] Explain read view and visibility rules
- [ ] Know differences between isolation levels
- [ ] Identify undo log growth issues
- [ ] Answer interview questions confidently

## 🔗 Next: Increment 6 - Locking & Deadlocks

Ready when you are!

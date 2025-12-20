# Module 3: Transaction Management & Concurrency Control

## 🎯 Learning Objectives

- Master MVCC (Multi-Version Concurrency Control) implementation
- Understand InnoDB locking mechanisms in depth
- Learn about deadlock detection and prevention
- Explore transaction isolation levels and their trade-offs
- Optimize for high-concurrency scenarios

## 📖 Theory

### ACID Properties

- **Atomicity**: All or nothing (undo logs)
- **Consistency**: Valid state transitions (constraints, triggers)
- **Isolation**: Concurrent transactions don't interfere (MVCC, locks)
- **Durability**: Committed data persists (redo logs)

### MVCC (Multi-Version Concurrency Control)

MVCC allows **readers and writers to work concurrently** without blocking each other.

**How it works**:

```
Transaction Timeline:

T1: START TRANSACTION
T1: SELECT * FROM users WHERE user_id = 1;  -- Sees version V1
                                             
T2: START TRANSACTION                        
T2: UPDATE users SET age = 30 WHERE user_id = 1;  -- Creates version V2
T2: COMMIT                                   
                                             
T1: SELECT * FROM users WHERE user_id = 1;  -- Still sees V1 (snapshot isolation)
T1: COMMIT
```

**Implementation Details**:

Each row has hidden columns:
- `DB_TRX_ID`: Transaction ID that created this version
- `DB_ROLL_PTR`: Pointer to undo log (previous version)
- `DB_ROW_ID`: Row ID (if no primary key)

```
Current Row:  [user_id=1, age=30, DB_TRX_ID=102, DB_ROLL_PTR=→]
                                                              ↓
Undo Log:     [user_id=1, age=25, DB_TRX_ID=100, DB_ROLL_PTR=→]
                                                              ↓
Undo Log:     [user_id=1, age=20, DB_TRX_ID=95, DB_ROLL_PTR=NULL]
```

**Read View**:
- Each transaction gets a consistent snapshot (read view)
- Read view contains: `trx_id_current`, `trx_ids_active[]`
- Determines which row versions are visible

### InnoDB Locking Mechanisms

**Lock Types**:

1. **Shared Lock (S)**: Allows reading, blocks writes
2. **Exclusive Lock (X)**: Blocks both reads and writes

**Lock Granularity**:

```
┌─────────────────────────────────────────┐
│ Table Lock                              │
│  ├─ Intention Shared (IS)               │
│  └─ Intention Exclusive (IX)            │
│                                         │
│  ┌───────────────────────────────────┐  │
│  │ Row Lock                          │  │
│  │  ├─ Record Lock (single row)     │  │
│  │  ├─ Gap Lock (between rows)      │  │
│  │  └─ Next-Key Lock (record + gap) │  │
│  └───────────────────────────────────┘  │
└─────────────────────────────────────────┘
```

**Lock Modes**:

| Lock Type | Description | Example |
|-----------|-------------|---------|
| **Record Lock** | Lock on index record | `WHERE id = 10` |
| **Gap Lock** | Lock on gap between records | Prevents inserts in range |
| **Next-Key Lock** | Record + gap before it | Default for range queries |
| **Insert Intention Lock** | Special gap lock for INSERT | Allows concurrent inserts |

**Example - Next-Key Locking**:

```
Index values: 10, 20, 30, 40

SELECT * FROM t WHERE id > 15 AND id < 35 FOR UPDATE;

Locks acquired:
- Record lock on 20
- Gap lock on (10, 20)
- Record lock on 30
- Gap lock on (20, 30)
- Gap lock on (30, 40)
```

### Isolation Levels

| Level | Dirty Read | Non-Repeatable Read | Phantom Read | Implementation |
|-------|------------|---------------------|--------------|----------------|
| **READ UNCOMMITTED** | ✅ Possible | ✅ Possible | ✅ Possible | No MVCC |
| **READ COMMITTED** | ❌ Prevented | ✅ Possible | ✅ Possible | MVCC, fresh snapshot per query |
| **REPEATABLE READ** | ❌ Prevented | ❌ Prevented | ⚠️ Mostly prevented | MVCC, snapshot per transaction |
| **SERIALIZABLE** | ❌ Prevented | ❌ Prevented | ❌ Prevented | Locks on reads |

**Default**: InnoDB uses `REPEATABLE READ`

### Deadlock Detection

**Deadlock Example**:

```
T1: UPDATE users SET age = 30 WHERE user_id = 1;  -- Locks row 1
T2: UPDATE users SET age = 40 WHERE user_id = 2;  -- Locks row 2

T1: UPDATE users SET age = 50 WHERE user_id = 2;  -- Waits for T2
T2: UPDATE users SET age = 60 WHERE user_id = 1;  -- Waits for T1

💥 DEADLOCK!
```

**InnoDB's Deadlock Detection**:
- Maintains **wait-for graph**
- Detects cycles in the graph
- Rolls back smallest transaction (least rows modified)
- Returns error: `ERROR 1213: Deadlock found when trying to get lock`

## 🧪 Hands-On Labs

### Lab 3.1: MVCC in Action

**Objective**: Observe MVCC behavior with concurrent transactions

**Setup**: Open **three terminal sessions**

**Session 1 - Long-running transaction**:
```sql
START TRANSACTION;
SELECT * FROM users WHERE user_id = 1;
-- Note the age value

-- Keep this transaction open!
```

**Session 2 - Update the row**:
```sql
START TRANSACTION;
UPDATE users SET age = 99 WHERE user_id = 1;
COMMIT;
```

**Session 3 - Check current state**:
```sql
SELECT * FROM users WHERE user_id = 1;
-- Shows age = 99
```

**Back to Session 1**:
```sql
-- Read again - still sees old value!
SELECT * FROM users WHERE user_id = 1;

-- Check transaction isolation level
SELECT @@transaction_isolation;

-- Commit to see new value
COMMIT;
SELECT * FROM users WHERE user_id = 1;
-- Now shows age = 99
```

**Deep Dive - View Undo Log Activity**:
```sql
-- Check undo log usage
SELECT 
    VARIABLE_NAME,
    VARIABLE_VALUE
FROM performance_schema.global_status
WHERE VARIABLE_NAME LIKE 'Innodb_undo%';

-- View history list length (number of undo records)
SHOW ENGINE INNODB STATUS\G
-- Look for "History list length"
```

### Lab 3.2: Understanding Lock Types

**Objective**: Observe different lock types in action

```sql
-- Enable InnoDB lock monitoring
SET GLOBAL innodb_status_output_locks=ON;

-- Session 1: Acquire shared lock
START TRANSACTION;
SELECT * FROM users WHERE user_id = 1 LOCK IN SHARE MODE;

-- Session 2: Try to acquire exclusive lock (will wait)
START TRANSACTION;
UPDATE users SET age = 50 WHERE user_id = 1;
-- This will block!

-- Session 3: View locks
SELECT 
    ENGINE_TRANSACTION_ID,
    OBJECT_NAME,
    INDEX_NAME,
    LOCK_TYPE,
    LOCK_MODE,
    LOCK_STATUS,
    LOCK_DATA
FROM performance_schema.data_locks
WHERE OBJECT_SCHEMA = 'learning_db';

-- Session 1: Commit to release lock
COMMIT;

-- Session 2: Now completes
COMMIT;
```

**Understanding Lock Modes**:
```sql
-- Record lock
START TRANSACTION;
SELECT * FROM users WHERE user_id = 1 FOR UPDATE;
-- Check locks in performance_schema.data_locks

-- Gap lock (prevents inserts in range)
START TRANSACTION;
SELECT * FROM users WHERE user_id BETWEEN 5 AND 15 FOR UPDATE;
-- Check locks - you'll see gap locks

COMMIT;
```

### Lab 3.3: Isolation Level Experiments

**Objective**: Understand isolation level differences

**Experiment 1: READ COMMITTED vs REPEATABLE READ**

**Session 1**:
```sql
-- Set to READ COMMITTED
SET SESSION TRANSACTION ISOLATION LEVEL READ COMMITTED;
START TRANSACTION;
SELECT * FROM users WHERE user_id = 1;
-- Note the age
```

**Session 2**:
```sql
UPDATE users SET age = 88 WHERE user_id = 1;
COMMIT;
```

**Session 1**:
```sql
-- Read again - sees NEW value (non-repeatable read)
SELECT * FROM users WHERE user_id = 1;
COMMIT;

-- Now try with REPEATABLE READ
SET SESSION TRANSACTION ISOLATION LEVEL REPEATABLE READ;
START TRANSACTION;
SELECT * FROM users WHERE user_id = 1;
```

**Session 2**:
```sql
UPDATE users SET age = 77 WHERE user_id = 1;
COMMIT;
```

**Session 1**:
```sql
-- Read again - sees OLD value (repeatable read)
SELECT * FROM users WHERE user_id = 1;
COMMIT;
```

**Experiment 2: Phantom Reads**

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
VALUES ('phantom', 'phantom@example.com', 'Phantom', 'User', 35);
COMMIT;
```

**Session 1**:
```sql
-- Read again - count is SAME (phantom read prevented by MVCC)
SELECT COUNT(*) FROM users WHERE age > 30;

-- But if you try to update...
UPDATE users SET status = 'active' WHERE age > 30;
-- You'll update the new row too! (semi-consistent read)

COMMIT;
```

### Lab 3.4: Deadlock Creation and Analysis

**Objective**: Create and analyze deadlocks

**Session 1**:
```sql
START TRANSACTION;
UPDATE users SET age = 30 WHERE user_id = 1;
-- Wait here...
```

**Session 2**:
```sql
START TRANSACTION;
UPDATE users SET age = 40 WHERE user_id = 2;
-- Now try to update user_id = 1
UPDATE users SET age = 50 WHERE user_id = 1;
-- This will wait for Session 1
```

**Session 1**:
```sql
-- This will cause deadlock!
UPDATE users SET age = 60 WHERE user_id = 2;
-- ERROR 1213: Deadlock found when trying to get lock
```

**Analyze the deadlock**:
```sql
-- View latest deadlock
SHOW ENGINE INNODB STATUS\G

-- Look for "LATEST DETECTED DEADLOCK" section
-- It shows:
-- - Transactions involved
-- - Locks held and waited for
-- - Which transaction was rolled back
```

**View deadlock count**:
```sql
SELECT 
    VARIABLE_NAME,
    VARIABLE_VALUE
FROM performance_schema.global_status
WHERE VARIABLE_NAME = 'Innodb_deadlocks';
```

### Lab 3.5: Lock Wait Timeout

**Objective**: Understand lock wait behavior

```sql
-- Check current lock wait timeout
SHOW VARIABLES LIKE 'innodb_lock_wait_timeout';

-- Set a shorter timeout for testing
SET SESSION innodb_lock_wait_timeout = 5;

-- Session 1: Hold a lock
START TRANSACTION;
UPDATE users SET age = 100 WHERE user_id = 1;

-- Session 2: Try to acquire same lock
START TRANSACTION;
UPDATE users SET age = 200 WHERE user_id = 1;
-- After 5 seconds: ERROR 1205: Lock wait timeout exceeded

-- Session 1: Release lock
COMMIT;
```

**Monitor lock waits**:
```sql
-- View current lock waits
SELECT 
    waiting_trx_id,
    waiting_pid,
    waiting_query,
    blocking_trx_id,
    blocking_pid,
    blocking_query
FROM sys.innodb_lock_waits;

-- View transaction details
SELECT 
    trx_id,
    trx_state,
    trx_started,
    trx_requested_lock_id,
    trx_wait_started,
    trx_rows_locked,
    trx_rows_modified
FROM information_schema.INNODB_TRX;
```

### Lab 3.6: Optimistic vs Pessimistic Locking

**Objective**: Compare locking strategies

**Pessimistic Locking** (lock immediately):
```sql
START TRANSACTION;
-- Lock the row immediately
SELECT * FROM users WHERE user_id = 1 FOR UPDATE;

-- Do some processing...
-- Other transactions can't modify this row

UPDATE users SET age = age + 1 WHERE user_id = 1;
COMMIT;
```

**Optimistic Locking** (check before update):
```sql
-- Add version column
ALTER TABLE users ADD COLUMN version INT DEFAULT 0;

-- Read without locking
START TRANSACTION;
SELECT user_id, age, version FROM users WHERE user_id = 1;
-- Suppose we get: age=30, version=5

-- Do some processing...

-- Update only if version hasn't changed
UPDATE users 
SET age = 31, version = version + 1 
WHERE user_id = 1 AND version = 5;

-- Check affected rows
SELECT ROW_COUNT();
-- If 0, someone else modified it - retry or fail
-- If 1, success!

COMMIT;
```

## 🎯 Staff Interview Questions

### Question 1: MVCC vs Locking
**Q**: When would you prefer locking over MVCC? What are the trade-offs?

**A**:
**MVCC (default for reads)**:
- ✅ High concurrency (readers don't block writers)
- ✅ Better performance for read-heavy workloads
- ❌ Undo log growth with long transactions
- ❌ Phantom reads possible (in REPEATABLE READ)

**Locking (SELECT ... FOR UPDATE)**:
- ✅ Prevents lost updates
- ✅ Ensures latest data is read
- ✅ Necessary for critical updates (e.g., inventory, balance)
- ❌ Lower concurrency (blocks other transactions)

**Use locking when**:
- Updating based on current value (e.g., `balance = balance - 100`)
- Preventing race conditions
- Ensuring data hasn't changed since read

### Question 2: Deadlock Prevention
**Q**: How would you design a system to minimize deadlocks?

**A**:
**Strategies**:

1. **Access resources in consistent order**:
   ```sql
   -- Always update users before orders
   UPDATE users ...
   UPDATE orders ...
   ```

2. **Keep transactions short**:
   - Minimize time between BEGIN and COMMIT
   - Avoid user interaction within transactions

3. **Use appropriate isolation level**:
   - READ COMMITTED reduces lock duration
   - Trade-off: allows non-repeatable reads

4. **Use indexes**:
   - Reduces rows scanned/locked
   - Faster transactions = less lock contention

5. **Batch operations**:
   ```sql
   -- Instead of multiple single-row updates
   UPDATE users SET status = 'active' WHERE user_id IN (1,2,3,4,5);
   ```

6. **Retry logic**:
   ```python
   max_retries = 3
   for attempt in range(max_retries):
       try:
           execute_transaction()
           break
       except DeadlockError:
           if attempt == max_retries - 1:
               raise
           sleep(random.uniform(0.1, 0.5))
   ```

### Question 3: Isolation Level Selection
**Q**: Your application has a reporting query that takes 5 minutes. Users complain about inconsistent results. How do you fix this?

**A**:
**Problem**: Long-running transaction with REPEATABLE READ sees stale data

**Solutions**:

1. **Use READ COMMITTED**:
   ```sql
   SET SESSION TRANSACTION ISOLATION LEVEL READ COMMITTED;
   -- Gets fresh data for each query
   ```
   - ✅ Always sees latest data
   - ❌ Results may be inconsistent within transaction

2. **Create a snapshot**:
   ```sql
   CREATE TABLE report_snapshot AS
   SELECT * FROM large_table WHERE ...;
   -- Query the snapshot
   ```

3. **Use read replica**:
   - Run reports on replica
   - Doesn't impact master performance

4. **Optimize query**:
   - Add indexes to reduce runtime
   - Shorter transaction = less staleness

## 📝 Key Takeaways

1. **MVCC enables high concurrency** - readers and writers don't block each other
2. **Choose isolation level carefully** - balance consistency vs performance
3. **Use explicit locking** when you need to prevent lost updates
4. **Deadlocks are inevitable** in high-concurrency systems - design for retries
5. **Keep transactions short** - reduces lock contention and undo log growth
6. **Monitor lock waits** - use performance_schema to identify bottlenecks

## 🔗 Next Steps

Proceed to **Module 4: Replication & High Availability** to learn about scaling reads and ensuring uptime.

```bash
cd ../04-replication
cat README.md
```

## 📚 Further Reading

- [InnoDB Locking](https://dev.mysql.com/doc/refman/8.0/en/innodb-locking.html)
- [Transaction Isolation Levels](https://dev.mysql.com/doc/refman/8.0/en/innodb-transaction-isolation-levels.html)
- [MVCC in InnoDB](https://dev.mysql.com/doc/refman/8.0/en/innodb-multi-versioning.html)

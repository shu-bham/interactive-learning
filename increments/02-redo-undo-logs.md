# 🎯 Increment 2: Redo/Undo Logs & Crash Recovery

**Duration**: 45 minutes  
**Difficulty**: ⭐⭐⭐⭐ Advanced

## 📋 Quick Summary

**What you'll master**: How MySQL ensures **durability** (the D in ACID) and enables **crash recovery** using redo logs, plus how **undo logs** power MVCC for concurrent transactions.

**Key concepts**: 
- **Redo logs** = Write-ahead logging for crash recovery
- **Undo logs** = Old row versions for rollback and MVCC
- **LSN** (Log Sequence Number) = Position tracking in redo log
- **Checkpoint** = Point where all dirty pages are flushed to disk

**Why it matters**: Understanding this is critical for:
- Troubleshooting database crashes and recovery
- Tuning write performance (`innodb_flush_log_at_trx_commit`)
- Explaining MVCC implementation in interviews
- Capacity planning for transaction-heavy workloads

---

## What You'll Learn

By the end of this increment, you'll be able to:
- Explain how redo logs ensure durability and crash recovery
- Understand LSN (Log Sequence Number) and checkpoint mechanics
- Monitor redo log activity and identify bottlenecks
- Explain how undo logs enable MVCC and rollback
- Answer staff-level questions about crash recovery

## 🎓 Theory (15 minutes)

### The Durability Problem

**Challenge**: How do you make transactions durable without writing every change to disk immediately?

**Solution**: **Write-Ahead Logging (WAL)**

```
Transaction Flow:
1. Modify data in buffer pool (in memory)
2. Write changes to redo log (sequential, fast)
3. Return "COMMIT" to user
4. Later: Flush dirty pages to disk (random, slow)
```

**Key Insight**: Sequential writes to redo log are **much faster** than random writes to data files!

### Redo Log Architecture

```
┌─────────────────────────────────────────────────┐
│              Transaction Execution               │
└────────────────────┬────────────────────────────┘
                     ↓
         ┌───────────────────────┐
         │  Redo Log Buffer      │  (In memory)
         │  (innodb_log_buffer)  │
         └───────────┬───────────┘
                     ↓ Flush on commit
         ┌───────────────────────┐
         │  Redo Log Files       │  (On disk)
         │  ib_logfile0          │  Circular buffer
         │  ib_logfile1          │  
         └───────────────────────┘
                     ↓ Apply during recovery
         ┌───────────────────────┐
         │  Data Files (.ibd)    │
         └───────────────────────┘
```

### LSN (Log Sequence Number)

LSN is a **monotonically increasing** number representing position in the redo log.

**Key LSNs**:
- **Current LSN**: Latest log entry written
- **Flushed LSN**: Latest log entry written to disk
- **Checkpoint LSN**: All changes before this are on disk

```
Timeline:
Checkpoint LSN    Flushed LSN      Current LSN
     ↓                ↓                ↓
-----|----------------|----------------|------>
     |                |                |
  All dirty      Redo log         Redo log
  pages          on disk          in buffer
  flushed
```

**Checkpoint Age** = Current LSN - Checkpoint LSN
- Large checkpoint age = Many dirty pages waiting to be flushed
- Can cause stalls if it grows too large

### Crash Recovery Process

**What happens when MySQL crashes**:

```
1. MySQL restarts
2. Read redo logs from last checkpoint LSN
3. Replay all committed transactions (REDO phase)
4. Rollback uncommitted transactions using undo logs (UNDO phase)
5. Database is consistent again!
```

**Example**:
```
T1: BEGIN
T1: UPDATE users SET age = 30 WHERE id = 1
T1: COMMIT  ← Redo log written, data still in buffer pool
💥 CRASH before dirty page flushed to disk

Recovery:
- Replay redo log entry for T1
- Row with id=1 gets age=30
- Database is consistent!
```

### Undo Logs

Undo logs serve **two purposes**:

1. **Transaction Rollback**: Restore old values on ROLLBACK
2. **MVCC**: Provide old row versions for concurrent reads

**Undo Log Structure**:
```
Current Row:  [id=1, age=30, TRX_ID=102, ROLL_PTR→]
                                                  ↓
Undo Log:     [id=1, age=25, TRX_ID=100, ROLL_PTR→]
                                                  ↓
Undo Log:     [id=1, age=20, TRX_ID=95, ROLL_PTR=NULL]
```

**Purge Thread**: Cleans up old undo log entries when no transaction needs them

### Critical Configuration Parameters

| Parameter | Values | Impact |
|-----------|--------|--------|
| `innodb_flush_log_at_trx_commit` | **0**: Flush every second<br>**1**: Flush on commit (safest)<br>**2**: Write to OS cache on commit | Durability vs Performance |
| `innodb_log_file_size` | Default: 48MB<br>Recommended: 128MB-2GB | Larger = fewer checkpoints, better write performance |
| `innodb_log_buffer_size` | Default: 16MB | Larger = less frequent flushes |

**Staff Interview Tip**: Always recommend `innodb_flush_log_at_trx_commit=1` for production unless you can tolerate data loss!

---

## 🧪 Hands-On Exercises (25 minutes)

### Exercise 1: Explore Redo Log Configuration (5 min)

```sql
-- View redo log settings
SHOW VARIABLES LIKE 'innodb_log%';

-- Key variables to note:
-- innodb_log_file_size: Size of each redo log file
-- innodb_log_files_in_group: Number of redo log files (usually 2)
-- innodb_log_buffer_size: Redo log buffer in memory
-- innodb_flush_log_at_trx_commit: Flush behavior

-- Check current flush behavior
SELECT @@innodb_flush_log_at_trx_commit;
-- 1 = safest (flush on every commit)
-- 0 = fastest (flush every second, can lose 1 sec of data)
-- 2 = middle ground (write to OS cache on commit)
```

### Exercise 2: Monitor LSN and Checkpoint Activity (10 min)

```sql
-- View current LSN values
SELECT 
    VARIABLE_NAME,
    VARIABLE_VALUE
FROM performance_schema.global_status
WHERE VARIABLE_NAME IN (
    'Innodb_lsn_current',
    'Innodb_lsn_flushed',
    'Innodb_lsn_last_checkpoint'
);

-- Calculate checkpoint age
SELECT 
    (SELECT VARIABLE_VALUE FROM performance_schema.global_status 
     WHERE VARIABLE_NAME = 'Innodb_lsn_current') AS current_lsn,
    (SELECT VARIABLE_VALUE FROM performance_schema.global_status 
     WHERE VARIABLE_NAME = 'Innodb_lsn_last_checkpoint') AS checkpoint_lsn,
    (SELECT VARIABLE_VALUE FROM performance_schema.global_status 
     WHERE VARIABLE_NAME = 'Innodb_lsn_current') -
    (SELECT VARIABLE_VALUE FROM performance_schema.global_status 
     WHERE VARIABLE_NAME = 'Innodb_lsn_last_checkpoint') AS checkpoint_age;

-- View redo log write statistics
SHOW STATUS LIKE 'Innodb_log%';
-- Look for:
-- Innodb_log_writes: Number of writes to redo log
-- Innodb_log_write_requests: Number of write requests
-- Innodb_os_log_written: Bytes written to redo log
```

**Now generate some write activity**:

```sql
-- Create a test table
CREATE TABLE redo_test (
    id INT AUTO_INCREMENT PRIMARY KEY,
    data VARCHAR(1000),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB;

-- Check LSN before writes
SELECT VARIABLE_VALUE AS lsn_before
FROM performance_schema.global_status
WHERE VARIABLE_NAME = 'Innodb_lsn_current';

-- Insert 10,000 rows
INSERT INTO redo_test (data)
WITH RECURSIVE numbers AS (
    SELECT 1 AS n
    UNION ALL
    SELECT n + 1 FROM numbers WHERE n < 10000
)
SELECT REPEAT('X', 1000) FROM numbers;

-- Check LSN after writes
SELECT VARIABLE_VALUE AS lsn_after
FROM performance_schema.global_status
WHERE VARIABLE_NAME = 'Innodb_lsn_current';

-- Calculate how much redo log was generated
-- (lsn_after - lsn_before) = bytes written to redo log
```

### Exercise 3: Understanding Undo Logs (10 min)

```sql
-- View undo log configuration
SHOW VARIABLES LIKE '%undo%';

-- View undo tablespace information
SELECT 
    TABLESPACE_NAME,
    FILE_NAME,
    FILE_SIZE / 1024 / 1024 AS size_mb
FROM information_schema.FILES
WHERE TABLESPACE_NAME LIKE '%undo%';

-- Monitor undo log usage
SELECT 
    VARIABLE_NAME,
    VARIABLE_VALUE
FROM performance_schema.global_status
WHERE VARIABLE_NAME LIKE 'Innodb_undo%';

-- Check history list length (number of unpurged undo records)
SHOW ENGINE INNODB STATUS\G
-- Look for "History list length" in the output
-- High value = many old row versions waiting to be purged
-- Usually caused by long-running transactions
```

**Demonstrate undo log growth with long transaction**:

```sql
-- Session 1: Start a long-running transaction
START TRANSACTION;
SELECT * FROM users WHERE user_id = 1;
-- Don't commit yet!

-- Session 2: Make updates
UPDATE users SET age = age + 1 WHERE user_id < 100;
COMMIT;

-- Session 3: Check history list length
SHOW ENGINE INNODB STATUS\G
-- History list length will be > 0

-- Session 1: Now commit
COMMIT;

-- Session 3: Check again - history list should decrease
SHOW ENGINE INNODB STATUS\G
```

## 🎯 Challenge Exercise

**Scenario**: Simulate crash recovery behavior

```sql
-- 1. Create a test table
CREATE TABLE crash_test (
    id INT AUTO_INCREMENT PRIMARY KEY,
    value INT,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB;

INSERT INTO crash_test (value) VALUES (100), (200), (300);

-- 2. Check current data
SELECT * FROM crash_test;

-- 3. Start a transaction
START TRANSACTION;
UPDATE crash_test SET value = 999 WHERE id = 1;

-- 4. Check redo log LSN
SELECT VARIABLE_VALUE FROM performance_schema.global_status 
WHERE VARIABLE_NAME = 'Innodb_lsn_current';

-- 5. Commit (redo log written, but page might still be in buffer pool)
COMMIT;

-- 6. Verify update
SELECT * FROM crash_test WHERE id = 1;

-- In a real crash scenario:
-- - If crash happens after COMMIT, redo log ensures data is recovered
-- - If crash happens before COMMIT, undo log rolls back the change
```

**Question**: What would happen if we set `innodb_flush_log_at_trx_commit=0` and crashed right after COMMIT?

<details>
<summary>Click for answer</summary>
With value 0, redo log is flushed every second (not on commit). If crash happens within that 1-second window after COMMIT, the transaction could be lost! This is why production systems use value 1.
</details>

---

## 📝 Key Takeaways

1. **Redo logs ensure durability** - committed transactions survive crashes
2. **LSN tracks position** in redo log - critical for recovery
3. **Checkpoint age** indicates how far behind disk writes are from memory
4. **Undo logs enable MVCC** - old row versions for concurrent reads
5. **`innodb_flush_log_at_trx_commit=1`** is safest for production
6. **Long transactions** prevent undo log purging, causing growth

## 🎤 Interview Question Practice

### Q1: Explain the crash recovery process in MySQL

**Your Answer Should Cover**:
1. **Redo Phase**: Replay redo log from last checkpoint LSN
   - Reapply all committed transactions
   - Ensures durability
2. **Undo Phase**: Rollback uncommitted transactions
   - Use undo logs to restore old values
   - Ensures atomicity
3. **Result**: Database returns to consistent state

**Follow-up**: "How does checkpoint LSN help?"
- Checkpoint = point where all dirty pages are flushed
- Recovery only needs to replay from checkpoint, not from beginning
- Reduces recovery time

### Q2: What's the trade-off between performance and durability?

**Your Answer**:

| Setting | Durability | Performance | Use Case |
|---------|-----------|-------------|----------|
| `=1` | ✅ Full | ⚠️ Slower | Production, financial systems |
| `=2` | ⚠️ OS crash loses data | ✅ Faster | Can tolerate small data loss |
| `=0` | ❌ Can lose 1 sec | ✅ Fastest | Development, analytics |

**Key Point**: In production, always use `=1` unless business explicitly accepts data loss risk.

### Q3: Why do undo logs grow? How do you fix it?

**Causes**:
- Long-running transactions prevent purge
- Slow purge threads can't keep up
- Large transactions create many undo records

**Solutions**:
- Keep transactions short
- Commit frequently in batch operations
- Increase `innodb_purge_threads` (default: 4)
- Monitor history list length: `SHOW ENGINE INNODB STATUS`

---

## ✅ Completion Checklist

Before moving to Increment 3, ensure you can:
- [ ] Explain how redo logs ensure crash recovery
- [ ] Describe what LSN is and why it matters
- [ ] Monitor checkpoint age and redo log activity
- [ ] Explain the difference between redo and undo logs
- [ ] Understand the trade-offs of `innodb_flush_log_at_trx_commit`
- [ ] Answer the three interview questions above confidently

## 🔗 Next Increment

**Increment 3: Query Execution & EXPLAIN Mastery**
- Understanding the query execution pipeline
- Deep dive into EXPLAIN output
- Identifying slow queries
- Query optimization techniques

---

**Ready to proceed?** Update `progress.md` and let me know when you're ready for Increment 3!

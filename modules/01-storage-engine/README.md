# Module 1: InnoDB Storage Engine Internals

## 🎯 Learning Objectives

- Understand InnoDB architecture and its components
- Master buffer pool mechanics and memory management
- Explore redo/undo log internals and crash recovery
- Learn about tablespace structure and file organization
- Analyze doublewrite buffer and data integrity mechanisms

## 📖 Theory

### InnoDB Architecture Overview

InnoDB is MySQL's default storage engine, designed for:
- **ACID compliance**: Full transaction support
- **Row-level locking**: High concurrency
- **Crash recovery**: Automatic recovery using redo logs
- **Foreign key support**: Referential integrity
- **MVCC**: Multi-version concurrency control

### Key Components

```
┌─────────────────────────────────────────────────────────┐
│                    MySQL Server Layer                    │
├─────────────────────────────────────────────────────────┤
│                    InnoDB Storage Engine                 │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐  │
│  │ Buffer Pool  │  │  Change      │  │  Adaptive    │  │
│  │              │  │  Buffer      │  │  Hash Index  │  │
│  └──────────────┘  └──────────────┘  └──────────────┘  │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐  │
│  │ Redo Log     │  │  Undo Log    │  │  Doublewrite │  │
│  │ Buffer       │  │  Segments    │  │  Buffer      │  │
│  └──────────────┘  └──────────────┘  └──────────────┘  │
├─────────────────────────────────────────────────────────┤
│                    File System Layer                     │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐  │
│  │ System       │  │  Redo Log    │  │  Undo        │  │
│  │ Tablespace   │  │  Files       │  │  Tablespace  │  │
│  │ (ibdata1)    │  │  (ib_logfile)│  │              │  │
│  └──────────────┘  └──────────────┘  └──────────────┘  │
│  ┌──────────────┐                                       │
│  │ Per-table    │                                       │
│  │ Tablespaces  │                                       │
│  │ (.ibd files) │                                       │
│  └──────────────┘                                       │
└─────────────────────────────────────────────────────────┘
```

### 1. Buffer Pool

The buffer pool is InnoDB's **in-memory cache** for data and indexes.

**Key Concepts**:
- **Pages**: Data is stored in 16KB pages
- **LRU List**: Least Recently Used algorithm for page eviction
- **Free List**: Available pages for new data
- **Flush List**: Modified (dirty) pages waiting to be written to disk

**Buffer Pool Structure**:
```
Buffer Pool
├── Young Sublist (5/8 of pool) - Recently accessed pages
├── Old Sublist (3/8 of pool) - Less recently accessed
└── Midpoint - Insertion point for new pages
```

### 2. Redo Logs

Redo logs ensure **durability** and enable crash recovery.

**How it works**:
1. Transaction modifies data in buffer pool
2. Changes are written to redo log buffer
3. Redo log buffer is flushed to disk (based on `innodb_flush_log_at_trx_commit`)
4. On crash, redo logs replay uncommitted changes

**Configuration Parameters**:
- `innodb_log_file_size`: Size of each redo log file
- `innodb_log_files_in_group`: Number of redo log files
- `innodb_flush_log_at_trx_commit`: Flush behavior (0, 1, 2)

### 3. Undo Logs

Undo logs support **MVCC** and **rollback** operations.

**Purpose**:
- Store old versions of rows for MVCC
- Enable transaction rollback
- Support consistent reads

**Undo Log Lifecycle**:
```
Transaction Start → Modify Row → Store Old Version in Undo Log
                                          ↓
                    Commit → Mark Undo Log for Purge
                                          ↓
                    Purge Thread → Clean Up Old Versions
```

### 4. Doublewrite Buffer

Prevents **partial page writes** during crashes.

**How it works**:
1. Dirty pages are first written to doublewrite buffer (sequential write)
2. Then written to actual tablespace location (random write)
3. On crash, if page is corrupt, restore from doublewrite buffer

### 5. Tablespace Structure

**System Tablespace** (`ibdata1`):
- Data dictionary
- Undo logs (in older versions)
- Doublewrite buffer
- Change buffer

**File-per-table Tablespace** (`.ibd` files):
- Table data and indexes
- Enabled by `innodb_file_per_table=ON`

## 🧪 Hands-On Labs

### Lab 1.1: Exploring Buffer Pool

**Objective**: Understand buffer pool usage and monitoring

```sql
-- Connect to MySQL
-- docker exec -it mysql-master mysql -uroot -prootpass learning_db

-- Check buffer pool configuration
SHOW VARIABLES LIKE 'innodb_buffer_pool%';

-- View buffer pool status
SHOW STATUS LIKE 'Innodb_buffer_pool%';

-- Calculate buffer pool hit ratio (should be > 99% in production)
SELECT 
    VARIABLE_VALUE AS buffer_pool_reads,
    (SELECT VARIABLE_VALUE FROM performance_schema.global_status 
     WHERE VARIABLE_NAME = 'Innodb_buffer_pool_read_requests') AS read_requests,
    ROUND(
        (1 - VARIABLE_VALUE / 
         (SELECT VARIABLE_VALUE FROM performance_schema.global_status 
          WHERE VARIABLE_NAME = 'Innodb_buffer_pool_read_requests')) * 100, 
        2
    ) AS hit_ratio_percent
FROM performance_schema.global_status
WHERE VARIABLE_NAME = 'Innodb_buffer_pool_reads';

-- View buffer pool pages by type
SELECT 
    PAGE_TYPE,
    COUNT(*) AS page_count,
    ROUND(COUNT(*) * 16 / 1024, 2) AS size_mb
FROM information_schema.INNODB_BUFFER_PAGE
GROUP BY PAGE_TYPE
ORDER BY page_count DESC;

-- View which tables are in buffer pool
SELECT 
    TABLE_NAME,
    COUNT(*) AS pages_cached,
    ROUND(COUNT(*) * 16 / 1024, 2) AS size_mb,
    ROUND(100 * COUNT(*) / (SELECT COUNT(*) 
                            FROM information_schema.INNODB_BUFFER_PAGE), 2) AS percent_of_pool
FROM information_schema.INNODB_BUFFER_PAGE
WHERE TABLE_NAME IS NOT NULL
GROUP BY TABLE_NAME
ORDER BY pages_cached DESC
LIMIT 10;
```

**Exercise**:
1. Run a query that scans the `users` table
2. Check which pages are now in the buffer pool
3. Run the same query again and observe the hit ratio improvement

### Lab 1.2: Redo Log Analysis

**Objective**: Understand redo log behavior and checkpointing

```sql
-- Check redo log configuration
SHOW VARIABLES LIKE 'innodb_log%';

-- View redo log status
SHOW STATUS LIKE 'Innodb_log%';

-- Monitor LSN (Log Sequence Number) - the position in redo log
SELECT 
    VARIABLE_NAME,
    VARIABLE_VALUE
FROM performance_schema.global_status
WHERE VARIABLE_NAME IN (
    'Innodb_lsn_current',
    'Innodb_lsn_flushed',
    'Innodb_lsn_last_checkpoint'
);

-- Calculate checkpoint age (how far behind checkpoint is from current LSN)
SELECT 
    (SELECT VARIABLE_VALUE FROM performance_schema.global_status 
     WHERE VARIABLE_NAME = 'Innodb_lsn_current') -
    (SELECT VARIABLE_VALUE FROM performance_schema.global_status 
     WHERE VARIABLE_NAME = 'Innodb_lsn_last_checkpoint') AS checkpoint_age;
```

**Exercise - Simulate Heavy Writes**:
```sql
-- Create a test table
CREATE TABLE redo_test (
    id INT AUTO_INCREMENT PRIMARY KEY,
    data VARCHAR(1000),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB;

-- Before: Check current LSN
SELECT VARIABLE_VALUE AS lsn_before
FROM performance_schema.global_status
WHERE VARIABLE_NAME = 'Innodb_lsn_current';

-- Insert 10,000 rows
INSERT INTO redo_test (data)
SELECT REPEAT('X', 1000)
FROM (
    SELECT 1 UNION SELECT 2 UNION SELECT 3 UNION SELECT 4 UNION SELECT 5
) t1,
(
    SELECT 1 UNION SELECT 2 UNION SELECT 3 UNION SELECT 4 UNION SELECT 5
) t2,
(
    SELECT 1 UNION SELECT 2 UNION SELECT 3 UNION SELECT 4 UNION SELECT 5
) t3,
(
    SELECT 1 UNION SELECT 2 UNION SELECT 3 UNION SELECT 4 UNION SELECT 5
) t4;

-- After: Check new LSN
SELECT VARIABLE_VALUE AS lsn_after
FROM performance_schema.global_status
WHERE VARIABLE_NAME = 'Innodb_lsn_current';

-- Observe the LSN increase
```

### Lab 1.3: Understanding Undo Logs and MVCC

**Objective**: See how undo logs support MVCC

```sql
-- Check undo log configuration
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
```

**Exercise - MVCC in Action**:

Open **two terminal sessions** to MySQL:

**Session 1**:
```sql
-- Start a transaction
START TRANSACTION;

-- Read current data
SELECT * FROM users WHERE user_id = 1;

-- Keep this transaction open!
```

**Session 2**:
```sql
-- Update the same row
UPDATE users SET age = 99 WHERE user_id = 1;
COMMIT;

-- Verify the update
SELECT * FROM users WHERE user_id = 1;
```

**Back to Session 1**:
```sql
-- Read again - you'll see the OLD value (MVCC in action!)
SELECT * FROM users WHERE user_id = 1;

-- Commit to see new value
COMMIT;
SELECT * FROM users WHERE user_id = 1;
```

**What happened?**
- Session 1's transaction sees a consistent snapshot
- The old version is stored in undo logs
- Session 2's update creates a new version
- Both sessions see different versions simultaneously!

### Lab 1.4: Tablespace and Page Structure

**Objective**: Explore tablespace files and page organization

```sql
-- View all tablespaces
SELECT 
    TABLESPACE_NAME,
    FILE_NAME,
    FILE_TYPE,
    ROUND(FILE_SIZE / 1024 / 1024, 2) AS size_mb,
    ROUND(ALLOCATED_SIZE / 1024 / 1024, 2) AS allocated_mb
FROM information_schema.FILES
ORDER BY FILE_SIZE DESC;

-- Check file-per-table setting
SHOW VARIABLES LIKE 'innodb_file_per_table';

-- View table statistics
SELECT 
    TABLE_NAME,
    ENGINE,
    TABLE_ROWS,
    ROUND(DATA_LENGTH / 1024 / 1024, 2) AS data_mb,
    ROUND(INDEX_LENGTH / 1024 / 1024, 2) AS index_mb,
    ROUND((DATA_LENGTH + INDEX_LENGTH) / 1024 / 1024, 2) AS total_mb
FROM information_schema.TABLES
WHERE TABLE_SCHEMA = 'learning_db'
ORDER BY (DATA_LENGTH + INDEX_LENGTH) DESC;

-- View page information for a specific table
SELECT 
    PAGE_NUMBER,
    PAGE_TYPE,
    NUMBER_RECORDS,
    DATA_SIZE,
    INDEX_NAME
FROM information_schema.INNODB_BUFFER_PAGE
WHERE TABLE_NAME = '`learning_db`.`users`'
ORDER BY PAGE_NUMBER
LIMIT 20;
```

### Lab 1.5: Doublewrite Buffer

**Objective**: Understand doublewrite buffer mechanics

```sql
-- Check doublewrite buffer status
SHOW VARIABLES LIKE 'innodb_doublewrite%';

-- Monitor doublewrite buffer activity
SELECT 
    VARIABLE_NAME,
    VARIABLE_VALUE
FROM performance_schema.global_status
WHERE VARIABLE_NAME LIKE 'Innodb_dblwr%';

-- Calculate doublewrite ratio
SELECT 
    (SELECT VARIABLE_VALUE FROM performance_schema.global_status 
     WHERE VARIABLE_NAME = 'Innodb_dblwr_writes') AS dblwr_writes,
    (SELECT VARIABLE_VALUE FROM performance_schema.global_status 
     WHERE VARIABLE_NAME = 'Innodb_dblwr_pages_written') AS pages_written,
    ROUND(
        (SELECT VARIABLE_VALUE FROM performance_schema.global_status 
         WHERE VARIABLE_NAME = 'Innodb_dblwr_pages_written') /
        (SELECT VARIABLE_VALUE FROM performance_schema.global_status 
         WHERE VARIABLE_NAME = 'Innodb_dblwr_writes'),
        2
    ) AS pages_per_write;
```

## 🎯 Staff Interview Questions

### Question 1: Buffer Pool Sizing
**Q**: How would you determine the optimal buffer pool size for a production MySQL server with 64GB RAM?

**A**: 
- General rule: 70-80% of available RAM for dedicated MySQL servers
- For 64GB: Start with 48-52GB
- Monitor buffer pool hit ratio (should be > 99%)
- Check `Innodb_buffer_pool_reads` vs `Innodb_buffer_pool_read_requests`
- Consider other processes and OS requirements
- Use `innodb_buffer_pool_instances` for better concurrency (1 instance per 1GB)

### Question 2: Crash Recovery
**Q**: Explain what happens during MySQL crash recovery. How does InnoDB ensure data consistency?

**A**:
1. **Redo Log Replay**: InnoDB reads redo logs and replays committed transactions
2. **Undo Log Rollback**: Uncommitted transactions are rolled back using undo logs
3. **Doublewrite Buffer Check**: Corrupted pages are restored from doublewrite buffer
4. **Checkpoint Recovery**: Start from last checkpoint LSN
5. **Purge Operations**: Clean up old undo log entries

Key parameters:
- `innodb_flush_log_at_trx_commit=1`: Ensures durability (flush on every commit)
- `innodb_flush_method=O_DIRECT`: Bypasses OS cache for consistency

### Question 3: MVCC Trade-offs
**Q**: What are the trade-offs of MVCC? When might it cause performance issues?

**A**:
**Benefits**:
- Readers don't block writers
- Writers don't block readers
- High concurrency

**Trade-offs**:
- **Undo Log Growth**: Long-running transactions prevent purging old versions
- **History List Length**: Can grow unbounded, causing performance degradation
- **Storage Overhead**: Multiple versions consume space
- **Purge Lag**: Purge thread may not keep up with write-heavy workloads

**Mitigation**:
- Keep transactions short
- Monitor `SHOW ENGINE INNODB STATUS` for history list length
- Tune purge threads: `innodb_purge_threads`

## 📝 Key Takeaways

1. **Buffer Pool** is critical for performance - monitor hit ratio closely
2. **Redo Logs** ensure durability - size them appropriately for write workload
3. **Undo Logs** enable MVCC - watch for long-running transactions
4. **Doublewrite Buffer** prevents corruption - small performance cost for safety
5. **Tablespace Structure** affects backup and recovery strategies

## 🔗 Next Steps

Proceed to **Module 2: Query Execution & Optimization** to learn how MySQL processes and optimizes queries.

```bash
cd ../02-query-optimization
cat README.md
```

## 📚 Further Reading

- [MySQL InnoDB Documentation](https://dev.mysql.com/doc/refman/8.0/en/innodb-storage-engine.html)
- [InnoDB Architecture Diagram](https://dev.mysql.com/doc/refman/8.0/en/innodb-architecture.html)
- "High Performance MySQL" - Chapter on InnoDB
- MySQL Source Code: `storage/innobase/`

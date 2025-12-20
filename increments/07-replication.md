# 🎯 Increment 7: Replication Architecture & Binary Logs

**Duration**: 45 minutes  
**Difficulty**: ⭐⭐⭐⭐ Advanced

## 📋 Quick Summary

**What you'll master**: MySQL replication internals, binary log formats, and GTID-based replication for high availability.

**Key concepts**: 
- **Binary log** = Record of all data changes
- **GTID** = Global Transaction Identifier for reliable replication
- **Replication lag** = Delay between master and replica
- **Parallel replication** = Multiple threads apply changes

**Why it matters**: 
- **Scalability** - read replicas for horizontal scaling
- **High availability** - failover to replica on master failure
- **Disaster recovery** - point-in-time recovery
- **Staff expectation** - design HA database architectures

---

## What You'll Learn

- Understand binary log formats (STATEMENT, ROW, MIXED)
- Set up and monitor replication
- Use GTID for reliable replication
- Troubleshoot replication lag
- Design replication topologies

## 🎓 Theory (20 minutes)

### Replication Architecture Overview

```
┌─────────────────────────────────────────────────────────┐
│                    MASTER SERVER                         │
│  ┌────────────────────────────────────────────────────┐ │
│  │ 1. Execute Transaction                             │ │
│  │ 2. Write to Binary Log (binlog)                    │ │
│  │ 3. Binlog Dump Thread → Send events to replica    │ │
│  └────────────────────────────────────────────────────┘ │
└─────────────────────────┬───────────────────────────────┘
                          ↓ Network
┌─────────────────────────────────────────────────────────┐
│                   REPLICA SERVER                         │
│  ┌────────────────────────────────────────────────────┐ │
│  │ I/O Thread:                                        │ │
│  │ - Connects to master                               │ │
│  │ - Reads binlog events                              │ │
│  │ - Writes to Relay Log                              │ │
│  └────────────────────────────────────────────────────┘ │
│                          ↓                               │
│  ┌────────────────────────────────────────────────────┐ │
│  │ Relay Log (relay-log files)                        │ │
│  │ - Stores events from master                        │ │
│  │ - Similar format to binlog                         │ │
│  └────────────────────────────────────────────────────┘ │
│                          ↓                               │
│  ┌────────────────────────────────────────────────────┐ │
│  │ SQL Thread (Coordinator):                          │ │
│  │ - Reads from relay log                             │ │
│  │ - Distributes to worker threads (parallel repl)   │ │
│  │ - Applies transactions to replica                  │ │
│  └────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────┘
```

### Binary Log Formats

| Format | What's Logged | Pros | Cons | Use Case |
|--------|---------------|------|------|----------|
| **STATEMENT** | SQL statements | Small size, readable | Non-deterministic (NOW(), RAND()) unsafe | Legacy systems |
| **ROW** | Row changes (before/after) | Deterministic, safe | Larger size | **Recommended** (default in 8.0) |
| **MIXED** | Auto-choose based on statement | Balanced | Complex to debug | Transition scenarios |

**Example - ROW format**:
```
UPDATE users SET age = 30 WHERE user_id = 1;

ROW format logs:
- Table: users
- Before: {user_id: 1, age: 25, ...}
- After:  {user_id: 1, age: 30, ...}
```

**Why ROW is safer**:
```sql
-- STATEMENT format problem:
UPDATE users SET last_login = NOW() WHERE status = 'active';
-- NOW() evaluated at different times on master vs replica!

-- ROW format: Logs actual timestamp value, always consistent
```

### Relay Log Deep Dive

**What is a Relay Log?**
- Local copy of master's binary log on replica
- Allows replica to apply changes at its own pace
- Enables crash recovery (relay_log_recovery=ON)

**Relay Log Files**:
```
/var/lib/mysql/
├── mysql-relay-bin.000001  ← Relay log file
├── mysql-relay-bin.000002
├── mysql-relay-bin.index   ← Index of all relay logs
└── relay-log.info          ← Position tracking (deprecated in 8.0)
```

**Relay Log Lifecycle**:
```
1. I/O thread writes events to relay log
2. SQL thread reads and applies events
3. After applying, relay log is automatically purged
4. New relay log created when:
   - Size limit reached (max_relay_log_size)
   - Replica restarts
   - FLUSH LOGS executed
```

**Relay Log Recovery**:
```
If replica crashes:
1. relay_log_recovery=ON → Discard relay logs
2. Re-fetch events from master using GTID or position
3. Ensures consistency after crash
```

### GTID (Global Transaction Identifier) Deep Dive

**GTID Format**:
```
server_uuid:transaction_number

Example: 3E11FA47-71CA-11E1-9E33-C80AA9429562:23
         └─────────────────┬──────────────────┘ └┬┘
                    Server UUID                Transaction #
```

**How GTIDs Work**:

1. **Master generates GTID**:
   ```
   BEGIN;
   UPDATE users SET age = 30 WHERE user_id = 1;
   COMMIT;  ← GTID assigned: server1:100
   ```

2. **Written to binary log**:
   ```
   GTID_EVENT: server1:100
   QUERY_EVENT: BEGIN
   UPDATE_ROWS_EVENT: users table
   XID_EVENT: COMMIT
   ```

3. **Replica tracks executed GTIDs**:
   ```sql
   SHOW REPLICA STATUS\G
   -- Retrieved_Gtid_Set: server1:1-100
   -- Executed_Gtid_Set: server1:1-99
   ```

**GTID Benefits**:

✅ **Automatic Position Tracking**:
```
Traditional: CHANGE MASTER TO MASTER_LOG_FILE='mysql-bin.000003', MASTER_LOG_POS=154;
GTID:        CHANGE MASTER TO MASTER_AUTO_POSITION=1;  ← Automatic!
```

✅ **Easy Failover**:
```
Master fails → Promote replica to master
Other replicas: CHANGE MASTER TO new_master, MASTER_AUTO_POSITION=1;
No manual position calculation needed!
```

✅ **Consistency Verification**:
```sql
-- Check if replica has all master transactions
SELECT GTID_SUBSET(master_gtid_set, replica_gtid_set);
```

**GTID Sets**:
```
Format: server_uuid:transaction_range

Examples:
- Single: 3E11FA47:23
- Range: 3E11FA47:1-100
- Multiple servers: 3E11FA47:1-100,5A22BC33:1-50
- Gaps: 3E11FA47:1-10:15-20  (11-14 missing)
```

### Replication Strategies

#### 1. **Asynchronous Replication** (Default)

```
Master                          Replica
  ↓
COMMIT → Return to client       I/O thread fetches
         (doesn't wait)         SQL thread applies
```

**Pros**: Fast, low latency  
**Cons**: Data loss possible if master crashes before replica catches up

#### 2. **Semi-Synchronous Replication**

```
Master                          Replica
  ↓
COMMIT → Wait for ACK ←──────── I/O thread writes to relay log
         Return to client       SQL thread applies later
```

**Configuration**:
```sql
-- On master
INSTALL PLUGIN rpl_semi_sync_master SONAME 'semisync_master.so';
SET GLOBAL rpl_semi_sync_master_enabled = 1;
SET GLOBAL rpl_semi_sync_master_timeout = 1000; -- 1 second

-- On replica
INSTALL PLUGIN rpl_semi_sync_replica SONAME 'semisync_replica.so';
SET GLOBAL rpl_semi_sync_replica_enabled = 1;
```

**Pros**: Stronger durability guarantee  
**Cons**: Slightly higher latency

#### 3. **Parallel Replication**

**Problem**: Single SQL thread is bottleneck

**Solution**: Multiple worker threads apply transactions in parallel

```
Replica:
  I/O Thread → Relay Log
                   ↓
  Coordinator Thread (SQL Thread)
       ↓          ↓          ↓
   Worker 1   Worker 2   Worker 3
   (DB: db1)  (DB: db2)  (DB: db3)
```

**Configuration**:
```sql
-- Number of parallel workers
SET GLOBAL replica_parallel_workers = 4;

-- Parallelization strategy
SET GLOBAL replica_parallel_type = 'LOGICAL_CLOCK';
-- Options:
-- - DATABASE: Parallel by database (old)
-- - LOGICAL_CLOCK: Parallel by commit order (recommended)

-- Preserve commit order
SET GLOBAL replica_preserve_commit_order = ON;
```

**How LOGICAL_CLOCK works**:
```
Master commits:
T1: UPDATE db1.users ...  (commit timestamp: 100)
T2: UPDATE db2.orders ... (commit timestamp: 100) ← Same timestamp
T3: UPDATE db1.users ...  (commit timestamp: 101)

Replica can execute T1 and T2 in parallel (same timestamp)
T3 must wait for T1 to complete (same table)
```

### Replication Topologies

#### 1. **Master-Replica (Single Replica)**
```
     Master
        ↓
     Replica
```
**Use**: Simple HA, read scaling

#### 2. **Master-Multiple Replicas**
```
        Master
       ↙  ↓  ↘
   Rep1  Rep2  Rep3
```
**Use**: Read scaling, geographic distribution

#### 3. **Chain Replication**
```
   Master → Replica1 → Replica2
```
**Use**: Reduce master load, cross-datacenter

#### 4. **Master-Master (Active-Active)**
```
   Master1 ⇄ Master2
```
**Use**: High availability, write scaling  
**Warning**: Conflict resolution needed!

#### 5. **Group Replication** (MySQL 8.0+)
```
   Node1 ⇄ Node2 ⇄ Node3
     ↕       ↕       ↕
   (All nodes can write)
```
**Use**: Multi-master with automatic conflict resolution

---

## 🧪 Hands-On Exercises (30 minutes)

### Exercise 1: Setup Replication (15 min)

```sql
-- On master: Create replication user
CREATE USER 'repl'@'%' IDENTIFIED BY 'replpass';
GRANT REPLICATION SLAVE ON *.* TO 'repl'@'%';

-- Check binary log status
SHOW MASTER STATUS;

-- On replica: Configure replication
CHANGE REPLICATION SOURCE TO
  SOURCE_HOST='mysql-master',
  SOURCE_USER='repl',
  SOURCE_PASSWORD='replpass',
  SOURCE_AUTO_POSITION=1;  -- Use GTID

-- Start replication
START REPLICA;

-- Check status
SHOW REPLICA STATUS\G
-- Look for:
-- - Replica_IO_Running: Yes
-- - Replica_SQL_Running: Yes
-- - Seconds_Behind_Source: 0
```

### Exercise 2: Monitor Replication (10 min)

```sql
-- On master: Make changes
INSERT INTO users (username, email, first_name, last_name)
VALUES ('repl_test', 'repl@test.com', 'Repl', 'Test');

-- On replica: Verify replication
SELECT * FROM users WHERE username = 'repl_test';

-- Check replication lag
SHOW REPLICA STATUS\G
-- Seconds_Behind_Source should be 0 or very small

-- View binary log events
SHOW BINLOG EVENTS IN 'mysql-bin.000001' LIMIT 10;
```

### Exercise 3: Relay Log Monitoring (5 min)

```sql
-- On replica: View relay log files
SHOW RELAYLOG EVENTS LIMIT 10;

-- Check relay log configuration
SHOW VARIABLES LIKE 'relay_log%';

-- View relay log file list
SHOW REPLICA STATUS\G
-- Look for:
-- - Relay_Log_File: Current relay log file
-- - Relay_Log_Pos: Position in relay log
-- - Relay_Master_Log_File: Corresponding master binlog file

-- Monitor relay log space usage
SELECT 
    VARIABLE_NAME,
    VARIABLE_VALUE / 1024 / 1024 AS size_mb
FROM performance_schema.global_status
WHERE VARIABLE_NAME LIKE 'Relay_log%';
```

### Exercise 4: GTID Tracking (5 min)

```sql
-- On master: View GTID status
SHOW MASTER STATUS;
-- Note the Executed_Gtid_Set

-- View server UUID
SELECT @@server_uuid;

-- On replica: Check GTID synchronization
SHOW REPLICA STATUS\G
-- Compare:
-- - Retrieved_Gtid_Set: GTIDs fetched from master
-- - Executed_Gtid_Set: GTIDs applied to replica

-- Check if replica has specific GTID
SELECT GTID_SUBSET('3E11FA47-71CA-11E1-9E33-C80AA9429562:1-100',
                   @@GLOBAL.gtid_executed) AS has_all_transactions;

-- View GTID gaps (missing transactions)
SELECT @@GLOBAL.gtid_executed;
-- Look for gaps in ranges (e.g., 1-10:15-20 means 11-14 missing)
```

### Exercise 5: Replication Lag Troubleshooting (5 min)

```sql
-- On replica: Check lag in detail
SHOW REPLICA STATUS\G
-- Key metrics:
-- - Seconds_Behind_Source: Lag in seconds
-- - Replica_SQL_Running_State: What SQL thread is doing

-- Check for long-running queries blocking replication
SELECT 
    ID,
    USER,
    HOST,
    DB,
    COMMAND,
    TIME,
    STATE,
    INFO
FROM information_schema.PROCESSLIST
WHERE TIME > 10
ORDER BY TIME DESC;

-- View replication worker threads (parallel replication)
SELECT 
    WORKER_ID,
    THREAD_ID,
    SERVICE_STATE,
    LAST_ERROR_NUMBER,
    LAST_ERROR_MESSAGE
FROM performance_schema.replication_applier_status_by_worker;

-- Monitor replication throughput
SHOW STATUS LIKE 'Replica_rows%';
-- Replica_rows_last_search_algorithm_used
-- Shows how replica is finding rows to update
```

## 🎯 Advanced Exercise: Simulating Failover (15 min)

**Scenario**: Master crashes, promote replica to new master

### Step 1: Set up replication (if not already done)

**On Master**:
```sql
-- Create replication user
CREATE USER 'repl'@'%' IDENTIFIED BY 'replpass';
GRANT REPLICATION SLAVE ON *.* TO 'repl'@'%';
FLUSH PRIVILEGES;

-- Verify GTID is enabled
SHOW VARIABLES LIKE 'gtid_mode';
-- Should show: ON

-- Check current GTID set
SHOW MASTER STATUS;
-- Note the Executed_Gtid_Set
```

**On Replica**:
```sql
-- Configure replication
CHANGE REPLICATION SOURCE TO
  SOURCE_HOST='mysql-master',
  SOURCE_USER='repl',
  SOURCE_PASSWORD='replpass',
  SOURCE_AUTO_POSITION=1;

-- Start replication
START REPLICA;

-- Verify replication is running
SHOW REPLICA STATUS\G
-- Replica_IO_Running: Yes
-- Replica_SQL_Running: Yes
```

### Step 2: Create test data on master

**On Master**:
```sql
-- Create test table
CREATE TABLE failover_test (
    id INT AUTO_INCREMENT PRIMARY KEY,
    data VARCHAR(100),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB;

-- Insert some data
INSERT INTO failover_test (data) VALUES 
    ('Before failover - record 1'),
    ('Before failover - record 2'),
    ('Before failover - record 3');

-- Check GTID
SHOW MASTER STATUS;
-- Note the Executed_Gtid_Set (e.g., server1:1-5)
```

**On Replica**:
```sql
-- Verify data replicated
SELECT * FROM failover_test;
-- Should see 3 records

-- Check GTID synchronization
SHOW REPLICA STATUS\G
-- Retrieved_Gtid_Set should match master's Executed_Gtid_Set
```

### Step 3: Simulate master failure

**Stop the master container** (simulating crash):
```bash
docker stop mysql-master
```

**On Replica** - Verify replication stopped:
```sql
SHOW REPLICA STATUS\G
-- Replica_IO_Running: Connecting (trying to reconnect)
-- Replica_SQL_Running: Yes (still processing relay log)
```

### Step 4: Promote replica to master

**On Replica**:
```sql
-- Stop replication
STOP REPLICA;

-- Reset replica status (make it a standalone master)
RESET REPLICA ALL;

-- Disable read-only mode
SET GLOBAL read_only = OFF;
-- Note: super_read_only is commented out in our config

-- Verify it's now a master
SHOW MASTER STATUS;
-- Should show binary log position and GTID set

-- Test write capability
INSERT INTO failover_test (data) VALUES ('After failover - new master');

SELECT * FROM failover_test;
-- Should see 4 records now
```

### Step 5: Verify GTID continuity

**On New Master (former replica)**:
```sql
-- Check GTID set
SELECT @@GLOBAL.gtid_executed;
-- Should show continuous GTID range from old master + new transactions

-- Example output:
-- 3E11FA47-71CA-11E1-9E33-C80AA9429562:1-5,    <- Old master
-- 5A22BC33-8D45-11E1-9E33-C80AA9429562:1       <- New master (this server)
```

### Step 6: (Optional) Bring old master back as replica

**Start the old master**:
```bash
docker start mysql-master
```

**On Old Master** (now will become replica):
```sql
-- Configure it to replicate from new master
CHANGE REPLICATION SOURCE TO
  SOURCE_HOST='mysql-replica',  -- New master
  SOURCE_USER='repl',
  SOURCE_PASSWORD='replpass',
  SOURCE_AUTO_POSITION=1;  -- GTID handles position automatically!

-- Start replication
START REPLICA;

-- Verify
SHOW REPLICA STATUS\G

-- Check data
SELECT * FROM failover_test;
-- Should now see all 4 records (including the one added after failover)
```

### Step 7: Verify complete failover

**On New Master**:
```sql
-- Insert more data
INSERT INTO failover_test (data) VALUES ('Post-failover test');

-- Check replication
SHOW REPLICA HOSTS;
-- Should show old master connected as replica
```

**On Old Master (now replica)**:
```sql
-- Verify new data replicated
SELECT * FROM failover_test ORDER BY id;
-- Should see all 5 records

-- Check GTID synchronization
SHOW REPLICA STATUS\G
-- Retrieved_Gtid_Set should include GTIDs from both servers
```

### What You Learned

✅ **GTID makes failover automatic** - No manual position calculation  
✅ **Replica promotion is simple** - Just disable read-only and reset replica  
✅ **Role reversal is easy** - Old master can become replica seamlessly  
✅ **Data consistency guaranteed** - GTID ensures no transactions are lost or duplicated  

### Cleanup (Return to original setup)

```bash
# Stop both containers
docker-compose stop mysql-master mysql-replica

# Remove volumes to start fresh
docker volume rm interactive-learning_mysql-master-data
docker volume rm interactive-learning_mysql-replica-data

# Restart
docker-compose up -d mysql-master mysql-replica
```

---

## 📝 Key Takeaways

1. **Relay logs** are local copies of master binlog on replica
2. **GTID** enables automatic failover and position tracking
3. **ROW format** is safest (deterministic, no function issues)
4. **Parallel replication** uses LOGICAL_CLOCK for better throughput
5. **Semi-synchronous replication** provides durability guarantees
6. **Monitor Seconds_Behind_Source** to track replication lag
7. **relay_log_recovery=ON** ensures consistency after crashes

---

## 🎤 Interview Questions

### Q1: How would you handle replication lag?

**Answer**:

**Diagnosis**:
```sql
SHOW REPLICA STATUS\G
-- Check Seconds_Behind_Source
-- Check Replica_SQL_Running_State
```

**Solutions**:
1. **Enable parallel replication**:
   ```sql
   SET GLOBAL replica_parallel_workers = 4;
   SET GLOBAL replica_parallel_type = 'LOGICAL_CLOCK';
   ```

2. **Optimize slow queries** on replica:
   - Check slow query log
   - Add missing indexes

3. **Check for long-running transactions**:
   ```sql
   SELECT * FROM information_schema.PROCESSLIST WHERE TIME > 10;
   ```

4. **Increase resources**: Faster disk, more CPU

5. **Consider semi-sync replication** to prevent lag accumulation

### Q2: Explain how GTID makes failover easier

**Answer**:

**Traditional Replication** (position-based):
```sql
-- On new master after failover:
SHOW MASTER STATUS;
-- File: mysql-bin.000005, Position: 12345

-- On each replica:
CHANGE MASTER TO 
  MASTER_HOST='new-master',
  MASTER_LOG_FILE='mysql-bin.000005',  ← Manual!
  MASTER_LOG_POS=12345;                 ← Error-prone!
```

**GTID Replication**:
```sql
-- On each replica:
CHANGE MASTER TO 
  MASTER_HOST='new-master',
  MASTER_AUTO_POSITION=1;  ← Automatic! No position needed!
```

**Why GTID is better**:
- Replica automatically finds correct position
- No risk of wrong binlog file/position
- Can handle missing transactions gracefully
- Easier to verify consistency: `SELECT GTID_SUBSET(...)`

### Q3: What's the difference between relay log and binary log?

**Answer**:

**Binary Log** (on master):
- Records all data changes on master
- Used for replication and point-in-time recovery
- Permanent (until manually purged)
- Format: STATEMENT, ROW, or MIXED

**Relay Log** (on replica):
- Local copy of master's binary log
- Temporary (auto-purged after applying)
- Allows replica to apply changes at its own pace
- Enables crash recovery with `relay_log_recovery=ON`

**Flow**:
```
Master binlog → Network → Replica relay log → Replica data
```

---

## ✅ Completion Checklist

- [ ] Understand binary log formats (STATEMENT, ROW, MIXED)
- [ ] Know GTID format and benefits
- [ ] Understand relay log lifecycle and recovery
- [ ] Can set up GTID-based replication
- [ ] Monitor replication lag and troubleshoot issues
- [ ] Understand parallel replication strategies
- [ ] Know different replication topologies
- [ ] Can explain semi-synchronous replication

## 🔗 Next: Increment 8 - Performance Schema

# 🎯 Increment 6: Locking Mechanisms & Deadlock Prevention

**Duration**: 50 minutes  
**Difficulty**: ⭐⭐⭐⭐⭐ Expert

## 📋 Quick Summary

**What you'll master**: InnoDB's sophisticated locking system including row locks, gap locks, and next-key locks, plus deadlock detection and prevention strategies.

**Key concepts**: 
- **Row locks** = Lock on specific index records
- **Gap locks** = Lock on space between records
- **Next-key locks** = Row lock + gap lock (default)
- **Deadlock detection** = Automatic detection and victim selection

**Why it matters**: 
- **Concurrency control** - balance between consistency and performance
- **Deadlock debugging** - common production issue
- **Lock contention** - major performance bottleneck
- **Staff expectation** - must design deadlock-free systems

---

## What You'll Learn

- Understand all InnoDB lock types
- Create and analyze deadlocks
- Use Performance Schema to monitor locks
- Design deadlock-free systems
- Optimize lock contention

## 🎓 Theory (20 minutes)

### Lock Types

**By Compatibility**:
- **Shared (S)**: Allows reads, blocks writes
- **Exclusive (X)**: Blocks both reads and writes

**By Granularity**:
```
Table Level:
├─ Intention Shared (IS)
└─ Intention Exclusive (IX)

Row Level:
├─ Record Lock (single row)
├─ Gap Lock (between rows)
└─ Next-Key Lock (record + gap)
```

### Next-Key Locking

**Default for range queries in REPEATABLE READ**:

```
Index values: 10, 20, 30, 40

SELECT * FROM t WHERE id > 15 AND id < 35 FOR UPDATE;

Locks acquired:
(-∞, 10]  - Gap lock
(10, 20]  - Next-key lock (gap + record)
(20, 30]  - Next-key lock
(30, 40]  - Gap lock
```

**Purpose**: Prevent phantom reads

### Deadlock Example

```
Time  | Transaction 1              | Transaction 2
------|----------------------------|---------------------------
T1    | UPDATE users SET age=30    |
      | WHERE user_id=1            |
      | (locks row 1)              |
------|----------------------------|---------------------------
T2    |                            | UPDATE users SET age=40
      |                            | WHERE user_id=2
      |                            | (locks row 2)
------|----------------------------|---------------------------
T3    | UPDATE users SET age=50    |
      | WHERE user_id=2            |
      | (waits for row 2)          |
------|----------------------------|---------------------------
T4    |                            | UPDATE users SET age=60
      |                            | WHERE user_id=1
      |                            | (waits for row 1)
------|----------------------------|---------------------------
      | 💥 DEADLOCK DETECTED!      |
      | T1 rolled back             |
```

---

## 🧪 Hands-On Exercises (25 minutes)

### Exercise 1: Lock Monitoring (10 min)

```sql
-- Enable lock monitoring
SET GLOBAL innodb_status_output_locks=ON;

-- Session 1: Acquire locks
START TRANSACTION;
SELECT * FROM users WHERE user_id = 1 FOR UPDATE;

-- Session 2: View locks
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

-- Session 1: Commit
COMMIT;
```

### Exercise 2: Create a Deadlock (10 min)

```sql
-- Session 1
START TRANSACTION;
UPDATE users SET age = 30 WHERE user_id = 1;
-- Wait...

-- Session 2
START TRANSACTION;
UPDATE users SET age = 40 WHERE user_id = 2;
-- Now update user 1
UPDATE users SET age = 50 WHERE user_id = 1;
-- Waits...

-- Session 1
UPDATE users SET age = 60 WHERE user_id = 2;
-- ERROR 1213: Deadlock found!

-- View deadlock info
SHOW ENGINE INNODB STATUS\G
-- Look for "LATEST DETECTED DEADLOCK"
```

### Exercise 3: Gap Locks (5 min)

```sql
-- Session 1
START TRANSACTION;
SELECT * FROM users 
WHERE user_id BETWEEN 5 AND 15 
FOR UPDATE;

-- Session 2: Try to insert in gap
INSERT INTO users (user_id, username, email)
VALUES (10, 'test', 'test@test.com');
-- Blocked by gap lock!

-- Session 1: Commit
COMMIT;
```

---

## 📝 Key Takeaways

1. **Next-key locks** prevent phantom reads
2. **Gap locks** block inserts in ranges
3. **Deadlocks** are detected automatically
4. **Access resources in consistent order** to prevent deadlocks
5. **Monitor locks** with Performance Schema

---

## 🎤 Interview Questions

### Q1: How would you prevent deadlocks?

**Answer**:
1. Access tables/rows in consistent order
2. Keep transactions short
3. Use appropriate isolation level
4. Add indexes to reduce lock scope
5. Implement retry logic

### Q2: What's the difference between gap lock and next-key lock?

**Answer**:
- **Gap lock**: Locks space between records
- **Next-key lock**: Gap lock + record lock
- Next-key is default for range queries in REPEATABLE READ

---

## ✅ Completion Checklist

- [ ] Understand all lock types
- [ ] Can create and analyze deadlocks
- [ ] Know deadlock prevention strategies
- [ ] Can monitor locks with Performance Schema

## 🔗 Next: Increment 7 - Replication Architecture

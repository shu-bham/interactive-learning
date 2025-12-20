# 🎯 Increment 4: Index Internals & B+Tree Deep Dive

**Duration**: 60 minutes  
**Difficulty**: ⭐⭐⭐⭐⭐ Expert

## 📋 Quick Summary

**What you'll master**: The internal structure of InnoDB indexes, how B+Trees work, and advanced indexing strategies for optimal performance.

**Key concepts**: 
- **B+Tree structure** = Balanced tree with data in leaf nodes
- **Clustered index** = Table data stored in primary key order
- **Secondary index** = Contains indexed columns + primary key pointer
- **Index selectivity** = Ratio of distinct values to total rows

**Why it matters**: 
- **Foundation of performance** - indexes are the #1 performance lever
- **Interview deep-dive topic** - expect detailed B+Tree questions at staff level
- **Production decisions** - choosing wrong index strategy kills performance
- **Capacity planning** - indexes consume significant disk and memory

---

## What You'll Learn

By the end of this increment, you'll be able to:
- Explain B+Tree structure and operations in detail
- Understand the difference between clustered and secondary indexes
- Choose optimal index strategies for different query patterns
- Identify index fragmentation and maintenance needs
- Calculate index size and selectivity
- Answer expert-level questions about index internals

## 🎓 Theory (25 minutes)

### Why B+Trees?

**Requirements for database indexes**:
- ✅ Fast lookups: O(log n)
- ✅ Efficient range scans
- ✅ Sequential access for sorting
- ✅ Balanced (no skew)
- ✅ Good for both reads and writes

**B+Tree delivers all of these!**

### B+Tree Structure

```
                    [Root Node - Internal]
                    [10 | 20 | 30 | 40]
                   /    |    |    |    \
                  /     |    |    |     \
        [Internal]  [Internal] [Internal] [Internal]
        [5|8]       [15|18]    [25|28]    [35|38]
       /  |  \      /  |  \    /  |  \    /  |  \
     [L] [L] [L]  [L] [L] [L][L] [L] [L][L] [L] [L]
      ↓   ↓   ↓    ↓   ↓   ↓  ↓   ↓   ↓  ↓   ↓   ↓
    Data Data Data...........................Data
     ↔    ↔    ↔    ↔    ↔    ↔    ↔    ↔    ↔
    (Leaf nodes are linked for range scans)
```

**Key Properties**:
1. **All data in leaf nodes** - internal nodes only have keys
2. **Leaf nodes are linked** - enables efficient range scans
3. **Balanced** - all leaf nodes at same depth
4. **Page size: 16KB** - each node is one page
5. **Fanout ~1200** - each internal node can have ~1200 children

### Clustered Index (Primary Key)

**InnoDB stores table data IN the primary key B+Tree**:

```
Primary Key Index (Clustered):
                [Root: PK values]
                       ↓
            [Internal: PK values]
                       ↓
        [Leaf: PK + ALL row data]
        
Example for users table (PK = user_id):
Leaf Node: [user_id=1, username='john', email='john@...', age=30, ...]
           [user_id=2, username='alice', email='alice@...', age=28, ...]
```

**Implications**:
- ✅ Fast PK lookups (single B+Tree traversal)
- ✅ Range scans on PK are efficient
- ⚠️ Table is physically ordered by PK
- ⚠️ Secondary indexes must store PK (not row pointer)

### Secondary Index

**Secondary indexes store: indexed columns + primary key**:

```
Secondary Index on email:
                [Root: email values]
                       ↓
            [Internal: email values]
                       ↓
        [Leaf: email + PK]
        
Example:
Leaf Node: [email='alice@...', user_id=2]
           [email='bob@...', user_id=5]
           [email='john@...', user_id=1]
```

**Lookup process**:
1. Traverse secondary index B+Tree to find PK
2. Traverse primary index B+Tree to get full row
3. **Two B+Tree lookups!** (unless covering index)

### Composite Index

**Index on multiple columns**: `INDEX(col1, col2, col3)`

```
Composite Index on (country_code, status, age):
Leaf Node: [country='AU', status='active', age=25, PK=4]
           [country='AU', status='active', age=30, PK=9]
           [country='US', status='active', age=28, PK=1]
           [country='US', status='inactive', age=35, PK=6]
```

**Leftmost Prefix Rule**:
- Index `(A, B, C)` can be used for:
  - ✅ `WHERE A = ?`
  - ✅ `WHERE A = ? AND B = ?`
  - ✅ `WHERE A = ? AND B = ? AND C = ?`
  - ❌ `WHERE B = ?`
  - ❌ `WHERE C = ?`
  - ⚠️ `WHERE A = ? AND C = ?` (only uses A)

### Index Selectivity

**Selectivity** = Number of distinct values / Total rows

```sql
-- High selectivity (good for indexing)
SELECT COUNT(DISTINCT email) / COUNT(*) FROM users;
-- Result: 1.0 (every email is unique)

-- Low selectivity (poor for indexing)
SELECT COUNT(DISTINCT status) / COUNT(*) FROM users;
-- Result: 0.003 (only 3 distinct values: active, inactive, suspended)
```

**Rule of thumb**:
- Selectivity > 0.1 (10%) → Good candidate for index
- Selectivity < 0.01 (1%) → Poor candidate for index

### Index Cardinality

**Cardinality** = Number of distinct values in indexed column

```sql
SELECT 
    INDEX_NAME,
    COLUMN_NAME,
    CARDINALITY,
    TABLE_ROWS,
    ROUND(CARDINALITY / TABLE_ROWS, 4) AS selectivity
FROM information_schema.STATISTICS s
JOIN information_schema.TABLES t 
    ON s.TABLE_SCHEMA = t.TABLE_SCHEMA 
    AND s.TABLE_NAME = t.TABLE_NAME
WHERE s.TABLE_SCHEMA = 'learning_db' 
  AND s.TABLE_NAME = 'users'
  AND s.SEQ_IN_INDEX = 1;
```

---

## 🧪 Hands-On Exercises (30 minutes)

### Exercise 1: Exploring Index Structure (10 min)

```sql
-- View all indexes on users table
SHOW INDEX FROM users;

-- Detailed index information
SELECT 
    INDEX_NAME,
    SEQ_IN_INDEX,
    COLUMN_NAME,
    COLLATION,
    CARDINALITY,
    SUB_PART,
    PACKED,
    NULLABLE,
    INDEX_TYPE
FROM information_schema.STATISTICS
WHERE TABLE_SCHEMA = 'learning_db' 
  AND TABLE_NAME = 'users'
ORDER BY INDEX_NAME, SEQ_IN_INDEX;

-- Calculate index selectivity
SELECT 
    INDEX_NAME,
    COLUMN_NAME,
    CARDINALITY,
    (SELECT TABLE_ROWS FROM information_schema.TABLES 
     WHERE TABLE_SCHEMA = 'learning_db' AND TABLE_NAME = 'users') AS total_rows,
    ROUND(
        CARDINALITY / 
        (SELECT TABLE_ROWS FROM information_schema.TABLES 
         WHERE TABLE_SCHEMA = 'learning_db' AND TABLE_NAME = 'users'),
        4
    ) AS selectivity
FROM information_schema.STATISTICS
WHERE TABLE_SCHEMA = 'learning_db' 
  AND TABLE_NAME = 'users'
  AND SEQ_IN_INDEX = 1
ORDER BY selectivity DESC;
```

### Exercise 2: Primary vs Secondary Index Performance (10 min)

```sql
-- Lookup by primary key (single B+Tree traversal)
EXPLAIN ANALYZE
SELECT * FROM users WHERE user_id = 5;
-- Note the execution time

-- Lookup by secondary index (two B+Tree traversals)
EXPLAIN ANALYZE
SELECT * FROM users WHERE email = 'alice.smith@example.com';
-- Compare execution time - should be slightly slower

-- Covering index (single B+Tree traversal, no table lookup)
EXPLAIN ANALYZE
SELECT user_id, email FROM users WHERE email = 'alice.smith@example.com';
-- Should be faster than previous query

-- Demonstrate the difference with a range scan
EXPLAIN ANALYZE
SELECT * FROM users WHERE user_id BETWEEN 1 AND 100;
-- Primary key range scan

EXPLAIN ANALYZE
SELECT * FROM users WHERE email BETWEEN 'a' AND 'c';
-- Secondary index range scan (slower due to random PK lookups)
```

### Exercise 3: Composite Index Behavior (10 min)

```sql
-- Create a composite index
CREATE INDEX idx_country_status_age ON users(country_code, status, age);

-- Test leftmost prefix rule

-- Uses entire index (all 3 columns)
EXPLAIN SELECT * FROM users 
WHERE country_code = 'US' AND status = 'active' AND age > 25;
-- Check key_len in output

-- Uses first 2 columns
EXPLAIN SELECT * FROM users 
WHERE country_code = 'US' AND status = 'active';
-- key_len should be smaller

-- Uses only first column
EXPLAIN SELECT * FROM users 
WHERE country_code = 'US';
-- key_len should be even smaller

-- Does NOT use index (skips leftmost column)
EXPLAIN SELECT * FROM users 
WHERE status = 'active' AND age > 25;
-- Should show different index or table scan

-- Uses only first column (skips middle column)
EXPLAIN SELECT * FROM users 
WHERE country_code = 'US' AND age > 25;
-- key_len shows only country_code is used

-- Calculate key_len manually
SELECT 
    s.INDEX_NAME,
    GROUP_CONCAT(s.COLUMN_NAME ORDER BY s.SEQ_IN_INDEX) AS columns,
    SUM(
        CASE 
            WHEN c.DATA_TYPE = 'int' THEN 4
            WHEN c.DATA_TYPE = 'bigint' THEN 8
            WHEN c.DATA_TYPE = 'char' THEN c.CHARACTER_MAXIMUM_LENGTH * 4 + 1
            WHEN c.DATA_TYPE = 'varchar' THEN c.CHARACTER_MAXIMUM_LENGTH * 4 + 2
            WHEN c.DATA_TYPE = 'timestamp' THEN 4
            ELSE 0
        END
    ) AS calculated_key_len
FROM information_schema.STATISTICS s
JOIN information_schema.COLUMNS c 
    ON s.TABLE_SCHEMA = c.TABLE_SCHEMA 
    AND s.TABLE_NAME = c.TABLE_NAME 
    AND s.COLUMN_NAME = c.COLUMN_NAME
WHERE s.TABLE_SCHEMA = 'learning_db' 
  AND s.TABLE_NAME = 'users'
  AND s.INDEX_NAME = 'idx_country_status_age'
GROUP BY s.INDEX_NAME;
```

## 🎯 Challenge Exercise: Index Strategy Design

**Scenario**: Design optimal indexes for a high-traffic application.

```sql
-- Create a realistic table
CREATE TABLE page_views (
    view_id BIGINT AUTO_INCREMENT PRIMARY KEY,
    user_id BIGINT NOT NULL,
    page_url VARCHAR(500),
    view_date DATE NOT NULL,
    view_timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    session_id VARCHAR(100),
    device_type ENUM('mobile', 'tablet', 'desktop'),
    country_code CHAR(2)
) ENGINE=InnoDB;

-- Common query patterns:
-- Q1: Find all views by a user
SELECT * FROM page_views WHERE user_id = ?;

-- Q2: Find views for a specific date range
SELECT * FROM page_views 
WHERE view_date BETWEEN '2024-01-01' AND '2024-01-31';

-- Q3: Analytics query - views by country and device
SELECT country_code, device_type, COUNT(*) 
FROM page_views 
WHERE view_date BETWEEN '2024-01-01' AND '2024-01-31'
GROUP BY country_code, device_type;

-- Q4: User activity timeline
SELECT page_url, view_timestamp 
FROM page_views 
WHERE user_id = ? 
ORDER BY view_timestamp DESC 
LIMIT 20;
```

**Your task**: Design indexes for these queries.

<details>
<summary>Click for solution</summary>

```sql
-- For Q1 and Q4: User activity queries
CREATE INDEX idx_user_timestamp ON page_views(user_id, view_timestamp);
-- Covers both user lookup and sorting by timestamp

-- For Q2 and Q3: Date-based analytics
CREATE INDEX idx_date_country_device ON page_views(view_date, country_code, device_type);
-- Covering index for Q3, efficient range scan for Q2

-- Verify with EXPLAIN
EXPLAIN SELECT * FROM page_views WHERE user_id = 123;
EXPLAIN SELECT page_url, view_timestamp 
FROM page_views WHERE user_id = 123 ORDER BY view_timestamp DESC LIMIT 20;
EXPLAIN SELECT country_code, device_type, COUNT(*) 
FROM page_views 
WHERE view_date BETWEEN '2024-01-01' AND '2024-01-31'
GROUP BY country_code, device_type;
```

**Why these indexes?**
- `idx_user_timestamp`: Supports user lookups and provides sorted order
- `idx_date_country_device`: Covering index for analytics, efficient date ranges
- Avoided redundant indexes (e.g., separate index on user_id alone)

</details>

---

## 📝 Key Takeaways

1. **B+Tree structure** enables O(log n) lookups and efficient range scans
2. **Clustered index** stores actual table data in PK order
3. **Secondary indexes** require two B+Tree lookups (unless covering)
4. **Composite indexes** follow leftmost prefix rule
5. **Index selectivity** determines index effectiveness
6. **Page size is 16KB** - affects all index calculations
7. **Choose indexes based on query patterns**, not just columns

---

## 🎤 Interview Question Practice

### Q1: Explain the difference between clustered and secondary indexes in InnoDB

**Your Answer**:

**Clustered Index (Primary Key)**:
- Table data is stored IN the B+Tree leaf nodes
- One per table (the primary key)
- Leaf nodes contain: PK + all row columns
- Lookup: Single B+Tree traversal
- Table is physically ordered by PK

**Secondary Index**:
- Separate B+Tree structure
- Multiple per table
- Leaf nodes contain: indexed columns + PK value
- Lookup: Two B+Tree traversals (index → PK → data)
- Not physically ordered

**Example**:
```
Clustered (PK=user_id):
  Leaf: [user_id=1, username='john', email='john@...', ...]

Secondary (email):
  Leaf: [email='john@...', user_id=1]
  Then lookup user_id=1 in clustered index
```

**Implication**: Choose a small PK (secondary indexes store it!)

### Q2: When would you use a composite index vs multiple single-column indexes?

**Your Answer**:

**Use Composite Index when**:
- Queries filter on multiple columns together
- Want to create a covering index
- Columns are frequently used in combination

**Example**:
```sql
-- Query pattern
SELECT * FROM orders 
WHERE user_id = ? AND status = 'pending';

-- Better: Composite index
CREATE INDEX idx_user_status ON orders(user_id, status);

-- Worse: Two separate indexes
CREATE INDEX idx_user ON orders(user_id);
CREATE INDEX idx_status ON orders(status);
-- MySQL can only use ONE index per table in most cases
```

**Use Separate Indexes when**:
- Queries filter on columns independently
- Different query patterns need different indexes

**Trade-off**:
- Composite: Fewer indexes, better for specific query patterns
- Separate: More flexible, but MySQL picks only one

### Q3: How do you determine if an index is being used efficiently?

**Your Answer**:

**Check these metrics**:

1. **EXPLAIN output**:
   ```sql
   EXPLAIN SELECT ...
   -- Look for:
   -- - type: Should be const, eq_ref, ref, or range (not ALL)
   -- - key: Should show your index name
   -- - rows: Should be low
   -- - Extra: "Using index" is best (covering index)
   ```

2. **Index statistics**:
   ```sql
   SELECT 
       INDEX_NAME,
       CARDINALITY,
       CARDINALITY / TABLE_ROWS AS selectivity
   FROM information_schema.STATISTICS
   -- High selectivity (> 0.1) = good index
   ```

3. **Performance Schema**:
   ```sql
   SELECT 
       OBJECT_NAME,
       INDEX_NAME,
       COUNT_STAR,
       COUNT_READ,
       COUNT_FETCH
   FROM performance_schema.table_io_waits_summary_by_index_usage
   WHERE OBJECT_SCHEMA = 'learning_db'
   ORDER BY COUNT_STAR DESC;
   -- Shows which indexes are actually used
   ```

4. **Unused indexes**:
   ```sql
   -- Find indexes never used
   SELECT * FROM sys.schema_unused_indexes;
   ```

---

## ✅ Completion Checklist

Before moving to Increment 5, ensure you can:
- [ ] Explain B+Tree structure and why it's used
- [ ] Describe the difference between clustered and secondary indexes
- [ ] Understand the leftmost prefix rule for composite indexes
- [ ] Calculate index selectivity and cardinality
- [ ] Design indexes based on query patterns
- [ ] Identify when covering indexes help
- [ ] Answer the three interview questions above confidently

## 🔗 Next Increment

**Increment 5: MVCC & Transaction Isolation Levels**
- Deep dive into Multi-Version Concurrency Control
- How read views work
- Isolation level implementation details
- Phantom reads and gap locks

---

**Ready to proceed?** Update `progress.md` and let me know when you're ready for Increment 5!

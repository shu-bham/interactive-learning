# Module 2: Query Execution & Optimization

## 🎯 Learning Objectives

- Understand MySQL query execution pipeline
- Master EXPLAIN and execution plan analysis
- Learn index internals and B+Tree structure
- Optimize queries using cost-based optimization
- Identify and fix common query performance issues

## 📖 Theory

### Query Execution Pipeline

```
┌─────────────────────────────────────────────────────────┐
│  1. Connection Handler                                   │
│     ↓                                                    │
│  2. Query Cache (deprecated in 8.0)                     │
│     ↓                                                    │
│  3. Parser                                               │
│     ├─ Syntax Check                                     │
│     └─ Parse Tree Generation                            │
│     ↓                                                    │
│  4. Preprocessor                                         │
│     ├─ Semantic Check                                   │
│     └─ Privilege Check                                  │
│     ↓                                                    │
│  5. Query Optimizer                                      │
│     ├─ Logical Optimization (rewrite rules)             │
│     ├─ Physical Optimization (access methods)           │
│     ├─ Cost-based Selection                             │
│     └─ Execution Plan Generation                        │
│     ↓                                                    │
│  6. Query Execution Engine                               │
│     ├─ Storage Engine API Calls                         │
│     └─ Result Set Building                              │
│     ↓                                                    │
│  7. Return Results to Client                             │
└─────────────────────────────────────────────────────────┘
```

### B+Tree Index Structure

InnoDB uses B+Tree for all indexes (primary and secondary).

```
                    [Root Node]
                   /     |     \
                  /      |      \
            [Internal] [Internal] [Internal]
            /    \      /    \      /    \
        [Leaf] [Leaf] [Leaf] [Leaf] [Leaf] [Leaf]
          ↓      ↓      ↓      ↓      ↓      ↓
        [Data] [Data] [Data] [Data] [Data] [Data]
```

**Key Characteristics**:
- **Leaf nodes** contain actual data (clustered index) or primary key values (secondary index)
- **Internal nodes** contain keys and pointers
- **Leaf nodes are linked** for range scans
- **Balanced tree** ensures O(log n) search time
- **Page size**: 16KB per node

**Primary (Clustered) Index**:
- Table data is stored in primary key order
- Leaf nodes contain full row data
- One per table

**Secondary Index**:
- Leaf nodes contain indexed columns + primary key
- Requires additional lookup to get full row (if needed)
- Multiple per table

### Cost-Based Optimizer

The optimizer estimates costs for different execution plans:

**Cost Factors**:
- **I/O Cost**: Reading pages from disk
- **CPU Cost**: Processing rows
- **Memory Cost**: Sorting, temporary tables

**Statistics Used**:
- Table cardinality (row count)
- Index cardinality (distinct values)
- Data distribution (histograms in MySQL 8.0)
- Index selectivity

## 🧪 Hands-On Labs

### Lab 2.1: Understanding EXPLAIN

**Objective**: Master EXPLAIN output interpretation

```sql
-- Basic EXPLAIN
EXPLAIN SELECT * FROM users WHERE email = 'john.doe@example.com';

-- EXPLAIN with FORMAT=JSON for more details
EXPLAIN FORMAT=JSON 
SELECT * FROM users WHERE email = 'john.doe@example.com';

-- EXPLAIN ANALYZE (MySQL 8.0.18+) - shows actual execution metrics
EXPLAIN ANALYZE
SELECT * FROM users WHERE email = 'john.doe@example.com';
```

**Understanding EXPLAIN Columns**:

| Column | Description |
|--------|-------------|
| `id` | Query identifier (for subqueries) |
| `select_type` | Type of SELECT (SIMPLE, PRIMARY, SUBQUERY, etc.) |
| `table` | Table being accessed |
| `partitions` | Partitions accessed |
| `type` | Join type (system, const, eq_ref, ref, range, index, ALL) |
| `possible_keys` | Indexes that could be used |
| `key` | Index actually used |
| `key_len` | Length of key used |
| `ref` | Columns compared to index |
| `rows` | Estimated rows to examine |
| `filtered` | Percentage of rows filtered by condition |
| `Extra` | Additional information |

**Join Types (Best to Worst)**:
1. **system**: Table has only one row
2. **const**: At most one matching row (primary key or unique index)
3. **eq_ref**: One row per previous table combination (join on primary/unique key)
4. **ref**: Multiple rows with matching index value
5. **range**: Index range scan (BETWEEN, >, <, IN)
6. **index**: Full index scan
7. **ALL**: Full table scan (worst!)

**Exercise - Compare Access Methods**:

```sql
-- Full table scan (type: ALL)
EXPLAIN SELECT * FROM users WHERE age > 25;

-- Index range scan (type: range)
EXPLAIN SELECT * FROM users WHERE user_id BETWEEN 1 AND 5;

-- Index lookup (type: ref)
EXPLAIN SELECT * FROM users WHERE status = 'active';

-- Constant lookup (type: const)
EXPLAIN SELECT * FROM users WHERE user_id = 1;

-- Join analysis
EXPLAIN SELECT 
    u.username,
    o.order_id,
    o.total_amount
FROM users u
INNER JOIN orders o ON u.user_id = o.user_id
WHERE u.status = 'active';
```

### Lab 2.2: Index Selection and Optimization

**Objective**: Understand how MySQL chooses indexes

```sql
-- View available indexes
SHOW INDEX FROM users;

-- Force index usage
EXPLAIN SELECT * FROM users FORCE INDEX (idx_email) WHERE email LIKE 'john%';

-- Ignore an index
EXPLAIN SELECT * FROM users IGNORE INDEX (idx_email) WHERE email = 'john.doe@example.com';

-- Compare optimizer choices
EXPLAIN SELECT * FROM users WHERE email = 'john.doe@example.com' AND status = 'active';

-- Check index statistics
SELECT 
    TABLE_NAME,
    INDEX_NAME,
    SEQ_IN_INDEX,
    COLUMN_NAME,
    CARDINALITY,
    SUB_PART,
    NULLABLE
FROM information_schema.STATISTICS
WHERE TABLE_SCHEMA = 'learning_db' AND TABLE_NAME = 'users'
ORDER BY INDEX_NAME, SEQ_IN_INDEX;
```

**Exercise - Index Cardinality Impact**:

```sql
-- Analyze table to update statistics
ANALYZE TABLE users;

-- Check cardinality before
SELECT 
    INDEX_NAME,
    CARDINALITY
FROM information_schema.STATISTICS
WHERE TABLE_SCHEMA = 'learning_db' 
  AND TABLE_NAME = 'users'
  AND SEQ_IN_INDEX = 1;

-- Insert duplicate data to reduce cardinality
INSERT INTO users (username, email, first_name, last_name, status, country_code)
SELECT 
    CONCAT(username, '_dup', n),
    CONCAT('dup', n, '_', email),
    first_name,
    last_name,
    status,
    country_code
FROM users,
(SELECT 1 AS n UNION SELECT 2 UNION SELECT 3 UNION SELECT 4 UNION SELECT 5) nums;

-- Re-analyze
ANALYZE TABLE users;

-- Check cardinality after
SELECT 
    INDEX_NAME,
    CARDINALITY
FROM information_schema.STATISTICS
WHERE TABLE_SCHEMA = 'learning_db' 
  AND TABLE_NAME = 'users'
  AND SEQ_IN_INDEX = 1;

-- See how optimizer behavior changes
EXPLAIN SELECT * FROM users WHERE status = 'active';
```

### Lab 2.3: Composite Index Optimization

**Objective**: Master multi-column index usage

```sql
-- Create a composite index
CREATE INDEX idx_country_status_age ON users(country_code, status, age);

-- Test index usage with different WHERE clauses

-- Uses index fully (all columns in order)
EXPLAIN SELECT * FROM users 
WHERE country_code = 'US' AND status = 'active' AND age > 25;

-- Uses index partially (leftmost prefix)
EXPLAIN SELECT * FROM users 
WHERE country_code = 'US' AND status = 'active';

-- Uses index (leftmost column)
EXPLAIN SELECT * FROM users 
WHERE country_code = 'US';

-- Does NOT use index (skips leftmost column)
EXPLAIN SELECT * FROM users 
WHERE status = 'active' AND age > 25;

-- Does NOT use index (starts with middle column)
EXPLAIN SELECT * FROM users 
WHERE status = 'active';
```

**Leftmost Prefix Rule**:
For index `(col1, col2, col3)`:
- ✅ `WHERE col1 = ?`
- ✅ `WHERE col1 = ? AND col2 = ?`
- ✅ `WHERE col1 = ? AND col2 = ? AND col3 = ?`
- ❌ `WHERE col2 = ?`
- ❌ `WHERE col2 = ? AND col3 = ?`
- ⚠️ `WHERE col1 = ? AND col3 = ?` (uses only col1)

### Lab 2.4: Query Rewriting and Optimization

**Objective**: Learn query optimization techniques

**Example 1: Subquery vs JOIN**

```sql
-- Subquery (often slower)
EXPLAIN SELECT * FROM users 
WHERE user_id IN (SELECT user_id FROM orders WHERE status = 'delivered');

-- JOIN (usually faster)
EXPLAIN SELECT DISTINCT u.* FROM users u
INNER JOIN orders o ON u.user_id = o.user_id
WHERE o.status = 'delivered';

-- Even better: EXISTS
EXPLAIN SELECT * FROM users u
WHERE EXISTS (
    SELECT 1 FROM orders o 
    WHERE o.user_id = u.user_id AND o.status = 'delivered'
);
```

**Example 2: Avoid Functions on Indexed Columns**

```sql
-- Bad: Function on indexed column prevents index usage
EXPLAIN SELECT * FROM users WHERE YEAR(created_at) = 2024;

-- Good: Rewrite to use index
EXPLAIN SELECT * FROM users 
WHERE created_at >= '2024-01-01' AND created_at < '2025-01-01';
```

**Example 3: LIMIT Optimization**

```sql
-- Inefficient: Sorts all rows then limits
EXPLAIN SELECT * FROM orders ORDER BY order_date DESC LIMIT 10;

-- Better: Use index for sorting
EXPLAIN SELECT * FROM orders ORDER BY order_id DESC LIMIT 10;

-- Pagination optimization (avoid OFFSET on large datasets)
-- Bad
EXPLAIN SELECT * FROM orders ORDER BY order_id LIMIT 1000, 10;

-- Good: Use WHERE clause instead
EXPLAIN SELECT * FROM orders 
WHERE order_id > 1000 
ORDER BY order_id 
LIMIT 10;
```

### Lab 2.5: Optimizer Trace

**Objective**: Deep dive into optimizer decision-making

```sql
-- Enable optimizer trace
SET optimizer_trace="enabled=on";

-- Run a query
SELECT * FROM users u
INNER JOIN orders o ON u.user_id = o.user_id
WHERE u.status = 'active' AND o.total_amount > 100;

-- View optimizer trace
SELECT * FROM information_schema.OPTIMIZER_TRACE\G

-- Disable optimizer trace
SET optimizer_trace="enabled=off";
```

**Analyzing Optimizer Trace**:
The trace shows:
- **join_preparation**: Query rewrite and preparation
- **join_optimization**: Cost calculation for different plans
- **considered_execution_plans**: All plans evaluated
- **chosen_execution_plan**: Final selected plan with costs

### Lab 2.6: Index Condition Pushdown (ICP)

**Objective**: Understand ICP optimization

```sql
-- Create a scenario for ICP
CREATE INDEX idx_status_age ON users(status, age);

-- Without ICP, MySQL would:
-- 1. Use index to find rows with status='active'
-- 2. Fetch full rows from table
-- 3. Filter by age in server layer

-- With ICP (enabled by default), MySQL:
-- 1. Use index to find rows with status='active'
-- 2. Filter by age using index (before fetching full rows)
-- 3. Fetch only matching rows

EXPLAIN SELECT * FROM users 
WHERE status = 'active' AND age BETWEEN 25 AND 35;

-- Look for "Using index condition" in Extra column

-- Disable ICP to compare
SET optimizer_switch='index_condition_pushdown=off';
EXPLAIN SELECT * FROM users 
WHERE status = 'active' AND age BETWEEN 25 AND 35;

-- Re-enable ICP
SET optimizer_switch='index_condition_pushdown=on';
```

## 🎯 Staff Interview Questions

### Question 1: Index Selection
**Q**: You have a query with `WHERE col1 = ? AND col2 = ?`. You can create either `INDEX(col1, col2)` or `INDEX(col2, col1)`. How do you decide?

**A**:
Consider:
1. **Selectivity**: Put more selective column first (fewer distinct values = better)
2. **Query patterns**: If queries often filter by col1 alone, put it first
3. **Cardinality**: Check `SELECT COUNT(DISTINCT col1)` vs `COUNT(DISTINCT col2)`
4. **Range conditions**: If col2 has range condition (`>`, `<`, `BETWEEN`), put it last

Example:
- `country_code` has 200 distinct values
- `status` has 3 distinct values
- Create `INDEX(country_code, status)` for better selectivity

### Question 2: Covering Index
**Q**: What is a covering index? When would you use it?

**A**:
A **covering index** contains all columns needed by a query, eliminating table lookups.

**Example**:
```sql
-- Query needs: user_id, email, status
CREATE INDEX idx_covering ON users(user_id, email, status);

-- This query is "covered" - no table access needed
SELECT user_id, email, status FROM users WHERE user_id > 100;
-- EXPLAIN shows: "Using index" in Extra column
```

**Benefits**:
- Faster queries (no table lookups)
- Reduced I/O

**Trade-offs**:
- Larger index size
- Slower writes (more index maintenance)

**When to use**:
- Frequently run queries
- Read-heavy workloads
- Queries selecting few columns

### Question 3: Query Performance Degradation
**Q**: A query that was fast yesterday is now slow. How do you troubleshoot?

**A**:
1. **Check EXPLAIN**: Has the execution plan changed?
   ```sql
   EXPLAIN SELECT ...;
   ```

2. **Verify statistics**: Are they stale?
   ```sql
   ANALYZE TABLE table_name;
   ```

3. **Check index usage**:
   ```sql
   SHOW INDEX FROM table_name;
   ```

4. **Look for table locks**:
   ```sql
   SHOW PROCESSLIST;
   SHOW ENGINE INNODB STATUS;
   ```

5. **Check data growth**: Has table size increased significantly?
   ```sql
   SELECT TABLE_ROWS, DATA_LENGTH 
   FROM information_schema.TABLES 
   WHERE TABLE_NAME = 'table_name';
   ```

6. **Review slow query log**:
   ```sql
   SHOW VARIABLES LIKE 'slow_query_log%';
   ```

7. **Check for parameter changes**: `SHOW VARIABLES;`

## 📝 Key Takeaways

1. **EXPLAIN is your best friend** - always analyze execution plans
2. **Index selectivity matters** - more selective columns first in composite indexes
3. **Avoid functions on indexed columns** - they prevent index usage
4. **JOIN is usually better than subqueries** - especially correlated subqueries
5. **Keep statistics updated** - run `ANALYZE TABLE` regularly
6. **Covering indexes** can dramatically improve read performance

## 🔗 Next Steps

Proceed to **Module 3: Transaction Management & Concurrency** to learn about MVCC, locking, and isolation levels.

```bash
cd ../03-transactions
cat README.md
```

## 📚 Further Reading

- [MySQL Optimizer Documentation](https://dev.mysql.com/doc/refman/8.0/en/optimization.html)
- [EXPLAIN Output Format](https://dev.mysql.com/doc/refman/8.0/en/explain-output.html)
- "High Performance MySQL" - Query Optimization chapter

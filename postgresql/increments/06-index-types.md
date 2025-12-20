# 🎯 Increment 06: Index Types (B-Tree, GIN, GiST, BRIN)

**Duration**: 60 minutes  
**Difficulty**: ⭐⭐⭐⭐⭐ Expert

## 📋 Quick Summary

MySQL is mostly a "B-Tree world". PostgreSQL, however, has a specialized engine for almost every data type. Knowing when to use a **GIN** index instead of a **B-Tree** is a key differentiator for a senior PostgreSQL developer.

**Key Concepts**:
- **B-Tree**: The default. High cardinality, ranges, sorting.
- **GIN (Generalized Inverted Index)**: For composite values (JSONB, Arrays, Full-text).
- **GiST / SP-GiST**: For complex data like Geometry (PostGIS) or Ranges.
- **BRIN (Block Range Index)**: For multi-terabyte "naturally ordered" data (timestamps).
- **Partial/Expression Indexes**: Index only what you need.

---

## 🎓 Theory (25 minutes)

### 1. The Heavy Hitters

| Index Type | Best For... | MySQL Equivalent |
|------------|-------------|------------------|
| **B-Tree** | Equality, Range, Sort | B+Tree (InnoDB) |
| **GIN** | JSONB, Arrays, Text Search | (Limited) |
| **Hash** | Equality only (`=`) | (Memory engine only) |
| **BRIN** | Huge time-series tables | (None) |

### 2. GIN - The Inverted Index

Think of an index at the back of a book. It lists every word (key) and all pages (rows) where it appears.
Used for:
- JSONB columns: `WHERE data @> '{"key": "value"}'`
- Arrays: `WHERE tags @> ARRAY['postgres']`

### 3. BRIN - The Efficiency Giant

BRIN stores only the **Min** and **Max** value for a block of pages (default 128 pages).
If a table is indexed by `created_at` and data is inserted sequentially, BRIN is **tiny** (e.g., 100KB for a 10GB table) and very fast for ranges.

### 4. Special PostgreSQL Features

- **Partial Index**: `CREATE INDEX ... WHERE active = true;` (Tiny index for specialized queries).
- **Expression Index**: `CREATE INDEX ... ON users (lower(email));` (Fixes the "function on column" performance killer).

---

## 🧪 Hands-On Exercises (25 minutes)

### Exercise 1: Expression Index vs Sequential Scan

```sql
-- 1. Try a search with a function
EXPLAIN ANALYZE SELECT * FROM users WHERE lower(email) = 'alice@example.com';
-- Result: Seq Scan (even if index on email exists!)

-- 2. Create an expression index
CREATE INDEX idx_users_lower_email ON users (lower(email));

-- 3. Try again
EXPLAIN ANALYZE SELECT * FROM users WHERE lower(email) = 'alice@example.com';
-- Result: Index Scan!
```

### Exercise 2: The Power of GIST (Ranges)

PostgreSQL has native **Range types**.

```sql
-- 1. Create a table for room bookings
CREATE TABLE bookings (
    room_id INT,
    during TSTZRANGE -- A range of timestamps
);

-- 2. Create a GIST index
CREATE INDEX idx_bookings_during ON bookings USING GIST (during);

-- 3. Query "Is the room available between these times?"
SELECT * FROM bookings 
WHERE during && tstzrange('2024-01-01 10:00', '2024-01-01 12:00');
```

### Exercise 3: Partial Index for "Active" Rows

```sql
-- 1. Create index only for active users
CREATE INDEX idx_active_users ON users (user_id) WHERE status = 'active';

-- 2. Query active users
EXPLAIN SELECT * FROM users WHERE user_id = 5 AND status = 'active';
```

---

## 🎤 Interview Question Practice

**Q1**: "If I have a JSONB column with 50 keys, should I create 50 B-Tree expression indexes or one GIN index?"

**Answer**: One **GIN** index. A GIN index on the JSONB column (using `jsonb_path_ops`) will support most "contains" (`@>`) queries across ALL keys in that column. It is much more efficient than managing dozens of individual indexes.

**Q2**: "When would you use a BRIN index over a B-Tree?"

**Answer**: For extremely large tables (billions of rows) where the data is physically ordered by the index key (like a `created_at` timestamp). BRIN is orders of magnitude smaller than B-Tree, saving massive amounts of RAM and disk space, while still providing incredible performance for range scans.

---

## ✅ Completion Checklist

- [ ] Explain the difference between B-Tree and GIN
- [ ] Create an expression index and verify it works with `EXPLAIN`
- [ ] Understand why BRIN is useful for time-series data
- [ ] Know how to check what index type a table is using (`\d table_name`)

## 🔗 Next: Increment 07 - Table Bloat, VACUUM & Autovacuum
Ready to deal with the "Cleanup Crew"? Let's master the most important maintenance task in PostgreSQL.

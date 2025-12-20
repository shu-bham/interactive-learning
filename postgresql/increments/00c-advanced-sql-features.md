# 🎯 Increment 00c: Advanced SQL Features (CTEs, Window, JSONB, Arrays)

**Duration**: 50 minutes  
**Difficulty**: ⭐⭐⭐ Professional

## 📋 Quick Summary

PostgreSQL is often called the "programmable database" because of its advanced data types and expressive SQL features. For a senior dev, mastering these is the difference between a 100-line messy query and a 10-line elegant CTE.

**Key Concepts**:
- **CTEs (WITH clause)**: Better than subqueries for readability and recursion.
- **Window Functions**: Perform calculations across a set of rows related to the current row.
- **JSONB**: Production-grade document storage within a relational table.
- **Arrays**: Native list support for simple 1:N relations without join tables.

---

## 🎓 Theory (20 minutes)

### 1. Common Table Expressions (CTEs)

PostgreSQL was a pioneer in CTEs. They make queries readable and support **Recursion** (crucial for tree/graph data).

```sql
WITH user_orders AS (
    SELECT user_id, SUM(amount) as total
    FROM orders
    GROUP BY user_id
)
SELECT u.username, uo.total
FROM users u
JOIN user_orders uo ON u.user_id = uo.user_id;
```

### 2. Window Functions

Essential for analytics. They let you aggregate without collapsing rows.

- `ROW_NUMBER()`: Unique increment within a partition.
- `RANK()`: Increment with ties.
- `LAG()` / `LEAD()`: Access previous/next row's value.

### 3. JSONB (Binary JSON)

JSONB is indexed and supports GIN (Generalized Inverted Index).
- **Notation**: `->` (get as json), `->>` (get as text), `@>` (contains).

### 4. Arrays

Store a list of tags directly: `tags TEXT[]`.
Avoid join tables for simple, low-velocity metadata.

---

## 🧪 Hands-On Exercises (20 minutes)

### Exercise 1: Window Functions for Ranking

```sql
-- Rank users by their total spend
SELECT 
    u.username,
    SUM(o.amount) as spend,
    RANK() OVER (ORDER BY SUM(o.amount) DESC) as spend_rank
FROM users u
JOIN orders o ON u.user_id = o.user_id
GROUP BY u.username;
```

### Exercise 2: JSONB Basics

```sql
-- 1. Create a table with JSONB
CREATE TABLE job_postings (
    id SERIAL PRIMARY KEY,
    title TEXT,
    attributes JSONB
);

-- 2. Insert rich data
INSERT INTO job_postings (title, attributes) VALUES
('Staff Engineer', '{"skills": ["Go", "Postgres", "Redis"], "remote": true, "salary_min": 150000}'),
('Senior Analyst', '{"skills": ["Python", "SQL", "Tableau"], "remote": false, "salary_min": 100000}');

-- 3. Query into the JSON
SELECT title FROM job_postings 
WHERE attributes->'skills' ? 'Postgres'; -- Does skills list contain 'Postgres'?

-- 4. Fast key access
SELECT title, attributes->>'salary_min' as salary
FROM job_postings
WHERE (attributes->>'salary_min')::INT > 120000;
```

### Exercise 3: Working with Arrays

```sql
-- Get users who had their first order in 2024 (using our init data)
SELECT username, ARRAY_AGG(order_id) as all_orders
FROM users
JOIN orders USING (user_id)
GROUP BY username;
```

---

## 🎤 Interview Question Practice

**Q1**: "When should I use a CTE instead of a temporary table?"

**Answer**: Use CTEs for readability, small to medium result sets, and when the logic is part of a single query. Temporary tables are better for extremely large datasets that need to be reused across multiple queries in the same session, or when you need to add indexes to the intermediate result.

**Q2**: "How does `JSONB` compare to the `JSON` type in PostgreSQL?"

**Answer**: `JSON` is stored as text and must be reparsed on every access. `JSONB` is stored in a decomposed binary format. `JSONB` is slightly slower to insert but magnitudes faster to query and supports indexing. Always default to `JSONB`.

---

## ✅ Completion Checklist

- [ ] Write a recursive CTE (bonus: look up the syntax for it!)
- [ ] Calculate a moving average using window functions
- [ ] Filter a table based on a value nested inside a JSONB column
- [ ] Understand when to use an Array vs a Join Table

## 🔗 Next Phase: Core Architecture
Congratulations! You've mastered the syntax basics. Now things get interesting as we look under the hood at **Shared Buffers and Memory Management**.

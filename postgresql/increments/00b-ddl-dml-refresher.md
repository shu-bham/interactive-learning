# 🎯 Increment 00b: DDL, DML, Grouping & Joins

**Duration**: 40 minutes  
**Difficulty**: ⭐⭐ Intermediate

## 📋 Quick Summary

PostgreSQL improves on many basic DML operations with features like the `RETURNING` clause and transactional DDL. If you've ever accidentally dropped a table in MySQL and couldn't undo it, you'll love PostgreSQL.

**Key Concepts**:
- **Transactional DDL**: Almost all DDL operations can be rolled back!
- **RETURNING**: Get data back from your `INSERT`, `UPDATE`, or `DELETE` instantly.
- **ON CONFLICT**: PostgreSQL's equivalent to `UPSERT`.
- **DISTINCT ON**: A unique PostgreSQL way to fetch the "first" row per group.

---

## 🎓 Theory (15 minutes)

### 1. Transactional DDL (The Superpower)

In MySQL, DDL statements (like `CREATE`, `DROP`, `ALTER`) trigger an **implicit commit**. You cannot roll them back.
In PostgreSQL, you can wrap them in a transaction:

```sql
BEGIN;
DROP TABLE users; 
SELECT * FROM users; -- Fails, table is gone
ROLLBACK;
SELECT * FROM users; -- Works! Table is back.
```

### 2. DML with RETURNING

Instead of doing an `INSERT` and then a `SELECT LAST_INSERT_ID()`, just use `RETURNING`:

```sql
INSERT INTO users (username, email) 
VALUES ('newbie', 'new@test.com') 
RETURNING user_id, created_at;
```

### 3. UPSERT: ON CONFLICT

| Goal | MySQL | PostgreSQL |
|------|-------|------------|
| Ignore duplicate | `INSERT IGNORE` | `ON CONFLICT DO NOTHING` |
| Update on duplicate| `ON DUPLICATE KEY UPDATE` | `ON CONFLICT (...) DO UPDATE SET` |

### 4. DISTINCT ON

Fetch the single latest order for every user:
```sql
SELECT DISTINCT ON (user_id) user_id, amount, order_date
FROM orders
ORDER BY user_id, order_date DESC;
```
*MySQL Equivalent*: Requires a complex subquery or a CTE with `ROW_NUMBER()`.

---

## 🧪 Hands-On Exercises (20 minutes)

### Exercise 1: Transactional DDL Safety

```sql
BEGIN;
-- Let's try to "accidentally" drop the users table
DROP TABLE users CASCADE; 
-- Check if it exists (it shouldn't)
SELECT * FROM users;
-- Oops! Roll it back
ROLLBACK;
-- Verify safety
SELECT COUNT(*) FROM users;
```

### Exercise 2: Master the UPSERT

```sql
-- 1. Try a normal insert that triggers a conflict
-- (john_doe already exists from our init script)
INSERT INTO users (username, email, age) 
VALUES ('john_doe', 'john_new@example.com', 31);
-- ❌ Fails with unique violation

-- 2. Use ON CONFLICT to update instead
INSERT INTO users (username, email, age) 
VALUES ('john_doe', 'john_new@example.com', 31)
ON CONFLICT (username) 
DO UPDATE SET 
    age = EXCLUDED.age,
    email = EXCLUDED.email
RETURNING user_id, username, email, age;
```

### Exercise 3: Grouping & Aggregations

PostgreSQL is strict about `GROUP BY`. You **must** include all non-aggregated columns in the `GROUP BY` clause.

```sql
-- Calculate spend per user status
SELECT 
    u.status, 
    COUNT(o.order_id) as total_orders,
    SUM(o.amount) as total_spend
FROM users u
LEFT JOIN orders o ON u.user_id = o.user_id
GROUP BY u.status
HAVING SUM(o.amount) > 100;
```

---

## 🎤 Interview Question Practice

**Q1**: "Does PostgreSQL support `LOCK TABLES` like MySQL?"

**Answer**: Yes, but it's rarely used. PostgreSQL's MVCC and granular row-level locking make `LOCK TABLES` almost always unnecessary and bad for concurrency. We use `SELECT ... FOR UPDATE` for row locking inside transactions.

**Q2**: "What is the `EXCLUDED` keyword in an `ON CONFLICT` clause?"

**Answer**: `EXCLUDED` is a special table that contains the row values that were proposed for insertion but caused a conflict. It allows you to reference those values in the `DO UPDATE` part.

---

## ✅ Completion Checklist

- [ ] Demonstrate a `ROLLBACK` of an `ALTER TABLE` command
- [ ] Use `RETURNING *` in an `UPDATE` statement
- [ ] Write a `SELECT DISTINCT ON` query
- [ ] Explain why `EXCLUDED` is used in upserts

## 🔗 Next: Increment 00c - Advanced SQL Features
Ready to see common table expressions (CTEs), Window Functions, and arrays?

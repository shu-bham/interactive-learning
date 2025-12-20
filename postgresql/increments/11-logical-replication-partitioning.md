# 🎯 Increment 11: Logical Replication & Partitioning

**Duration**: 60 minutes  
**Difficulty**: ⭐⭐⭐⭐⭐ Expert

## 📋 Quick Summary

PostgreSQL's **Logical Replication** is its answer to MySQL's flexible Row-Based Replication. It allows you to replicate specific tables, even between different major versions. Combined with **Declarative Partitioning**, it forms the backbone of modern large-scale PostgreSQL architectures.

**Key Concepts**:
- **Publication**: The source (Primary) defines what to send.
- **Subscription**: The target (Replica) defines what to receive.
- **Declarative Partitioning**: Range, List, and Hash partitioning (similar to MySQL).
- **Partition Pruning**: The planner skips irrelevant partitions.

---

## 🎓 Theory (25 minutes)

### 1. Logical Replication (Pub/Sub)

Unlike Physical Replication (which moves bytes), Logical Replication moves **changes to individual rows**.

**Why use it?**
- Upgrading from PG 15 to PG 16 with near-zero downtime.
- Replicating from multiple masters into one Data Warehouse.
- Replicating only the `users` table to a specific region for performance.

### 2. Declarative Partitioning

PostgreSQL supports three main types:
- **Range**: `PARTITION BY RANGE (created_at)`
- **List**: `PARTITION BY LIST (country_code)`
- **Hash**: `PARTITION BY HASH (user_id)`

**The Secret Sauce**: **Partition Pruning**. If you query `WHERE country_code = 'US'`, the planner won't even look at the files for 'UK', 'CA', etc.

---

## 🧪 Hands-On Exercises (25 minutes)

### Exercise 1: Setting up a Publication

```sql
-- 1. Create a publication for our users table
CREATE PUBLICATION all_users FOR TABLE users;

-- 2. Verify publication
SELECT * FROM pg_publication;
```

### Exercise 2: Creating a Partitioned Table

```sql
-- 1. Create the parent (partitioned) table
CREATE TABLE measurements (
    id SERIAL,
    measured_at TIMESTAMPTZ NOT NULL,
    value FLOAT
) PARTITION BY RANGE (measured_at);

-- 2. Create partitions
CREATE TABLE measurements_y2024 PARTITION OF measurements
    FOR VALUES FROM ('2024-01-01') TO ('2025-01-01');

CREATE TABLE measurements_y2025 PARTITION OF measurements
    FOR VALUES FROM ('2025-01-01') TO ('2026-01-01');

-- 3. Insert into the parent (PG automatically routes to correct partition)
INSERT INTO measurements (measured_at, value) 
VALUES ('2024-06-15', 23.5), ('2025-02-10', 25.1);
```

### Exercise 3: Verifying Partition Pruning

```sql
-- Use EXPLAIN to see pruning in action
EXPLAIN SELECT * FROM measurements WHERE measured_at = '2024-06-15';
-- Look at the "Append" or "Seq Scan" node - it should only visit measurements_y2024!
```

---

## 🎤 Interview Question Practice

**Q1**: "When should I choose Logical Replication over Physical Streaming Replication?"

**Answer**: Use Logical Replication if:
1. You only need to replicate subset of tables.
2. You are replicating between different major PostgreSQL versions (e.g., for an upgrade).
3. You need to consolidate data from multiple sources into one.
4. You need to perform writes on the subscriber (though this requires care).

**Q2**: "How does partitioning help with performance and maintenance?"

**Answer**: Performance: **Partition Pruning** allows the engine to ignore irrelevant data, speeding up queries. Maintenance: You can drop an entire year of data instantly by doing `DROP TABLE measurements_y2023`, which is much faster and generates zero bloat compared to a massive `DELETE` statement.

---

## ✅ Completion Checklist

- [ ] Explain the difference between Publication and Subscription
- [ ] Create a partitioned table and insert data into it
- [ ] Verify partition pruning using `EXPLAIN`
- [ ] Know how to check if logical replication is lagging (`pg_subscription_rel`)

## 🔗 Next: Increment 12 - Extensions & Advanced Features
Ready to turn PostgreSQL into a GIS database or a search engine? Let's explore the world of **Extensions**.

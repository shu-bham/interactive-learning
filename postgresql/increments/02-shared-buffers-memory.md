# 🎯 Increment 02: Shared Buffers & Memory Management

**Duration**: 50 minutes  
**Difficulty**: ⭐⭐⭐⭐ Deep Dive

## 📋 Quick Summary

PostgreSQL memory management is fundamentally different from MySQL. While InnoDB tries to cache everything in its **Buffer Pool**, PostgreSQL uses a **"Double Buffering"** strategy, relying heavily on the Operating System's Page Cache.

**Key Concepts**:
- **Shared Buffers**: PostgreSQL's internal cache for data pages.
- **Double Buffering**: Data lives in both Shared Buffers AND OS Cache.
- **work_mem**: Memory allocated for each sort/join operation (per-backend).
- **maintenance_work_mem**: Memory for utility tasks (VACUUM, Index builds).

---

## 🎓 Theory (20 minutes)

### 1. Shared Buffers vs InnoDB Buffer Pool

| Feature | MySQL (InnoDB) | PostgreSQL |
|---------|---------------|------------|
| Recommendation | 70-80% of total RAM | 25% of total RAM (typically) |
| Strategy | Direct I/O (often bypasses OS cache) | Buffered I/O (relies on OS cache) |
| Hit Ratio | Critical (>99%) | Important, but OS cache hit also counts |

> [!IMPORTANT]
> **Why only 25% for Shared Buffers?** Because PostgreSQL uses the standard `write()` system call, the OS also caches the same data. If you give 80% to PostgreSQL, you might suffer from "Double Buffering" waste. PostgreSQL designers chose to let the OS handle the filesystem complexity.

### 2. Memory Types in PostgreSQL

1. **Shared Memory** (Global):
   - `shared_buffers`: Data page cache.
   - `wal_buffers`: WAL records before flush.
   - `clog`: Transaction status (Commit Log).

2. **Local Memory** (Per Backend/Process):
   - `work_mem`: Used for `ORDER BY`, `DISTINCT`, `JOIN`. (Can be used multiple times per query!)
   - `maintenance_work_mem`: Used for `CREATE INDEX`, `VACUUM`.
   - `temp_buffers`: Temporary table data.

### 3. The work_mem Trap 🪤

If `work_mem = 64MB` and a query has 4 sorts, it can use **256MB**. If you have 100 connections doing this, you'll hit OOM (Out of Memory). Senior devs monitor `temp_files` to see when `work_mem` is too small.

---

## 🧪 Hands-On Exercises (20 minutes)

### Exercise 1: Inspecting Memory Settings

```sql
-- View global memory settings
SELECT name, setting, unit, context 
FROM pg_settings 
WHERE name IN ('shared_buffers', 'work_mem', 'maintenance_work_mem', 'effective_cache_size');
```

**Note**: `effective_cache_size` is just a "hint" to the planner about how much OS cache is available; it doesn't actually allocate memory.

### Exercise 2: Buffer Cache Hits (pg_buffercache)

PostgreSQL has an extension to see exactly what's in memory.

```sql
-- 1. Enable the extension
CREATE EXTENSION IF NOT EXISTS pg_buffercache;

-- 2. See how much of each table is in Shared Buffers
SELECT 
    c.relname, 
    count(*) AS buffers,
    (count(*) * 8192) / (1024 * 1024) as size_mb
FROM pg_buffercache b
INNER JOIN pg_class c ON b.relfilenode = pg_relation_filenode(c.oid)
AND b.reldatabase IN (0, (SELECT oid FROM pg_database WHERE datname = current_database()))
GROUP BY c.relname
ORDER BY 2 DESC
LIMIT 10;
```

### Exercise 3: Observing work_mem in Action (EXPLAIN)

```sql
-- Set work_mem very low to force a disk transition
SET work_mem = '64kB';

-- Run a sort on a large-ish table
EXPLAIN (ANALYZE, BUFFERS)
SELECT * FROM users ORDER BY email;
```

Look for: `Sort Method: quicksort  Memory: 25kB`. This tells you the sort fit entirely in memory. If the table were larger or `work_mem` smaller, you would see `Sort Method: external merge  Disk: ...`, indicating the sort spilled to disk.

To force the disk spill, insert more rows:

```sql
-- Insert 10,000 rows to ensure we exceed 64kB work_mem
INSERT INTO users (email, name)
SELECT 
    md5(random()::text) || '@example.com',
    'User ' || i
FROM generate_series(10001, 20000) s(i);

-- Re-run the sort
EXPLAIN (ANALYZE, BUFFERS)
SELECT * FROM users ORDER BY email;
```

---

## 🎤 Interview Question Practice

**Q1**: "Why shouldn't I set `shared_buffers` to 80% of my RAM in PostgreSQL like I do in MySQL?"

**Answer**: PostgreSQL relies on the Operating System cache for I/O efficiency. Setting `shared_buffers` too high can cause "Double Buffering" where the same page is cached twice (wasteful) and reduces the memory available for per-connection operations (`work_mem`). 25% is the industry standard starting point.

**Q2**: "A query is logging 'temporary file: path ... size ...'. What does this mean?"

**Answer**: It means a sort or hash operation exceeded the allocated `work_mem` for that backend process and had to spill to disk. This is a performance killer. You should either optimize the query or increase `work_mem` (carefully).

---

## ✅ Completion Checklist

- [ ] Explain the difference between `shared_buffers` and `work_mem`
- [ ] Calculate how much memory a query with 3 joins might use if `work_mem` is 10MB
- [ ] Check which tables are consuming the most space in the internal buffer cache
- [ ] Understand the role of the OS Page Cache in PostgreSQL performance

## 🔗 Next: Increment 03 - WAL (Write-Ahead Log) & Crash Recovery
Ready to see how PostgreSQL ensures your data is never lost, even if someone pulls the plug?

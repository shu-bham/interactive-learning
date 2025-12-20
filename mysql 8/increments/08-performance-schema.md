# 🎯 Increment 8: Performance Schema Deep Dive

**Duration**: 45 minutes  
**Difficulty**: ⭐⭐⭐⭐ Advanced

## 📋 Quick Summary

**What you'll master**: MySQL's built-in performance monitoring system for identifying bottlenecks and optimizing queries.

**Key concepts**: 
- **Performance Schema** = Low-overhead monitoring framework
- **Instrumentation** = What to monitor (statements, waits, locks)
- **Consumers** = Where data is stored
- **sys schema** = Simplified views for common queries

**Why it matters**: 
- **Production debugging** - identify slow queries and bottlenecks
- **Proactive monitoring** - catch issues before they impact users
- **Capacity planning** - understand resource usage patterns
- **Staff expectation** - use data to drive optimization decisions

---

## What You'll Learn

- Enable and configure Performance Schema
- Query statement statistics
- Analyze wait events and bottlenecks
- Use sys schema for quick insights
- Profile query execution

## 🎓 Theory (15 minutes)

### Performance Schema Architecture

```
Instrumentation Points → Performance Schema Tables → Analysis
(What to monitor)        (Where data is stored)     (Queries)
```

**Key Tables**:
- `events_statements_*`: Query execution stats
- `events_waits_*`: Wait events (I/O, locks, etc.)
- `table_io_waits_*`: Table access stats
- `file_*`: File I/O stats

**sys Schema**: Simplified views for common queries

---

## 🧪 Hands-On Exercises (25 minutes)

### Exercise 1: Top Slow Queries (10 min)

```sql
-- Find slowest queries
SELECT 
    DIGEST_TEXT,
    COUNT_STAR AS exec_count,
    ROUND(AVG_TIMER_WAIT / 1000000000, 2) AS avg_ms,
    ROUND(MAX_TIMER_WAIT / 1000000000, 2) AS max_ms,
    ROUND(SUM_TIMER_WAIT / 1000000000, 2) AS total_ms
FROM performance_schema.events_statements_summary_by_digest
ORDER BY SUM_TIMER_WAIT DESC
LIMIT 10;

-- Using sys schema (easier)
SELECT * FROM sys.statement_analysis
LIMIT 10;
```

### Exercise 2: Table Access Patterns (10 min)

```sql
-- Which tables are accessed most?
SELECT 
    OBJECT_SCHEMA,
    OBJECT_NAME,
    COUNT_STAR AS total_ops,
    COUNT_READ,
    COUNT_WRITE,
    COUNT_FETCH,
    COUNT_INSERT,
    COUNT_UPDATE,
    COUNT_DELETE
FROM performance_schema.table_io_waits_summary_by_table
WHERE OBJECT_SCHEMA = 'learning_db'
ORDER BY COUNT_STAR DESC;

-- Index usage statistics
SELECT 
    OBJECT_NAME,
    INDEX_NAME,
    COUNT_STAR,
    COUNT_READ,
    COUNT_FETCH
FROM performance_schema.table_io_waits_summary_by_index_usage
WHERE OBJECT_SCHEMA = 'learning_db'
ORDER BY COUNT_STAR DESC;
```

### Exercise 3: Wait Event Analysis (5 min)

```sql
-- What are we waiting on?
SELECT 
    EVENT_NAME,
    COUNT_STAR,
    ROUND(SUM_TIMER_WAIT / 1000000000, 2) AS total_ms,
    ROUND(AVG_TIMER_WAIT / 1000000000, 2) AS avg_ms
FROM performance_schema.events_waits_summary_global_by_event_name
WHERE COUNT_STAR > 0
ORDER BY SUM_TIMER_WAIT DESC
LIMIT 10;
```

---

## 📝 Key Takeaways

1. **Performance Schema** is essential for production monitoring
2. **sys schema** provides easy-to-use views
3. **Statement analysis** identifies slow queries
4. **Wait events** reveal bottlenecks
5. **Low overhead** - safe for production use

---

## 🎤 Interview Questions

### Q1: How would you identify the slowest query in production?

**Answer**:
```sql
SELECT * FROM sys.statement_analysis
ORDER BY total_latency DESC
LIMIT 1;
```

### Q2: What's the difference between Performance Schema and slow query log?

**Answer**:
- **Performance Schema**: In-memory, real-time, aggregated stats
- **Slow query log**: File-based, individual queries, more overhead
- Use both: Performance Schema for ongoing monitoring, slow query log for detailed analysis

---

## ✅ Completion Checklist

- [ ] Understand Performance Schema architecture
- [ ] Can query statement statistics
- [ ] Know how to use sys schema
- [ ] Can identify bottlenecks with wait events

## 🔗 Next: Increment 9 - Interview Preparation

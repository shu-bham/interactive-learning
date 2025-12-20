# 🎯 Increment 03: WAL (Write-Ahead Log) & Crash Recovery

**Duration**: 50 minutes  
**Difficulty**: ⭐⭐⭐⭐ Deep Dive

## 📋 Quick Summary

How does PostgreSQL guarantee data isn't lost during a crash? The **Write-Ahead Log (WAL)**. It follows a simple rule: "Changes must be written to the log before they are written to the data files."

**Key Concepts**:
- **WAL Files**: The sequence of log files (found in `pg_wal`).
- **LSN (Log Sequence Number)**: A unique pointer to a byte location in the WAL.
- **Checkpointing**: The process of syncing "dirty" memory pages to disk.
- **Full Page Writes**: How PostgreSQL prevents "torn page" corruption after a crash.

---

## 🎓 Theory (20 minutes)

### 1. WAL vs InnoDB Redo Logs

| Feature | MySQL (InnoDB) Redo | PostgreSQL WAL |
|---------|---------------|------------|
| Circularity | Fixed-size circular buffer | Growing/rotating files (segment files) |
| Format | Physical changes | Physical and Logical |
| Use Case | Crash Recovery only | Recovery + Archive + Replication |

> [!TIP]
> In MySQL, the Redo log is a fixed size (e.g., 2 files of 512MB). In PostgreSQL, WAL files are usually 16MB segments that are recycled or archived.

### 2. The Checkpoint Process

When you `UPDATE` a row:
1. The backend process changes the page in **Shared Buffers**.
2. A WAL record is written to **WAL Buffers**.
3. On `COMMIT`, the WAL Buffer is flushed to the **WAL Segment file**.
4. **The Data File is NOT changed yet.** (It's still "dirty" in memory).

**The Checkpoint** eventually comes along:
1. Identifies all dirty pages.
2. Flushes them to the data files on disk.
3. Updates the `pg_control` file to mark a "safe point".

### 3. Crash Recovery: The "Redo" Phase

If the server crashes:
1. PostgreSQL finds the last successful Checkpoint in `pg_control`.
2. It starts reading WAL from that point onwards.
3. It "replays" every change to the data pages.
4. If a page was already on disk, it skips; if not, it applies the change.

---

## 🧪 Hands-On Exercises (20 minutes)

### Exercise 1: Finding the WAL

```bash
# In your terminal
docker exec -it postgresql-primary ls -lh /var/lib/postgresql/data/pg_wal
```
You'll see 16MB files with cryptic names like `000000010000000000000001`.

### Exercise 2: Observing LSN (Log Sequence Number)

LSNs are the "clock" of the database logs.

```sql
-- Get current WAL insert LSN
SELECT pg_current_wal_insert_lsn();

-- Make a change
UPDATE users SET age = age + 1 WHERE user_id = 1;

-- See it move
SELECT pg_current_wal_insert_lsn();

-- Calculate how many bytes of WAL were generated
SELECT pg_wal_lsn_diff(pg_current_wal_insert_lsn(), '0/1000000'); -- (Use your first LSN)
```

### Exercise 3: Inspecting the Control File

The `pg_control` file is the master record of the DB state.

```bash
docker exec -it postgresql-primary pg_controldata /var/lib/postgresql/data
```
**Look for**:
- `Database cluster state`: Should be `in production`.
- `Latest checkpoint location`: The LSN of the last flush.

---

## 🎤 Interview Question Practice

**Q1**: "What are 'Full Page Writes' in PostgreSQL and why are they needed?"

**Answer**: PostgreSQL writes 8KB pages. Operating systems often write in 512B or 4KB blocks. If a crash happens mid-write, a page might be "torn" (half old, half new). Standard WAL can't fix a torn page because it only records *changes*. To prevent this, after every checkpoint, the first time a page is modified, PostgreSQL writes the **entire page** to the WAL. This is called a Full Page Write.

**Q2**: "What happens if my `pg_wal` directory fills up?"

**Answer**: The database will immediately stop and refuse to start (PANIC). This is a critical failure. You must increase disk space or move WAL files. **NEVER** manually delete files in `pg_wal` unless you are a recovery expert, as you will likely corrupt the database.

---

## ✅ Completion Checklist

- [ ] Explain the relationship between `Shared Buffers`, `WAL`, and `Data Files`
- [ ] Understand what triggers a Checkpoint
- [ ] Read the current LSN and calculate WAL volume
- [ ] Explain why the `pg_control` file is so vital

## 🔗 Next: Increment 04 - MVCC Implementation in PostgreSQL
Ready to see why PostgreSQL never deletes data (immediately)? Time to learn about **Bloat** and **Multi-Version Concurrency Control**.

# Increment 03: The Dict (Hashtable) and SkipLists

We've covered strings and optimized sequential structures. Now we move to the "heavy" data structures that power Redis's large-scale performance: **Hashtables** and **SkipLists**.

## 1. The Dict (Hashtable)

Redis uses a hashtable implementation called `dict`. Unlike a standard hash map that might block the thread during a resize, Redis performs **Incremental Rehashing**.

### Why Incremental Rehashing?
If you have 10 million keys and you need to resize the hash map, a full rehash would take several seconds, blocking all client requests.

### How it works:
1. Redis maintains **two** hashtables: `ht[0]` (old) and `ht[ht[0]]` (new).
2. During a resize, every time a client performs a CRUD operation, Redis moves a small bucket of keys from `ht[0]` to `ht[1]`.
3. Redis also uses a timer to move buckets in the background when it's idle.
4. Once `ht[0]` is empty, `ht[1]` becomes the primary table.

> [!IMPORTANT]
> **Tech Jargon Refresher: Load Factor**
> The ratio of the number of elements to the number of buckets ($Load Factor = n/m$). Redis starts rehashing when the load factor exceeds 1 (or 5 if background saves are running to avoid CoW overhead).

---

## 2. SkipLists: Why not Red-Black Trees?

Sorted Sets (ZSETs) in Redis are implemented using two structures: a Hash Table (for O(1) score lookup) and a **SkipList** (for range queries).

### Why SkipLists over Balanced Trees (AVL/Red-Black)?
1. **Concurrency Friendly**: While Redis is single-threaded, SkipLists are generally easier to implement in a lock-free manner for future-proofing.
2. **Range Queries**: SkipLists are naturally optimized for `ZRANGE` operations.
3. **Simplicity**: They are simpler to implement and debug than complex tree balancing logic.
4. **Memory Efficiency**: You can tune the "random level" probability to trade off memory for speed.

---

## 3. Hands-on Exercise: Observing Large Sets

### Step 1: Create a large Sorted Set
Connect to `redis-primary` and seed some data:
```bash
# We'll use a lua script to seed 1000 members efficiently
docker exec -it redis-primary redis-cli "EVAL" "for i=1,1000 do redis.call('ZADD', 'mysortedset', i, 'member'..i) end" 0
```

### Step 2: Check encoding
```redis
OBJECT ENCODING mysortedset
# Answer: "skiplist"
```

### Step 3: The SCAN Command
As a Staff Engineer, you should **never** use `KEYS *` in production. You use `SCAN`.

```redis
# Try a scan with a small count to see the cursor in action
SCAN 0 COUNT 10
```

---

## Your Task
1. Use a large number of `HSET` operations to trigger a conversion from `listpack` to `hashtable`.
2. Research the command `INFO memory` and `INFO stats`. Which field tells you if a rehash is currently in progress?
3. Find out why Redis disables rehashing during an RDB snapshot or AOF rewrite (Hint: It involves the OS kernel and `fork()`).

---

## Solutions & Staff Level Insights

### Task 2: Detecting Rehash
**Field**: Under `INFO stats`, look for `rehash_events`. Under `INFO keyspace`, you can see the number of keys. While there isn't a single "rehash_active" boolean in all versions, checking the size difference between the tables in `DEBUG HT` (if available in your build) or observing latency spikes during large resizes is key.

### Task 3: The Fork/CoW Conflict
**Why disable rehash during background saves?**
When Redis saves to disk (RDB), it calls `fork()`. The OS uses **Copy-on-Write (CoW)**.
- If Redis performs a rehash while the child process is saving, it will modify almost every memory page (moving keys between hash tables).
- This causes the OS to copy almost the entire memory space, potentially doubling Redis's memory usage and causing the system to swap or OOM.
- **Staff Insight**: This is why you should always have `overcommit_memory = 1` and enough swap space when running Redis in production.

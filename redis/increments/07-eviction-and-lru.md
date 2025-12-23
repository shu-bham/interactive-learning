# Increment 07: Memory Eviction (Approximated LRU & LFU)

Every Redis instance has a limit (unless configured otherwise). When that limit (`maxmemory`) is reached, Redis must decide which keys to evict. As a Staff Engineer, you must know that Redis does NOT use a "true" LRU, and for a very good reason.

---

## 1. Why NOT "True" LRU?

In a textbook **Least Recently Used (LRU)** algorithm:
1. You maintain a doubly linked list of all items.
2. Every time an item is accessed, you move it to the head.
3. To evict, you remove the item at the tail.

**The Problem**: In Redis, maintaining this global list for millions of keys would be a nightmare for performance and memory. Moving a node to the head on every single `GET` would require locks or atomic operations that would slow down the core single thread.

---

## 2. Approximated LRU (The Sampling Strategy)

Redis uses an **Approximated LRU** algorithm.
- Every `redisObject` header contains a 24-bit field representing the **LRU Clock** (the last time it was accessed).
- When eviction is needed, Redis **samples** $N$ random keys (default $N=5$).
- It looks at the LRU clocks of those 5 keys and evicts the one that is oldest.

### Staff level Insight:
With $N=5$, the approximation is statistically very close to true LRU, but with zero overhead during normal operations (just a timestamp update). Increasing `maxmemory-samples` improves accuracy at a slight CPU cost.

---

## 3. LFU (Least Frequently Used)

Redis 4.0 introduced **LFU**. This is often better for caches because it accounts for "popularity" rather than just "recency."

- **The Problem**: A key accessed once 1 second ago might not be as valuable as a key accessed 1,000 times yesterday.
- **Implementation**: Redis "recycles" the 24-bit LRU field to store:
    - 8 bits: **Counter** (Logarithmic counter of hits).
    - 16 bits: **Last Decay Time** (So the counter decreases over time if not accessed).

---

## 4. Eviction Policies

- `allkeys-lru`: Evict any key using LRU.
- `volatile-lru`: Evict only keys with an `EXPIRE` set.
- `allkeys-lfu`: Evict based on popularity.
- `noeviction`: Return an error on writes (Standard for pure databases).

---

## Hands-on Exercise: Triggering Eviction

Let's use our `redis-primary` (the standalone one from Module 1/2) for this, as it's easier to observe.

### Step 1: Set a tiny memory limit
```bash
docker exec -it redis-primary redis-cli CONFIG SET maxmemory 10mb
docker exec -it redis-primary redis-cli CONFIG SET maxmemory-policy allkeys-lru
```

### Step 2: Flood it with data
```bash
# We'll write data until we hit the 10MB limit and trigger evictions
docker exec -it redis-primary redis-cli "EVAL" "for i=1,100000 do redis.call('SET', 'evicted_key'..i, string.rep('A', 1000)) end" 0
```
*Note: This might error out once memory is full if policy is noeviction, but with `allkeys-lru` it should keep running.*

### Step 3: Observe Stats
```redis
INFO stats
# Look for: evicted_keys
```

---

## Your Task
1. Run the eviction test and check how many keys were evicted using `INFO stats`.
2. Compare the `evicted_keys` count when using `maxmemory-samples 5` vs `maxmemory-samples 20`. (Warning: High samples increases latency!).
3. Research the "Idle Time" calculation. How does Redis calculate the age of a key with only 24 bits? (Hint: The clock wraps around).

---

## Solutions & Staff Level Insights

### Task 2: Sampling Impact
Increasing samples from 5 to 20 makes the eviction decisions "smarter" (evicting objectively older keys), but it doubles the CPU time spent in the eviction loop. For most workloads, 5 is the "sweet spot."

### Task 3: The 24-bit Clock
- A 24-bit clock at 1-second resolution wraps around every **~194 days**.
- Redis handles the "wrap-around" by calculating the difference between the current global clock and the key's clock, assuming if the current clock is smaller, a wrap-around occurred.
- **Staff Insight**: This is why Redis doesn't need 64-bit timestamps for every key—it trades off extreme precision for massive memory savings.

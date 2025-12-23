# Increment 00: Basic Redis Commands Refresher

Before we peel back the layers and look at the C source code and memory layouts, let's ensure we are aligned on the core vocabulary of Redis. Even as a Senior Developer, a quick refresher on the nuances of these commands is valuable.

## 1. Strings (The Foundation)
The most basic type. A string can store text, integers, or binary data (up to 512MB).

- `SET key value [EX seconds]`: Set value with optional expiration.
- `GET key`: Retrieve value.
- `INCR key` / `DECR key`: Atomic increment/decrement (useful for rate limiting/counters).
- `MSET` / `MGET`: Atomic multi-set/multi-get (reduces network round-trips).

> [!TIP]
> **Staff Level Tip**: Use `SET KEY VALUE NX` (Not eXists) or `XX` (eXists) for lightweight distributed locks or conditional updates.

---

## 2. Lists (Linked Lists/Listpacks)
Ordered collections of strings.

- `LPUSH` / `RPUSH`: Add to head/tail.
- `LPOP` / `RPOP`: Remove from head/tail.
- `LRANGE key start stop`: Get a range of elements.
- `BLPOP` / `BRPOP`: **Blocking** pops. Essential for implementing simple message queues.

---

## 3. Sets (Unordered Collections)
Unique, unordered strings.

- `SADD key member`: Add member.
- `SISMEMBER key member`: Check existence in $O(1)$.
- `SINTER` / `SUNION` / `SDIFF`: Set operations (Intersection, Union, Difference).

---

## 4. Hashes (Fields & Values)
Ideal for representing "Objects" (e.g., a User profile).

- `HSET key field value`: Set a field.
- `HGET key field`: Get a field.
- `HGETALL key`: Get everything (Be careful with huge hashes!).
- `HINCRBY key field increment`: Atomic field increment.

---

## 5. Sorted Sets (ZSETs)
Every member is associated with a **Score**. Members are ordered by score.

- `ZADD key score member`: Add with score.
- `ZRANGE key start stop [WITHSCORES]`: Get range by index.
- `ZRANK key member`: Get position of a member.
- `ZREVRANGE`: Get range in reverse order (high to low).

---

## Hands-on Refresher

### Step 1: Atomic Counters
```redis
SET page_views 100
INCR page_views
GET page_views
# Result: 101
```

### Step 2: Modeling a User Object
```redis
HSET user:1001 name "John" age 30 email "john@example.com"
HGETALL user:1001
```

### Step 3: Leaderboard (Sorted Set)
```redis
ZADD highscores 500 "player1" 800 "player2" 650 "player3"
ZREVRANGE highscores 0 2 WITHSCORES
# Result: player2 (800), player3 (650), player1 (500)
```

---

## Your Task
1. Look up the `EXPIRE` and `TTL` commands. How would you set a key to expire in 60 seconds and then check how much time is left?
2. What is the difference between `DEL` and `UNLINK`? (Important for large keys!).
3. Try to use `LPUSH` and `LTRIM` together to maintain a "capped list" of only the last 5 elements.

---

## Solutions & Staff Level Insights

### Task 1: Expiration
- `EXPIRE mykey 60`
- `TTL mykey` (Returns seconds remaining, -2 if key doesn't exist, -1 if no timeout).

### Task 2: `DEL` vs `UNLINK`
- `DEL` is synchronous and blocking. If you delete a 1GB hash, Redis will hang until the memory is freed.
- `UNLINK` is **non-blocking**. It removes the key from the keyspace instantly but reclaims the memory in a background thread.
- **Staff Level**: Always use `UNLINK` for large collections to avoid blocking the single-threaded event loop.

### Task 3: Capped Lists
```redis
LPUSH mylist "new_item"
LTRIM mylist 0 4
```
This ensures the list never grows beyond 5 elements. Efficient for "recent notifications" or "last 5 logins".

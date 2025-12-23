# Increment 10: Client-Side Caching (Tracking & Invalidation)

In many high-scale architectures, even a sub-millisecond network round-trip to Redis is too much. For extremely hot keys, we want to cache data **inside the application memory**. However, the hardest problem in computer science is **Cache Invalidation**.

Redis 6.0 solved this with a feature called **Client-Side Caching**.

---

## 1. The Challenge of Invalidation

If your App (Client A) caches a value `user:1` in its local RAM, and another App (Client B) updates `user:1` in Redis, Client A's local cache is now "stale" (dirty).

---

## 2. How Redis 6.0 Tracking Works

Redis maintains a "Tracking Table" (using a globally limited pool of memory). When a client has tracking enabled:
1. Client A sends `GET user:1`.
2. Redis returns the value AND remembers that Client A is interested in `user:1`.
3. If any other client changes `user:1`, Redis sends an **invalidating message** to Client A.
4. Client A receives the message and purges its local cache.

### Staff Insight: The Tracking Table Size
The Tracking Table is stored in the `Dict` we learned about in Module 1. If it gets too large, Redis will evict tracking entries (sending invalidations to clients) to protect its own memory.

---

## 3. Two Modes: Default vs. BCAST

### Default Mode (Standard)
- Redis remembers the keys you've read.
- **Pro**: Efficient communication.
- **Con**: Redis uses more memory to track millions of specific keys per client.

### Broadcasting Mode (BCAST)
- The client registers a **prefix** (e.g., `user:*`).
- Redis doesn't track specific keys. It just sends an invalidation if *anything* matching that prefix changes.
- **Pro**: Redis uses zero extra memory to track keys.
- **Con**: Clients might get "noisy" invalidations for keys they didn't actually cache.

---

## 4. Hands-on Exercise: Simulating Invalidation

We need two connections for this.

### Step 1: Enable Tracking on Connection 1
```bash
docker exec -it redis-primary redis-cli
```
Inside the CLI:
```redis
# Put the connection in RESP3 mode (required for push messages in the same connection)
HELLO 3
# Enable tracking
CLIENT TRACKING on
# Read a key to start tracking it
GET my-hot-key
```

### Step 2: Update from Connection 2
Open a second terminal:
```bash
docker exec -it redis-primary redis-cli SET my-hot-key "updated-value"
```

### Step 3: Observe Invalidation
Go back to Terminal 1. You will see a push message:
`->32 [invalidate] ["my-hot-key"]`

---

## Your Task
1. Research the `CLIENT TRACKING` parameter `BCAST`. How would you track all keys starting with `app1:`?
2. What happens if a client disconnects? Does Redis keep tracking it?
3. **Staff Level**: Why is Client-Side Caching often preferred over a standard TTL-based local cache (like Guava or LRU Cache in Java/Go)?

---

## Solutions & Staff Level Insights

### Task 1: BCAST mode
Command: `CLIENT TRACKING on BCAST PREFIX app1:`
This is much more scalable for Redis when you have thousands of clients.

### Task 2: Disconnection
The moment a client disconnects, Redis wipes its tracking entries for that client. Tracking is **stateful** to the connection.

### Task 3: Invalidation vs. TTL
- **TTL Cache**: You might serve stale data for the duration of the TTL (e.g., 60 seconds).
- **Client-Side Caching**: You get **near-instant** invalidation. This allows you to have a "permanent" local cache that only updates when necessary, drastically reducing Redis load without sacrificing consistency.

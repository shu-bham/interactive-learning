# Increment 01: Core Architecture & SDS

Welcome to the first module of your Redis Internals journey. As a Staff-level candidate, you need to understand not just that Redis is fast, but *why* it is fast and what memory trade-offs it makes.

## 1. The Reactor Pattern (Why Single-Threaded?)

Redis is often called "single-threaded," but that's a half-truth (especially since version 6.0). However, the core execution of commands is strictly single-threaded.

### How it works:
Redis uses the **Reactor Pattern**. It has a single-threaded event loop that handles file events (network sockets) and time events (expiration, background tasks).

> [!NOTE]
> **Tech Jargon Refresher: Reactor Pattern**
> A design pattern for synchronous event demultiplexing. One thread manages many concurrent connections by waiting for "readiness" events (EPOLL/KQUEUE) and dispatching them to handlers.

### Why not multi-threaded for everything?
1. **CPU is not the bottleneck**: Redis is usually bound by memory or network.
2. **Simplicity**: No locks, mutexes, or race conditions. This makes the code extremely fast and maintainable.
3. **Context Switching**: Avoiding the overhead of switching thousands of threads.

---

## 2. Simple Dynamic Strings (SDS)

Redis does NOT use standard C strings (`char*`). It uses its own implementation called **SDS**.

### Why SDS?
In C, a string is a null-terminated array. To find its length, you must traverse it (`O(N)`).
In Redis, an SDS looks like this:

```c
struct sdshdr {
    int len;     // Number of bytes currently used
    int free;    // Number of unused bytes
    char buf[];  // The actual data
};
```

### Key Advantages for Staff Scaling:
1. **O(1) Length**: Constant time `STRLEN`.
2. **Binary Safe**: Can store images or serialized data because it doesn't rely on `\0` to find the end.
3. **Reduced Reallocations**: SDS uses **Pre-allocation** and **Lazy Freeing** to minimize `malloc()` calls.

---

## 3. Hands-on Exercise: Inspecting Memory

Let's start the Redis cluster and see how Redis handles memory for different string sizes.

### Step 1: Start Redis
Run the following command in your terminal:
```bash
docker-compose -f redis/docker-compose.yml up -d
```

### Step 2: Connect via CLI
```bash
docker exec -it redis-primary redis-cli
```

### Step 3: Observe Memory Efficiency
In `redis-cli`, try these commands:

```redis
# Setting a small string
SET mykey "hello"
OBJECT ENCODING mykey
# Answer: "embstr" (Embedded string - stored with the redisObject header to save a malloc)

# Setting a large string (>44 bytes in v7)
SET mybigkey "this is a much longer string that will definitely exceed the embstr limit"
OBJECT ENCODING mybigkey
# Answer: "raw" (Stored separately from the header)
```

> [!IMPORTANT]
> **Staff Insight**: Redis optimizes "embstr" to be cache-line friendly. If the string is small enough, it fits in the same allocation as the metadata header, reducing pointer chasing.

---

## Your Task
1. Spin up the Docker containers.
2. Use `OBJECT ENCODING` to find the threshold where a string changes from `embstr` to `raw`.
3. Inform me once you've completed this and are ready for the next deep dive (Linked Lists & ZipLists).

---

## Solutions & Staff Level Insights

### Task 1: The `embstr` vs `raw` Threshold
**Question**: What is the threshold for a string changing from `embstr` to `raw`?

**Solution**:
- In Redis 7.2, the threshold is **44 bytes**.
- If the string length is `<= 44`, it is encoded as `embstr`.
- If the string length is `> 44`, it is encoded as `raw`.

**Staff Level Why?**:
Redis uses a `redisObject` header which is 16 bytes. An SDS header for small strings is 3 bytes (v7). The metadata + string data must fit into a single 64-byte allocation (a common CPU cache line size).
$16 (header) + 3 (sds) + 44 (data) + 1 (null terminator) = 64 bytes$.
By keeping it at 64 bytes, Redis ensures the entire object is fetched in a single CPU cache load, avoiding a secondary pointer dereference.

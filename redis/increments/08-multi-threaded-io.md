# Increment 08: Multi-threaded IO (Redis 6+)

For years, the "Redis is single-threaded" mantra was absolute. However, as network speeds moved from 1Gbps to 10Gbps and 100Gbps, the single thread became a bottleneck—not because of CPU, but because of **Network IO**.

---

## 1. The Bottleneck: Read/Write syscalls

In the old model:
1. The single thread reads from a socket.
2. Parsed the request.
3. Executed the command.
4. Serialized the response.
5. Wrote back to the socket.

**The Staff Insight**: Steps 1, 2, 4, and 5 are "boring" work that involves a lot of CPU time in system calls and memory copying. Only Step 3 (Execution) actually needs the thread-safety of a single thread.

---

## 2. The Redis 6 Model: Threaded IO

Redis 6.0 introduced **Threaded IO**. It offloaded the reading and writing to background threads while keeping the command execution single-threaded.

### How it works:
- **Main Thread**: Handles the event loop and **executes all commands**.
- **IO Threads**: Handle the network serialization, parsing (optional), and writing the response to the socket.

> [!IMPORTANT]
> **Tech Jargon Refresher: Lock-free Execution**
> Because the background threads only handle the "wrapping" of data and not the data structures themselves (the Dict, SkipList, etc.), the main thread can still operate without any heavyweight locks or mutexes.

---

## 3. Configuration & Optimization

Multi-threading is **OFF** by default. To enable it, you modify `redis.conf`:

```redis
# Setting the number of threads (usually # of Cores / 2)
io-threads 4

# By default, threads only handle writes. 
# Enable this to handle reads as well (useful for high-bandwidth ingestion).
io-threads-do-reads yes
```

### When to use Multi-threading?
- **Staff Rule of Thumb**: Don't enable it unless you are actually hitting a bottleneck. If your `INFO stats` shows high `instantaneous_ops_per_sec` but low CPU usage, you probably don't need it.
- **Cost**: Enabling threads increases context switching and memory overhead.

---

## 4. Hands-on Exercise: Simulation

### Step 1: Enable Threads
On your `redis-primary`:
```bash
docker exec -it redis-primary redis-cli CONFIG SET io-threads 4
# Note: Some versions require a restart to change io-threads. Check the error msg.
```

### Step 2: High Throughput Test
Use the `redis-benchmark` tool (included in the image) to see the difference.
```bash
# Test without threads (default)
docker exec -it redis-primary redis-benchmark -t set,get -n 100000 -q

# Watch the CPU usage of the container
docker stats redis-primary
```

---

## Your Task
1. Look at the `INFO` output. Is there a field that specifically tells you the number of active IO threads?
2. Research: Does Redis use multi-threading for the `DEL` command? (Hint: Module 0 refresher on `UNLINK`).
3. **Staff Challenge**: If you have a cluster of 10 nodes, would it be better to have 10 nodes with 1 IO Thread each, or 5 nodes with 4 IO Threads each? Why?

---

## Solutions & Staff Level Insights

### Task 2: Background Deletion
Yes! Even before Redis 6, Redis used "worker threads" for **Bio** (Background IO) operations:
- `UNLINK` (Lazy free).
- `AOF` fsyncs.
- `RDB` closing files.
This is separate from "Threaded IO" which focuses on network pipes.

### Task 3: Sharding vs Threads
**Staff Solution**: Usually, 10 nodes with 1 thread is better.
- Sharding (more nodes) increases **Total Memory Capacity** and provides better **Fault Tolerance**.
- Adding threads only increases **Throughput per Node**.
High-scale architectures (like those at Twitter/AWS) prefer horizontal sharding over vertical threading until the overhead of managing too many nodes becomes the primary constraint.

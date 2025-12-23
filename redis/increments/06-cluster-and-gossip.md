# Increment 06: Redis Cluster & Gossip Protocol

When a single Redis node (or a Primary-Replica pair) is no longer enough to handle your traffic or dataset size, you move to **Redis Cluster**. This is where horizontal scaling happens.

---

## 1. The Sharding Model: Hash Slots

Unlike many other distributed systems that use consistent hashing, Redis Cluster uses **Hash Slots**.

- There are fixed **16,384** (2^14) hash slots.
- Every key is mapped to a slot using the formula: `HASH_SLOT = CRC16(key) mod 16384`.
- These slots are distributed among the nodes in the cluster.

### Staff Insight: Why 16,384?
It's a balance between bitmap size and cluster scale. In the Gossip protocol, nodes exchange which slots they own. A heartbeat packet for 16k slots is roughly 2KB. If it were 65k slots, the heartbeat packets would be too large, causing network congestion in large clusters.

---

## 2. Gossip Protocol: Node-to-Node Communication

Redis Cluster does not use a central coordinator (like Zookeeper). It is a **Peer-to-Peer** system.

Nodes communicate using the **Gossip Protocol** to:
1. **Failure Detection**: If a node can't reach another node, it marks it as `PFAIL` (Possible Failure). If enough nodes agree, it becomes `FAIL`.
2. **Configuration Updates**: Sharing which node owns which hash slots.
3. **Cluster State**: Ensuring every node knows the current topography.

---

## 3. Client Redirection: MOVED vs. ASK

As a Staff Engineer, you must understand how clients interact with a cluster. The cluster does not "proxy" requests.

- **MOVED**: The node says, "I don't have this slot, go to Node X permanently." The client updates its local slot-to-node map.
- **ASK**: The node says, "I'm currently migrating this slot; for this specific request, go to Node X, but don't update your map yet."

---

## 4. Hash Tags (Forcing Keys to the same slot)

Sometimes you need multiple keys to reside on the same node (e.g., for multi-key operations or transactions). You use **Hash Tags**.
- Redis only hashes the content inside `{}`.
- `SET {user:100}:profile "..."` and `SET {user:100}:settings "..."` will always land on the same hash slot and thus the same node.

---

## Hands-on Exercise: Building your 6-Node Cluster

To truly understand how clusters work, you need to build one. We will set up a cluster with 3 Master nodes and 3 Replicas.

### Step 1: Start the Nodes
Navigate to the `redis/cluster` directory and start the containers:
```bash
cd redis/cluster
docker-compose up -d
```

### Step 2: Initialize the Cluster
Once the containers are running, they are just 6 standalone nodes. We need to tell them to form a cluster. Run this command:

```bash
docker exec -it redis-node-1 redis-cli --cluster create \
173.20.0.11:6379 173.20.0.12:6379 173.20.0.13:6379 \
173.20.0.14:6379 173.20.0.15:6379 173.20.0.16:6379 \
--cluster-replicas 1 --cluster-yes
```

> [!NOTE]
> **What just happened?**
> The `--cluster-replicas 1` flag tells Redis to assign 1 replica for every master. Since we provided 6 IPs, Redis will create 3 Masters and 3 Replicas automatically.

### Step 3: Verify the Topography
Check which node owns which slots:
```bash
docker exec -it redis-node-1 redis-cli cluster nodes
```

### Step 4: Testing Redirection (MOVED)
Try to set a key using a regular client (not cluster-aware):
```bash
docker exec -it redis-node-1 redis-cli set mykey "hello"
```
If `mykey` doesn't hash to a slot owned by `node-1`, you will see a `(error) MOVED ...` response.

Now try with the cluster-aware flag `-c`:
```bash
docker exec -it redis-node-1 redis-cli -c set mykey "hello"
```
Redis-cli will automatically follow the redirection and perform the operation on the correct node.

### Step 5: Manual Failover Experiment
As a Staff Engineer, you need to know how the cluster recovers.
1. Identify a Master and its Replica:
```bash
docker exec -it redis-node-1 redis-cli cluster nodes
```
2. "Kill" a Master node:
```bash
docker stop redis-node-1
```
3. Watch the logs/status of the remaining nodes:
```bash
docker exec -it redis-node-2 redis-cli cluster nodes
```
You will see `node-1` marked as `fail` and its replica (e.g., `node-4`) promoted to `master`.

4. Bring `node-1` back online:
```bash
docker start redis-node-1
docker exec -it redis-node-1 redis-cli cluster nodes
```
`node-1` will rejoin as a **replica** of the new master.

### Step 6: Hash Tag Experiment
Verify that you can force keys onto the same node:
```bash
# These keys will have different CRC16 hashes
docker exec -it redis-node-1 redis-cli -c set user:1:name "John"
docker exec -it redis-node-1 redis-cli -c set user:1:age "30"

# These keys will have the EXACT same hash slot because of the {tag}
docker exec -it redis-node-1 redis-cli -c set {user:1}:name "John"
docker exec -it redis-node-1 redis-cli -c set {user:1}:age "30"

# Verify they are on the same node
# First, get the slot number
SLOT=$(docker exec -it redis-node-1 redis-cli cluster keyslot {user:1} | tr -d '\r')
# Then, get the keys in that slot (on the node that owns it)
docker exec -it redis-node-1 redis-cli -c cluster getkeysinslot $SLOT 10
```

### Step 7: Resharding (Moving Slots)
Moving slots between nodes is how you scale out.
```bash
# This starts an interactive resharding process
docker exec -it redis-node-1 redis-cli --cluster reshard 173.20.0.11:6379
```
*Note: You don't have to complete the resharding now, but observe the prompts: How many slots? Who is the source? Who is the target?*

---

## Your Task
1. Calculate the Hash Slot for the key `user:123` and `{user:123}:metadata`. Will they land on the same node?
2. What happens to the cluster if a Primary node fails and there is no Replica? (Does the whole cluster stay up?).
3. Research `cluster-node-timeout`. What is the trade-off of setting this too low or too high?

---

## Solutions & Staff Level Insights

### Task 1: Hash Tags
Yes, they will land on the same node because Redis only hashes what is inside the curly braces `{}`. If curly braces are present, it only processes `user:123`.

### Task 2: Cluster Integrity
By default, if any part of the 16,384 slots is not covered by a healthy node, the **entire cluster** stops accepting writes (`cluster-require-full-coverage yes`).
- **Staff Level**: For many production systems, we set this to `no` so that partial outages don't take down the entire global keyspace.

### Task 3: Cluster Node Timeout
- **Too Low**: Risk of "flapping" and false failure detections during minor network blips.
- **Too High**: Long detection times (e.g., 15 seconds) where clients might be trying to reach a dead node, causing latency spikes.

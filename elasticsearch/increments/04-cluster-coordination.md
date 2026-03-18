# Increment 04: Cluster Coordination & Master Nodes

How do distributed nodes agree on cluster state? How is split-brain prevented? This module covers ES's consensus and coordination layer.

---

## 1. Node Roles

ES nodes can have different roles:

| Role | Config | Purpose |
|------|--------|---------|
| Master-eligible | `node.master: true` | Can be elected cluster master |
| Data | `node.data: true` | Stores shards, handles CRUD |
| Ingest | `node.ingest: true` | Pre-processes documents (pipelines) |
| Coordinating-only | all false | Routes requests, aggregates results |
| ML | `node.ml: true` | Machine learning jobs |

```yaml
# Example: dedicated master node (no data)
node.master: true
node.data: false
node.ingest: false
```

> [!IMPORTANT]
> **Staff Insight**: In production clusters (>5 nodes), use **dedicated master nodes**. At least 3 master-eligible nodes for quorum. They should be small VMs (2 CPU, 4GB RAM) but with fast, stable networking. Data nodes handle the heavy lifting.

---

## 2. Cluster State

The **cluster state** is the source of truth for:
- Which indices exist
- Mappings and settings for each index
- Which nodes are in the cluster
- Shard allocation (which shard is on which node)

The **elected master** manages cluster state:
1. Receives changes (create index, add node, etc.)
2. Updates cluster state
3. Publishes to all nodes

```
Master Node                     Data Nodes
    │                           ┌─────────┐
    │  Cluster state update     │ Node 2  │
    ├──────────────────────────►│         │
    │                           └─────────┘
    │                           ┌─────────┐
    │                           │ Node 3  │
    ├──────────────────────────►│         │
    │                           └─────────┘
    │                           ┌─────────┐
    │                           │ Node 4  │
    └──────────────────────────►│         │
                                └─────────┘
```

> [!WARNING]
> **Staff Insight**: Large cluster states (many indices, many shards) can cause slow propagation and master instability. Avoid having thousands of tiny indices — use time-based rollover instead.

---

## 3. Master Election (ES 7+ Coordination Layer)

ES 7.0 replaced Zen Discovery with a new coordination subsystem based on a **Raft-like consensus** algorithm.

### How it works:

1. **Initial bootstrapping**: First-ever cluster start uses `cluster.initial_master_nodes`
2. **Leader election**: Master-eligible nodes vote; majority wins
3. **Heartbeats**: Nodes ping the master; master pings all nodes
4. **Failure detection**: If master is unreachable, new election occurs

### Key configs:

```yaml
# Required for first-time cluster bootstrap (ES 7+)
cluster.initial_master_nodes: ["node-1", "node-2", "node-3"]

# Fault detection timeouts
cluster.fault_detection.leader_check.interval: 1s
cluster.fault_detection.leader_check.timeout: 10s
cluster.fault_detection.follower_check.interval: 1s
cluster.fault_detection.follower_check.timeout: 10s
```

---

## 4. Split-Brain Prevention

**Split-brain**: When network partition causes two groups of nodes to each elect their own master, leading to divergent cluster states.

### Old way (ES <7): `minimum_master_nodes`
```yaml
# Deprecated in ES 7+
discovery.zen.minimum_master_nodes: 2
```
You had to manually calculate: `(master_eligible_nodes / 2) + 1`

### New way (ES 7+): Automatic quorum
ES 7+ handles this automatically:
- The voting configuration tracks which nodes can vote
- Quorum is automatically maintained
- No manual `minimum_master_nodes` calculation

> [!NOTE]
> **Staff Insight**: With 3 master-eligible nodes, you can lose 1 and still maintain quorum. With 2 nodes, you cannot safely tolerate any failure (no majority possible). **Always use an odd number of master-eligible nodes (3 or 5)**.

---

## 5. Cluster Health

```bash
GET /_cluster/health
```

| Status | Meaning |
|--------|---------|
| 🟢 Green | All primary and replica shards allocated |
| 🟡 Yellow | All primaries allocated, but some replicas are not |
| 🔴 Red | Some primary shards are unallocated |

Common causes of non-green:
- **Yellow**: Not enough nodes for replica placement (e.g., 1 node with 1 replica configured)
- **Red**: Node containing a primary shard is down, no replica was available

---

## 6. Hands-on: Cluster Internals

### Step 1: Check cluster health and state
```bash
# Health overview
curl -X GET "http://localhost:9200/_cluster/health?pretty"

# Detailed cluster state (warning: can be large)
curl -X GET "http://localhost:9200/_cluster/state?pretty" | head -100

# Just the master
curl -X GET "http://localhost:9200/_cat/master?v"
```

### Step 2: See node roles
```bash
curl -X GET "http://localhost:9200/_cat/nodes?v&h=name,node.role,master"
```

The `node.role` column shows:
- `m` = master-eligible
- `d` = data
- `i` = ingest
- `*` in master column = current master

### Step 3: Simulate master failure
```bash
# Find current master
MASTER=$(curl -s "http://localhost:9200/_cat/master?h=node")
echo "Current master: $MASTER"

# Stop the master node
docker stop $MASTER

# Wait and check new master
sleep 15
curl -X GET "http://localhost:9200/_cat/master?v"

# Bring it back
docker start $MASTER
sleep 10
curl -X GET "http://localhost:9200/_cat/nodes?v&h=name,node.role,master"
```

### Step 4: Watch cluster state changes
```bash
# Get cluster state version
curl -s "http://localhost:9200/_cluster/state?filter_path=version" | jq

# Create an index (triggers cluster state change)
curl -X PUT "http://localhost:9200/test-state"

# Check version again — it increased
curl -s "http://localhost:9200/_cluster/state?filter_path=version" | jq
```

### Step 5: Pending tasks (cluster-level queue)
```bash
curl -X GET "http://localhost:9200/_cluster/pending_tasks?pretty"
```

Under high load, you might see tasks queueing here.

---

## 7. Scaling the Control Plane

| Cluster Size | Master-Eligible Nodes | Recommendation |
|--------------|----------------------|----------------|
| 1-3 nodes | All can be master-eligible | Simple setup |
| 4-10 nodes | 3 dedicated masters | Start separating roles |
| 10+ nodes | 3-5 dedicated masters | Definitely separate |
| 50+ nodes | 5 dedicated masters | Consider region awareness |

> [!TIP]
> **Staff Insight**: Master nodes don't need much heap (4-8GB is usually enough). What they need is **stable, low-latency networking**. Put them in the same availability zone or use dedicated network paths.

---

## 8. Debugging Cluster Issues

### Common issues and commands:

```bash
# Why is my shard unassigned?
curl -X GET "http://localhost:9200/_cluster/allocation/explain?pretty"

# Hot threads (what's consuming CPU)
curl -X GET "http://localhost:9200/_nodes/hot_threads"

# Pending tasks building up?
curl -X GET "http://localhost:9200/_cluster/pending_tasks?pretty"

# Task queue stats
curl -X GET "http://localhost:9200/_cat/thread_pool?v&h=node_name,name,active,rejected,completed"
```

---

## Your Task

1. **Master failover timing**: Stop the master node. Measure how long until a new master is elected. What configs affect this?

2. **Two-node problem**: Start only 2 nodes from your docker-compose. Stop 1. Can the remaining node elect itself as master? Why or why not?

3. **Cluster state size**: Create 100 indices with 1 shard each. Check the cluster state size. Now delete them. Does the cluster state shrink?

---

## Solutions & Staff Level Insights

### Task 1: Failover timing
Default failover takes ~10-30 seconds depending on:
- `cluster.fault_detection.leader_check.timeout` (how long to wait before declaring master dead)
- `cluster.fault_detection.leader_check.retry_count`

Lower values = faster failover but more false positives.

### Task 2: Two-node quorum
With 2 master-eligible nodes, quorum = 2. If 1 dies, the survivor cannot form a quorum alone. The cluster goes into a waiting state until the other node returns.

**Lesson**: 2 master-eligible nodes is worse than 1 (single node at least works standalone). Always use 1 or 3+.

### Task 3: Cluster state size
Creating indices increases cluster state. Deleting them **should** shrink it, but ES keeps some tombstones temporarily. The cluster state is stored in memory on all nodes — this is why "many small indices" is an anti-pattern.

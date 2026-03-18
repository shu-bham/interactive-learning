# Increment 00: Mental Model Shift — RDBMS to Search Engine

As a backend engineer fluent in MySQL/PostgreSQL, your instincts are tuned for ACID transactions and normalized schemas. Elasticsearch requires you to **unlearn** some of those instincts.

---

## 1. Storage Engine vs Search Engine

| Aspect | PostgreSQL/MySQL | Elasticsearch |
|--------|-----------------|---------------|
| Primary goal | **Store** data reliably | **Find** data quickly |
| Data model | Normalized tables, foreign keys | Denormalized JSON documents |
| Consistency | Strong (ACID) | Eventual (by default) |
| Schema | Strict, predefined | Dynamic, but dangerous |
| Indexing | B-tree (secondary) | Inverted index (primary) |
| Scaling | Vertical first, read replicas | Horizontal sharding built-in |

> [!IMPORTANT]
> **Mental Shift #1**: In an RDBMS, you normalize to avoid data duplication. In ES, you **denormalize aggressively** because joins are expensive (and often impossible across shards).

---

## 2. Write-Once Segments vs Mutable B-Trees

In PostgreSQL, when you `UPDATE` a row, the database modifies pages in place (with MVCC for versioning). 

In Elasticsearch (built on Lucene):
- Documents are written to **immutable segments**
- An "update" is really a **delete + insert** (the old doc is marked deleted, a new segment gets the new version)
- Deleted documents consume space until a **segment merge** reclaims them

```
Write Flow:
┌─────────────┐     ┌─────────────┐     ┌─────────────┐
│  In-Memory  │ ──► │  Segment 1  │     │  Segment 2  │
│   Buffer    │     │ (immutable) │     │ (immutable) │
└─────────────┘     └─────────────┘     └─────────────┘
                           │                   │
                           └───────┬───────────┘
                                   ▼
                           ┌─────────────┐
                           │  Merged     │
                           │  Segment    │
                           └─────────────┘
```

> [!NOTE]
> **Staff Insight**: This immutability is why ES excels at append-heavy workloads (logs, events) but struggles with high-frequency updates to the same document. Sound familiar? It's similar to how LSM-trees work in RocksDB.

---

## 3. Eventual Consistency is the Default

When you index a document in Elasticsearch, it's **not immediately searchable**.

```
You ──► Primary Shard ──► Replica Shards
              │
              ▼
        In-Memory Buffer (not searchable yet)
              │
              ▼ (after refresh_interval, default 1s)
        Searchable Segment
```

This means:
- `POST /products/_doc` returns `201 Created`
- `GET /products/_search?q=...` might NOT find it for up to 1 second

> [!WARNING]
> **Staff Insight**: If you need read-your-writes consistency, you can use `?refresh=wait_for` — but this kills throughput. In high-volume indexing, **never** use this.

---

## 4. No Transactions, No Joins

Unlike PostgreSQL, Elasticsearch has:
- **No multi-document transactions** — you cannot atomically update two documents
- **No JOINs** — there's no `LEFT JOIN` across indices

### How do you model relationships then?

| RDBMS Pattern | ES Equivalent |
|---------------|---------------|
| Foreign key | Denormalize (embed the data) |
| Many-to-many | Application-side join or parent-child |
| Normalized tables | Flatten into single document |

**Example**: Instead of `orders` and `order_items` tables:

```json
// Single denormalized document
{
  "order_id": 123,
  "customer_name": "Alice",
  "items": [
    { "product": "Laptop", "qty": 1, "price": 999 },
    { "product": "Mouse", "qty": 2, "price": 25 }
  ],
  "total": 1049
}
```

---

## 5. Hands-on: Start Your Cluster

### Step 1: Start the 3-node cluster
```bash
cd elasticsearch
docker-compose up -d
```

Wait ~30 seconds for the cluster to form, then verify:
```bash
curl -s http://localhost:9200/_cluster/health?pretty
```

You should see:
```json
{
  "cluster_name": "es-learning-cluster",
  "status": "green",
  "number_of_nodes": 3,
  ...
}
```

### Step 2: Index your first document
```bash
# Create an index and add a document
curl -X POST "http://localhost:9200/products/_doc/1?pretty" \
  -H "Content-Type: application/json" \
  -d '{"name": "Laptop", "price": 999, "category": "electronics"}'
```

### Step 3: Experience eventual consistency
```bash
# Immediately search (might not find it)
curl -s "http://localhost:9200/products/_search?q=laptop" | jq '.hits.total.value'

# Wait 1 second, then search again
sleep 1
curl -s "http://localhost:9200/products/_search?q=laptop" | jq '.hits.total.value'
```

### Step 4: Force refresh (understand the cost)
```bash
# Index with immediate refresh
curl -X POST "http://localhost:9200/products/_doc/2?refresh=true&pretty" \
  -H "Content-Type: application/json" \
  -d '{"name": "Phone", "price": 699, "category": "electronics"}'

# Now it's immediately searchable
curl -s "http://localhost:9200/products/_search?q=phone" | jq '.hits.total.value'
```

---

## Your Task

1. **Denormalization exercise**: Think about your current project's `users` and `orders` tables. How would you model them in ES for a "search user's recent orders" use case?

2. **Consistency test**: Index 100 documents in a loop without `refresh=true`. Immediately search. How many do you find? Wait 2 seconds. How many now?

3. **Update penalty**: Index a document, then update it 10 times. Use `GET /products/_stats` to see how many segments exist. Why does this matter?

---

## Solutions & Staff Level Insights

### Task 1: Denormalization
You'd embed recent orders directly in the user document:
```json
{
  "user_id": "u123",
  "name": "Alice",
  "recent_orders": [
    { "order_id": "o1", "total": 150, "date": "2024-01-15" },
    { "order_id": "o2", "total": 89, "date": "2024-01-10" }
  ]
}
```
**Trade-off**: When an order changes, you must re-index the entire user document.

### Task 2: Consistency
You'll find fewer than 100 initially. After the default 1s refresh, you'll find all 100. This is the **near real-time** nature of ES.

### Task 3: Segment explosion
Each update creates a new segment (old doc is deleted-marked). Too many small segments hurt search performance. ES automatically merges them, but frequent updates are expensive. This is why ES is **not** a good fit for high-update-frequency OLTP workloads.

# Increment 07: Aggregations Internals

Aggregations power ES's analytics capabilities. Understanding how they work under the hood helps you write efficient aggregation queries.

---

## 1. Aggregation Types

| Type | What it does | Example |
|------|--------------|---------|
| **Bucket** | Groups documents into buckets | `terms`, `date_histogram`, `range` |
| **Metric** | Computes metrics over documents | `sum`, `avg`, `min`, `max`, `cardinality` |
| **Pipeline** | Operates on other aggregations' output | `derivative`, `moving_avg`, `bucket_sort` |

---

## 2. How Aggregations Work

### The Scatter-Gather Pattern

```
Coordinating Node
       │
       │ Scatter request to all shards
       ├────────────┬────────────┐
       ▼            ▼            ▼
    Shard 0      Shard 1      Shard 2
       │            │            │
       │ Local      │ Local      │ Local
       │ aggregation│ aggregation│ aggregation
       │            │            │
       └────────────┴────────────┘
                    │
                    ▼
           Coordinating Node
                    │
           Merge partial results
                    │
                    ▼
              Final result
```

> [!WARNING]
> **Staff Insight**: Each shard computes aggregations locally, then results are merged. For high-cardinality `terms` aggregations, this can be approximate — shards might not return the same top terms.

---

## 3. Doc Values: Columnar Storage

Aggregations don't use the inverted index. They use **doc_values** — a columnar data structure.

```
Inverted Index (for search):        Doc Values (for aggs):
"laptop"  → [1, 5, 9, 12]          doc_id | category    | price
"phone"   → [2, 7, 11]                1   | electronics | 999
                                      2   | electronics | 699
                                      5   | electronics | 1299
```

Doc values allow efficient:
- Sorting
- Aggregations
- Script field access

> [!NOTE]
> **Staff Insight**: Doc values are enabled by default for all field types that support them. The main exception is `text` fields (they only have inverted index). Use `keyword` or `text` with a `.raw` subfield for aggregations on strings.

---

## 4. Terms Aggregation Deep-Dive

The most common aggregation:

```json
{
  "aggs": {
    "categories": {
      "terms": {
        "field": "category",
        "size": 10
      }
    }
  }
}
```

### The Accuracy Problem

With 3 shards, each returns its top 10 categories. But:
- Shard 1 might have category "A" at #11 (not returned)
- Shard 2 might have category "A" at #3 (returned)
- Shard 3 might have category "A" at #8 (returned)

When merged, category "A" might be underrepresented.

### Solution: `shard_size`

```json
{
  "aggs": {
    "categories": {
      "terms": {
        "field": "category",
        "size": 10,
        "shard_size": 50
      }
    }
  }
}
```

Each shard returns top 50, coordinating node merges, takes final top 10. More accurate, but more network overhead.

---

## 5. Global Ordinals

For `keyword` fields, ES uses **global ordinals** to speed up terms aggregations.

```
Original values:         Ordinals:
"electronics" → 0        doc_id | ordinal
"food"        → 1           1   | 0
"clothing"    → 2           2   | 0
                            3   | 1
                            4   | 2
```

Instead of comparing strings, ES compares integers. Much faster!

### The catch
Global ordinals must be built on first aggregation or refresh. For high-cardinality fields (millions of unique values), this is expensive and uses heap memory.

> [!TIP]
> **Staff Insight**: For very high-cardinality fields (like user IDs), consider:
> - Use `execution_hint: map` to skip global ordinals
> - Pre-aggregate at ingest time
> - Use `composite` aggregation with pagination

---

## 6. Cardinality: Approximate Counting

```json
{
  "aggs": {
    "unique_users": {
      "cardinality": {
        "field": "user_id"
      }
    }
  }
}
```

Under the hood, this uses **HyperLogLog++** — a probabilistic data structure.

| Precision | Memory | Error |
|-----------|--------|-------|
| Default (3000) | ~3KB | ~1-6% |
| Low (100) | ~100B | ~10%+ |
| High (40000) | ~40KB | <0.5% |

```json
{
  "aggs": {
    "unique_users": {
      "cardinality": {
        "field": "user_id",
        "precision_threshold": 10000
      }
    }
  }
}
```

> [!NOTE]
> **Staff Insight**: Cardinality is always an estimate. For exact counts on low-cardinality fields, use `terms` aggregation and count buckets. For high-cardinality, accept the ~1% error.

---

## 7. Hands-on: Aggregation Exploration

### Step 1: Create test data
```bash
curl -X PUT "http://localhost:9200/orders" -H "Content-Type: application/json" -d '
{
  "mappings": {
    "properties": {
      "product": { "type": "keyword" },
      "category": { "type": "keyword" },
      "price": { "type": "float" },
      "quantity": { "type": "integer" },
      "customer_id": { "type": "keyword" },
      "order_date": { "type": "date" }
    }
  }
}'

# Generate random orders
for i in $(seq 1 500); do
  PRODUCTS=("laptop" "phone" "tablet" "headphones" "charger")
  CATEGORIES=("electronics" "accessories")
  PRODUCT=${PRODUCTS[$RANDOM % 5]}
  CATEGORY=${CATEGORIES[$RANDOM % 2]}
  PRICE=$((RANDOM % 1000 + 50))
  QUANTITY=$((RANDOM % 5 + 1))
  CUSTOMER=$((RANDOM % 100))
  DATE="2024-01-$((RANDOM % 28 + 1))"
  
  curl -s -X POST "http://localhost:9200/orders/_doc" -H "Content-Type: application/json" -d "
  {\"product\":\"$PRODUCT\",\"category\":\"$CATEGORY\",\"price\":$PRICE,\"quantity\":$QUANTITY,\"customer_id\":\"user_$CUSTOMER\",\"order_date\":\"$DATE\"}" > /dev/null
done

curl -X POST "http://localhost:9200/orders/_refresh"
```

### Step 2: Basic bucket aggregation
```bash
curl -X GET "http://localhost:9200/orders/_search?pretty" -H "Content-Type: application/json" -d '
{
  "size": 0,
  "aggs": {
    "by_category": {
      "terms": { "field": "category" }
    }
  }
}'
```

### Step 3: Nested aggregations (bucket + metric)
```bash
curl -X GET "http://localhost:9200/orders/_search?pretty" -H "Content-Type: application/json" -d '
{
  "size": 0,
  "aggs": {
    "by_category": {
      "terms": { "field": "category" },
      "aggs": {
        "total_revenue": {
          "sum": {
            "script": {
              "source": "doc[\"price\"].value * doc[\"quantity\"].value"
            }
          }
        },
        "avg_price": {
          "avg": { "field": "price" }
        }
      }
    }
  }
}'
```

### Step 4: Date histogram
```bash
curl -X GET "http://localhost:9200/orders/_search?pretty" -H "Content-Type: application/json" -d '
{
  "size": 0,
  "aggs": {
    "sales_over_time": {
      "date_histogram": {
        "field": "order_date",
        "calendar_interval": "week"
      },
      "aggs": {
        "revenue": {
          "sum": {
            "script": { "source": "doc[\"price\"].value * doc[\"quantity\"].value" }
          }
        }
      }
    }
  }
}'
```

### Step 5: Cardinality (unique count)
```bash
curl -X GET "http://localhost:9200/orders/_search?pretty" -H "Content-Type: application/json" -d '
{
  "size": 0,
  "aggs": {
    "unique_customers": {
      "cardinality": {
        "field": "customer_id",
        "precision_threshold": 100
      }
    }
  }
}'
```

### Step 6: Top hits (get actual docs per bucket)
```bash
curl -X GET "http://localhost:9200/orders/_search?pretty" -H "Content-Type: application/json" -d '
{
  "size": 0,
  "aggs": {
    "by_product": {
      "terms": { "field": "product", "size": 3 },
      "aggs": {
        "top_orders": {
          "top_hits": {
            "size": 2,
            "sort": [{ "price": "desc" }]
          }
        }
      }
    }
  }
}'
```

---

## 8. Composite Aggregation: Pagination

For large result sets, use `composite`:

```bash
curl -X GET "http://localhost:9200/orders/_search?pretty" -H "Content-Type: application/json" -d '
{
  "size": 0,
  "aggs": {
    "all_products": {
      "composite": {
        "size": 5,
        "sources": [
          { "product": { "terms": { "field": "product" } } }
        ]
      }
    }
  }
}'
```

Use the `after_key` from the response to paginate:
```json
{
  "composite": {
    "size": 5,
    "sources": [...],
    "after": { "product": "laptop" }
  }
}
```

---

## 9. Performance Considerations

| Pattern | Problem | Solution |
|---------|---------|----------|
| High-cardinality terms | Memory pressure | Use `composite` or pre-aggregate |
| Deep nesting | Combinatorial explosion | Limit depth, use filter |
| Scripts in aggs | CPU intensive | Pre-compute fields |
| Large `size` | Memory, network | Paginate with `composite` |

> [!IMPORTANT]
> **Staff Insight**: Aggregations can be more expensive than queries. A query might scan 10 docs; an aggregation scans ALL matching docs. Always filter first, then aggregate.

---

## Your Task

1. **shard_size experiment**: Run a terms aggregation with `size: 5`. Note results. Run again with `shard_size: 100`. Are the counts different?

2. **Global ordinals**: Create an index with 100,000 unique values in a keyword field. Run a terms aggregation. Check `/_nodes/stats/indices` for memory usage.

3. **Composite pagination**: Write a script that uses composite aggregation to iterate through ALL unique product/category combinations.

---

## Solutions & Staff Level Insights

### Task 1: shard_size effect
With low shard_size, you might get slightly inaccurate counts for items near the cutoff. Higher shard_size improves accuracy at the cost of more data transfer.

### Task 2: Global ordinals memory
High-cardinality fields cause heap memory usage to spike when global ordinals are built. Monitor `segments.term_vectors_memory_in_bytes` and related metrics.

### Task 3: Composite iteration
```bash
AFTER=""
while true; do
  RESULT=$(curl -s "http://localhost:9200/orders/_search" -H "Content-Type: application/json" -d "
  {\"size\":0,\"aggs\":{\"combo\":{\"composite\":{\"size\":100,\"sources\":[{\"product\":{\"terms\":{\"field\":\"product\"}}},{\"category\":{\"terms\":{\"field\":\"category\"}}}]$AFTER}}}}")
  
  echo "$RESULT" | jq '.aggregations.combo.buckets'
  
  AFTER_KEY=$(echo "$RESULT" | jq -c '.aggregations.combo.after_key')
  if [ "$AFTER_KEY" == "null" ]; then break; fi
  AFTER=",\"after\":$AFTER_KEY"
done
```

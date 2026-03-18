# Increment 02: Document Model & Mappings

Elasticsearch is a document store. Understanding how documents are stored and how mappings (schemas) work is crucial for building efficient search applications.

---

## 1. Documents: The Basic Unit

In ES, everything is a JSON document stored in an **index**.

```json
// A document in the "products" index
{
  "_index": "products",
  "_id": "abc123",
  "_source": {
    "name": "MacBook Pro",
    "price": 2499,
    "specs": {
      "cpu": "M3",
      "ram_gb": 16
    },
    "tags": ["laptop", "apple", "pro"]
  }
}
```

| Field | Purpose |
|-------|---------|
| `_index` | Which index (like a database table) |
| `_id` | Unique document ID (auto-generated or provided) |
| `_source` | The original JSON you indexed |

> [!NOTE]
> **Staff Insight**: The `_source` field is stored as-is and returned on search. It's **not** used for searching — the inverted index is. This means you're storing data twice: once in `_source`, once in the index. You can disable `_source` to save space, but then you lose the ability to reindex.

---

## 2. Mappings: ES's Schema

Unlike a schemaless MongoDB, ES **has a schema** — it's called a **mapping**. The catch? ES will create one automatically (dynamic mapping) if you don't define it.

### Dynamic Mapping (Convenient but Dangerous)

```bash
# Index without defining a mapping
curl -X POST "http://localhost:9200/users/_doc/1" -H "Content-Type: application/json" -d '
{"name": "Alice", "age": 30, "active": true}'
```

ES infers:
- `name` → `text` + `keyword` (multi-field)
- `age` → `long`
- `active` → `boolean`

### The Problem

```bash
# Later, someone indexes this:
curl -X POST "http://localhost:9200/users/_doc/2" -H "Content-Type: application/json" -d '
{"name": "Bob", "age": "thirty", "active": "yes"}'
```

💥 **Error!** ES already decided `age` is `long`. It can't accept "thirty".

> [!CAUTION]
> **Staff Insight**: In production, ALWAYS define explicit mappings. Dynamic mapping is a prototype footgun. Use `"dynamic": "strict"` to reject unmapped fields entirely.

---

## 3. Field Types Deep-Dive

### Text vs Keyword

This is the most important distinction in ES:

| Type | Analyzed? | Use Case | Example |
|------|-----------|----------|---------|
| `text` | Yes | Full-text search | "The quick brown fox" → search for "quick" |
| `keyword` | No | Exact match, aggregations, sorting | "user-123" → filter by exact ID |

```json
{
  "mappings": {
    "properties": {
      "title": { "type": "text" },                    // Full-text search
      "status": { "type": "keyword" },                // Exact filter
      "description": {                                 // Both!
        "type": "text",
        "fields": {
          "raw": { "type": "keyword" }
        }
      }
    }
  }
}
```

Now you can:
- Full-text search on `description`
- Sort or aggregate on `description.raw`

### Numeric Types

| Type | Range | Use Case |
|------|-------|----------|
| `long` | -2^63 to 2^63-1 | IDs, counts |
| `integer` | -2^31 to 2^31-1 | Smaller counts |
| `double` | 64-bit floating | Prices with decimals |
| `scaled_float` | Integer stored with scale factor | Prices (store cents, display dollars) |

> [!TIP]
> **Staff Insight**: For prices, use `scaled_float` with `scaling_factor: 100`. Store 1999 for $19.99. It's more space-efficient and avoids floating-point precision issues.

### Date

Dates are stored internally as **milliseconds since epoch** (long integer).

```json
{
  "mappings": {
    "properties": {
      "created_at": {
        "type": "date",
        "format": "yyyy-MM-dd HH:mm:ss||epoch_millis"
      }
    }
  }
}
```

---

## 4. Nested vs Object: The Hidden Pitfall

This trips up even experienced engineers.

### Object Type (Flattened)

```json
{
  "user": "Alice",
  "comments": [
    { "author": "Bob", "text": "Great!" },
    { "author": "Carol", "text": "Terrible!" }
  ]
}
```

ES flattens arrays of objects internally:
```
comments.author: ["Bob", "Carol"]
comments.text: ["Great!", "Terrible!"]
```

**Problem**: Query "comments where author=Bob AND text=Terrible!" will match — even though Bob said "Great!".

### Nested Type (Preserves Relationships)

```json
{
  "mappings": {
    "properties": {
      "comments": {
        "type": "nested",
        "properties": {
          "author": { "type": "keyword" },
          "text": { "type": "text" }
        }
      }
    }
  }
}
```

Now each object in the array is indexed as a **hidden separate document**, preserving the relationship.

> [!WARNING]
> **Staff Insight**: Nested documents count toward your document count and have performance implications. Each nested object is a Lucene document. An array of 100 nested objects = 101 Lucene docs (1 parent + 100 nested). Be mindful of `index.mapping.nested_objects.limit` (default: 10,000).

---

## 5. Hands-on: Mapping Design

### Step 1: Create an index with explicit mapping
```bash
curl -X PUT "http://localhost:9200/ecommerce" -H "Content-Type: application/json" -d '
{
  "settings": {
    "number_of_shards": 1,
    "number_of_replicas": 0
  },
  "mappings": {
    "dynamic": "strict",
    "properties": {
      "product_id": { "type": "keyword" },
      "name": { 
        "type": "text",
        "fields": { "raw": { "type": "keyword" } }
      },
      "description": { "type": "text", "analyzer": "english" },
      "price": { "type": "scaled_float", "scaling_factor": 100 },
      "category": { "type": "keyword" },
      "reviews": {
        "type": "nested",
        "properties": {
          "user": { "type": "keyword" },
          "rating": { "type": "integer" },
          "comment": { "type": "text" }
        }
      },
      "created_at": { "type": "date" }
    }
  }
}'
```

### Step 2: Index a document
```bash
curl -X POST "http://localhost:9200/ecommerce/_doc/1" -H "Content-Type: application/json" -d '
{
  "product_id": "LAPTOP-001",
  "name": "MacBook Pro 16-inch",
  "description": "Powerful laptop for professionals with M3 chip",
  "price": 249900,
  "category": "electronics",
  "reviews": [
    { "user": "alice", "rating": 5, "comment": "Best laptop ever!" },
    { "user": "bob", "rating": 4, "comment": "Great but expensive" }
  ],
  "created_at": "2024-01-15T10:30:00Z"
}'
```

### Step 3: Try to index an unmapped field (should fail)
```bash
curl -X POST "http://localhost:9200/ecommerce/_doc/2" -H "Content-Type: application/json" -d '
{
  "product_id": "PHONE-001",
  "name": "iPhone 15",
  "in_stock": true
}'
```

You'll get an error: `"mapping set to strict, dynamic introduction of [in_stock] is not allowed"`.

### Step 4: Query nested documents correctly
```bash
# Wrong way (treats nested as object — would match incorrectly)
curl -X GET "http://localhost:9200/ecommerce/_search?pretty" -H "Content-Type: application/json" -d '
{
  "query": {
    "bool": {
      "must": [
        { "term": { "reviews.user": "alice" } },
        { "term": { "reviews.rating": 4 } }
      ]
    }
  }
}'

# Right way (nested query)
curl -X GET "http://localhost:9200/ecommerce/_search?pretty" -H "Content-Type: application/json" -d '
{
  "query": {
    "nested": {
      "path": "reviews",
      "query": {
        "bool": {
          "must": [
            { "term": { "reviews.user": "alice" } },
            { "term": { "reviews.rating": 5 } }
          ]
        }
      }
    }
  }
}'
```

---

## 6. Mapping Mutations: What You Can and Can't Do

| Action | Allowed? | Notes |
|--------|----------|-------|
| Add new field | ✅ Yes | Just index a doc with the new field |
| Change field type | ❌ No | Must reindex to a new index |
| Add multi-field | ✅ Yes | But only new docs will have it |
| Change analyzer | ❌ No | Must reindex |

> [!IMPORTANT]
> **Staff Insight**: In production, always use index aliases. Create `products-v1`, alias it to `products`. When you need to change mappings, create `products-v2`, reindex, switch the alias atomically.

---

## Your Task

1. **Dynamic mapping experiment**: Create an index without a mapping. Index 3 documents with slightly different fields. Use `GET /index/_mapping` to see what ES inferred. Are there any surprises?

2. **Nested vs Object**: Create an index with an object-type array. Index a document with 2 array elements. Query to prove the "cross-object matching" bug described above.

3. **Mapping evolution**: Add a new field `"stock_count": {"type": "integer"}` to an existing index. Index new documents. Query old documents — what value do they have for `stock_count`?

---

## Solutions & Staff Level Insights

### Task 1: Dynamic mapping surprises
Common surprises:
- Strings become `text` + `keyword` multi-field (verbose)
- Integers in one doc, floats in another → conflict!
- Date-like strings become `date` (might break if format varies)

### Task 2: Nested bug demo
With object type, querying `author=X AND text=Y` can match a doc where X wrote A and someone else wrote Y. The arrays are flattened.

### Task 3: Mapping evolution
Old documents return `null` for the new field (it wasn't indexed). If you need to backfill, you must reindex those documents.

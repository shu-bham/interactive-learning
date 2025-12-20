# 🎯 Increment 00a: Syntax Basics (PostgreSQL vs MySQL)

**Duration**: 30 minutes  
**Difficulty**: ⭐ Introduction

## 📋 Quick Summary

As a MySQL veteran, PostgreSQL will feel very familiar yet occasionally "picky". PostgreSQL strictly follows SQL standards, which leads to some syntax differences you'll need to master first.

**Key Differences**:
- **Quotes**: Double quotes `"` for identifiers, Single quotes `'` for strings.
- **Data Types**: `TEXT` is preferred over `VARCHAR(long)`, `JSONB` for JSON.
- **Booleans**: Native `BOOLEAN` type (not `TINYINT`).
- **Standard SQL**: Strict adherence to SQL-92 and beyond.

---

## 🎓 Theory (10 minutes)

### 1. Quotation Marks (The most common pitfall!)

| Item | MySQL | PostgreSQL |
|------|-------|------------|
| String Literals | `'text'` or `"text"` | `'text'` ONLY |
| Identifiers (Table/Col) | `` `table` `` | `"table"` ONLY (and optional unless case-sensitive/reserved) |

> [!WARNING]
> In PostgreSQL, identifiers are **case-folded to lower case** by default. If you use `CREATE TABLE "Users"`, you MUST quote it as `"Users"` every time. If you use `CREATE TABLE Users`, it will be stored and accessed as `users`.

### 2. Data Types Mapping

| MySQL | PostgreSQL | Note |
|-------|------------|------|
| `TINYINT` | `SMALLINT` or `BOOLEAN` | Use `BOOLEAN` for true/false |
| `DATETIME` | `TIMESTAMP` | Use `TIMESTAMP WITH TIME ZONE` (timestamptz) |
| `LONGTEXT` | `TEXT` | `TEXT` in PG has no performance penalty vs `VARCHAR` |
| `UNSIGNED` | (None) | Use `CHECK` constraints or larger types |
| `AUTO_INCREMENT` | `SERIAL` or `GENERATED ALWAYS AS IDENTITY` | Identity columns are SQL standard |

### 3. Schema Concept

In MySQL: `DB Name` ≈ `Schema`.
In PostgreSQL: `Instance` > `Database` > `Schema`.
The default schema is always `public`.

---

## 🧪 Hands-On Exercises (15 minutes)

### Exercise 1: Exploring Case Sensitivity (psql)

Connect using our script:
```bash
./scripts/connect-primary.sh
```

Run these commands in `psql`:

```sql
-- 1. Create a table with quoted uppercase
CREATE TABLE "UpperTable" (id INT, "UserName" TEXT);

-- 2. Try to query it without quotes (this will fail)
SELECT * FROM UpperTable;

-- 3. Query it correctly
SELECT * FROM "UpperTable";

-- 4. Clean up
DROP TABLE "UpperTable";
```

### Exercise 2: Boolean and String Strictness

```sql
-- 1. Create a table with Boolean
CREATE TABLE feature_flags (
    name TEXT PRIMARY KEY,
    is_enabled BOOLEAN DEFAULT false
);

-- 2. Valid insertion
INSERT INTO feature_flags VALUES ('new_ui', true);
INSERT INTO feature_flags VALUES ('beta_docs', 'yes'); -- PG handles 'yes'/'no' string to bool

-- 3. See how it's stored
SELECT * FROM feature_flags;

-- 4. Try MySQL style boolean (will fail)
-- INSERT INTO feature_flags VALUES ('broken', 1); 
```

### Exercise 3: Userful `psql` Commands

PostgreSQL's command line is powerful. Practice these:

| Command | Description | MySQL Equivalent |
|---------|-------------|------------------|
| `\dt` | List tables | `SHOW TABLES;` |
| `\d table_name` | Describe table | `DESC table_name;` |
| `\l` | List databases | `SHOW DATABASES;` |
| `\dn` | List schemas | (N/A) |
| `\df` | List functions | `SHOW FUNCTION STATUS;` |
| `\q` | Quit | `exit;` |

---

## 🎤 Interview Question Practice

**Q1**: "Does PostgreSQL distinguish between `''` (empty string) and `NULL`?"

**Answer**: Yes, strictly. Like standard SQL, an empty string is a valid string with length 0, while `NULL` represents an unknown/empty value. 
*MySQL Tip*: In Oracle mode, MySQL might treat them similarly, but in standard mode they are also distinct.

**Q2**: "What is the benefit of using `JSONB` over `JSON` in PostgreSQL?"

**Answer**: `JSON` stores a literal copy of the input text (fast insert, slow query). `JSONB` stores a decomposed binary format (slightly slower insert, much faster queries with indexing support). Always use `JSONB` for production.

---

## ✅ Completion Checklist

- [ ] Connect to PostgreSQL using the terminal
- [ ] Understand the difference between `'` and `"`
- [ ] Practice using at least 5 `\` commands in psql
- [ ] Explain the difference between `TIMESTAMP` and `TIMESTAMPTZ`

## 🔗 Next: Increment 00b - DDL, DML, Grouping & Joins
Ready? Let me know and we'll practice the core CRUD operations.

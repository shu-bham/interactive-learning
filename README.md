# MySQL Deep Internals - Interactive Learning Session

> **Target Audience**: Senior Backend Developers (6+ years) preparing for Staff-level positions
> 
> **Focus**: MySQL internals, architecture, performance optimization, and advanced database engineering

## 🎯 Learning Objectives

By completing this hands-on session, you will:

- Understand InnoDB storage engine architecture at a deep level
- Master query optimization and execution plan analysis
- Gain expertise in transaction management and MVCC
- Learn replication internals and high availability patterns
- Develop advanced performance tuning skills
- Build confidence for staff-level technical interviews

## 🚀 Quick Start

### Prerequisites
- Docker installed on your Mac
- Basic MySQL knowledge (you have this!)
- Terminal access
- 4GB+ RAM available for Docker

### Setup Environment

```bash
# Clone or navigate to the project directory
cd /Users/shubhamcs/Desktop/github/interactive-learning

# Start the MySQL environment
docker-compose up -d

# Verify containers are running
docker-compose ps

# Connect to MySQL master
docker exec -it mysql-master mysql -uroot -prootpass learning_db
```

### Access Points

- **MySQL Master**: `localhost:3306`
- **MySQL Replica**: `localhost:3307`
- **phpMyAdmin**: `http://localhost:8080`

**Credentials**:
- Root: `root` / `rootpass`
- Dev User: `devuser` / `devpass`

## 📚 Learning Modules

### Module 1: Storage Engine Internals (InnoDB Deep Dive)
**Location**: `modules/01-storage-engine/`

Learn about:
- InnoDB architecture and components
- Buffer pool mechanics and management
- Redo/undo log internals
- Doublewrite buffer and crash recovery
- Tablespace and file structure

### Module 2: Query Execution & Optimization
**Location**: `modules/02-query-optimization/`

Master:
- Query parser and optimizer internals
- Execution plan analysis (EXPLAIN deep dive)
- Index strategies and B+Tree structure
- Cost-based optimization
- Query rewriting techniques

### Module 3: Transaction Management & Concurrency
**Location**: `modules/03-transactions/`

Explore:
- MVCC (Multi-Version Concurrency Control) implementation
- Lock mechanisms (row, gap, next-key locks)
- Deadlock detection and resolution
- Isolation levels internals
- Transaction log management

### Module 4: Replication & High Availability
**Location**: `modules/04-replication/`

Understand:
- Binary log format and internals
- GTID-based replication
- Replication topologies
- Group replication architecture
- Failover strategies

### Module 5: Performance Monitoring & Tuning
**Location**: `modules/05-performance/`

Develop skills in:
- Performance Schema deep dive
- Query profiling and analysis
- Slow query log interpretation
- Resource bottleneck identification
- Memory and disk I/O optimization

### Module 6: Advanced Topics
**Location**: `modules/06-advanced/`

Cover:
- Partitioning strategies and internals
- Full-text search mechanics
- JSON support and indexing
- Security and authentication plugins
- Backup and recovery internals

## 🛠️ Utility Scripts

```bash
# Connect to master
./scripts/connect-master.sh

# Connect to replica
./scripts/connect-replica.sh

# Reset environment
./scripts/reset-environment.sh

# Generate load for testing
./scripts/generate-load.sh

# Analyze slow queries
./scripts/analyze-slow-queries.sh
```

## 📊 Sample Database Schema

The learning environment includes a realistic e-commerce database:

- **users**: User accounts with various indexes
- **orders**: Order transactions
- **order_items**: Order line items
- **products**: Product catalog with full-text search
- **user_activity_log**: Partitioned activity tracking

## 🎓 Learning Path

### Recommended Sequence

1. **Day 1-2**: Storage Engine Internals
2. **Day 3-4**: Query Optimization
3. **Day 5-6**: Transactions & Concurrency
4. **Day 7-8**: Replication & HA
5. **Day 9-10**: Performance Tuning
6. **Day 11-12**: Advanced Topics & Interview Prep

### Study Approach

Each module contains:
- **Theory**: Conceptual explanations with diagrams
- **Hands-on Labs**: Interactive exercises
- **Real-world Scenarios**: Production-like problems
- **Interview Questions**: Staff-level technical questions
- **Further Reading**: Deep-dive resources

## 🔍 Staff Interview Focus Areas

This session specifically prepares you for:

- Architecture design discussions
- Performance troubleshooting scenarios
- Scalability and reliability questions
- Trade-off analysis
- Production incident resolution
- System design with MySQL at scale

## 📝 Progress Tracking

Track your progress in `progress.md`:
- Mark completed modules
- Note key learnings
- Document questions for review
- Record interview preparation notes

## 🤝 Contributing

Found an issue or want to add content? This is your learning repository!

## 📖 Additional Resources

- MySQL Official Documentation
- MySQL Internals Manual
- High Performance MySQL (Book)
- MySQL Source Code (GitHub)

---

**Ready to dive deep?** Start with Module 1: Storage Engine Internals!

```bash
cd modules/01-storage-engine
cat README.md
```

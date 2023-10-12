---
layout: post
title:  "Insight h2database 更新、读写锁以及事务原理"
date:   2023-10-08 21:28:37 +0800
categories: 源码阅读
tags: h2数据库 设计模式 并发编程 事务控制
---

* content
{:toc}

> 文章基于 RegularTable 来分析和拆解更新操作。
> 
> PageStore 存储引擎默认不开启 MVCC，锁模型比较简单，方便了解更新的整个流程。
> 
> 主要涉及读写锁（事务隔离），数据更新的实现、事务的提交和回滚。
> 

## 相关概念

> 讨论更新操作，就需要涉及到事务隔离级别以及事务的概念。
> 
> 也就是讨论如何控制并发读写的问题、以及undolog 的问题。

### ①MVCC

> multi version concurrency。在 h2database 实现中，默认 MVStore 存储引擎支持该特性。
> 
> 为了简化事务实现模型，只关注非 MVCC 模式。 MVCC 实现原理参考《Insight h2database MVCC 实现原理》。

```java
/**
 * Check if multi version concurrency is enabled for this database.
 * 使用 PageStore 存储引擎时，使用 MVCC=true 开启。
 * @see org.h2.engine.Database#isMultiVersion
 */
public boolean isMultiVersion() {
    // this.multiVersion = ci.getProperty("MVCC", dbSettings.mvStore);
    return multiVersion;
}

/**
 * 通过设置或者版本确定是否启用 MVStore 存储引擎
 * @see org.h2.engine.DbSettings#mvStore
 */
public boolean mvStore = get("MV_STORE", Constants.VERSION_MINOR >= 4);
```

### ②事务隔离级别

> the isolation level. 在 h2database 中，通过 LOCK_MODE 体现。不同的锁定模式决定了事务级别。参考命令 SET LOCK_MODE int。

- **SET LOCK_MODE 命令是数据库级别的，影响全局（affects all connections）。**

- 默认的事务隔离级别为 READ_COMMITTED。MVStore 存储引擎默认支持。

- **对于 RegularTable 只存在三种级别：READ_UNCOMMITTED， READ_COMMITTED, SERIALIZABLE(默认)。**

- READ_UNCOMMITTED，即无锁定模式（仅用于测试）

- READ_COMMITTED, 避免了脏读，相比于 SERIALIZABLE，并发性能更好，事务的读写操作不阻塞。开启 MVCC 模式即可。

- SERIALIZABLE，不同事务（session）读写互斥。可以防止脏读、不可重复读和幻读，但是效率较低，因为它会锁定所涉及的全部表，直到整个事务完成。

## RegularTable 表级独占锁

> 更新流程中，首先会调用 table.lock(session, exclusive = true, false); 
> 
> 在 RegularTable 中，表会按照 session 粒度控制并发度。这个方法只能当前 session 可重入，其他 session 想 lock 成功，需要等待当前会话释放锁。

### ①独占锁示例

```sql
-- session 1 更新数据并持有锁
SET AUTOCOMMIT OFF;
update city set code = 'bjx' where id = 9;

-- session 2 获取锁超时，异常
select * from city where id = 5;

Timeout trying to lock table "CITY"; SQL statement:
select * from city where id = 5 [50200-184] HYT00/50200
```

### ②独占锁实现

> 独占锁是个 Java 经典的多线程同步案例。同时包含了死锁检测的解决方案。

```java
/**
 * 通过会话，给表加锁。
 * 如果要加写锁，会存在等待锁的情况。
 * 如果发生锁超时，将抛出DbException异常。如上示例。
 * @param session 当前会话
 * @param exclusive 如果为true，表示需要写锁；如果为false，表示需要读锁。写锁是排他的，即在同一时间只能有一个线程持有写锁。读锁是共享的，即在同一时间可以有多个线程持有读锁。
 * @see org.h2.table.RegularTable#lock
 */
public boolean lock(Session session, boolean exclusive, boolean forceLockEvenInMvcc) {
    int lockMode = database.getLockMode();
    // 无锁模式，直接返回。 
    if (lockMode == Constants.LOCK_MODE_OFF) {
        // 返回是否存在独占 session, 没有使用到，约等于无，不用关注。
        return lockExclusiveSession != null;
    }
    // 如果是当前 session 独占，相当于锁重入（如果一个会话已经持有了这个表的独占锁，那么它可以再次获取这个锁，而不会被自己阻塞。）
    if (lockExclusiveSession == session) {
        return true;
    }
    synchronized (database) {
        // double check 😁
        if (lockExclusiveSession == session) {
            return true;
        }
        // 读锁，共享，直接返回。
        if (!exclusive && lockSharedSessions.contains(session)) {
            return true;
        }
        // 写锁，进入等待队列
        session.setWaitForLock(this, Thread.currentThread());
        waitingSessions.addLast(session);
        try {
            // while 循环出队列加锁 or 等待加锁。
            // 真正的加锁在 doLock2 方法中。根据读写锁不同(exclusive), 执行不同的操作。
            doLock1(session, lockMode, exclusive);
        } finally {
            session.setWaitForLock(null, null);
            waitingSessions.remove(session);
        }
    }
    return false;
}
```

## RegularTable 更新流程

> 了解独占锁的工作机制后，对于数据更新事务的原子性、一致性、隔离级别就没有疑问了。以下主要列出数据更新的主流程，比如查找并更新，触发器时机。

```java
/**
 * 执行数据更新
 * @see org.h2.command.dml.Update#update
 */
public int update() {
    // 记录哪些数据需要更新。
    RowList rows = new RowList(session);
    try {
        Table table = tableFilter.getTable();
        session.getUser().checkRight(table, Right.UPDATE);
        // 尝试添加写锁（独占锁）
        table.lock(session, true, false);
        // 查询需要更新的数据， select by condition
        while (tableFilter.next()) {
            if (condition == null || Boolean.TRUE.equals(condition.getBooleanValue(session))) {
                // 旧数据，直接查出来的。
                Row oldRow = tableFilter.get();
                // 新数据，根据更新语句，重新赋值后的。
                Row newRow = table.getTemplateRow();
                // 执行 set column 表达式...
                boolean done = false;
                if (table.fireRow()) {
                    // 数据变更前，分发执行触发器。触发器太多可不行❌
                    done = table.fireBeforeRow(session, oldRow, newRow);
                }
                if (!done) {
                    rows.add(oldRow);
                    rows.add(newRow);
                }
            }
        }

        // 存储引擎执行真正的数据更新操作。⛳
        table.updateRows(this, session, rows);
        if (table.fireRow()) {
            for (rows.reset(); rows.hasNext();) {
                // 数据变更后，分发执行触发器
                table.fireAfterRow(session, o, n, false);
            }
        }
        return count;
    } finally {
        rows.close();
    }
}
```

## 事务控制

> 因为 RegularTable PageStore 存储引擎事务是 SERIALIZABLE 级别， 就不存在读写并发的情况，远没有 MVCC 模式提交事务那么复杂。事务的提交不做过多分析，主要关注事务回滚的实现。

### ①AutoCommit

> 和其他数据库一样， h2database 会话默认的 AutoCommit = true。更新命令执行完成会自动发起 commit 操作。
> 
> 开启事务的情况下，由用户手动发起 commit 操作。

```java
/**
 * 更新命令执行完成后，收尾工作之一判断是否需要发起自动提交✔
 * @see org.h2.command.Command#stop
 */
private void stop() {
    // AutoCommit 状态，自动提交事务。
    if (session.getAutoCommit()) {
        session.commit(false);
    }
}
```

### ②事务提交

> org.h2.command.dml.TransactionCommand#update 命令处理

```java
/**
 * Commit the current transaction. 
 *
 * @see org.h2.engine.Session#commit
 */
public void commit(boolean ddl) {
    // 事务持久化机制，及时存盘数据库操作记录。
    if (containsUncommitted()) {
        database.commit(this);
    }
    if (undoLog.size() > 0) {
        undoLog.clear();
    }
    // 释放当前会话关联 table 的读写锁。
    // @see org.h2.engine.Session#unlockAll
    endTransaction();
}
```

### ③事务回滚

> org.h2.command.dml.TransactionCommand#update 命令处理

**事务的回滚依赖 undoLog**。实现类：org.h2.engine.UndoLogRecord，undoLog 只存在两种操作 INSERT DELETE。对应到 SQL 操作：

- Insert SQL: INSERT new, 回滚操作为：DELETE new

- Update SQL: DELETE old, INSERT new, 回滚操作为：DELETE new, INSERT old

- Delete SQL: DELETE old, 回滚操作为：INSERT old

```java
/**
 * 事务回滚操作。
 * 事务回滚的过程就是按照逆序回放事务中的操作（undoLog中的操作逆序执行）。
 *
 * @param savepoint 如果指定保存点，事务将回滚到这个保存点。
 * @param trimToSize if the list should be trimmed
 */
public void rollbackTo(Savepoint savepoint, boolean trimToSize) {
    // 保存点持有的是当前会话开始时 undoLog 的位置。默认都是 0。
    int index = savepoint == null ? 0 : savepoint.logIndex;
    // 当前会话 undoLog 队列逆向回放，重置现场。
    while (undoLog.size() > index) {
        UndoLogRecord entry = undoLog.getLast();
        // 如上的对应操作规则，回放操作。
        entry.undo(this);
        undoLog.removeLast(trimToSize);
    }
}
```

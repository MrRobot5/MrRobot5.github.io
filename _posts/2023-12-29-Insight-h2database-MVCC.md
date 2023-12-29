---
layout: post
title:  "Insight h2database MVCC 实现原理"
date:   2023-12-29 19:02:54 +0800
categories: 源码阅读
tags: h2数据库 并发编程 事务控制
---

* content
{:toc}

> 基于《Insight h2database 更新、读写锁以及事务原理》对于更新流程有了深入了解。在独占锁的简单模型上，分析 h2database 基于乐观锁（并发控制机制）的行锁锁定机制。

## MVCC 使用示例

### ①环境准备

验证 h2database MVCC 机制，需要有并发的环境，不能再使用 `org.h2.tools.Shell` 。可以使用 debug 模式，运行 `org.h2.tools.Console`。使用不同的浏览器模拟多 session

配置图片sss

### ②并发读写示例

```sql
-- session 1 更新数据并打标
SET AUTOCOMMIT OFF;
update city set code = 'bjx' where id = 9;

-- session 2 读取数据正常
select * from city where id = 9;

-- session 2 更新数据异常，提示 Timeout，其实是并发更新冲突异常
update city set code = 'sjx' where id = 9;

Timeout trying to lock table "CITY"; 
```

上述的并发异常，在内部的错误代码为：**org.h2.api.ErrorCode#CONCURRENT_UPDATE_1**
trying to update the same row from within two connections at the same time



## RegularTable 乐观锁机制

> MVCC 模式下，不再使用锁机制来控制并发。而是通过乐观锁并发控制机制来实现数据读写的一致性。

### ①无锁模型

```java
/**
 * 多版本控制（MVCC）模式下的加锁逻辑
 * @see org.h2.table.RegularTable#lock
 */
public boolean lock(Session session, boolean exclusive, boolean forceLockEvenInMvcc) {
    int lockMode = database.getLockMode();
    if (lockMode == Constants.LOCK_MODE_OFF) {
        return lockExclusiveSession != null;
    }
    // 指定 MVCC=true，启用了多版本控制（MVCC）
    // database.multiVersion =ci.getProperty("MVCC", dbSettings.mvStore);
    if (database.isMultiVersion()) {
        // MVCC 模式下: 更新操作（update, delete, insert）使用共享锁
        if (exclusive) {
            exclusive = false;
        } else {
            if (lockExclusiveSession == null) {
                return false;
            }
        }
    }
    // MVCC模式（exclusive = false），可以理解为无锁。
    return true;
}
```

### ②版本控制

乐观锁是基于行数据，行数据包含如下两个关键属性：

- org.h2.result.Row#deleted 数据更新，其实是先 delete、后 insert 的组合操作。通过标识一行数据是否处于删除状态，防止其他 session 再次进行类似操作，起到冲突检测的目的。

- org.h2.result.Row#sessionId 如何实现多版本的数据隔离，就是通过指定唯一的sessionId ，配合数据的读写控制，达到根据session/事务间的数据隔离。

```java
/**
 * sessionId deleted 属性的作用机制。
 * @see org.h2.table.RegularTable#removeRow
 */
public void removeRow(Session session, Row row) {
    if (database.isMultiVersion()) {
        // 对于同一条数据，不允许重复更新。并发更新止步于此❌
        // 例如：session 1 中 delete, 未提交；session 2 仍然可以查到此数据，但并不能做 update/delete 操作。
        if (row.isDeleted()) {
            throw DbException.get(ErrorCode.CONCURRENT_UPDATE_1, getName());
        }
        int old = row.getSessionId();
        int newId = session.getId();
        if (old == 0) {
            // 设置唯一的版本号，独占该行数据。数据的变更与其他 session 隔离
            // 如果session 提交，sessionId 重置为 0。
            row.setSessionId(newId);
        } else if (old != newId) {
            // 如果不是同一 session，不可重入❌。当前行的锁机制。
            throw DbException.get(ErrorCode.CONCURRENT_UPDATE_1, getName());
        }
    }
}
```

可以通过更新操作更详细的了解作用机制。

## RegularTable MVCC 模式更新数据

> 更新操作其实是通过先删后增的组合操作实现的（RegularTable#removeRow ➕ RegularTable#addRow）。鉴于篇幅有限，主要分析 removeRow 的流程，addRow 多版本控制机制类似。

```java
/**
 * 主索引（聚集索引）删除一行数据
 * @see org.h2.index.PageDataIndex#remove
 */
public void remove(Session session, Row row) {
    try {
        // 直接从数据索引中删除这条数据。物理删除✔
        long key = row.getKey();
        PageData root = getPage(rootPageId, 0);
        root.remove(key);
    }
    if (multiVersion) {
        // 数据标识为已删除，逻辑删除。✔
        row.setDeleted(true);
        boolean wasAdded = delta.remove(row);
        // 暂存到 delta 集合中。这个非常重要，当前事务提交前，其他事务仍然可见本条数据。
        if (!wasAdded) {
            delta.add(row);
        }
    }
}
```



## RegularTable MVCC 模式读写数据隔离

> 一个事务种删除数据， 如果还未提交。其他事务怎么读到？
> 
> 同样的疑问，一个事务添加的数据，如果还未提交。已经加入主索引中，为什么其他事务怎么读不到？

```java
/**
 * MVCC 模式下，扫描读取多版本数据
 * @see org.h2.index.PageDataCursor#next
 */
public boolean next() {
    while (true) {
        // 如果存在暂存数据（delta），则先扫描暂存集合。
        if (delta != null) {
            row = delta.next();
            // delta 存储的逻辑删除数据，如果属于当前session，skip； 其他session， 有效。
            if (!row.isDeleted() || row.getSessionId() == session.getId()) {
                continue;
            }
        } else {
            nextRow();
            // 针对数据索引中存储的数据
            // 如果是新增数据（sessionId != 0），并且也非当前session 新增， 无效，skip。
            if (row != null && row.getSessionId() != 0 && row.getSessionId() != session.getId()) {
                continue;
            }
        }
        break;
    }
    return checkMax();
}
```

基于上述的分析，以及代码 Insight，很好解答以上疑问。

### ①数据删除、查询并发的情况

- session 1 中删除 row， row.deleted = true, row.sessionId = 1

- session 1 删除后再查询，row.sessionId == 当前session, 并且标识为删除，所以查不到

- session 2 查询row, row.sessionId != 当前session, 删除标识无效，可以查到



### ②数据添加、查询并发的情况

- session 1 中增加 row, row 写入到主索引中，row.sessionId = 1

- session 2 扫描主索引，可以扫描到 row, 但是 row.sessionId != 当前session, 对当前session 不可见，所以**逻辑上查询不到 row**。



## one more thing, MultiVersionIndex

> 为了简化模型，方便主流程分析，上述过程只是分析了主索引（PageDataIndex）在MVCC 模式下的并发操作。对于其他的BTree 索引，其实也是经过了类似的处理。

数据其实是通过 MultiVersionIndex实现的。

- org.h2.index.MultiVersionIndex 代理和封装了 PageBtreeIndex。它由一个常规索引（PageBtreeIndex）和一个内存中的树索引组合而成。

- 针对事务操作的中间数据（包括新行和删除行，也就是多版本数据），使用 Delta 来暂存并支持搜索。

```java
/**
 * 代理索引的查询操作，其实是委托真正 PageBtreeIndex 索引以及暂存索引实现的。
 * @see org.h2.index.MultiVersionIndex#find
 */
public Cursor find(Session session, SearchRow first, SearchRow last) {
    synchronized (sync) {
        Cursor baseCursor = base.find(session, first, last);
        Cursor deltaCursor = delta.find(session, first, last);
        // 融合搜索
        return new MultiVersionCursor(session, this, baseCursor, deltaCursor, sync);
    }
}
```



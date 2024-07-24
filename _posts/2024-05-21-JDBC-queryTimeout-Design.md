---
layout: post
title:  "JDBC queryTimeout 实现机制"
date:   2024-05-21 20:17:05 +0800
categories: 源码阅读
tags: Mysql h2数据库 架构设计
---

* content
{:toc}


> 超时机制是个常见的设计，对于系统的稳定性和可靠性有重要的作用。
> 
> 本文分别从 H2 和 Mysql 两种数据库的实现方式，来了解数据库查询的超时设计。



## JDBC queryTimeout 概述

- 超时机制对于防止长时间运行的查询**占用过多资源**，或者数据库锁等问题导致的**死锁**非常有用。

- 不同的数据库和驱动对超时设置的实现可能不同（如H2 和 Mysql）。

- 如果执行时间超过了设置的阈值，**驱动/数据库**会尝试取消或终止执行中的查询。



## H2 queryTimeout 实现方案

> H2 在服务端定时循环检测中断。简单直接。

### ①超时设置

超时设置作用于当前session, 根据关键变量 cancelAt 来判断当前时间节点是否超过阈值。

setQueryTimeout 是以 Set SQL 命令实现的（`SET QUERY_TIMEOUT ?`）。

参考：org.h2.command.dml.SetTypes#QUERY_TIMEOUT

```java
/**
 * 给当前session 设置超时时间
 * @see org.h2.engine.Session#setQueryTimeout
 */
public void setQueryTimeout(int queryTimeout) {
    // 取数据库全局配置和session 配置中的最小值
    int max = database.getSettings().maxQueryTimeout;
    if (max != 0 && (max < queryTimeout || queryTimeout == 0)) {
        // the value must be at most max
        queryTimeout = max;
    }
    this.queryTimeout = queryTimeout;
    // 关键变量（volatile），记录超时时间节点。
    // 执行查询命令前，会重置 cancelAt = now + queryTimeout;
    this.cancelAt = 0;
}
```

### ②中断操作

执行数据检索的过程中，会定期检查是否超时，来决定是否中断。

```java
/**
 * 数据检索和查询过程中，定期检测 timeout
 * @see org.h2.table.TableFilter#next
 */
public boolean next() {
    // 数据扫描检测 4095次，触发检测 timeout
    if ((++scanCount & 4095) == 0) {
        // 实际调用 session.checkCanceled();
        // 👉 如果当前时间大于或等于cancelAt设置的时间，意味着取消操作的时间已经到了或者过了，事务应该被取消。抛出一个DbException异常。
        checkTimeout();
    }
    if (cursor.next()) {
        currentSearchRow = cursor.getSearchRow();
        // 执行数据扫描和筛选...
    }
}
```



## Mysql queryTimeout 实现方案

> Mysql 在客户端多线程检测并主动发起中断操作。
> 
> 查询操作开始时启动计时器。如果操作在超时时间内完成，则正常继续。如果操作未在超时时间内完成，则触发一个中断或异常。

### ①超时设置

客户端（驱动）`timeoutInMillis` 变量赋值操作。

```java
/**
 * 当前Statement对象设置超时，发起查询操作前，决定是否启动计时器
 * @see com.mysql.jdbc.StatementImpl#setQueryTimeout
 */
public synchronized void setQueryTimeout(int seconds) throws SQLException {
	if (seconds < 0) {
		throw SQLError.createSQLException(Messages.getString("Statement.21"), "S1009", this.getExceptionInterceptor());
	} else {
		this.timeoutInMillis = seconds * 1000;
	}
}
```

### ②中断操作

需要理解多线程的并发操作。

```java
/**
 * 客户端发起sql 请求前，会启动超时计时器，用于执行中断操作。
 * @see StatementImpl#execute(String, boolean)
 */
private synchronized boolean execute(String sql, boolean returnGeneratedKeys) throws SQLException {

    try {
        // 如果启用并设置了超时时间，会启动计时器。
        if (locallyScopedConn.getEnableQueryTimeouts() && this.timeoutInMillis != 0 && locallyScopedConn.versionMeetsMinimum(5, 0, 0)) {
            timeoutTask = new StatementImpl.CancelTask(this);
            // (Timer)ctr.newInstance("MySQL Statement Cancellation Timer", Boolean.TRUE);
            locallyScopedConn.getCancelTimer().schedule(timeoutTask, (long)this.timeoutInMillis);
        }
        // 主线程发起 sql 请求。如果超时，计时器会发起 "KILL QUERY " + CancelTask.this.connectionId， 中断主线程阻塞。
        rs = locallyScopedConn.execSQL(this, sql, -1, (Buffer)null, this.resultSetType, this.resultSetConcurrency, doStreaming, this.currentCatalog, cachedFields);

        synchronized(this.cancelTimeoutMutex) {
            // 检测启动器是否发起超时KILL, 决定 throw MySQLTimeoutException()
            if (this.wasCancelled) {
                SQLException cause = null;
                if (this.wasCancelledByTimeout) {
                    cause = new MySQLTimeoutException();
                }
                throw cause;
            }
        }
    }

}
```

## 总结

- 如上述的源码分析，超时的时间精度和驱动/数据库有关，实际的超时时间可能会比设置的时间稍长。

- 上述两种超时实现方案各有优势，H2 数据库相对简单直观，Mysql 复杂但控制更加精准。

- 合理的超时设定，可以提升数据库的稳定性，减少不必要的资源浪费和占用。

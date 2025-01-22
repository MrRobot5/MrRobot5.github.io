---
layout: post
title:  "使用数据库连接池场景下的 too many connections 问题排查"
date:   2023-05-07 17:25:01 +0800
categories: 实战问题
tags: DataSource
---
* content
{:toc}

> 在应用工程里，存在一个后台执行 SQL 脚本的接口。在大量的使用后，提示异常：`Could not create connection to database server. Attempted reconnect 3 times. Giving up.` 同时，其他连接这个 mysql 的应用，也提示异常。
> 
> 执行 SQL 使用数据库连接池，理论上不应该出现连接超量的情况。

## 问题分析

```java
// 通过指定数据源，执行对应的 update SQL
@PostMapping("/update/{dataSource}/{count}")
public ResponseResult<String> update(@PathVariable String dataSource, @PathVariable Integer count , @RequestBody String sql) {
    // 获取数据源
    Map<String, DataSource> dataSourceMap = getDataSources();
    DataSource source = dataSourceMap.get(dataSource);
    // 执行
    return ResponseResult.ok(sqlService.execute(source,sql,count));
}
```

代码比较简单，猜测可能有以下两个问题：

1. 在执行过程中，没有close connection，导致连接池一直在创建新的 connection。

2. 获取数据源的过程中，存在数据源对象泄露，导致创建了很多 DataSource。

## 解疑 Connection close

> jdbc 关闭连接的顺序是：ResultSet → Statement → Connection

在工程代码中，没有发现手动关闭 Statement 的操作。是不是会阻塞 connection close ?

```java
/**
 * HikariDataSource Connection 会自动关闭 Statement
 * @see com.zaxxer.hikari.pool.ProxyConnection This is the proxy class for java.sql.Connection.
 */
@Override
public final void close() throws SQLException {
  // automatic resource cleanup
  closeStatements();

  if (delegate != ClosedConnection.CLOSED_CONNECTION) {
	 try {
		// fall back operation...
		if (isCommitStateDirty && !isAutoCommit) {
		   delegate.rollback();
		}
	 }
	 finally {
		// return resource
		delegate = ClosedConnection.CLOSED_CONNECTION;
		poolEntry.recycle(lastAccess);
	 }
  }
}
```

```java
// 关闭 statement, 会级联关闭 results
// @see com.mysql.jdbc.StatementImpl#realClose
protected synchronized void realClose(boolean calledExplicitly, boolean closeOpenResults) throws SQLException {
	if (closeOpenResults) {
		if (this.results != null) {
			try {
				this.results.close();
			} catch (Exception var4) {
			}
		}
		this.closeAllOpenResults();
	}
}
```

## 解疑 HikariDataSource

```java
/**
* We only create connections if we need another idle connection or have threads still waiting
* for a new connection.  Otherwise we bail out of the request to create.
*
* @return true if we should create a connection, false if the need has disappeared
* @see com.zaxxer.hikari.pool.HikariPool.PoolEntryCreator#shouldCreateAnotherConnection
*/
private synchronized boolean shouldCreateAnotherConnection() {
	// The property controls the maximum number of connections that HikariCP will keep in the pool, including both idle and in-use connections.
	return getTotalConnections() < config.getMaximumPoolSize() &&
	(connectionBag.getWaitingThreadCount() > 0 || getIdleConnections() < config.getMinimumIdle());
}
```

[终于理解Spring Boot 为什么青睐HikariCP了，图解的太透彻了！](https://zhuanlan.zhihu.com/p/392484378)

源码结合实践，数据库连接池肯定不会无限制创建连接。

## 解疑 工程代码 getDataSources

```java
public Map<String, DataSource> getDataSources(){
	// 没有缓存或者单例处理，每调用一次，初始化一次 DataSource 😅
	Map<String, DataSource> dataSources = new HashMap<>();
	datadaSourcesConfig.forEach((k, v) -> {
		// spring boot, Convenience class for building a DataSource with common implementations and properties.
		DataSourceBuilder builder = DataSourceBuilder.create();
		builder.url(v.getUrl());
		builder.username(v.getUsername());
		DataSource dataSource = builder.build();
		dataSources.put(k, dataSource);
	});
	return dataSources;
}
```

## 总结

- **先入为主的想法，会让排查思路受困**，不能快速找到问题。例如：出现`too many connections`异常，就直接认为是使用 connection 过程中有问题，其实是创建了太多的连接池，间接持有了很多 connection 导致的。

- 对于所使用的 DataSource，以及 jdbc 底层的执行机制不了解，导致**排查过程中疑点众多，不能快速定位**。

- 从线上的异常堆栈也能看出来，是初始化数据源过程抛出异常。因为不了解 HikariDataSource 工作机制，忽略这个重要信息。

- 框架和工具的自动化处理，让编程工作变得更加方便。例如: jdbc connection close 模板代码，已经没有必要。

## 扩展知识

### 异常信息是哪里来的？

> Could not create connection to database server. Attempted reconnect 3 times. Giving up. -- mysql-connector-java-5.1.47.jar

#### MySQL connection 配置

```java
// 启用自动连接，HighAvailability
private BooleanConnectionProperty autoReconnect = new BooleanConnectionProperty("autoReconnect", false, Messages.getString("ConnectionProperties.autoReconnect"), "1.1", HA_CATEGORY, 0);

// 最多尝试连接次数，默认 3 次。
private IntegerConnectionProperty maxReconnects = new IntegerConnectionProperty("maxReconnects", 3, 1, Integer.MAX_VALUE, Messages.getString("ConnectionProperties.maxReconnects"), "1.1", HA_CATEGORY, 4);

// 异常提示配置 mysql-connector-java-5.1.47.jar!\com\mysql\jdbc\LocalizedErrorMessages.properties
Connection.UnableToConnectWithRetries=Could not create connection to database server. \
Attempted reconnect {0} times. Giving up.
```

#### MySQL Driver 创建连接

```java
// autoReconnect 
public void createNewIO(boolean isForReconnect) throws SQLException {
    synchronized (getConnectionMutex()) {
        // jdbc.url autoReconnect 指定为 true，识别为 HighAvailability
        if (!getHighAvailability()) {
            connectOneTryOnly(isForReconnect, mergedProps);
            return;
        }
        // maxReconnects 默认为 3，重试失败的提示就是： Attempted reconnect 3 times. Giving up.
        connectWithRetries(isForReconnect, mergedProps);
    }
}
```

### MySQL 相关操作

```sql
-- 查看最大连接数
show variables LIKE "max_connections"

-- 修改最大连接数（临时修改）
set GLOBAL max_connections=1024
```

### About Pool Sizing

[About Pool Sizing · brettwooldridge/HikariCP Wiki · GitHub](https://github.com/brettwooldridge/HikariCP/wiki/About-Pool-Sizing)

- Even a computer with one CPU core can "simultaneously" support dozens or hundreds of threads. But we all [should] know that this is merely a trick by the operating system though the magic of *time-slicing*. 并发和并行的区别。

- In reality, that single core can only execute *one* thread at a time; then the OS switches contexts and that core executes code for another thread, and so on. 多线程的切换是有代价的。

- When we look at what the major bottlenecks for a database are, they can be summarized as three basic categories: *CPU*, *Disk*, *Network*. 数据库性能分析点

- On a server with 8 computing cores, setting the number of connections to 8 would provide optimal performance, and anything beyond this would start slowing down due to the overhead of context switching. 理想情况

- And it is during this time that the OS could put that CPU resource to better use by executing some more code for another thread. So, because threads become blocked on I/O, we can actually get more work done by having a number of connections/threads that is greater than the number of physical computing cores. 综合各种情况，需要一套公式和压测，决定如何充分发挥服务器性能



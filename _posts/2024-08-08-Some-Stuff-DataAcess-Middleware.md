---
layout: post
title:  "数据层中间件使用二三事"
date:   2024-08-08 17:50:00 +0800
categories: 实战问题
tags: Spring DataSource Mybatis 事务控制
---

* content
{:toc}

> 近期在运维和改造旧系统的过程中，遇到了几个Mybatis 缓存、Spring 事务管理、数据库连接池影响事务隔离级别的问题。
> 
> 特此记录问题的场景和主要原因，方便后续避坑和查阅。

## Mybatis 一级缓存

### ①问题场景

使用 Mybatis 从数据库中查询的数据，再次查询发现前后两次查询结果不一致。

问题场景的代码示例：

```java
BlogMapper bMapper = session.getMapper(BlogMapper.class);
Blog blog = bMapper.selectBlog(2);
System.out.println(blog.getName());
blog.setName("changed");
// 再次查询相同的数据时，MyBatis 会直接从缓存中获取结果，而不再执行 SQL 语句。
Blog blog2 = bMapper.selectBlog(2);
// 打印结果："changed"。 blog 和 blog2 为同一对象。🎈
System.out.println(blog2.getName());
```

### ②分析过程

> 由于业务逻辑比较复杂，第一次查询的结果，在其他方法中对属性重新赋值。导致的现象比较奇怪。
> 
> 通过开启 debug日志，打印 Mybatis SQL, 第二次查询没有发起 SQL 请求（再次执行相同的 SQL 语句时，MyBatis 会直接从缓存中获取结果，而不再发送 SQL 请求到数据库）。
> 
> Mybatis 使用了一级缓存。两次查询结果是同一对象。

```java
/**
 * 一级缓存是 MyBatis 默认开启的缓存机制，它是基于 SqlSession 级别的缓存。
 * @see BaseExecutor#query(MappedStatement, Object, RowBounds, ResultHandler, CacheKey, BoundSql)
 */
public <E> List<E> query(MappedStatement ms, Object parameter, RowBounds rowBounds, ResultHandler resultHandler, CacheKey key, BoundSql boundSql) throws SQLException {
	// By default, flushCacheRequired is false for select statements
	if (queryStack == 0 && ms.isFlushCacheRequired()) {
		clearLocalCache();
	}
	try {
		// 相同 SQL (CacheKey 一样)再次查询，直接从缓存中获取结果。
		list = resultHandler == null ? (List<E>) localCache.getObject(key) : null;
		if (list != null) {
			handleLocallyCachedOutputParameters(ms, key, parameter, boundSql);
		} else {
			// 发送 SQL 请求到数据库
			list = queryFromDatabase(ms, parameter, rowBounds, resultHandler, key, boundSql);
		}
	}
	return list;
}
```

### ③相关知识

- MyBatis 一级缓存（Local Cache）是 MyBatis 默认开启的缓存机制，它是基于 SqlSession 级别的缓存。

- 缓存失效场景：执行 SqlSession 的增删改操作（如 insert, update, delete），会清空一级缓存。



## Spring 事务嵌套

### ①问题场景

为了解决**大事务**更新过程中，多事务间数据不可见的问题。

在后置处理方法中开启新事务，调整事务隔离级别为 **READ_UNCOMMITTED**。方便汇总计算逻辑可以及时共享数据。

带来的问题是： 有一定概率抛出异常 *CannotAcquireLockException*

> Error updating database.  Cause: java.sql.SQLException: Lock wait timeout exceeded; try restarting transaction

### ②分析过程

开启新事务，用的是 Spring事务管理 `REQUIRES_NEW` 传播行为。

将当前事务 A 挂起，创建一个新的事务 B。

事务 A 中发起某条数据的update, 尚未提交。事务 B 同样发起这条数据的 update, 导致超时锁等待异常。

参考数据库的锁机制： [Insight h2database 更新、读写锁以及事务原理](./2023-10-08-Insight-h2database-update-execute-locks-transaction.md)

### ③总结

- 这个问题是个典型的资源竞争 **(Resource Contention)**/死锁 **(Deadlock)** 问题。

- 使用Spring 事务嵌套，需要特别注意更新数据的边界。尽量有充分的测试和验证，避免线上事故。

## DBCP 事务隔离级别失效

### ①问题场景

在Spring 事务管理中，通过配置 `Isolation.READ_UNCOMMITTED` ，修改当前会话/数据库连接的事务隔离级别。

在测试验证中，其他事务更新过程中的数据，当前事务中 select 结果中没有。

也就是说，事务隔离级别并没有生效。

### ②分析过程

排查思路：使用 JdbcTemplate 以及原生 Jdbc API 开启事务隔离级别，把问题范围缩小并定位到数据库连接池组件（DBCP）上。

```java
/**
 * 验证数据库连接的有效性
 * @param sql 如果sql参数是null或为空字符串，代码会调用连接的isValid(timeout)方法来检查连接是否有效。
 *            如果sql参数不为null，代码会执行这条SQL作为一个查询，并检查结果集（ResultSet）是否至少包含一行。
 * @see org.apache.commons.dbcp2.PoolableConnectionFactory#validateConnection
 * @see org.apache.commons.dbcp2.PoolableConnection#validate
 */
public void validate(final String sql, int timeout) throws SQLException {
	if (sql == null || sql.length() == 0) {
		// java.sql.Connection.isValid
		if (!isValid(timeout)) {
			throw new SQLException("isValid() returned false");
		}
		return;
	}

	if (!sql.equals(lastValidationSql)) {
		lastValidationSql = sql;
		// 此处创建了prepareStatement， 并缓存到当前 connection ❌
		validationPreparedStatement = getInnermostDelegateInternal().prepareStatement(sql);
	}
}
```

👉DBCP validationQuery 事务隔离级别失效 Example. [TransactionIsolationExample](https://github.com/MrRobot5/java-snippet/blob/main/jdbc/src/main/java/com/foo/example/TransactionIsolationExample.java)

Spring 事务开启前、数据库连接池获取 Connection 之前，由于DBCP 已经创建了 prepareStatement， 导致后续再次设置事务隔离级别失效。





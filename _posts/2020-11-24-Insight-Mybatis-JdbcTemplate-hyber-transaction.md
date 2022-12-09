---
layout: post
title:  "Insight Mybatis JdbcTemplate 混合事务控制的实现"
date:   2020-11-24 21:45:24 +0800
categories: jekyll update
---
# Insight Mybatis JdbcTemplate 混合事务控制的实现

## 混合使用的背景

最近项目中需要引入工作流引擎，实现业务和流程设计、流转的解耦。

工作流流引擎选用的是snaker，轻量、易上手、可定制。访问数据库用的是JdbcTemplate 。

项目中原有的持久层框架是Mybatis。

这样就带来一个`问题：怎样保证业务逻辑(Mybatis) 和工作流流引擎(JdbcTemplate )处于事务控制中`，避免数据异常。

比如：业务单据创建成功后，审批流程启动。如果单据创建成功，审批流程启动异常，事务就应该回滚，否则就成僵尸单据了。

## 混合事务控制的配置

```xml
<!-- 按照正常的Spring事务管理配置即可，黑魔法在框架的扩展上体现。 -->
<tx:annotation-driven proxy-target-class="true" />

<bean class="org.springframework.jdbc.datasource.DataSourceTransactionManager">
    <property name="dataSource" ref="dataSource" />
</bean>
```

## 混合事务控制的分析

首先，事务控制的原理是通过AOP进行事务增强，实现数据连接事务的开启、提交或者回滚。

然后，事务控制的核心是开启事务后，会把对应的Connection 关联到当前的线程中，所有关联的数据库操作，使用的都是这个Connection，才能保证逻辑事务的完整性。

所以，Mybatis 和JdbcTempate 混合事务控制，保证数据一致性，`关键就是保证不同框架获取到的是事务开启后的同一个Connection 对象`。剩下的就是AOP 拦截器实现提交或者回滚即可。

## Insight Mybatis 事务的开启

**关键类**：

org.mybatis.spring.transaction.SpringManagedTransactionFactory

org.mybatis.spring.SqlSessionTemplate.SqlSessionInterceptor

**工作原理** 

```java
/**
 * 动态代理 SqlSession，拦截对应的方法，事务相关的操作托管给Spring's Transaction Manager
 * 通过这个InvocationHandler， 把所有的Mybatis 数据库操作的getSqlSession 都委托给Spring 处理，偷天换日。
 * 核心实现：
 * 给当前线程绑定一个 SqlSession对象，这样就能够保证后续的持久化操作获取的都是这个 SqlSession对象。
 */
private class SqlSessionInterceptor implements InvocationHandler {
	@Override
	public Object invoke(Object proxy, Method method, Object[] args) throws Throwable {
        // 从Spring事务管理器获取 sqlSession，或者在需要时创建一个新sqlSession。
        // Retrieve a sqlSession for the given key that is bound to the current thread.
        // @see SqlSessionUtils#getSqlSession
		SqlSession sqlSession = getSqlSession(...);
		try {
			Object result = method.invoke(sqlSession, args);
			if (!isSqlSessionTransactional(sqlSession, SqlSessionTemplate.this.sqlSessionFactory)) {
				// force commit even on non-dirty sessions because some databases require
				// a commit/rollback before calling close()
				sqlSession.commit(true);
			}
			return result;
		} catch (Throwable t) {
			// ...
		}
	}
}

```

```java
/**
 * 管理从Spring's transaction manager 获取的 connection
 * 如果事务管理是启用状态，那么commit/rollback/close 操作统一交给事务管理器去完成。
 */
public class SpringManagedTransaction implements Transaction {

    @Override
    public Connection getConnection() throws SQLException {
        if (this.connection == null) {
            openConnection();
        }
        return this.connection;
    }

    /**
     * Gets a connection from Spring transaction manager and discovers if this
     * {@code Transaction} should manage connection or let it to Spring.
     * <p>
     * It also reads autocommit setting because when using Spring Transaction MyBatis
     * thinks that autocommit is always false and will always call commit/rollback
     * so we need to no-op that calls.
     */
    private void openConnection() throws SQLException {
        // 获取的Connection 操作，会检测是否启用了事务管理器。如果有事务管理器，会给当前线程绑定或者获取一个 Connection对象。 （Will bind a Connection to the thread if transaction synchronization is active）
        this.connection = DataSourceUtils.getConnection(this.dataSource);
        this.autoCommit = this.connection.getAutoCommit();
        this.isConnectionTransactional = DataSourceUtils.isConnectionTransactional(this.connection, this.dataSource);
    }
}
```

## Insight JdbcTempate 事务的开启

```java
public <T> T execute(CallableStatementCreator csc, CallableStatementCallback<T> action) {
	// 和Mybatis SpringManagedTransaction 获取Connection 调用同样的方法。
	Connection con = DataSourceUtils.getConnection(getDataSource());
	CallableStatement cs = null;
	try {
		cs = csc.createCallableStatement(conToUse);
		applyStatementSettings(cs);
		T result = action.doInCallableStatement(csToUse);
		handleWarnings(cs);
		return result;
	}
	catch (SQLException ex) {
		// ...
	}
	finally {
		JdbcUtils.closeStatement(cs);
		DataSourceUtils.releaseConnection(con, getDataSource());
	}
}
```

## 总结

- `Mybatis JdbcTemplate 获取Connection 的方式殊途同归`，保证获取的是同一个 Connection。
- Mybatis 事务启用后，会给当前的线程注册两个对象，SqlSession 和 Connection。
- 如果Spring 事务是否启用的判断方式是根据`当前线程的ThreadLocal 是否有初始化`。
- 如果需要把事务托管给Spring，最简单的是通过 `DataSourceUtils.getConnection` 获取连接。
- 借鉴Spring 框架的集成Mybatis 的方式，为后续的通用设计提供参考。
















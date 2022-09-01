# Insight Mybatis 日志打印

## 日志打印引发的疑问

> 在使用Mybatis 查询过程中，会有如下日志打印：
>
> *DEBUG com.foo.dao.FooMapper.selectFooList - <== Total: 276*
>
> 我们知道，Mybatis 只有接口，并不存在日志中的这个类和对应的方法，那么Mybatis 执行日志是怎么打印的？

## Insight 分析和总结

1. MappedStatement 初始化过程中，初始对应的logger，`logger 的name即mappedStatementId，也就是接口名 + 方法名`
2. 如果当前应用的日志isDebugEnabled()，那么`Mybatis 会在对 Connection、PreparedStatement、ResultSet 进行动态代理`。这样，就会分别打印出需要执行的SQL、SQL入参、结果集等。
3. 动态代理的实现类有：`ConnectionLogger、PreparedStatementLogger、ResultSetLogger`，都是实现了InvocationHandler。
4. 如果应用的日志级别为TRACE， Mybatis 会详细的打印出ResultSet 的所有返回数据。
5. Mybatis 能实现基于接口的数据库操作，就是基于动态代理的实现的。动态代理的使用在Mybatis 的实现中随处可见。
6. `既然一个类对应一个代理实现类，那么能不能用静态代理去实现呢？`如果是全部的方法增强，那么可以静态代理，如果是个别方法去增强，那么还是动态代理更加方便和灵活。打印日志只需要对个别的方法进行拦截，在不侵入原有数据库从操作逻辑的前提下，还是动态代理更加合适。

## 源码分析

### 日志增强的切入点

```java
/**
 * 获取DB Connection
 * 如果DEBUG日志级别，会对获取的connection 进行日志增强代理。
 * @param statementLog 根据 MappedStatement.getStatementLog() 获得。MappedStatement 初始化过程中，会针对每个Mapper 接口的方法，初始对应的logger，即statementLog = LogFactory.getLog(logId)
 * 
 * @from org.apache.ibatis.executor.BaseExecutor#getConnection
 */
protected Connection getConnection(Log statementLog) throws SQLException {
	Connection connection = transaction.getConnection();
	if (statementLog.isDebugEnabled()) {
		// 针对日志DEBUG级别，会对当前的connection 进行代理，通过statementLog 打印日志和传递Logger
		return ConnectionLogger.newInstance(connection, statementLog, queryStack);
	} else {
		return connection;
	}
}
```



### 结果集打印的实现

```java
/**
 * JDBC 查询结果集的日志增强实现。
 * ResultSetLogger 实现InvocationHandler 接口，拦截 java.sql.ResultSet#next， 对查询结果进行统计和打印
 */
public final class ResultSetLogger extends BaseJdbcLogger implements InvocationHandler {

	@Override
	public Object invoke(Object proxy, Method method, Object[] params) throws Throwable {
		try {
			if (Object.class.equals(method.getDeclaringClass())) {
				return method.invoke(this, params);
			}
			Object o = method.invoke(rs, params);
            // 拦截next() 方法，进行row count统计和结果数据打印。 
			if ("next".equals(method.getName())) {
				if (((Boolean) o)) {
					rows++;
                    // 如果应用的日志级别为TRACE， Mybatis 会详细的打印出ResultSet 的所有返回数据。
					if (isTraceEnabled()) {
						ResultSetMetaData rsmd = rs.getMetaData();
						final int columnCount = rsmd.getColumnCount();
						if (first) {
							first = false;
							printColumnHeaders(rsmd, columnCount);
						}
						printColumnValues(columnCount);
					}
				} else {
                    // 结果集遍历完后，打印 Total 信息，解答本文的疑问。
					debug("     Total: " + rows, false);
				}
			}
			clearColumnInfo();
			return o;
		} catch (Throwable t) {
			throw ExceptionUtil.unwrapThrowable(t);
		}
	}
}
```

### Mybatis 日志打印配置

```xml
<?xml version="1.0" encoding="UTF-8"?>
<Configuration status="WARN">
    <properties>
        <property name="patternlayout">%d{HH:mm:ss} [%t] %p %c - %m%n</property>
    </properties>

    <Appenders>
        <Console name="Console" target="SYSTEM_OUT" follow="true">
            <PatternLayout pattern="${patternlayout}"/>
        </Console>
    </Appenders>

    <Loggers>
        <Root level="INFO">
            <AppenderRef ref="Console"/>
        </Root>
        <!-- name对应Mapper 所在的包路径下 -->
        <Logger name="com.foo.dao" level="TRACE" additivity="true"/>
    </Loggers>
</Configuration>

```


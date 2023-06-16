---
layout: post
title:  "ShardingJDBC 读写分离路由机制实现原理"
date:   2022-09-08 18:11:28 +0800
categories: 源码阅读
tags: ShardingJDBC
---
* content
{:toc}

> ShardingSphere-JDBC 支持分库分表和读写分离。
> 
> 是一种Datasource 实现，通过托管原有的Datasource，根据策略实现请求分发/路由。本文关注读写分离的主要实现。

## 读写分离配置

```yaml
spring
  shardingsphere
	  master-slave:
		name: ds_ms
		master-data-source-name: ds_master
		slave-data-source-names: 
		  - ds_slave0
		  - ds_slave1
```

```xml
<?xml version="1.0" encoding="UTF-8"?>
<beans>
    <!-- 4.0.0-RC2 之后版本 负载均衡策略配置方式 -->
    <master-slave:load-balance-algorithm id="randomStrategy" type="RANDOM" />

    <master-slave:data-source id="masterSlaveDataSource" master-data-source-name="ds_master" slave-data-source-names="ds_slave0, ds_slave1" strategy-ref="randomStrategy">
        <master-slave:props>
            <prop key="sql.show">true</prop>
            <prop key="executor.size">10</prop>
        </master-slave:props>
    </master-slave:data-source>
</beans>
```

### 参考文档

[Spring命名空间配置 :: ShardingSphere](https://shardingsphere.apache.org/document/legacy/4.x/document/cn/manual/sharding-jdbc/configuration/config-spring-namespace/#%E8%AF%BB%E5%86%99%E5%88%86%E7%A6%BB)

[Yaml配置 :: ShardingSphere](https://shardingsphere.apache.org/document/legacy/4.x/document/cn/manual/sharding-jdbc/configuration/config-yaml/)



## Primary Class

### 配置解析

- org.apache.shardingsphere.shardingjdbc.spring.namespace.handler.MasterSlaveNamespaceHandler 命名空间（master-slave）处理器

- org.apache.shardingsphere.shardingjdbc.spring.namespace.parser.MasterSlaveDataSourceBeanDefinitionParser Xml 配置文件解析

- org.apache.shardingsphere.core.yaml.config.masterslave.YamlMasterSlaveRuleConfiguration Yaml 文件配置

- org.apache.shardingsphere.shardingjdbc.jdbc.core.datasource.MasterSlaveDataSource 读写分离数据源（数据源代理）



### 读写路由

- org.apache.shardingsphere.shardingjdbc.jdbc.core.connection.MasterSlaveConnection **Jdbc-Connection**

- org.apache.shardingsphere.shardingjdbc.jdbc.core.statement.MasterSlavePreparedStatement **Jdbc-Statement**

- org.apache.shardingsphere.core.route.router.masterslave.**MasterSlaveRouter**
  
  

## Code Insight

```java
public final class MasterSlaveRouter {
    
    /**
     * Route Master slave.
     */
    public Collection<String> route(final String sql) {
		// 判断Sql 类型，然后根据策略，判断使用哪个数据源
        Collection<String> result = route(new SQLJudgeEngine(sql).judge().getType());
        if (showSQL) {
             // log.info("SQL: {} ::: DataSources: {}") 方便调试
             SQLLogger.logSQL(sql, result);
        }
        return result;
    }
    
	// 根据以下策略，判断使用主库 或者 从库（只读库）
    private Collection<String> route(final SQLType sqlType) {
        if (isMasterRoute(sqlType)) {
            // 当前MasterSlaveConnection 使用过主库
            MasterVisitedManager.setMasterVisited();
            return Collections.singletonList(masterSlaveRule.getMasterDataSourceName());
        }
        return Collections.singletonList(masterSlaveRule.getLoadBalanceAlgorithm().getDataSource(
                masterSlaveRule.getName(), masterSlaveRule.getMasterDataSourceName(), new ArrayList<>(masterSlaveRule.getSlaveDataSourceNames())));
    }
    
	// 使用主库策略：非查询Sql || 已经访问过主库（兼容事务） || 指定使用主库
    private boolean isMasterRoute(final SQLType sqlType) {
        return SQLType.DQL != sqlType || MasterVisitedManager.isMasterVisited() || HintManager.isMasterRouteOnly();
    }
}
```

## Topic 事务控制-读写数据一致

> 如果拆分读写库，由于主从同步的延时，应用肯定存在读写数据不一致的情况。框架是如何解决的？

前提：Spring 事务控制，启用事务的情况下，MasterSlaveConnection 会绑定到当前的线程。

分析：参考上述的 `isMasterRoute` 判断策略，对于 isMasterVisited 的情况，及时是查询SQL，也是走主库，保障写入和查询处于同一个Session。

```java
// see MasterSlaveConnection
public final void close() throws SQLException {
	// 逻辑关闭 MasterSlaveConnection
	closed = true;
	// 清除主库访问标识，针对读写分离的场景。
	MasterVisitedManager.clear();
	TransactionTypeHolder.clear();
	int connectionSize = cachedConnections.size();
	try {
		forceExecuteTemplateForClose.execute(cachedConnections.entries(), new ForceExecuteCallback<Entry<String, Connection>>() {
	
			@Override
			public void execute(final Entry<String, Connection> cachedConnections) throws SQLException {
				// actual connection.close(); 下层的数据源实现
				cachedConnections.getValue().close();
			}
		});
	} finally {
		cachedConnections.clear();
		rootInvokeHook.finish(connectionSize);
	}
}
```

结论：开启事务，如果有DDL 执行，那么之后的所有访问都是主库。全程由 MasterVisitedManager 来控制。

### Bad Case

```java
// @Transactional 如果启用事务，insert selectAll 会使用相同Connection， 并且 setMasterVisited = true 
@Override
public List<User> saveOne(User user) {
	user.setUpdateTime(new Date());
	userMapper.insert(user);
	// 未开启事务的场景下，selectAll 使用的Connection 与上述的insert 不同。insert 使用主库，selectAll 使用从库
	// 如果遇到主从延时，selectAll 就查不到上述insert 的数据。不可知的问题。
	List<User> users = userMapper.selectAll();
	return users;
}
```



## 总结

- 简单来说，只要是查询 SQL，默认就会使用从库查询，简单好用。

- 框架作用于 Jdbc 层，无感知适配所有的 ORM 持久层框架。

- 对于事务的问题，一定要加 @Transaction，避免不必要的诡异问题出现。

- 每个大版本的变化很大，文档很重要。做开源非常不容易。规划/开发/fix/文档/宣传



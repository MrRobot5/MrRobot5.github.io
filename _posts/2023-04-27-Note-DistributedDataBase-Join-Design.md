---
layout: post
title:  "笔记 分布式数据库 Join 查询思路"
date:   2023-04-27 20:49:40 +0800
categories: jekyll update
---

# 笔记 分布式数据库 Join 查询思路

> 相对于单例数据库的查询操作，分布式数据查询会有很多技术难题。
> 
> 本文记录 Mysql 分库分表 和 Elasticsearch Join 查询的实现思路，学习分布式场景数据处理的设计思路。

## Mysql 分库分表 Join 查询场景

> 分库分表场景下，查询语句如何分发，数据如何组织。相较于NoSQL 数据库，Mysql 在SQL 规范的范围内，相对比较容易适配分布式场景。
> 
> 基于 sharding-jdbc 中间件的方案，了解整个设计思路。

### sharding-jdbc

- sharding-jdbc 代理了原始的 datasource, 实现 jdbc 规范来完成分库分表的分发和组装，应用层无感知。

- 执行流程：SQL解析 => 执行器优化 => **SQL路由** => SQL改写 => SQL执行 => **结果归并** `io.shardingsphere.core.executor.ExecutorEngine#execute`

- Join 语句的解析，决定了要分发 SQL 到哪些实例节点上。对应SQL路由。

- SQL 改写就是要把原始（逻辑）表名，改为实际分片的表名。

- 复杂情况下，**Join 查询分发的最多执行的次数** = 数据库实例 × 表A分片数 × 表B分片数

### Code Insight

示例代码工程：git@github.com:cluoHeadon/sharding-jdbc-demo.git

```java
/**
 * 执行查询 SQL 切入点，从这里可以完整 debug 执行流程
 * @see ShardingPreparedStatement#execute()
 * @see ParsingSQLRouter#route(String, List, SQLStatement) Join 查询实际涉及哪些表，就是在路由规则里匹配得出来的。
 */
public boolean execute() throws SQLException {
	try {
		// 根据参数（决定分片）和具体的SQL 来匹配相关的实际 Table。
		Collection<PreparedStatementUnit> preparedStatementUnits = route();
		// 使用线程池，分发执行和结果归并。
		return new PreparedStatementExecutor(getConnection().getShardingContext().getExecutorEngine(), routeResult.getSqlStatement().getType(), preparedStatementUnits).execute();
	} finally {
		JDBCShardingRefreshHandler.build(routeResult, connection).execute();
		clearBatch();
	}
}
```



### SQL 路由策略

启用 sql 打印，直观看到实际分发执行的 SQL

```properties
# 打印的代码，就是在上述route 得出 ExecutionUnits 后，打印的
sharding.jdbc.config.sharding.props.sql.show=true
```

sharding-jdbc 根据不同的SQL 语句，会有不同的路由策略。我们关注的 Join 查询，实际相关就是以下两种策略。

- StandardRoutingEngine **binding-tables 模式**

- ComplexRoutingEngine 最复杂的情况，**笛卡尔组合关联关系**。

```sql
-- 参数不明，不能定位分片的情况
select * from order o inner join order_item oi on o.order_id = oi.order_id 

-- 路由结果
-- Actual SQL: db1 ::: select * from order_1 o inner join order_item_1 oi on o.order_id = oi.order_id 
-- Actual SQL: db1 ::: select * from order_1 o inner join order_item_0 oi on o.order_id = oi.order_id 
-- Actual SQL: db1 ::: select * from order_0 o inner join order_item_1 oi on o.order_id = oi.order_id 
-- Actual SQL: db1 ::: select * from order_0 o inner join order_item_0 oi on o.order_id = oi.order_id 
-- Actual SQL: db0 ::: select * from order_1 o inner join order_item_1 oi on o.order_id = oi.order_id 
-- Actual SQL: db0 ::: select * from order_1 o inner join order_item_0 oi on o.order_id = oi.order_id 
-- Actual SQL: db0 ::: select * from order_0 o inner join order_item_1 oi on o.order_id = oi.order_id 
-- Actual SQL: db0 ::: select * from order_0 o inner join order_item_0 oi on o.order_id = oi.order_id
```



## Elasticsearch Join 查询场景

> 首先，对于 NoSQL 数据库，要求 Join 查询，可以考虑是不是使用场景和用法有问题。
> 
> 然后，不可避免的，有些场景需要这个功能。Join 查询的实现更贴近SQL 引擎。
> 
> 基于 elasticsearch-sql 组件的方案，了解大概的解决思路。

### elasticsearch-sql

- 这是个elasticsearch 插件，通过提供http 服务实现类 SQL 查询的功能，高版本的elasticsearch 已经具备该功能

- 因为 elasticsearch 没有 Join 查询的特性，所以实现 SQL Join 功能，需要提供更加底层的功能，涉及到 Join 算法。

### Code Insight

```java
/**
 * Execute the ActionRequest and returns the REST response using the channel.
 * @see org.elasticsearch.plugin.nlpcn.executors.ElasticDefaultRestExecutor#execute
 */
@Override
public void execute(Client client, Map<String, String> params, QueryAction queryAction, RestChannel channel) throws Exception{
	// sql parse
	SqlElasticRequestBuilder requestBuilder = queryAction.explain();
	
	// join 查询
	if(requestBuilder instanceof JoinRequestBuilder){
		// join 算法选择。包括：HashJoinElasticExecutor、NestedLoopsElasticExecutor
		ElasticJoinExecutor executor = ElasticJoinExecutor.createJoinExecutor(client,requestBuilder);
		executor.run();
		executor.sendResponse(channel);
	}
	// 其他类型查询 ...
}
```

### Join 算法

参考 

- [如何在分布式数据库中实现 **Hash Join**](https://zhuanlan.zhihu.com/p/35040231)

- [**Nested Loop Join***](https://zhuanlan.zhihu.com/p/81398139)

分别对应上述的两种算法实现。



## 总结

通过运行原理分析，对于运行流程有了清晰和深入的认知。

对于中间件的优化更加有目的性，使用上会更加谨慎和小心。













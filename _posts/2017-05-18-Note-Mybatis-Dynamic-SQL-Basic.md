---
layout: post
title:  "Note-Mybatis-动态 SQL 解析相关知识"
date:   2017-05-18 20:13:45 +0800
categories: 学习笔记
tags: Mybatis
---

* content
{:toc}

记录 Mybatis 动态 SQL、字符串替换相关的实现，方便后续源码阅读和借鉴。

# Dynamic SQL

[MyBatis 3 | Dynamic SQL](https://mybatis.org/mybatis-3/dynamic-sql.html)

> One of the most powerful features of MyBatis has always been its Dynamic SQL capabilities. OGNL based expressions.

## 使用示例

```xml
<select id="findActiveBlogLike" resultType="Blog">
  SELECT * FROM BLOG
  <!-- 只有在包含的标签返回任何内容时才会插入"WHERE"子句。如果内容以"AND"或"OR"开头，自动会将其去掉。 -->
  <where>
    <if test="title != null">
        AND title like #{title}
    </if>
    <if test="author != null and author.name != null">
        AND author_name like #{author.name}
    </if>
  </where>
</select>
```

## 标签解析实现类

```java
// org.apache.ibatis.scripting.xmltags.XMLScriptBuilder#initNodeHandlerMap
private void initNodeHandlerMap() {
	nodeHandlerMap.put("trim", new TrimHandler());
	nodeHandlerMap.put("where", new WhereHandler());
	nodeHandlerMap.put("set", new SetHandler());
	nodeHandlerMap.put("foreach", new ForEachHandler());
	nodeHandlerMap.put("if", new IfHandler());
	nodeHandlerMap.put("choose", new ChooseHandler());
	nodeHandlerMap.put("when", new IfHandler());
	nodeHandlerMap.put("otherwise", new OtherwiseHandler());
	nodeHandlerMap.put("bind", new BindHandler());
}
```

# 字符串替换

## 使用示例

```java
// dynamic SQL in annotated mapper class
@Select("select * from user where name = #{name} ORDER BY ${columnName}")
User findByName(@Param("name") String name);
```

## 参数注解语法使用场景

使用 `#{}` 语法可以生成 PreparedStatement 属性，参数注解替换为 PreparedStatement参数（占位符？）。防止 SQL 拼接注入等安全问题。

使用 `${}` 语法直接将未修改的字符串替换到SQL语句中，MyBatis不会修改或转义字符串。当 SQL 语句中的元数据（即表名或列名）是动态的时，字符串替换非常有用。



# 核心解析实现

## 查询主流程

```java
/**
 * select 查询执行主流程
 * @see org.apache.ibatis.session.defaults.DefaultSqlSession#selectList(java.lang.String, java.lang.Object, org.apache.ibatis.session.RowBounds)
 */
public List selectList(String statement, Object parameter, RowBounds rowBounds) {
	try {
		// 1. 根据 mapper 方法名称，从configuration 取出对应的 statement 主要就是动态sql xml片段
		MappedStatement ms = configuration.getMappedStatement(statement);
		// 2. 根据配置的 statement，执行查询，返回结果集
		List result = executor.query(ms, wrapCollection(parameter), rowBounds, Executor.NO_RESULT_HANDLER);
		return result;
	}
}

/**
 * 解析动态 sql，执行 sql 查询
 * @see org.apache.ibatis.executor.BaseExecutor#query(org.apache.ibatis.mapping.MappedStatement, java.lang.Object, org.apache.ibatis.session.RowBounds, org.apache.ibatis.session.ResultHandler)
 */
public List query(MappedStatement ms, Object parameter, RowBounds rowBounds, ResultHandler resultHandler) throws SQLException {
	// 动态sql就是在这个阶段完成解析，形成标准的sql 语句， eg: select * from dual where id = ?
	BoundSql boundSql = ms.getBoundSql(parameter);
	CacheKey key = createCacheKey(ms, parameter, rowBounds, boundSql);
	return query(ms, parameter, rowBounds, resultHandler, key, boundSql);
}
```

## 动态 SQL 解析主流程

```java
// 动态 sql 核心实现
// @see org.apache.ibatis.scripting.xmltags.DynamicSqlSource#getBoundSql
public BoundSql getBoundSql(Object parameterObject) {
    DynamicContext context = new DynamicContext(configuration, parameterObject);
    //1. 纯文本解析，包括 TextSqlNode, ForEachSqlNode, IfSqlNode, VarDeclSqlNode, TrimSqlNode, WhereSqlNode, SetSqlNode, ChooseSqlNode
    // 其中 ${columnName} 表达式实例化为 TextSqlNode，@see new GenericTokenParser("${", "}", new BindingTokenParser(context))
    rootSqlNode.apply(context);
    SqlSourceBuilder sqlSourceParser = new SqlSourceBuilder(configuration);
    Class parameterType = parameterObject == null ? Object.class : parameterObject.getClass();
    //2. 带有关联参数解析，prepareStatement 中用到的parameterMappings
    // 其中 #{name} 表达式就是在此处解析，@see new GenericTokenParser("#{", "}", handler);
    SqlSource sqlSource = sqlSourceParser.parse(context.getSql(), parameterType, context.getBindings());
    BoundSql boundSql = sqlSource.getBoundSql(parameterObject);
    
    return boundSql;
}
```

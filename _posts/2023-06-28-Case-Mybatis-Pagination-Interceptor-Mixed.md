---
layout: post
title:  "混合 Mybatis 分页插件集成适配探索"
date:   2023-06-28 20:47:55 +0800
categories: 实战问题
tags: Mybatis
---

* content
{:toc}

在工程服务化拆分过程中，由于不同工程配置差异，基础服务工程融合功能使用 Mybatis 插件有3个。为了集成、调和这些插件，遇到一些问题并总结思考。

## 问题场景

### 1️⃣插件列表

基础服务工程原有 Mybatis 分页插件：

com.baomidou.mybatisplus.extension.plugins.inner.PaginationInnerInterceptor

后续引入的分页插件：

- com.github.pagehelper.PageInterceptor 常用的开源分页插件

- com.foo.interceptor.PaginationInterceptor 内部实现的分页插件

### 2️⃣分页插件配置和使用

问题就出在内部实现的分页插件 PaginationInterceptor，非常的定制化，集成和适配带来很多问题。

```java
@Configuration
public class MybatisPlusConfig {

   // 工程原有的分页插件配置
   // 使用该插件，必须在Mapper 方法中显示声明 IPage 参数，没有 pagehelper 灵活。
   @Bean
    public MybatisPlusInterceptor mybatisPlusInterceptor() {
        MybatisPlusInterceptor interceptor = new MybatisPlusInterceptor();
        interceptor.addInnerInterceptor(new PaginationInnerInterceptor(DbType.MYSQL));
        return interceptor;
    }
	
}
```

```xml
<!-- 利用 PageHelperAutoConfiguration 加载机制，自动注册分页插件 -->
<dependency>
	<groupId>com.github.pagehelper</groupId>
	<artifactId>pagehelper-spring-boot-starter</artifactId>
	<version>1.3.0</version>
</dependency>
```

```xml
<!-- 常规 Mybatis plugin 配置 -->
<!-- PaginationInterceptor 分页针对的是 offset、limit 格式的分页参数，与常规的分页方式格格不入 -->
<configuration>
    <plugins>
		<plugin interceptor="com.foo.interceptor.PaginationInterceptor">
	</plugins>
</configuration>
```

PaginationInterceptor 分页实现思路，简直是灾难 🙉

### 3️⃣为什么不能合并❓

首先，工程服务的迁移是首要目标，上述分页插件使用方式各不相同，如果改写查询方法，耗时较久、浪费人力。

其次，插件的存在就是为了解决批量、共性功能需求存在。分页插件使用节省大量低效开发时间。

综合以上，决定继续引入和集成 PaginationInterceptor。



## 集成插件遇到的问题

### 问题1

借鉴 pagehelper PageHelperAutoConfiguration 集成思路，通过注入 sqlSessionFactory，得到 Mybatis configuration 并注册分页插件，结果遇到了 Spring 循环依赖。

`Error creating bean with name 'sqlSessionFactory': Requested bean is currently in creation: Is there an unresolvable circular reference?`

循环依赖可以通过指定 Bean 依赖顺序可以解决，但是有没有更简单的方式呢？

### 问题2

经过 MybatisPlus 动态代理的处理流程，PaginationInterceptor 分页插件中只能获取到拦截接口的定义，无法通过反射获取 target 真正的属性。

```java
// 拦截 Mybatis StatementHandler
@Intercepts({@Signature(type=StatementHandler.class,method="prepare",args={Connection.class, Integer.class })})
public class PaginationInterceptor implements Interceptor {
   
    @Override
    public Object intercept(Invocation invocation) throws Throwable {
        // 该实例实际上为 org.apache.ibatis.executor.statement.RoutingStatementHandler
        StatementHandler statementHandler = (StatementHandler)invocation.getTarget();
        MetaObject metaStatementHandler = SystemMetaObject.forObject(statementHandler);
        // Exception: There is no getter for property named 'delegate' in 'class com.sun.proxy.$Proxy275'
        MappedStatement mappedStatement = (MappedStatement)metaStatementHandler.getValue("delegate.mappedStatement");
        // ...
	}
	
}
```



### 问题3

PaginationInterceptor 分页插件与 MybatisPlus 分页模板方法的命名重名，从 parameterObject 获到的参数对象只判断 name 会有类型转换异常。



## 解决方案

通过查看 MybatisPlus 的初始化方式，其实配置非常简单。

```java
@Configuration
public class MybatisPlusConfig {
   
    /**
     * 迁移工程代码，引入内部实现的分页插件。
     * 分页声明的顺序很重要。必须在 MybatisPlusInterceptor 之前。
     */
    @Bean
    public PaginationInterceptor addPageInterceptor() {
        return new PaginationInterceptor();
    }

   // 工程原有的分页插件配置
   // 使用该插件，必须在Mapper 方法中显示声明 IPage 参数，没有 pagehelper 灵活。
   @Bean
    public MybatisPlusInterceptor mybatisPlusInterceptor() {
        MybatisPlusInterceptor interceptor = new MybatisPlusInterceptor();
        interceptor.addInnerInterceptor(new PaginationInnerInterceptor(DbType.MYSQL));
        return interceptor;
    }
	
}
```

问题1 借鉴 MybatisPlus 分页插件的配置方式，只需要声明 Bean，注册由 MybatisPlus 完成。MybatisPlus 托管 Mybatis 初始化流程，**借鉴 pagehelper 把问题变复杂了**。

问题2 是插件注册的顺序引起的，如上，调整声明顺序即可。

> 既然是经过 MybatisPlus 处理过的对象无法使用，那解决办法就是不经过 MybatisPlus 处理，调整 Mybatis 插件注册顺序即可😀

问题3 除了参数name 判断，同样需要 instanceof 判断，double check。



运行结果也是各不相同，一言难尽。

```sql
=>  Preparing: SELECT COUNT(*) FROM foo_table
=>  Preparing: SELECT count(0) FROM foo_table  
=>  Preparing: select count(1) count FROM foo_table
```

## Code Insight

由之前的知识点启发，从 org.apache.ibatis.session.Configuration#addInterceptor 着手去分析 MybatisPlus 插件处理流程。

得知，MybatisPlus 初始化的 interceptors 来源于 Spring Bean。

```java
// @see com.baomidou.mybatisplus.autoconfigure.MybatisPlusAutoConfiguration
public MybatisPlusAutoConfiguration(MybatisPlusProperties properties, ObjectProvider<Interceptor[]> interceptorsProvider, ApplicationContext applicationContext) {
	this.properties = properties;
	this.interceptors = interceptorsProvider.getIfAvailable();
	this.applicationContext = applicationContext;
}
```

`ObjectProvider` 为编程式注入而设计的接口，提供了便利的对象获取和处理方法。



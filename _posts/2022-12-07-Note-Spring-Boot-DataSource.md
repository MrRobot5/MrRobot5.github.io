---
layout: post
title:  "Spring Boot DataSource 知识梳理"
date:   2022-12-07 15:56:11 +0800
categories: 学习笔记
tags: SpringBoot DataSource
---
* content
{:toc}

> 梳理 Spring Boot 默认配置的数据库和连接池，以及自定义配置的方法

## database

> Spring Boot gives you **defaults on all things**. For example, the default database is H2.
> 
> Consequently, when you want to use any other database, you must define the connection attributes in the **application.properties** file.

### ①default

```properties
# org.springframework.boot.autoconfigure.jdbc.EmbeddedDatabaseConnection#H2
# 内嵌数据库支持 H2 Derby Hsqldb，首选 H2。
spring.datasource.url=jdbc:h2:mem:%s;DB_CLOSE_DELAY=-1;DB_CLOSE_ON_EXIT=FALSE
spring.datasource.username=sa
spring.datasource.password=
spring.datasource.driver-class-name=org.h2.Driver
```

### ②自定义

```properties
spring.datasource.url=jdbc:mysql://${MYSQL_HOST:localhost}:3306/db_example
spring.datasource.username=springuser
spring.datasource.password=ThePassword
spring.datasource.driver-class-name=com.mysql.cj.jdbc.Driver
#spring.jpa.show-sql: true
```

### ③Code Insight

```java
/**
 * 查找最匹配的 EmbeddedDatabaseConnection
 * Spring Boot 内置EmbeddedDatabaseConnection 配置。作为 DataSourceProperties 托底配置。
 * 如果没有指定的DatabaseConnection，就会取 EmbeddedDatabaseConnection。
 * @see org.springframework.boot.autoconfigure.jdbc.DataSourceProperties
 * @see org.springframework.boot.autoconfigure.jdbc.EmbeddedDatabaseConnection
 */
public static EmbeddedDatabaseConnection get(ClassLoader classLoader) {
	if (override != null) {
		return override;
	}
	// 按照定义顺序，遍历 H2 Derby Hsqldb
	for (EmbeddedDatabaseConnection candidate : EmbeddedDatabaseConnection.values()) {
		// 如果存在数据库 DriverClass，就返回对应数据库的 Connection
		if (candidate != NONE && ClassUtils.isPresent(candidate.getDriverClassName(), classLoader)) {
			return candidate;
		}
	}
	return NONE;
}
```



## DataSource

> 内置初始化支持 DBCP Tomcat-Pool HikariCP
> 
> We prefer HikariCP for its performance and concurrency. If HikariCP is available, we always choose it.

### ①default

根据 `spring-boot-starter-jdbc` 版本的不同，1.x 自动引入 `tomcat-jdbc` ， 2.x 自动引入 `HikariCP`。



### ②自定义

```properties
# 使用 tomcat pool
spring.datasource.type=org.apache.tomcat.jdbc.pool.DataSource
spring.datasource.tomcat.max-wait=10000
spring.datasource.tomcat.max-active=50
spring.datasource.tomcat.test-on-borrow=true

```

### ③Code Insight

```java
static class Hikari {

	@Bean
	// dataSourcet() 执行完成后，给dataSource实例绑定特有的 properties
	@ConfigurationProperties(prefix = "spring.datasource.hikari")
	HikariDataSource dataSource(DataSourceProperties properties) {
		// new DataSource(), 并且绑定基础的属性：jdbcUrl driverClassName username password
		HikariDataSource dataSource = createDataSource(properties, HikariDataSource.class);
		if (StringUtils.hasText(properties.getName())) {
			dataSource.setPoolName(properties.getName());
		}
		return dataSource;
	}

}
```

## Beans annotated with ConfigurationProperties

> 如上述的用法，ConfigurationProperties 如何绑定属性，并且绑定的时机非常关键。

Spring Boot 提供 org.springframework.boot.context.properties.ConfigurationPropertiesBindingPostProcessor 处理器，用来完成Bean 属性的绑定。

```java
/**
 * instance 之后，进行属性绑定，后续 Initialization 能够用到这些属性。
 * @see org.springframework.beans.factory.config.BeanPostProcessor#postProcessBeforeInitialization
 */
public Object postProcessBeforeInitialization(Object bean, String beanName) throws BeansException {
	ConfigurationProperties annotation = AnnotationUtils.findAnnotation(bean.getClass(), ConfigurationProperties.class);
	if (annotation != null) {
		postProcessBeforeInitialization(bean, beanName, annotation);
	}
	annotation = this.beans.findFactoryAnnotation(beanName, ConfigurationProperties.class);
	if (annotation != null) {
		postProcessBeforeInitialization(bean, beanName, annotation);
	}
	return bean;
}
```



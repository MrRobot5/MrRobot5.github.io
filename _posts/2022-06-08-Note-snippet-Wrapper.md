---
layout: post
title:  "包装模式（Wrapper）使用案例"
date:   2022-06-08 11:45:42 +0800
categories: 学习笔记
tags: 设计模式 Spring
---
* content
{:toc}

> 最近读源码，发现包装模式的写法案例。虽然不是严格的包装设计模式，但是能达到封装和适配的效果，简化使用方式和功能扩展。
> 
> 这种编程模式非常实用，实际开发过程中可以借鉴。

## 案例-MimeMessageHelper

> 在 Spring 封装javamail 的实现中，有个MimeMessageHelper 类。
> 
> 通过包装MimeMessage 对象，提供简便的操作API。同时，镜像操作MimeMessage对象，对MimeMessage 直接赋值的操作。

```java
/**
 * 虽然名为Helper, 并不是常用的static Helper。Helper 提供的简便API调用，会直接映射到mimeMessage 对象上
 * 使用方式：new MimeMessageHelper(mimeMessage);
 * @see org.springframework.mail.javamail.MimeMessageHelper
 */
public MimeMessageHelper(MimeMessage mimeMessage) {
	this(mimeMessage, null);
}
```

**借鉴：** 对于复杂的三方插件或者类库封装，可以参考spring 对javamail 的适配。



## 案例-Example

> tk mybatis 支持example 查询，通过Criteria 帮助类包装Example，提供方便的API，直接赋值到example。
> 
> Criteria 的操作 就是Example 的镜像操作。

```java

/**
 * Criteria 是通过example 对象创建的，通过Criteria 提供“set” API
 * 使用：example.createCriteria().andEqualTo("fooName", "foo");
 * @see tk.mybatis.mapper.entity.Example.Criteria
 */
public Criteria createCriteria() {
	// Example 的属性 propertyMap, exists 作为Criteria 构造参数，两者引用的是相同的对象。
	Criteria criteria = new Criteria(propertyMap, exists, notNull);
	return criteria;
}
```

## 总结

面向对象编程，提供了很多设计模式，能够很好的组织代码结构。

虽然有些需要花时间理解（比如：Criteria），但是利用模式，对于工程的扩展和维护有非常大的收益。

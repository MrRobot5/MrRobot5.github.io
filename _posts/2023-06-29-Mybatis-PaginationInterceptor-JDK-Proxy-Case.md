---
layout: post
title:  "Mybatis 分页插件 JDK 动态代理案例分析"
date:   2023-06-29 20:55:57 +0800
categories: 实战问题
tags: Mybatis 问题分析 动态代理 设计模式
---

* content
{:toc}


# 背景

工程A 代码迁移到 工程B 过程中，涉及到分页插件的附带迁移和融合。

工程B 已有 com.github.pagehelper.PageInterceptor、 com.baomidou.mybatisplus.extension.plugins.inner.PaginationInnerInterceptor 前提下。

引入了另外一个分页插件 com.foo.common.interceptor.PaginationInterceptor

## 运行时异常

调用 PaginationInterceptor 分页插件时，报错如下：

> Caused by: org.apache.ibatis.reflection.ReflectionException: There is no getter for property named 'delegate' in 'class com.sun.proxy.$Proxy280'

## 分页插件 PaginationInterceptor

<img src="{{ "/images/mybatis_paginationInterceptor_1.png" | prepend: site.baseurl }}" alt="TransactionsEssentials" style="zoom:50%;" />

# Debug 运行环境差异

## 没有经过代理的对象-工程A 环境

<img src="{{ "/images/mybatis_paginationInterceptor_2.png" | prepend: site.baseurl }}" alt="TransactionsEssentials" style="zoom:50%;" />

## 经过代理的对象-工程B 环境

<img src="{{ "/images/mybatis_paginationInterceptor_3.png" | prepend: site.baseurl }}" alt="TransactionsEssentials" style="zoom:50%;" />

# 动态代理分析

## 分页插件 Pointcut

<img src="{{ "/images/mybatis_paginationInterceptor_4.png" | prepend: site.baseurl }}" alt="TransactionsEssentials" style="zoom:50%;" />



## 问题分析

结合上述的运行环境和插件的拦截配置，问题出在基于接口生产的代理对象上。

- StatementHandler 对象经过了 MybatisPlusInterceptor wrap/动态处理。PaginationInterceptor 拦截处理时，**已经是 Proxy, 而不是原始对象**。PaginationInterceptor 无法访问 Proxy 的 delegate 属性。

- JDK Proxy 是基于接口实现的动态类生成。**StatementHandler** 对象的属性是不会暴露到代理对象中的。**所以出现上述的异常。

## 疑问

1️⃣疑问1： 为什么之前的工程，两个pagehelper 可以和 PaginationInterceptor 正常工作？

因为代理的接口不同，**pagehelper 是针对 Executor 拦截和代理的**。不影响 PaginationInterceptor 针对的StatementHandler。 这样，PaginationInterceptor intercept 获取的 target 是原始的 StatementHandler 对象，可以正常访问 delegate 属性。

```java
// com.baomidou.mybatisplus.extension.plugins.MybatisPlusInterceptor#plugin
@Override
public Object plugin(Object target) {
    if (target instanceof Executor || target instanceof StatementHandler) {
        // 原始的 StatementHandler 对象会在此转为 Proxy 对象
        return Plugin.wrap(target, this);
    }
    return target;
}
```



2️⃣疑问2：如果调整了MybatisPlusInterceptor 和 PaginationInterceptor 插件的顺序，可以解决吗？

可以的。按照上述的分析，未经代理的 StatementHandler 对象先被PaginationInterceptor，就不会出现异常。

```java
// 设计模式是责任链模式（Chain of Responsibility）。
// 处理过程是线性的，一个Interceptor处理完后，下一个Interceptor会接着处理上一个的输出。
public class InterceptorChain {

  private final List<Interceptor> interceptors = new ArrayList<>();

  public Object pluginAll(Object target) {
    for (Interceptor interceptor : interceptors) {
      target = interceptor.plugin(target);
    }
    return target;
  }

}
```



# 参考

## Mybatis Relector Fields 处理

```java
private void addFields(Class<?> clazz) {
	// 取表示类中声明的所有字段。上述的场景中，经过代理的 Proxy 类是没有 Field 🎯
	Field[] fields = clazz.getDeclaredFields();
	for (Field field : fields) {
		if (!setMethods.containsKey(field.getName())) {
			int modifiers = field.getModifiers();
			if (!(Modifier.isFinal(modifiers) && Modifier.isStatic(modifiers))) {
				addSetField(field);
			}
		}
		if (!getMethods.containsKey(field.getName())) {
			addGetField(field);
		}
	}
	// 递归调用，解析和缓存父类的属性
	if (clazz.getSuperclass() != null) {
		addFields(clazz.getSuperclass());
	}
}
```



## Clazz.getDeclaredFields()

- 用于获取表示某个类中声明的所有字段（**包括公共、保护、默认（包）访问和私有字段，但不包括继承的字段**）的 Field 对象数组。

- 这个方法不考虑字段的可访问性，并且只反映了在类声明中直接定义的字段。

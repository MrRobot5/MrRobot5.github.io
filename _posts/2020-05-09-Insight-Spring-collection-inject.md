---
layout: post
title:  "Spring 泛集合注入以及应用"
date:   2020-05-09 18:01:05 +0800
categories: 源码阅读
tags: Spring

---
* content
{:toc}

> 本文关注 Spring 注入泛集合的调用链，以及注入集合的排序问题和应用。
>
> 泛集合是指：Array、Collection、Map。

## Spring 泛集合注入的调用链

`构造注入`方式的调用链（Spring Version >= 4.x）：

* org.springframework.beans.factory.support.ConstructorResolver#autowireConstructor

  提供各种构造器的识别、构造参数实例化的实现

* org.springframework.beans.factory.support.ConstructorResolver#createArgumentArray

* org.springframework.beans.factory.support.ConstructorResolver#resolveAutowiredArgument

* org.springframework.beans.factory.support.DefaultListableBeanFactory#doResolveDependency

  `Spring 依赖注入的核心实现方法`。

* org.springframework.beans.factory.support.DefaultListableBeanFactory#`resolveMultipleBeans`

  泛集合注入实现，把需要的 beans 封装为 Array、Collection、Map。

  其中，Array和Collection 类型的注入是`经过排序后`的对象，Map 排序是以 LinkedHashMap 体现。

## Spring Bean 排序实现

### 关键类

org.springframework.core.Ordered，声明顺序的接口，用于类似拦截器、组件的执行优先级声明。

```java
// 根据升序顺序的约定，order value 越小，排序越靠前, 优先级越高。
int HIGHEST_PRECEDENCE = Integer.MIN_VALUE;
int LOWEST_PRECEDENCE = Integer.MAX_VALUE;
```

org.springframework.core.OrderComparator， 按照升序排序。支持实现 Ordered 接口的对象排序。

org.springframework.core.annotation.AnnotationAwareOrderComparator，支持使用顺序注解的对象排序，如：`@Order` 和@Priority 。兼容Ordered接口 。

### 排序实现

```java
public class OrderComparator implements Comparator<Object> {

	/**
	 * Shared default instance of OrderComparator.
	 */
	public static final OrderComparator INSTANCE = new OrderComparator();
    
    // 升序排序
	public int compare(Object o1, Object o2) {
		boolean p1 = (o1 instanceof PriorityOrdered);
		boolean p2 = (o2 instanceof PriorityOrdered);
        // 先区分是否实现Ordered 接口。实现 Ordered 接口的对象，排序靠前。
		if (p1 && !p2) {
			return -1;
		}
		else if (p2 && !p1) {
			return 1;
		}

		// 获取 order value，再基于value 对比排序。
		int i1 = getOrder(o1);
		int i2 = getOrder(o2);
		return (i1 < i2) ? -1 : (i1 > i2) ? 1 : 0;
	}

	/**
	 * 对外提供排序方法，方便调用。
	 */
	public static void sort(List<?> list) {
		if (list.size() > 1) {
			Collections.sort(list, INSTANCE);
		}
	}

}

```



> warning: Spring 3.x 没有对注入的集合没有排序，需要开发者sort，如果需要的话。

## Spring 集合注入的应用场景

在项目中与遇到策略模式来解耦业务的场景，通过组合相同接口的Bean来实现。

策略模式可以避开一长串的if-else，可读性、扩展性也好一些。

选用Spring 自动注入的优势：`随着业务的增加，只需要添加具体的实现类即可，无需关注策略的调度和实现`。引出的问题是：if-else 旧的代码有default 的处理，如何确保托底策略的bean 是在集合的最后？

```java
// 通过spring 注入 FooHandler 处理器实现
@Autowired
public FooService(List<FooHandler> fooHandlers) {
    // 注入完成后，fooHandlers 已经按照声明的优先级顺序排序了！！！
	this.fooHandlers = fooHandlers;
}

@Override
public void doBusiness(ReceiveMsg msg) throws Exception {
	for (FooHandler handler : fooHandlers) {
        // 需要确保默认的处理器，最后执行
		if (handler.support(msg)) {
			handler.handle(msg);
			return;
		}
	}
	throw new IllegalArgumentException("没有找到符合的处理器，检查入参或者默认的处理器...");
}
```


## 总结

可扩展性无论是框架还是应用程序，都是很重要的。Spring 集合注入在框架和模块中都有使用，我们在应用层的设计中也可参考。另外，不同版本实现排序，在使用中也需要注意。

延伸阅读：`TimSort`

参考：[Spring IOC（六）依赖查找](https://www.cnblogs.com/binarylei/p/10340455.html)


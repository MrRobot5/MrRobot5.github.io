---
layout: post
title:  "Spring 循环依赖的另一种解决方案"
date:   2020-08-13 16:02:38 +0800
categories: 源码阅读
tags: Spring 动态代理 设计模式 
---

* content
{:toc}


在 Spring 框架中，Bean 实例化和注入是相互的过程，循环依赖是一个必须要解决的问题。

除了通过三级缓存来解决循环依赖，还有一种编程式方式，借助**动态代理**，推迟对象的初始化解决循环依赖。

本文以 AbstractFactoryBean 实现方案，记录这种使用场景。

# AbstractFactoryBean

> AbstractFactoryBean 是 Spring 框架对于 FactoryBean 约定的一个模板实现，完成 单例对象或者原型对象的创建。支持对象延迟访问。

```java
/**
 * Expose the singleton instance or create a new prototype instance.
 * 对于还未实例化的清空，堆外暴露的只是代理对象。只有真正访问时，才会对实例化的对象发起的调用。
 */
@Override
public final T getObject() throws Exception {
    if (isSingleton()) {
        // 对于尚未实例化的Bean， 仍然支持实例返回。
        // 非实时初始化，就不会形成链式初始化，也就打破了循环依赖链条。
        return (this.initialized ? this.singletonInstance : getEarlySingletonInstance());
    }
    else {
        return createInstance();
    }
}

/**
 * Determine an 'eager singleton' instance, exposed in case of a
 * circular reference. Not called in a non-circular scenario.
 */
@SuppressWarnings("unchecked")
private T getEarlySingletonInstance() throws Exception {
    Class<?>[] ifcs = getEarlySingletonInterfaces();
    if (ifcs == null) {
        throw new FactoryBeanNotInitializedException(
                getClass().getName() + " does not support circular references");
    }
    if (this.earlySingletonInstance == null) {
        // 对于真正的单例对象，支持延时访问/调用。bean 初始化非强制依赖。
        // 解耦 bean 初始化和实际调用时机的耦合。打破初始化循环依赖。
        this.earlySingletonInstance = (T) Proxy.newProxyInstance(
                this.beanClassLoader, ifcs, new EarlySingletonInvocationHandler());
    }
    // 代理对象，作用：占位。
    return this.earlySingletonInstance;
}
```

# 相关知识点

- 循环依赖最可能出现的场景：constructor injection

- 循环依赖可以类比为：a classic chicken-and-egg scenario

- `FactoryBean`是一个编程契约。实现不应依赖于注解驱动的注入或其他反射机制。

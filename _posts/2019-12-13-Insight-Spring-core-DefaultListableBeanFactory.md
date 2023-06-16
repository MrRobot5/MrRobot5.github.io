---

layout: post
title:  "Spring 容器核心类 DefaultListableBeanFactory 知识点梳理"
date:   2019-12-13 11:50:45 +0800
categories: 学习笔记
tags: Spring
---
* content
{:toc}

Spring 容器默认的实现类。在遇到Spring bean 相关问题，都会涉及到 `DefaultListableBeanFactory`，因此列出常用的元素，方便知识梳理和 问题定位。

## 关键接口和类

* `ApplicationContext` Central interface to provide configuration for an application。除了提供标准的BeanFactory能力以外，还实现了ApplicationContextAware、ResourceLoaderAware这样的接口。
  
  ApplicationContext 主要功能是实现通用的context，也是BeanFactory。不同于简单的BeanFactory，还提供了初始化BeanFactory的一些特殊的Bean。我们经常使用的功能，对外提供的方法大部分都委托BeanFactory实现。

* `BeanFactory`最基础的访问bean容器的接口，定义了BeanFactory 的实现标准

* `ListableBeanFactory`主动扫描加载bean示例的BeanFactory定义

## 常用的方法

### ①getBean

`<T> T getBean(String name, Class<T> requiredType) throws BeansException;`

获取指定Class 的bean 实例。如果不存在，就实时实例化（new Clazz 和 bean-init ）

### ②doGetBean

`protected <T> T doGetBean(final String name, final Class<T> requiredType, final Object[] args, boolean typeCheckOnly) throws BeansException`

上述 getBean 逻辑的真正实现。bean 获取的核心实现都在这个方法中。

### ③createBean

`protected Object createBean(String beanName, RootBeanDefinition mbd, Object[] args) throws BeanCreationException `

Bean 实例化逻辑的真正实现。

creates a bean instance, populates the bean instance, applies post-processors, etc.

### ④getSingleton

`protected Object getSingleton(String beanName, boolean allowEarlyReference)`

Spring 默认都是以单例模式获取bean。 循环依赖解决方案参考此处的三级 cache。





## BeanFactory 标准

> Bean factory implementations should support the standard bean lifecycle interfaces* as far as possible. 

The full set of initialization methods and their standard order is:

1. BeanNameAware's setBeanName
2. BeanClassLoaderAware's setBeanClassLoader
3. BeanFactoryAware's setBeanFactory
4. EnvironmentAware's setEnvironment
5. EmbeddedValueResolverAware's setEmbeddedValueResolver
6. ResourceLoaderAware's setResourceLoader (only applicable when running in an application context)
7. ApplicationEventPublisherAware's setApplicationEventPublisher (only applicable when running in an application context)
8. MessageSourceAware's setMessageSource (only applicable when running in an application context)
9. ApplicationContextAware's setApplicationContext (only applicable when running in an application context)
10. ServletContextAware's setServletContext (only applicable when running in a web application context)
11. postProcessBeforeInitialization methods of BeanPostProcessors
12. InitializingBean's afterPropertiesSet
13. a custom init-method definition
14. postProcessAfterInitialization methods of BeanPostProcessors

On shutdown of a bean factory, the following lifecycle methods apply:

1. postProcessBeforeDestruction methods of DestructionAwareBeanPostProcessors
2. DisposableBean's destroy
3. a custom destroy-method definition
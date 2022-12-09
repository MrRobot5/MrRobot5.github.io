---
layout: post
title:  "insight Spring 容器核心类 DefaultListableBeanFactory"
date:   2019-12-13 11:50:45 +0800
categories: jekyll update
---
# Spring 容器核心类 DefaultListableBeanFactory

##  DefaultListableBeanFactory UML类图

![image-20191213101818455](D:\Users\yangpan3\AppData\Roaming\Typora\typora-user-images\image-20191213101818455.png)

## 关键接口和类

* `ApplicationContext` Central interface to provide configuration for an application。除了提供标准的BeanFactory能力以外，还实现了ApplicationContextAware、ResourceLoaderAware这样的接口。

  ApplicationContext 主要功能是实现通用的context，也是BeanFactory。不同于简单的BeanFactory，还提供了初始化BeanFactory的一些特殊的Bean。我们经常使用的功能，对外提供的方法大部分都委托BeanFactory实现。

* `BeanFactory`最基础的访问bean容器的接口，定义了BeanFactory 的实现标准

* `ListableBeanFactory`主动扫描加载bean示例的BeanFactory定义

* 



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
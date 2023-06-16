---

layout: post
title:  "Spring3 @RequestMapping 自定义Aspect不生效问题"
date:   2020-11-17 11:33:26 +0800
categories: 源码阅读
tags: Spring

---
* content
{:toc}

## 问题背景

> 现有项目使用Spring3 框架，想要对应用所有的请求进行统一监控。
> 
> 一种方案是配置全局的 `HandlerInterceptor`，实现对请求的监控。
> 
> 一种方案是基于AOP，拦截@RequestMapping，实现对Controller 的方法进行监控。项目中采用的是这种方案，主要目的是收集方法粒度的性能、可用率的数据。

## 问题描述

编写完自定义的Aspect 监控类后，发现切面不生效。

在spring-config.xml 中配置启用了@AspectJ 特性。

```xml
<!--Enables the use of the @AspectJ style of Spring AOP.-->
<aop:aspectj-autoproxy proxy-target-class="true" />
```

使用的是Spring3 的框架，web.xml 中集成Spring 配置如下所示

```xml
<!-- spring3 常见的配置方式，分为Spring容器配置 和 SpringMVC 配置，两个配置文件中各自扫描对应的包路径 -->
<context-param>
    <param-name>contextConfigLocation</param-name>
    <param-value>classpath:spring-config.xml</param-value>
</context-param>
<listener>
    <listener-class>org.springframework.web.context.ContextLoaderListener</listener-class>
</listener>

<servlet>
    <servlet-name>springmvc</servlet-name>
    <servlet-class>org.springframework.web.servlet.DispatcherServlet</servlet-class>
    <init-param>
        <param-name>contextConfigLocation</param-name>
        <param-value>classpath:spring-config-mvc.xml</param-value>
    </init-param>
    <load-on-startup>1</load-on-startup>
</servlet>
```

## Code Insight

首先确认自定义的AOP Bean 是正常加载后，剩下的问题就是探究为什么`<aop:aspectj-autoproxy/>`没有生效。

### ①aspectj-autoproxy 配置分析

aspectj-autoproxy 配置的工作原理参考 [Insight aop:aspectj-autoproxy 解析](https://blog.csdn.net/tt50335971/article/details/52181724)。

通过该配置，会给Spring 容器注册AnnotationAwareAspectJAutoProxyCreator， 属于`BeanPostProcessor` 组件，这样的话，就会在生成bean 的以后，根据Bean的特征，对bean 生成代理类。

> 作用：checking for marker interfaces or wrapping them with proxies.
> 
> 对应到本案例，就是检查是否存在 @RequestMapping 注解，并对符合条件的bean 进行代理，实现监控功能的增强。

通过检查AspectJ 语法和对应的路径，发现也正常，那么问题就可能出现在Spring 容器中。

### ②spring mvc 配置分析

通过上述的web.xml 配置，可以分析出存在两个spring 容器，容器是父子的关系。

```java
// listener配置的父容器
// Bootstrap listener to start up and shut down Spring's root WebApplicationContext
// org.springframework.web.context.ContextLoader#initWebApplicationContext
servletContext.setAttribute(WebApplicationContext.ROOT_WEB_APPLICATION_CONTEXT_ATTRIBUTE, this.context);

// servlet 配置的子容器
// Instantiate the WebApplicationContext for this servlet
ConfigurableWebApplicationContext wac = BeanUtils.instantiateClass(XmlWebApplicationContext.class);
wac.setEnvironment(getEnvironment());
// set root WebApplicationContext
wac.setParent(parent);
```

按照正常的思路来看，子容器应该能集成父容器的特性和注册的解析器、处理器等。

事实证明，`父容器注册AnnotationAwareAspectJAutoProxyCreator，子容器不会查找和使用。这也是AOP代理不生效的原因`。

### ③getBean的执行逻辑

```java
/**
 * 根据指定的类型，返回唯一的bean
 * 如果在当前的BeanFactory 找不到，会委托给父BeanFactory 查找，从而实现递归查找的策略
 */
public <T> T getBean(Class<T> requiredType) throws BeansException {
    Assert.notNull(requiredType, "Required type must not be null");
    String[] beanNames = getBeanNamesForType(requiredType);
    if (beanNames.length > 1) {
        // ......
    }
    if (beanNames.length == 1) {
        return getBean(beanNames[0], requiredType);
    }
    else if (beanNames.length == 0 && getParentBeanFactory() != null) {
        // 从父容器中查找指定的Bean
        return getParentBeanFactory().getBean(requiredType);
    }
    else {
        throw new NoSuchBeanDefinitionException(requiredType, "expected single bean but found " +
                beanNames.length + ": " + StringUtils.arrayToCommaDelimitedString(beanNames));
    }
}
```

## 解决方法和总结

需要在子容器的配置文件中添加：`<aop:aspectj-autoproxy proxy-target-class="true" />`

或者合并容器的配置，统一由servlet 启动加载。

从父容器中获取Bean 的方法：

org.springframework.beans.factory.BeanFactoryUtils#`beansOfTypeIncludingAncestors()`

## 备注

AOP - Aspect Oriented Programming

---
layout: post
title:  "SpringBoot MVC 静态资源配置实现"
date:   2022-05-18 17:16:33 +0800
categories: 源码阅读
tags: SpringBoot SpringMVC
---
* content
{:toc}

> **SpringBoot 默认支持以下路径的文件作为 web 静态资源。**
> 
> By default, Spring Boot serves static content from a directory called `/static` (or `/public` or `/resources` or `/META-INF/resources`) in the classpath or from the root of the `ServletContext`.

## SpringBoot Features

Developing Web Applications ➡Spring MVC Framework➡**Static Content**

[Reference](https://docs.spring.io/spring-boot/docs/2.5.2/reference/html/features.html#features.developing-web-applications.spring-mvc.static-content)

## 相关源码

- org.springframework.web.servlet.resource.**ResourceHttpRequestHandler**
  
  > **serves static resources** optimized for superior browser performance (according to the guidelines of Page Speed, YSlow, etc.)

- org.springframework.web.servlet.config.annotation.ResourceHandlerRegistry
  
  > **Stores registrations of resource handlers** for serving static resources such as images, css files and others through Spring MVC including setting cache headers optimized for efficient loading in a web browser.

- org.springframework.boot.autoconfigure.web.ResourceProperties

- org.springframework.boot.autoconfigure.web.WebMvcProperties

## 原理分析

自动配置入口：org.springframework.boot.autoconfigure.web.WebMvcAutoConfiguration.**WebMvcAutoConfigurationAdapter**

配置实现：

```java
@Override
public void addResourceHandlers(ResourceHandlerRegistry registry) {
    if (!this.resourceProperties.isAddMappings()) {
        logger.debug("Default resource handling disabled");
        return;
    }
    // 此处的cache 是指 HTTP协议的 Cache-Control
    Integer cachePeriod = this.resourceProperties.getCachePeriod();
    // 默认：/**， spring.mvc.static-path-pattern
    String staticPathPattern = this.mvcProperties.getStaticPathPattern();
    if (!registry.hasMappingForPattern(staticPathPattern)) {
        customizeResourceHandlerRegistration(
                registry.addResourceHandler(staticPathPattern)
            // 默认： [/META-INF/resources/, /resources/, /static/, /public/]
                .addResourceLocations(this.resourceProperties.getStaticLocations())
                .setCachePeriod(cachePeriod));
    }
}
```

## How To

### 自定义配置静态资源

#### 默认请求pattern 配置

```properties
# relocating all resources to /resources/**
spring.mvc.static-path-pattern=/resources/**
```

静态资源目录配置

```properties
spring.web.resources.static-locations=/webjars/**
```

### Spring MVC 配置

```xml
<mvc:default-servlet-handler/>
<mvc:resources location="/static/" mapping="/static/**" cache-period="864000"/>
```

---
layout: post
title:  "ThreadLocal 应用场景分析 - MDC"
date:   2022-09-19 10:54:07 +0800
categories: 学习笔记
tags: MDC ThreadLocal
---
* content
{:toc}

## Mapped Diagnostic Contexts (MDC)

> One of the design goals of logback is to audit and debug complex **distributed applications**. 
> 
> It lets the developer place information in a diagnostic context that can be subsequently retrieved by certain logback components. 

[Chapter 8: Mapped Diagnostic Context](https://logback.qos.ch/manual/mdc.html)

Java 常用的日志工具，logback log4j slf4j 都支持MDC 特性。本文分析 logback MDC。

## Code Insight

```java
// MDC operations such as put() and get() affect only the MDC of the current thread, and the children of the current thread. 
// Thus, there is no need for the developer to worry about thread-safety or synchronization when programming with the MDC because it handles these issues safely and transparently.
public class LogbackMDCAdapter implements MDCAdapter {

    // The internal map is copied so as

    // We wish to avoid unnecessarily copying of the map. To ensure
    // efficient/timely copying, we have a variable keeping track of the last
    // operation. 
    final ThreadLocal<Map<String, String>> copyOnThreadLocal = new ThreadLocal<Map<String, String>>();
	
}
```



## 使用方法

### Simple

```java
// 可以在任何地方put value, 由上述实现可以知道，存取和具体的日志技术无关。
MDC.put("first", "Dorothy");
Logger logger = LoggerFactory.getLogger(SimpleMDC.class);
MDC.put("last", "Parker");
logger.info("Check enclosed.");
```

```xml
<appender name="CONSOLE" class="ch.qos.logback.core.ConsoleAppender"> 
  <layout>
    <Pattern>%X{first} %X{last} - %m%n</Pattern>
  </layout> 
</appender>
```

打印结果：`Dorothy Parker - Check enclosed.`

### Web Application

logback 内置的Filter,  可以实现请求信息的提取和打印，帮助统计和排查问题。

`ch.qos.logback.classic.helpers.MDCInsertingServletFilter`

```xml
<!-- web.xml 配置，必须配置到filters 首位，保障后续打印都能使用MDC 保存的信息 -->
<filter>
  <filter-name>MDCInsertingServletFilter</filter-name>
  <filter-class>
    ch.qos.logback.classic.helpers.MDCInsertingServletFilter
  </filter-class>
</filter>
<filter-mapping>
  <filter-name>MDCInsertingServletFilter</filter-name>
  <url-pattern>/*</url-pattern>
</filter-mapping> 
```

打印pattern 配置 `%X{req.remoteHost} %X{req.requestURI}%n%d - %m%n`

```java
public class MDCInsertingServletFilter implements Filter {

    public void doFilter(ServletRequest request, ServletResponse response, FilterChain chain) throws IOException, ServletException {

		// put request information
        insertIntoMDC(request);
        try {
            chain.doFilter(request, response);
        } finally {
			// 从当前线程移除请求信息，防止复用线程信息混淆
            clearMDC();
        }
    }
	
}
```

## More

- LogbackMDCAdapter 实现，why track of the last operation？

和使用 InheritableThreadLocal 有什么区别？

参考： org.slf4j.helpers.BasicMDCAdapter













































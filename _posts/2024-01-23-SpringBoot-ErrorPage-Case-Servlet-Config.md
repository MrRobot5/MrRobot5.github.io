---
layout: post
title:  "SpringBoot ErrorPage 案例以及 Servlet 配置原理"
date:   2024-01-23 21:44:30 +0800
categories: 学习笔记
tags: SpringBoot Servlet SpringMVC
---

* content
{:toc}


# SpringBoot ErrorPage 案例

## 案例描述

调用后端接口，发现接口返回的数据有两组 json, 非数组。非常奇怪🙉

```json
{
    "name": "John",
    "age": 30
}
{
    "path": "/examples/servlets/servlet/JsonExample",
    "code": 500
}
```

## SpringMVC 运行时异常

```java
/**
 * Servlet 包版本问题，导致 SpringMVC Servlet 打印日志报错
 * @see org.springframework.web.servlet.FrameworkServlet#processRequest
 */
protected final void processRequest(HttpServletRequest request, HttpServletResponse response) {
    try {
        doService(request, response);
    }
    catch (ServletException | IOException ex) {
    }
    finally {
        // HttpStatus httpStatus = HttpStatus.resolve(status); since 5.0 才有这个方法 ❌
        logResult(request, response, failureCause, asyncManager);
        publishRequestHandledEvent(request, response, startTime, failureCause);
    }
}
```

## 问题分析

- 第一个 json 是业务逻辑返回内容。controller 逻辑没有发生异常，正常写入 response。

- 第二个 json 是 SpringMVC Servlet 发生异常后，由 Tomcat ErrorPage 转发到默认的错误处理 Servlet 生成的内容。

- 两个 json 内容通过 RequestDispatcher.include 方法，都写入到 response。

- 工作原理参考： [Servlet 异常处理和Spring Boot ErrorPage自动化配置](https://mrrobot5.github.io/2023/05/16/note-error-page-in-Spring-Boot/)

# 案例复现

> 借助 Tomcat examples 应用，可以快速搭建案例场景。✔

## 业务场景 Servlet

```java
import javax.servlet.*;
import javax.servlet.http.*;
import java.io.IOException;
import java.io.PrintWriter;

// Servlet 中返回 JSON 字符串
public class JsonServlet extends HttpServlet {
    protected void doGet(HttpServletRequest request, HttpServletResponse response) throws ServletException, IOException {

        response.setContentType("application/json");
        response.setCharacterEncoding("UTF-8");

        String json = "{\"name\": \"John\", \"age\": 30}";

        PrintWriter out = response.getWriter();
        out.print(json);
        // 业务内容写入 response, response 变为 submit 状态。
        out.flush();
        // 模拟上述 SpringMVC 异常
        if(true) {
            throw new RuntimeException("Bad area ref ");
        }
    }
}
```

## 异常处理 Servlet

```java
import javax.servlet.*;
import javax.servlet.http.*;
import java.io.IOException;
import java.io.PrintWriter;

// 对应 SpringBoot 提供的 BasicErrorController
public class ErrorServlet extends HttpServlet {
    protected void doGet(HttpServletRequest request, HttpServletResponse response) throws ServletException, IOException {
        String path = request.getRequestURI();

        String json = "{\"path\": \"" + path + "\", \"code\": 500}";

        PrintWriter out = response.getWriter();
        out.print(json);
    }
}
```

## errorPage 配置

```xml
<servlet>
    <servlet-name>JsonExample</servlet-name>
    <servlet-class>JsonServlet</servlet-class>
</servlet>
<servlet-mapping>
    <servlet-name>JsonExample</servlet-name>
    <url-pattern>/servlets/servlet/JsonExample</url-pattern>
</servlet-mapping>

<servlet>
    <servlet-name>ErrorExample</servlet-name>
    <servlet-class>ErrorServlet</servlet-class>
</servlet>
<!-- 对应的注册过程： org.springframework.boot.autoconfigure.web.BasicErrorController -->
<servlet-mapping>
    <servlet-name>ErrorExample</servlet-name>
    <url-pattern>/error</url-pattern>
</servlet-mapping>

<!-- 对应： ErrorPageRegistry.addErrorPages(errorPage); -->
<error-page>  
    <exception-type>java.lang.RuntimeException</exception-type>  
    <location>/error</location>
</error-page>
```

## 编译运行

```bash
cd /d/services/apache-tomcat-8.0.48/webapps/examples/WEB-INF/classes

# /D/repository/javax/servlet/servlet-api/2.4/servlet-api-2.4.jar
javac -cp servlet-api-2.4.jar JsonServlet.java

javac -cp servlet-api-2.4.jar ErrorServlet.java
```

运行 Tomcat。 访问链接 http://localhost:8080/examples/servlets/servlet/JsonExample

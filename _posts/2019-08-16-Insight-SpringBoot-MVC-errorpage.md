---
layout: post
title:  "Insight SpringBoot MVC 错误页面跳转原理"
date:   2019-08-16 15:56:37 +0800
categories: jekyll update
---
## Insight SpringBoot MVC 错误页面跳转原理

## 引子

​    为什么404的错误页显示 Whitelabel-page ?
​    根据浏览器的网络请求分析，肯定是服务内部跳转处理的。
​    根据返回Whitelabel 错误页的信息，肯定是spring-boot 处理的错误页
​    如何跳转的？spring-boot 如何替web容器托管了错误页处理功能？

> SpringBoot默认提供/Error映射，它以合理的方式处理所有错误，并在servlet容器中注册为“全局”错误页。对于机器客户端，它将生成一个JSON响应，其中包含错误、HTTP状态和异常消息的详细信息。对于浏览器客户端，有一个“Whitelabel”错误视图，它以HTML格式呈现相同的数据(要自定义它，只需添加一个解析为“Error”的视图)。要完全替换默认行为，您可以实现ErrorController并注册该类型的bean定义，或者简单地添加一个类型为ErrorAttributes的bean来使用现有机制，但替换内容。

## SpringBoot Features

对应：Developing Web Applications ➡Spring MVC Framework➡**Error Handing**

## 相关源码

* ErrorPageFilter 滤请求并转发请求到 error

* BasicErrorController 默认error请求处理

* ErrorMvcAutoConfiguration 默认错误注册配置、错误页跳转配置，例如：注册默认ErrorPage，注册 BasicErrorController

* ResourceHttpRequestHandler 默认的404错误，就是统一由该Handler 产生

* WhitelabelErrorViewConfiguration **我们看到的 spring-boot 默认错误页**

## Code Insight

ErrorPageFilter  实现web错误页跳转是通过来，非嵌入式应用程序(即已部署的WAR文件)提供。作用是过滤请求并转发到错误页，而不是让容器（例如：Tomcat）处理它们。

```java
private void doFilter(HttpServletRequest request, HttpServletResponse response, FilterChain chain) throws IOException, ServletException {
    // 包装response，支持错误分支判断，包装设计模式 
    ErrorWrapperResponse wrapped = new ErrorWrapperResponse(response);
    try {
         // 正常业务执行
        chain.doFilter(request, wrapped);
         // 如果请求response error（例如：404， 500），该Filter 进行判断转发到错误页
        if (wrapped.hasErrorToSend()) {
            // 服务内部定向跳转，这样，就请求到 BasicErrorController
            // request.getRequestDispatcher(errorPath).forward(request, response);
            handleErrorStatus(request, response, wrapped.getStatus(), wrapped.getMessage());
            response.flushBuffer();
        }
        // ...
    } catch (Throwable ex) {
        // ...
    }
}
```

ResourceHttpRequestHandler 优先判断404问题

```java
public void handleRequest(HttpServletRequest request, HttpServletResponse response) throws ServletException, IOException {

    // For very general mappings (e.g. "/") we need to check 404 first
    Resource resource = getResource(request);
    if (resource == null) {
        logger.trace("No matching resource found - returning 404");
         // response.hasErrorToSend = true;
        response.sendError(HttpServletResponse.SC_NOT_FOUND);
        return;
    }
    // ...
}
```

## How to: 替换默认错误页

在默认路径下，创建自定义的错误页文件即可

```shell
src/
 +- main/
     +- java/
     |   + <source code>
     +- resources/
         +- templates/
             +- error/
             |   +- 5xx.ftl
             +- <other templates>
```

## 参考

[7.1.10. SpringBoot Error Handling](https://docs.spring.io/spring-boot/docs/2.5.2/reference/html/features.html#features.developing-web-applications.spring-mvc.error-handling)

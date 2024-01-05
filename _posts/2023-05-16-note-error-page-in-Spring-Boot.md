---
layout: post
title:  "Servlet 异常处理和Spring Boot ErrorPage自动化配置"
date:   2023-05-16 18:03:01 +0800
categories: 学习笔记
tags: SpringBoot Servlet

---

* content
{:toc}

> Servlet 规范中，针对如何处理异常，有对应的定义。
> 
> Tomcat 是一个Servlet容器，对于Servlet 规范的一种实现。
> 
> Servlet 3.0 引入了 Servlet 容器初始化时的可插拔性，允许开发者通过`ServletContainerInitializer`接口注册组件，这为 SpringBoot 框架集成提供了便利。 
> 
> SpringBoot 集成功能就包括自动注册异常处理，无需开发者关注容器层配置。

以下分别从Servlet 规范，Tomcat 实现，SpringBoot 默认配置三层来分析。

## Servlet 异常处理和 error-page

> 在Servlet规范中，`error-page` 元素用于定义**如何处理在Web应用程序中发生的错误**。
> 
> 这个元素可以在 web.xml 部署描述文件中配置，用于指定特定错误代码或 Java 异常类型的处理页面。

### ①配置`error-page`的示例-HTTP状态码

```xml
<!-- 当发生404错误时，会显示/error-404.html页面。-->
<error-page>
    <error-code>404</error-code>
    <location>/error-404.html</location>
</error-page> 
```

### ②配置`error-page`的示例-Java异常类型

```xml
<!-- 当发生NullPointerException时，会显示/error-help.html页面。-->
<error-page>  
  <exception-type>java.lang.NullPointerException</exception-type>  
  <location>/error-help.html</location>  
</error-page>
```

## Tomcat error-page 处理流程

- error-page 解析和实例化过程，参考： org.apache.catalina.core.StandardContext#addErrorPage

- SpringBoot 初始化的过程中，会调用 addErrorPage，进行默认异常配置

- error-page 配置的执行过程，就是服务器内部转发的过程。 即 RequestDispatcher.forward(request, response)

```java
/**
 * Return the error page entry for the specified Java exception type,
 * if any; otherwise return <code>null</code>. 
 *
 * @see org.apache.catalina.core.StandardContext#findErrorPage(java.lang.String)
 */
@Override
public ErrorPage findErrorPage(String exceptionType) {
    synchronized (exceptionPages) {
        return (exceptionPages.get(exceptionType));
    }
}
```

```java
/**
 * 处理HTTP状态码或Java异常，转发到指定的 errorPage 页面。
 * 
 * @param errorPage The errorPage directive we are obeying
 * @see org.apache.catalina.core.StandardHostValve#custom
 */
private boolean custom(Request request, Response response, ErrorPage er    rorPage) {

    try {
        // Forward control to the specified location
        ServletContext servletContext = request.getContext().getServletContext();
        RequestDispatcher rd = servletContext.getRequestDispatcher(errorPage.                    getLocation());
        // 熟悉的 servlet 操作
        if (response.isCommitted()) {
            // 它用于在当前响应中包含另一个资源的内容。调用 include 方法不会清除响应缓冲区，当前Servlet的输出和被包含资源的输出将一起发送给客户端。
            rd.include(request.getRequest(), response.getResponse());
        } else {
            // 它用于将请求完全转发到另一个资源。新的资源将处理整个请求，并且原始请求的响应将被丢弃。
            rd.forward(request.getRequest(), response.getResponse());
        }

        // Indicate that we have successfully processed this custom page
        return (true);
    }
} 
```

## Spring Boot 自动配置 error-page

- Spring Boot 提供默认的错误处理机制，`BasicErrorController`。通过类似 Tomcat 添加error-page配置的方式，把默认的 ErrorPage 注册到 Java Web 容器中.

- 对应的异常处理器是 BasicErrorController ，转发到当前Controller 的异常，返回 ResponseEntity<>(exception, status) 给前台。
  
  参考：org.springframework.boot.autoconfigure.web.BasicErrorController#error

```java
/**
 * configures the container's error pages.
 * @see org.springframework.boot.autoconfigure.web.ErrorMvcAutoConfiguration
 */
private static class ErrorPageCustomizer implements ErrorPageRegistrar, Ordered {

    @Override
    public void registerErrorPages(ErrorPageRegistry errorPageRegistry) {
        // 默认使用/error, @see BasicErrorController's RequestMapping("${server.error.path:${error.path:/error}}")
        ErrorPage errorPage = new ErrorPage(this.properties.getServletPrefix() + this.properties.getError().getPath());
        // 约等于 Tomcat container.addErrorPages
        errorPageRegistry.addErrorPages(errorPage);
    }
}
```

## SpringMVC 自定义异常处理

> 在SpringMVC中，`@ExceptionHandler` 注解用于处理 Controller 中的特定异常。
> 
> Controller 发生注解指定的异常类型时，调用这个方法来处理异常。

配置示例：

```java
@Controller
public class MyController {

    @ExceptionHandler(value = { NullPointerException.class })
    public ModelAndView handleMyCustomException(NullPointerException ex) {
        ModelAndView mav = new ModelAndView();
        mav.addObject("error", ex.getMessage());
        mav.setViewName("errorPage");
        return mav;
    }
}
```

## 总结

1. error-page 属于 Servlet 规范，各种 Java Web 容器都有对应的实现

2. SpringBoot 在初始化 web 环境过程中，就默认注册了异常处理，当应用异常发生时，托底处理，返回错误信息。

3. SpringMVC 的异常处理配置是框架内部的机制，即使 SpringMVC 无法处理的异常，还有 SpringBoot 配置到 Web 容器(Tomcat)中的异常处理。

4. 如果SpringBoot 异常处理 BasicErrorController 发生了异常，还有Web 容器(Tomcat)默认的异常处理机制来兜底。

5. 全局的异常处理设计，使得异常处理逻辑与业务逻辑分离，有助于代码的维护和清晰性。

6. 从 error-page 在各层次的配置和作用原理中，又可以学习到架构分层的思想。

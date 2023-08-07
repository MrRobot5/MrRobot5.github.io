---
layout: post
title:  "笔记 SpringMVC Controller Advice 和 全局异常处理"
date:   2019-12-12 16:32:58 +0800
categories: 学习笔记 实战问题
tags: SpringMVC 问题分析
---

* content
{:toc}

SpringMVC 从3.2 版本之后，提供了全局 Controller 增强 Advice 特性。框架初始化过程（component scanning）中，针对功能 Advice 和 异常处理分别做了不同的解析。

# Controller Advice

> 针对 Controller 的自定义方法 `@ExceptionHandler`, `@InitBinder`, `@ModelAttribute`  ，如果想应用到全局，可以声明为 @ControllerAdvice

## ControllerAdvice

```java
@ControllerAdvice
public class ExampleAdvice {

    @InitBinder
    void initBinder(WebDataBinder binder) {
        binder.addCustomFormatter(new DateFormatter("yyyy-MM-dd"));
    }

    @ExceptionHandler({FileSystemException.class, RemoteException.class})
    public ResponseEntity<String> handle(IOException ex) {
        // ...
    }

    // @RequestMapping methods, etc.

}
```

## RestControllerAdvice

复合注解，ControllerAdvice + ResponseBody = RestControllerAdvice

实际上是针对 message conversion 处理的异常进行拦截和增强。

## Code Insight

### Advice 解析

如上，RestControllerAdvice 也属于 ControllerAdvice。因此，框架初始化过程中，只需要识别 @ControllerAdvice 注解的bean。

org.springframework.web.method.ControllerAdviceBean#findAnnotatedBeans

1️⃣ Controller 功能增强

org.springframework.web.servlet.mvc.method.annotation.RequestMappingHandlerAdapter#initControllerAdviceCache

2️⃣ Controller 异常拦截处理

org.springframework.web.servlet.mvc.method.annotation.ExceptionHandlerExceptionResolver#initExceptionHandlerAdviceCache

# 全局异常处理

## Code Insight

### Advice 应用

1️⃣ 异常处理分发

org.springframework.web.servlet.DispatcherServlet#processHandlerException

2️⃣ 获取匹配的异常处理方法

org.springframework.web.servlet.mvc.method.annotation.ExceptionHandlerExceptionResolver#getExceptionHandlerMethod

### 实战 Case 分析

> 在实际开发过程中，使用 ControllerAdvice 拦截 SomeFooException， 发现并没有达到预期效果。配置如下代码所示：

```java
// 业务异常SomeFooException 匹配到 handle 方法， 但是异常实例和 handle 入参类型不符合，抛出 IllegalArgumentException: No suitable resolver
@ExceptionHandler({IllegalArgumentException.class, SomeFooException.class})
public ResponseEntity<String> handle(IllegalArgumentException ex) {
    // ...
}
```

通过源代码跟踪分析，在上述 handle 方法反射调用发生异常（入参类型不匹配）。 SpringMVC 无法处理，**异常传递给 Tomcat 处理**。

```java
/**
 * Find an @ExceptionHandler method and invoke it to handle the raised exception.
 */
protected ModelAndView doResolveHandlerMethodException(HttpServletRequest request,
        HttpServletResponse response, @Nullable HandlerMethod handlerMethod, Exception exception) {
    // 根据异常类型，获取匹配的处理方法，如上述的 handle 方法
    ServletInvocableHandlerMethod exceptionHandlerMethod = getExceptionHandlerMethod(handlerMethod, exception);

    try {
        {
            // 反射调用，对 exception 进行异常包装和处理。
            exceptionHandlerMethod.invokeAndHandle(webRequest, mavContainer, exception, handlerMethod);
        }
    }
    catch (Throwable invocationEx) {
        // Any other than the original exception (or its cause) is unintended here,
        // probably an accident (e.g. failed assertion or the like).
        if (invocationEx != exception && invocationEx != exception.getCause() && logger.isWarnEnabled()) {
            logger.warn("Failure in @ExceptionHandler " + exceptionHandlerMethod, invocationEx);
        }
        // Continue with default processing of the original exception...
        // SpringMVC 无法处理的异常，传递给 Web 容器（Tomcat）处理。
        return null;
    }

}
```

不同异常处理的 response

1️⃣ Tomcat 异常处理返回信息。 Http StatusCode = 500

```json
{
    "timestamp": "2023-08-03 19:55:03",
    "status": 500,
    "error": "Internal Server Error",
    "message": "foo 必填",
    "path": "/example/saveOrUpdate"
}
```

2️⃣ SpringMVC 自定义异常处理返回信息。 Http StatusCode = 200

```json
{
    "message": "foo 必填",
    "code": 500,
    "data": null,
    "timestamp": 1691066025153
}
```

# 排查 Tips

1️⃣ Advice 未生效首先 check basePackages， 是否包含对应的 Controller。

2️⃣ 全局异常拦截未生效，首先检查异常是否包含、以及匹配的优先级顺序。

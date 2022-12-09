---
layout: post
title:  "Insight HandlerInterceptor 与@ExceptionHandler 的执行顺序"
date:   2022-09-13 14:54:42 +0800
categories: jekyll update
---
# Insight HandlerInterceptor 与@ExceptionHandler 的执行顺序

> 项目中HandlerInterceptor preHandle方法会把登录的用户信息存储在ThreadLocal，方便请求逻辑中获取，
> 
> afterCompletion方法中会remove。当发生异常时，想通过@ExceptionHandler打印当前的用户名，还能拿到用户信息吗？

## 概念明确

* HandlerInterceptor 请求拦截器，允许自定义处理程序执行链的工作流接口。afterCompletion方法，完成请求处理后回调，that is，渲染视图后回调。
* ExceptionHandler 用于处理特定处理程序类或方法中的异常的注解，主要在Servlet环境中使用，根据异常的类型进行映射。涉及的类有：，
* ExceptionHandlerMethodResolver 扫描发现ExceptionHandler 注解的方法，并注册到mappedMethods
* ExceptionHandlerExceptionResolver 通过@ExceptionHandler方法解析异常，根据如下的UML得知，最终会以HandlerExceptionResolver接口的形式，在DispatcherServlet中调用。

![image-20191210210542976](D:\Users\yangpan3\AppData\Roaming\Typora\typora-user-images\image-20191210210542976.png)

## Code Insight

```java
// mvc请求处理入口
protected void doDispatch(HttpServletRequest request, HttpServletResponse response) throws Exception {
    try {
        Exception dispatchException = null;
        try {
            mappedHandler = getHandler(processedRequest);
            // 登录校验和用户信息的缓存就是在此执行
            if (!mappedHandler.applyPreHandle(processedRequest, response)) {
                return;
            }

            // Actually invoke the handler.
            mv = ha.handle(processedRequest, response, mappedHandler.getHandler());
            // 注意，业务发生异常，postHandle 是不会执行的
            mappedHandler.applyPostHandle(processedRequest, response, mv);
        }
        catch (Exception ex) {
            dispatchException = ex;
        }
        // 返回结果处理，返回ModelAndView，包括Exception 处理，参考processHandlerException
        processDispatchResult(processedRequest, response, mappedHandler, mv, dispatchException);
    }
    catch (Exception ex) {
        // 用户信息ThreadLocal 是在此remove 的
        triggerAfterCompletion(processedRequest, response, mappedHandler, ex);
    }
}
```

## 结论

可以在请求发生异常时，在ExceptionHandler 中`可以拿到用户信息`。

这样就很方便根据打印的日志定位和排查问题。
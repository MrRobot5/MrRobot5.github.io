---
layout: post
title:  "error-page in Spring Boot"
date:   2023-05-16 18:03:01 +0800
categories: 学习笔记
tags: SpringBoot Servlet
---
* content
{:toc}

## Java Web 配置 error-page

```xml
<error-page>  
  <exception-type>java.lang.NullPointerException</exception-type>  
  <location>/WEB-INF/nullPointerException.html</location>  
 </error-page> 
```

## Spring Boot 配置 error-page

- Spring Boot 提供默认的错误处理机制，BasicErrorController。通过类似上述配置的方式，adding servlet container error pages.

- 如果拦截异常，并处理为自定义的格式。使用 Spring MVC @ExceptionHandler

- 默认 BasicErrorController 异常处理，即返回 ResponseEntity<>(exception, status)
  
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
        // 约等于 container.addErrorPages
        errorPageRegistry.addErrorPages(errorPage);
    }

}
```

## tomcat error page handle

- error-page 配置 org.apache.catalina.core.StandardContext#addErrorPage

- error page 如果有配置的情况，是服务器内部转发的过程。 即 RequestDispatcher.forward(request, response)

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
 * Handle an HTTP status code or Java exception by forwarding control
 * to the location included in the specified errorPage object.  It is
 * assumed that the caller has already recorded any request attributes
 * that are to be forwarded to this page.  Return <code>true</code> if
 * we successfully utilized the specified error page location, or
 * <code>false</code> if the default error report should be rendered.
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
            // Response is committed - including the error page is the
            // best we can do
            rd.include(request.getRequest(), response.getResponse());
        } else {
            // Reset the response (keeping the real error code and message)
            response.resetBuffer(true);
            response.setContentLength(-1);

            rd.forward(request.getRequest(), response.getResponse());

            // If we forward, the response is suspended again
            response.setSuspended(false);
        }

        // Indicate that we have successfully processed this custom page
        return (true);

    }
}
```

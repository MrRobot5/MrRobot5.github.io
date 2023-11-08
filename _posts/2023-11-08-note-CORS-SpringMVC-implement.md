---
layout: post
title:  "笔记 - 跨域理论以及 SpringMVC 配置实现原理"
date:   2023-11-08 14:22:28 +0800
categories: 学习笔记
tags: SpringMVC 网络协议
---

* content
{:toc}



> 随着应用的变多，互相嵌入和交互，跨域问题就变成常见的问题。
> 
> 现有的框架和中间件，可以用很简洁的配置去解决跨域。
> 
> 那么跨域背后的真相，以及实现原理是什么？

## 跨域资源共享（CORS）

- 浏览器的安全机制禁止跨域请求操作。❌

- 同时支持一种机制（CORS），如果**跨域的请求能够按照约定标识**（正确 CORS 响应头），那么浏览器就会放开跨域的安全机制。✔

- 简单请求不会触发 CORS 预检请求（OPTIONS）。

- 非简单请求（比如：application/json）会触发预检请求，可以从示例代码中验证。

参考文档： [跨源资源共享（CORS） - HTTP | MDN](https://developer.mozilla.org/zh-CN/docs/Web/HTTP/CORS)



## 跨域问题示例

1. 使用 SwitchHost 修改本地localhost ldms.foo.com webapp.foo.com

2. 本地环境启动 web 应用A（ldms.foo.com:3000）

3. 本地环境启动 web 应用B（webapp.foo.com:8080）,

4. 在 web 应用A里通过 Ajax 请求应用 B 域名的接口（webapp.foo.com:8080/something.json）

5. 默认情况下，就会出现跨域问题。

**浏览器的控制台提示错误**：

```html
Access to XMLHttpRequest at 'http://webapp.foo.com:8080/something.json' from origin 'http://ldms.foo.com:3000' 
has been blocked by CORS policy: 
No 'Access-Control-Allow-Origin' header is present on the requested resource.
```

Chrome Network Status 标识为 

```html
Cross-Origin Resource Sharing error: MissingAllowOriginHeader
```

[示例代码](https://github.com/MrRobot5/javascript-snippet/blob/master/public/cors.html)

## SpringMVC 跨域配置

### ①全局配置 WebMvcConfigurer

```java
/**
 * WebMvcConfigurer 实现类中，跨域配置
 * @see org.springframework.web.servlet.config.annotation.WebMvcConfigurer#addCorsMappings
 */
@Override
public void addCorsMappings(CorsRegistry registry) {
    registry.addMapping("/**")
        .allowedOrigins("*")
        .allowedMethods("GET", "POST", "PUT", "DELETE", "PATCH")
        .exposedHeaders("Location");
}
```

### ②方法级别配置 CrossOrigin

```java
@RestController
@RequestMapping("/account")
public class AccountController {

    @CrossOrigin
    @GetMapping("/{id}")
    public Account retrieve(@PathVariable Long id) {
        // ...
    }
}
```



## SpringMVC 跨域实现原理

### ①核心处理逻辑

```java
/**
 * 根据请求获取对应处理器的过程中，会判断是否要支持 Cors 
 * 
 * @see org.springframework.web.servlet.handler.AbstractHandlerMapping#getHandler
 * @see org.springframework.web.servlet.handler.AbstractHandlerMapping#getCorsHandlerExecutionChain
 */
@Override
@Nullable
public final HandlerExecutionChain getHandler(HttpServletRequest request) throws Exception {
    Object handler = getHandlerInternal(request);
    HandlerExecutionChain executionChain = getHandlerExecutionChain(handler, request);

    // 判断当前处理器是否配置 Cors，或者预检请求
    if (hasCorsConfigurationSource(handler) || CorsUtils.isPreFlightRequest(request)) {
        // 获取全局 Cors 配置
        CorsConfiguration config = (this.corsConfigurationSource != null ? this.corsConfigurationSource.getCorsConfiguration(request) : null);
        // 获取方法粒度  Cors 配置
        CorsConfiguration handlerConfig = getCorsConfiguration(handler, request);
        config = (config != null ? config.combine(handlerConfig) : handlerConfig);
        // 处理 CORS 相关的操作
        executionChain = getCorsHandlerExecutionChain(request, executionChain, config);
    }

    return executionChain;
}
```

### ②CORS 处理逻辑规则

- 对于预检请求（Pre-flight requests），会将所选的处理器（handler）替换为一个简单的 HttpRequestHandler， 检查并由 **CorsProcessor** 返回空 response。

- 对于实际的请求（actual requests），会给处理器插入一个 **CorsInterceptor**（HandlerInterceptor），该HandlerInterceptor 会进行 CORS 相关的检查并添加 CORS 头部信息。

### ③其他

```java
/**
 * 判断一个请求是否是有效的CORS请求
 * @see org.springframework.web.cors.CorsUtils#isCorsRequest
 */
public static boolean isCorsRequest(HttpServletRequest request) {
    // 获取请求头中的 "Origin" 字段的值。
    String origin = request.getHeader(HttpHeaders.ORIGIN);
    // origin 没有指定，是普通的请求
    if (origin == null) {
        return false;
    }
    UriComponents originUrl = UriComponentsBuilder.fromOriginHeader(origin).build();
    // 获取请求的协议（scheme）、服务器名称（host）和端口号（port）
    String scheme = request.getScheme();
    String host = request.getServerName();
    int port = request.getServerPort();
    // 如果有任何一个部分不相等，则返回true，表示是有效的CORS请求。
    return !(ObjectUtils.nullSafeEquals(scheme, originUrl.getScheme()) &&
            ObjectUtils.nullSafeEquals(host, originUrl.getHost()) &&
            getPort(scheme, port) == getPort(originUrl.getScheme(), originUrl.getPort()));

}
```

## 其他跨域配置

> 基于上述的理论和实现原理，我们可以得出，在服务端，每一层的处理，只要能够按照 CORS 规则标识 response， 都可以解决跨域问题。

### devServer 跨域配置

```javascript
module.exports = {
  // 默认情况下，代理时会保留主机头的来源，可以将 changeOrigin 设置为 true 以覆盖此行为。
  devServer: {
    proxy: {
      '/api': {
        target: 'http://localhost:3000',
        changeOrigin: true,
      },
    },
  },
};
```

### nginx 跨域配置

```nginx
# 和上述的 CORS 处理逻辑规则是不是很相似😁
add_header 'Access-Control-Allow-Origin' '*';
add_header 'Access-Control-Allow-Methods' 'GET, POST, OPTIONS, PUT, DELETE';
add_header 'Access-Control-Allow-Headers' 'Content-Type';
# 预检请求处理
if ($request_method = 'OPTIONS') {
	return 200;
}
```

## 总结

浏览器问：这个外乡人的请求有安全标识吗？有，放行。✔

服务器问：这个域名的请求咱们认可吗？认可，发放安全标识。✔



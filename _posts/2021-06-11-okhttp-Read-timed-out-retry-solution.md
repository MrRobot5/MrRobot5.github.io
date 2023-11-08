---

layout: post
title:  "okhttp Read timed out 重试方案解疑"
date:   2021-06-11 15:59:56 +0800
categories: 学习笔记
tags: okhttp 设计模式
---
* content
{:toc}


## 疑问

使用 okhttp 抓取数据场景中，偶发Read timed out异常。正常的做法是增加重试机制。

在查看文档过程中，发现okhttp 默认会注册`RetryAndFollowUpInterceptor ，字面上是支持重试的`。

那么，为什么timed out 异常不会重试，RetryAndFollowUpInterceptor  是干啥的？

## RetryAndFollowUpInterceptor分析

### 能做什么

> This interceptor recovers from failures and follows redirects as necessary.

1. **add authentication headers**
   
   ```java
   // 针对未授权的异常(HTTP Status-Code .401: Unauthorized)，尝试调用authenticate(), 继续请求操作
   client.authenticator().authenticate(route, userResponse);
   ```

2. **follow redirects**
   
   ```java
   /**
    * 针对重定向的异常
    * HTTP Status-Code 301: Moved Permanently.
    * HTTP Status-Code 302: Temporary Redirect.
    * HTTP Status-Code 303: See Other.
    * 通过重新构造request情况，达到自动跳转的目的
    */
   String location = userResponse.header("Location");
   HttpUrl url = userResponse.request().url().resolve(location);
   ```

3. **handle a client request timeout**(稀有场景)
   
   ```java
   case HTTP_CLIENT_TIMEOUT:
   // 408's are rare in practice, but some servers like HAProxy use this response code. The
   // spec says that we may repeat the request without modifications. Modern browsers also
   // repeat the request (even non-idempotent ones.)
   // 注意：此处的Timeout 不是上述的SocketTimeout...
   ```

参考：okhttp3.internal.http.RetryAndFollowUpInterceptor#followUpRequest

### 不能做什么

遇到如下的异常：ProtocolException、`InterruptedIOException`、SSLHandshakeException、CertificateException

称之为：`the failure is permanent`。

```java
if (e instanceof InterruptedIOException) {
    return e instanceof SocketTimeoutException && !requestSendStarted;
}
```

参考：okhttp3.internal.http.RetryAndFollowUpInterceptor#recover

## SocketTimeoutException 方案

1. 根据情况，适当调整timeout设置
   
   ```java
   new OkHttpClient.Builder()         
       .connectTimeout(10, TimeUnit.SECONDS)
       .writeTimeout(5, TimeUnit.SECONDS)
       .readTimeout(10, TimeUnit.SECONDS)
       .build();
   ```

2. 增加重试机制，对网络的波动进行容错
   
   实现Interceptor接口，对SocketTimeoutException catch 重试。

## 总结

通过上述的分析，RetryAndFollowUpInterceptor 解决的是http 协议应用层重试问题，而read timed out 通讯协议层的问题。解决timeout 对于RetryAndFollowUpInterceptor  不是职责内的功能。

## 其他

### okhttp3.Interceptor 注册

```java
Response getResponseWithInterceptorChain() throws IOException {
    // Build a full stack of interceptors.
    List<Interceptor> interceptors = new ArrayList<>();
    // 自定义的拦截器优先执行
    interceptors.addAll(client.interceptors());
    interceptors.add(retryAndFollowUpInterceptor);
    interceptors.add(new BridgeInterceptor(client.cookieJar()));
    interceptors.add(new CacheInterceptor(client.internalCache()));
    interceptors.add(new ConnectInterceptor(client));
    if (!forWebSocket) {
      interceptors.addAll(client.networkInterceptors());
    }
    // 真正的发起网络请求
    interceptors.add(new CallServerInterceptor(forWebSocket));

    Interceptor.Chain chain = new RealInterceptorChain(interceptors, null, null, null, 0,
        originalRequest, this, eventListener, client.connectTimeoutMillis(),
        client.readTimeoutMillis(), client.writeTimeoutMillis());
    // 调用链发起调用
    return chain.proceed(originalRequest);
}
```

## 参考

[浅析 OkHttp 拦截器之 RetryAndFollowUpInterceptor](https://blog.csdn.net/firefile/article/details/75346937)

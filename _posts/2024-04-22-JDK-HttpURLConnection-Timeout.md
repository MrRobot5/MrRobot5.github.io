---
layout: post
title:  "JDK-HttpURLConnection-超时管理机制"
date:   2024-04-22 18:57:51 +0800
categories: 学习笔记
tags: JNI 网络协议
---

* content
{:toc}


👉使用 JDK 的api 发起http 请求示例。http 请求连接超时其实是 Socket 连接超时。

```java
URL url = new URL("https://raw.github.com/square/okhttp/master/README.md");
// 真正的网络请求通过 sun.net.www.protocol.https.HttpsClient 实现
// 底层通过Socket 来建立网络连接
HttpURLConnection connection = (HttpURLConnection) url.openConnection();
// 作为方法参数，透传调用 java.net.Socket#connect(endpoint, timeout)
connection.setConnectTimeout(100);
```

openConnection 并不会发起网络连接。只有主动调用 connect()，或者获取response 相关的操作，才会发起网络通信。socket 连接建立通过DualStackPlainSocketImpl 实现。

参考：sun.net.www.protocol.http.HttpURLConnection#connect

### ①DualStackPlainSocketImpl

`DualStackPlainSocketImpl` 是 Java 中用于实现双栈 (IPv4/IPv6) 套接字的一个内部类。

```java
/**
 * 超时网络连接实现
 * 如果设置超时时间，首先设置操作系统socket 非阻塞模式，然后等待timeout获取socket 状态。决定是否抛中断异常
 * @param timeout 来自于 setConnectTimeout🎈
 * @see DualStackPlainSocketImpl#socketConnect(InetAddress, int, int)
 */
void socketConnect(InetAddress address, int port, int timeout) throws IOException {
    if (timeout <= 0) {
        connectResult = connect0(nativefd, address, port);
    } else {
        // 设置I/O为非阻塞模式，对应JNI Java_java_net_DualStackPlainSocketImpl_configureBlocking
        configureBlocking(nativefd, false);
        try {
            // 非阻塞模式，直接返回
            connectResult = connect0(nativefd, address, port);
            if (connectResult == WOULDBLOCK) {
                // 借助操作系统select api，实现超时等待。如果没有连接成功，则抛出异常
                // 对应JNI Java_java_net_DualStackPlainSocketImpl_waitForConnect
                waitForConnect(nativefd, timeout);
            }
        }
    }
}
```



### ②JNI

DualStackPlainSocketImpl 超时连接依赖的是操作系统 Socket Api 的超时机制。

👉 /jdk/src/windows/native/java/net/DualStackPlainSocketImpl.c

```c
/*
 * Class:     java_net_DualStackPlainSocketImpl
 * Method:    waitForConnect
 * Signature: (II)V
 */
JNIEXPORT void JNICALL Java_java_net_DualStackPlainSocketImpl_waitForConnect
  (JNIEnv *env, jclass clazz, jint fd, jint timeout) {
    // 设置超时时间
    struct timeval t;
    t.tv_sec = timeout / 1000;
    t.tv_usec = (timeout % 1000) * 1000;

    /*
     * 阻塞/等待一段时间
     */
    rv = select(fd+1, 0, &wr, &ex, &t);

    /*
     * 超过指定时间没有连接成功（rv == 0）, 则抛出异常 SocketTimeoutException，关闭 socket
     */
    if (rv == 0) {
        JNU_ThrowByName(env, JNU_JAVANETPKG "SocketTimeoutException", "connect timed out");
        shutdown( fd, SD_BOTH );
        return;
    }

}
```



## Windows Sockets API

> `DualStackPlainSocketImpl` 最终会调用 JNI（Java Native Interface）方法来执行实际的网络操作。这些 JNI 方法直接与操作系统（Windows）的网络API交互。

### ①ioctlsocket

> 作用：对 Socket 特殊的命令操作，比如非阻塞模式的设置、获取套接字的状态等。

[ioctlsocket function (winsock.h) - Win32 apps | Microsoft Learn](https://learn.microsoft.com/en-us/windows/win32/api/winsock/nf-winsock-ioctlsocket)

```c
// 命令 FIONBIO，用于设置套接字的阻塞/非阻塞模式。
// iMode 指定套接字是阻塞的（0）还是非阻塞的（非0）
iResult = ioctlsocket(m_socket, FIONBIO, &iMode);
```

### ②connect

> 作用：用于建立客户端 socket 与指定服务器的连接。

[connect 函数 (winsock2.h) - Win32 apps | Microsoft Learn](https://learn.microsoft.com/zh-cn/windows/win32/api/winsock2/nf-winsock2-connect)

- 在阻塞套接字上，返回值指示连接成功或失败。

- 使用非阻塞套接字时，无法立即完成连接尝试。 在这种情况下， 返回SOCKET_ERROR，使用 `select` 或 `WSAAsyncSelect` 等函数来检测连接何时完成。

### ③select

> 作用：监视多个套接字的状态变化，比如判断哪些套接字准备好进行读取、写入或者有异常。

[select 函数 (winsock2.h) - Win32 apps | Microsoft Learn](https://learn.microsoft.com/zh-cn/windows/win32/api/winsock2/nf-winsock2-select)

- `timeout`： `timeval` 结构的指针，该结构指定 `select` 函数等待一个事件发生的最长时间。如果设置为 `NULL`，`select` 函数将无限期等待。

## I/O多路复用

> `select` 和 `epoll` 都是I/O多路复用的技术，用于监视多个文件描述符（file descriptors）的状态变化，如可读、可写等。
> 
> 它们使得单个线程可以高效地管理多个并发I/O操作，但在实现和性能上有所不同。

- `select` 更为通用，但在处理大量文件描述符时性能较差。
- `epoll` 是Linux特有的，性能更优，特别是在高负载情况下。



## 总结

- JDK HttpURLConnection 超时机制是依赖操作系统 Socket Api 实现的。

- Socket 超时连接检测机制，和启动定时器机制类似，利于多线程配合来完成。



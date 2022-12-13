---
layout: post
title:  "Insight Jedis 和 RESP协议解析（通信协议实现 Example）"
date:   2017-11-04 10:58:52 +0800
categories: jekyll update

---

# Insight Jedis 和 RESP协议解析（通信协议实现 Example）

## RESP协议

> Redis clients use a protocol called **RESP** (REdis Serialization Protocol) to communicate with the Redis server.

- RESP can serialize different data types like integers, strings, and arrays.

- RESP uses prefixed-length to transfer bulk data.

- In RESP, different parts of the protocol are always terminated with "\r\n" (CRLF).
  
   [官方文档](https://redis.io/docs/reference/protocol-spec/) 详细介绍协议的定义和**每种数据类型的格式**。

协议规则非常简单，并且容易解析和阅读。

## Simple Strings 和Bulk Strings

- Simple Strings 用于系统内的回复等，可以理解为常量。

- Bulk Strings 用于命令参数，使用binary-safe string，确保输入数据不会因为字符集，操作系统等问题，造成数据读写问题。

- Simple String 表示“OK”为 `"+OK\r\n"`

- Bulk Strings 表示“hello”为 `"$5\r\nhello\r\n"`  ＝ 数据类型字符 + 长度 + 间隔符 + 数据 + 间隔符。

## Code Insight

    [Jedis](https://github.com/redis/jedis) is a Java client for Redis designed for performance and ease of use.

### 协议编码Example

根据协议的规范，可以用任何语言编解码通信数据。如下就是Jedis 对协议规则的实现。

```java
/**
 * set("name", "foo") Example
 * 
 * 支持的数据类型: Simple Strings, Errors, Integers, Bulk Strings and Arrays.
 * 数据类型的表示：Simple Strings(+), Errors, Integers(:), Bulk Strings($) and Arrays(*)
 * 不同的块之间一定要用CRLF间隔(\r\n)
 * @see redis.clients.jedis.Protocol#sendCommand
 */
private static void sendCommand(final RedisOutputStream os, final byte[] command, final byte[]... args) {
    try {
        os.write(ASTERISK_BYTE);// 数组类型，"*" 代表Arrays
        os.writeIntCrLf(args.length + 1);// 数组长度：参数(n) + 命令(1)， writeInt，writeCrLf 
        os.write(DOLLAR_BYTE);// String，"$" 代表Bulk Strings
        os.writeIntCrLf(command.length);// 长度
        os.write(command);// 操作命令 SET/[83, 69, 84]
        os.writeCrLf();// 间隔符号

        // 操作参数， args[0]="name".bytes(), args[1]="foo".bytes()
        for (final byte[] arg : args) {
            os.write(DOLLAR_BYTE); 
            os.writeIntCrLf(arg.length);
            os.write(arg);
            os.writeCrLf();
        }
    } catch (IOException e) {
        throw new JedisConnectionException(e);
    }
}
```

### 通信实现

> A client connects to a Redis server by creating a TCP connection to the port 6379.
> 
> Jedis 是直接使用socket 来完成通信。

```java
public void connect() {
    // 每次使用前，检查 socket 是否可用
    if (!isConnected()) {
      try {
        // socket 编程Example
        socket = new Socket();
        socket.connect(new InetSocketAddress(host, port), connectionTimeout);
        socket.setSoTimeout(soTimeout);

        if (ssl) {
            // 启用ssl 模式
            if (null == sslSocketFactory) {
                sslSocketFactory = (SSLSocketFactory)SSLSocketFactory.getDefault();
            }
            socket = (SSLSocket) sslSocketFactory.createSocket(socket, host, port, true);
        }
        // RedisOutputStream 提供buffer 和方便的协议写入方法
        outputStream = new RedisOutputStream(socket.getOutputStream());
        inputStream = new RedisInputStream(socket.getInputStream());
      } catch (IOException ex) {
        broken = true;
        throw new JedisConnectionException(ex);
      }
    }
}
```

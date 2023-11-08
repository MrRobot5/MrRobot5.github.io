---
layout: post
title:  "Communication In Lettuce(netty 编程 Example)"
date:   2018-04-12 17:11:06 +0800
categories: 学习笔记
tags: netty Redis 网络协议
---
* content
{:toc}


## Lettuce

> Lettuce is a fully non-blocking **Redis client built with netty** providing Reactive, Asynchronous and Synchronous Data Access .

## Netty In Lettuce

### ①关键类

- RedisURI [host='localhost', port=6379] 连接的封装，用于解析database password 等基础参数，还有集群，Sentinel 配置解析。

- DefaultEndpoint 通信 channel 的封装。除了提供 channel.write，还具备重连和重试的能力。

- RedisClient 负责构造和初始化Netty，thread-safe，reuse this instance as much as possible。

- ClientResources 管理（初始化和持有） **EventExecutorGroup**， Timer， EventBus 等资源。不需要重复创建。

### ②通信相关 ChannelHandler

```java
/**
 * lettuce 与 redis-server 通信提供编解码（RESP 协议），监控的实现
 * @see io.lettuce.core.ConnectionBuilder#buildHandlers()
 */
protected List<ChannelHandler> buildHandlers() {
	List<ChannelHandler> handlers = new ArrayList<>();
	handlers.add(new ChannelGroupListener(channelGroup));

	// Encodes RedisMessage into bytes following
	handlers.add(new CommandEncoder());
	// writing redis commands and reading responses from the server. core!!! 
	handlers.add(new CommandHandler());
	// 通过 eventBus 把连接状态相关的事件广播出去。
	handlers.add(new ConnectionEventTrigger(connectionEvents, connection, clientResources.eventBus()));

	// monitoring the channel and reconnecting when the connection is lost.
	if (clientOptions.isAutoReconnect()) {
		handlers.add(new ConnectionWatchdog());
	}
	return handlers;
}
```



## Netty 编程（Building a pipeline）

> Netty is *an asynchronous event-driven network application framework*  
> for rapid development of maintainable high performance protocol servers & clients.

### ①ChannelPipeline

- ChannelHandler 集合， 链式处理 channel 事件和读写操作。

- 对于I/O事件的处理顺序，可以参考 io.netty.channel.ChannelPipeline 文档的diagram。非常详细 👍

- 使用的设计模式 [Intercepting Filter pattern](http://www.oracle.com/technetwork/java/interceptingfilter-142169.html)

### ②ChannelOutboundHandler

- 下游最终到达 Socket.write()

### ③ChannelInboundHandler

- 上游源自 Socket.read()

## Redis client example in Netty

使用Netty 编写简单的Redis client 示例 [Source Code](https://github.com/netty/netty/tree/4.1/example/src/main/java/io/netty/example) ✨

```java
Bootstrap b = new Bootstrap();
b.group(group)
 .channel(NioSocketChannel.class)
 .handler(new ChannelInitializer<SocketChannel>() {
     /**
      * 发送顺序：STDIN -> RedisClientHandler -> RedisEncoder
      * 接收顺序：RedisDecoder -> RedisBulkStringAggregator -> RedisArrayAggregator -> RedisClientHandler -> STDOUT
      */
	 @Override
	 protected void initChannel(SocketChannel ch) throws Exception {
		 ChannelPipeline p = ch.pipeline();
		 // Decodes the Redis protocol into objects, that is ChannelInboundHandlerAdapter
		 p.addLast(new RedisDecoder());
		 // InboundHandler 针对Redis 协议的Bulk String 类型反序列化
		 p.addLast(new RedisBulkStringAggregator());
		 // InboundHandler 针对数组类型的返回结果反序列化
		 p.addLast(new RedisArrayAggregator());
		 // Encodes RedisMessage into bytes following, that is ChannelOutboundHandlerAdapter
		 p.addLast(new RedisEncoder());
		 // This handler read input from STDIN and write output to STDOUT, that is ChannelDuplexHandler
		 p.addLast(new RedisClientHandler());
	 }
 });

// Start the connection attempt.
Channel ch = b.connect(HOST, PORT).sync().channel();
```

## 总结

    如上的列子中可以看出，**使用Netty 实现 client 可以理解为build pipeline**。在ChannelPipeline 类文档中，详细介绍pipeline 的工作过程，以及如何使用。

    cs 架构的中间件都能看到netty 的应用场景。MQ Dubbo ElasticSearch Redis等。

    如上的Lettuce 在netty 框架的基础上，结合异步调用，queue 等特性，把性能充分的发挥出来。对于异步编程学习是个很好的参考。



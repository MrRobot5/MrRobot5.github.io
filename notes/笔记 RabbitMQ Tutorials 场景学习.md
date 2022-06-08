# RabbitMQ Tutorials 场景学习

https://www.rabbitmq.com/getstarted.html

## Work Queues

> The main idea behind Work Queues (aka: *Task Queues*) is to avoid doing a resource-intensive task immediately and having to wait for it to complete. Instead `we schedule the task to be done later`. 
>
> We encapsulate a *task* as a message and send it to a queue. A worker process running in the background will pop the tasks and eventually execute the job. When you run many workers the tasks will be shared between them.

### 应用场景

This concept is especially useful in web applications where it's impossible to `handle a complex task during a short HTTP request window`. 同步异步化思想。

### 优点和收益

One of the advantages of using a Task Queue is the ability to easily parallelise work. If we are building up a backlog of work, we can just add more workers and that way, scale easily.

### More

**MQ ACK机制（Message acknowledgment）** 半吊子英语害死人

You may wonder what happens if one of the `consumers starts a long task and dies with it only partly done`. With our current code, once RabbitMQ delivers a message to the consumer it immediately marks it for deletion. In this case, if you kill a worker we will lose the message it was just processing. We'll also lose all the messages that were dispatched to this particular worker but were not yet handled.

An acknowledgement is sent back by the consumer to tell RabbitMQ that a particular message has been received, processed and that RabbitMQ is free to delete it. `make sure a message is never lost`.

### More and More

提出问题，解决问题。

But our tasks will still be lost `if RabbitMQ server stops.`

When RabbitMQ quits or crashes it will forget the queues and messages unless you tell it not to. Two things are required to make sure that messages aren't lost: `we need to mark both the queue and messages as durable`.



## Publish/Subscribe

### fanout exchange（无差别）

Essentially（根本上）, published log messages are going to be broadcast to all the receivers.

using a `fanout exchange`, which doesn't give us much flexibility - it's only capable of mindless broadcasting(只能进行无脑的广播).

> The core idea in the messaging model in RabbitMQ is that the producer never sends any messages directly to a queue. Actually, quite often the producer doesn't even know if a message will be delivered to any queue at all.
>
> Instead, the producer can only send messages to an *exchange*. An exchange is a very simple thing. On one side it `receives messages from producers` and the other side it `pushes them to queues`. 

### Temporary queues

Firstly, whenever we connect to Rabbit we need a fresh, empty queue. To do this we could `create a queue with a random name`, or, even better - let the server choose a random queue name for us.

Secondly, once we disconnect the consumer the `queue should be automatically deleted`.

### Direct exchange(选择接收)

The routing algorithm behind a direct exchange is simple - a message goes to the queues whose binding key exactly `matches the routing key of the message`.

### Topic exchange

> Topic exchange is powerful and can `behave like other exchanges`.
>
> When a queue is `bound with "#" (hash) binding key` - it will receive all the messages, regardless of the routing key - like in fanout exchange.
>
> When special characters `"*" (star) and "#" (hash) aren't used in bindings,` the topic exchange will behave just like a direct one.

## RPC

```java
// 1. 发送请求 message
channel.basicPublish("", requestQueueName, props, message.getBytes("UTF-8"));
// 2. 利用BlockingQueue，实现异步调用的协调
// delivery handling is happening in a separate thread, we're going to need something to suspend the main thread before the response arrives.
final BlockingQueue<String> response = new ArrayBlockingQueue<>(1);
// 3. 临时订阅QueueName， 处理返回 message
String ctag = channel.basicConsume(replyQueueName, true, (consumerTag, delivery) -> {
    // unique correlationId number，match the appropriate response
	if (delivery.getProperties().getCorrelationId().equals(corrId)) {
		response.offer(new String(delivery.getBody(), "UTF-8"));
	}
}, consumerTag -> {
});
// 4. 线程阻塞，等待结果
String result = response.take();
channel.basicCancel(ctag);

```





# 名词解释

- Round-robin dispatching

  > RabbitMQ will send each message to the next consumer, in sequence. On average every consumer will get the same number of messages. This way of distributing messages is called round-robin. 

- *Remote Procedure Call* or *RPC*

  >  run a function on a remote computer and wait for the result
  >
  > Confusions like that result in an unpredictable system and adds unnecessary complexity to debugging(给调试带来不必要的麻烦). Instead of simplifying software, misused RPC can result in unmaintainable spaghetti code（误用RPC，会导致不可控的意大利面式的代码）.

- 












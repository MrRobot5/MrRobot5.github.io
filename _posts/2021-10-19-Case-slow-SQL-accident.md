---

layout: post
title:  "Case 因为慢SQL导致的线上服务不可用"
date:   2021-10-19 21:34:11 +0800
categories: jekyll update

---

# Case 因为慢SQL导致的线上服务不可用

> 记一次线上事故排查过程，事故的根本原因是慢SQL 查询。但线上问题的情况以及监控工具指标表现，并没有直接指向慢SQL 的问题，排查的过程值得记录和反思。

## 线上事故

系统使用人员反馈系统的操作卡顿或者不可用，数据列表查询有问题，后端请求响应非常慢。

## 初步问题排查分析

首先，第一反应应该是web-server出问题或者mysql-server 出问题。比如CPU打满或者内存打满，导致的服务不可用。

通过监控工具查看应用服务器的指标、JVM指标以及数据库服务器CPU、磁盘的指标，都处于正常范围。

然后，猜想是程序、功能方面的问题，通过查询mysql 状态，并**没有发现有查询的慢SQL**。查询JVM线程，没有突增。

那么问题是出现在哪呢？

## 问题排查分析plus

上述的基础指标排除完毕，那就尝试看是否有并发锁等待、事务死锁、mysql 死锁的情况。

### 线程dump

通过dump JVM线程，发现有很多线程等待，前端请求线程在调用getConnection()时候，阻塞了。

```
java.lang.Thread.State: TIMED_WAITING (parking)
        at sun.misc.Unsafe.park(Native Method)
        - parking to wait for  <0x0a9d2f48> (a java.util.concurrent.locks.AbstractQueuedSynchronizer$ConditionObject)
        at java.util.concurrent.locks.LockSupport.parkNanos(LockSupport.java:215)
        at com.alibaba.druid.pool.DruidDataSource.pollLast(DruidDataSource.java:1487)
        at com.alibaba.druid.pool.DruidDataSource.getConnectionInternal(DruidDataSource.java:1086)
        at com.alibaba.druid.pool.DruidDataSource.getConnectionDirect(DruidDataSource.java:953)
        at com.alibaba.druid.pool.DruidDataSource.getConnection(DruidDataSource.java:931)
```

### Insight getConnection()

DruidDataSource 实现线程池的机制是典型的生成者、消费者模式，通过类似BlockingQueue 来实现连接池的管理。

通过分析，是因为持有数据库连接的线程一直占用连接，导致其他需要和数据库交互的请求线程等待。这样的结果造成了系统的JVM CPU和堆栈都是正常情况，但是服务不可用。

同时，由于应用服务是受制于数据库连接池maxActive 的限制，并不会无限制创建mysql connection，导致数据库的IO链接也处于正常范围。

那么是什么请求一直在占用有限的connections？

```java
private DruidConnectionHolder pollLast(long nanos) throws InterruptedException {
    for (;;) {
        if (poolingCount == 0) {
            try {
                long startEstimate = estimate;
                // 如果连接池的连接都在工作，那么就需要等待
                estimate = notEmpty.awaitNanos(estimate); // signal by recycle or creator
                notEmptyWaitCount++;
                notEmptyWaitNanos += (startEstimate - estimate);
            } catch (InterruptedException ie) {
                notEmpty.signal(); // propagate to non-interrupted thread
            } finally {
                notEmptyWaitThreadCount--;
            }
        }

        // 从连接池获取空闲的连接，并标记
        decrementPoolingCount();
        DruidConnectionHolder last = connections[poolingCount];
        connections[poolingCount] = null;

        return last;
    }
}
```

### 原来是update

通过导出mysql 慢查询日志，发现竟然有超长执行时间的update语句。

在一开始的排查过程中，只关注事故的表象，排查select 慢sql并没有问题，导致排查走了弯路。

```sql
UPDATE `orders` SET `order_carrier_tel`='xxx-xxx-5501' WHERE `order_carrier_name`= 'xxx';
```

由于昨天新上的编辑功能，update 的where 条件没有索引，导致全表扫描，形成慢sql。

## 总结

1. 敬畏每一次上线。对于关键系统的code review 是不可缺失的，一次的疏忽或者冷门功能点的问题，都会导致线上的事故。
2. 90%的问题是出在数据库交互过程中。平时的代码编写，SQL编写一定要慎重。只有面对线上环境的请求和庞大的数据量时，才是真正的考验。

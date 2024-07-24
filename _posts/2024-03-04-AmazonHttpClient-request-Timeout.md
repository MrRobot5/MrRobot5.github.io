---
layout: post
title:  "AmazonHttpClient request 超时管理实现"
date:   2024-03-04 18:00:35 +0800
categories: 源码阅读 算法
tags: 架构设计 并发编程
---

* content
{:toc}

> 通过使用计时器任务和中断机制，实现了对客户端执行HTTP请求超时的管理。
> 
> 如果请求执行时间超过了设定的超时时间，则自动中断请求。
> 
> 有效地避免因为网络问题或服务器响应慢导致的客户端线程长时间挂起的问题。

## 计时器中断方案

> 常用的资源管理方案，启动线程异步监控和中断工作任务。🎈

### ①整体方案实现

```java
/**
 * 使用计时器方案，当http 请求超时，中断操作。
 * @see com.amazonaws.http.timers.client.ClientExecutionTimer 中断计时器
 * @see 源码
 */
private Response<Output> executeWithTimer() throws InterruptedException {
    // 启动一个计时器（异步线程），这个计时器在客户端执行超时时会被触发。
    ClientExecutionAbortTrackerTask clientExecutionTrackerTask =
            clientExecutionTimer.startTimer(getClientExecutionTimeout(requestConfig));
    try {
        executionContext.setClientExecutionTrackerTask(clientExecutionTrackerTask);
        // 执行正常的 http 请求
        return doExecute();
    } finally {
        // 取消计时器任务，避免不必要的中断。
        executionContext.getClientExecutionTrackerTask().cancelTask();
    }   
}

```

### ②中断任务调度

```java
/**
 * 启动一个计时器任务（定时调度），当客户端执行超过指定的超时时间时，这个任务会被执行。
 * @see com.amazonaws.http.timers.client.ClientExecutionTimer#scheduleTimerTask 源码
 */
private ClientExecutionAbortTrackerTask scheduleTimerTask(int clientExecutionTimeoutMillis) {
    // 执行中断当前线程并中止HTTP请求。
    ClientExecutionAbortTask timerTask = new ClientExecutionAbortTaskImpl(Thread.currentThread());
    // 调度延迟任务
    ScheduledFuture<?> timerTaskFuture = executor.schedule(timerTask, clientExecutionTimeoutMillis,
            TimeUnit.MILLISECONDS);
    return new ClientExecutionAbortTrackerTaskImpl(timerTask, timerTaskFuture);
}
```

### ③中断任务执行

```java
/**
 * @see com.amazonaws.http.timers.client.ClientExecutionAbortTaskImpl 源码
 */
public class ClientExecutionAbortTaskImpl implements ClientExecutionAbortTask {

    // 存储当前正在执行的HTTP请求 和任务线程，以便在需要时可以被中止。
    private HttpRequestBase currentHttpRequest;
    private final Thread thread;

    /**
     * 触发时中断调用线程并中止HTTP请求。
     */
    public void run() {
        if (!thread.isInterrupted()) {
            thread.interrupt();
        }
        if (!currentHttpRequest.isAborted()) {
            // 调用httpclient abortConnection()。 
            // Closes this socket.
            currentHttpRequest.abort();
        }                                    
    }
}
```



## 延时任务调度

> 使用工具类 TimeoutThreadPoolBuilder， 创建 ScheduledThreadPoolExecutor 来完成定时任务的调度。

### ①ScheduledThreadPoolExecutor

```java
/**
 * 创建执行延迟任务的线程池。
 * @see com.amazonaws.http.timers.TimeoutThreadPoolBuilder
 */
public static ScheduledThreadPoolExecutor buildDefaultTimeoutThreadPool(final String name) { 
    // 自定义的线程工厂，设置线程的名称、优先级等属性，有助于更好地管理和识别线程池中的线程。
    ScheduledThreadPoolExecutor executor = new ScheduledThreadPoolExecutor(5, getThreadFactory(name));
    // executor.setRemoveOnCancelPolicy(true);
    // 如果任务被取消，那么这个任务将会从线程池的工作队列中移除。防止因已取消的任务仍占用内存而导致的内存泄漏。
    safeSetRemoveOnCancel(executor);
    // 设置了非核心线程在空闲存活的时间。
    // 如果5秒内没有新的任务分配给它们，这些线程将被终止并从线程池中移除。有助于在负载较低时减少资源消耗。
    executor.setKeepAliveTime(5, TimeUnit.SECONDS);
    // 核心线程在空闲时也会在空闲存活的时间后被终止。🙉
    // 源码：int min = allowCoreThreadTimeOut ? 0 : corePoolSize;
    executor.allowCoreThreadTimeOut(true);

    return executor;
}

```

### ② DelayedWorkQueue

> DelayedWorkQueue 是一个为了提高性能特别设计的延迟队列，通过在内部使用基于堆的数据结构和维护任务索引，高效地管理和执行延迟任务。

- 使用基于堆的数据结构。堆是一种特殊的完全二叉树，其中每个节点都有一个值，父节点的值总是大于或小于其子节点的值，这使得堆可以有效地支持插入和删除最小（或最大）元素的操作。

- 除了存储任务本身外，还记录了它在堆数组中的索引。这个设计使得在取消任务时无需遍历整个队列来查找任务，从而将移除操作的时间复杂度从O(n)降低到O(log n)。当任务被移除时，它的`heapIndex`会被设置为-1，表示它不再位于堆中。

### ③堆操作

```java
/**
 * DelayedWorkQueue的siftUp方法是一个典型的堆操作，用于在添加新元素时维护堆的有序性。
 * 通过比较新元素与其父节点的顺序，并在必要时上移新元素，这个方法确保了堆结构的正确性和效率。
 * @see java.util.concurrent.ScheduledThreadPoolExecutor.DelayedWorkQueue#siftUp
 */
private void siftUp(int k, RunnableScheduledFuture<?> key) {
    // 只要当前元素不是根元素（堆的顶部），循环就继续。
    while (k > 0) {
        // 计算父节点索引
        int parent = (k - 1) >>> 1;
        RunnableScheduledFuture<?> e = queue[parent];
        // 比较当前元素与父节点
        if (key.compareTo(e) >= 0)
            // 如果key大于等于e（最小堆），则说明已经找到了key的正确位置，循环可以终止。
            break;
        // 交换元素和更新索引。如果当前元素小于其父节点，则将父节点下移
        queue[k] = e;
        setIndex(e, k);
        k = parent;
    }
    // 循环结束后，将key放置在其正确的位置
    queue[k] = key;
    setIndex(key, k);
}
```



# 笔记-parallel stream 实现原理

## Stream 基础概念

- A sequence of elements supporting **sequential** and **parallel** aggregate operations.

- A stream pipeline consists of a source, zero or more intermediate operations, and a terminal operation

- Streams are lazy

## 关键类

了解了上述的概念，要分析 parallel stream 作用原理，就要从*terminal operation* 源码入手。

```java
/**
 * Stream 定义的接口可以作为源码阅读的切入口
 *
 * Returns whether this stream, if a terminal operation were to be executed,
 * would execute in parallel. 注意：terminal operation executed
 * @see java.util.stream.BaseStream#isParallel
 */
boolean isParallel();
```

- **java.util.stream.AbstractPipeline**  *the core implementations of the Stream interface*

- java.util.stream.TerminalOp

- java.util.stream.ForEachOps.ForEachOp

- java.util.stream.ReduceOps.ReduceOp

## parallel stream

```java
/**
 * 通过TerminalOp 发生真正的调用，是否并行，在此处确定
 * Evaluate the pipeline with a terminal operation to produce a result.
 *
 * @see java.util.stream.AbstractPipeline#evaluate(java.util.stream.TerminalOp<E_OUT,R>)
 */
final <R> R evaluate(TerminalOp<E_OUT, R> terminalOp) {
	return isParallel() ? terminalOp.evaluateParallel(...) : terminalOp.evaluateSequential(...);
}
```

### 实现-ForEachOp

```java
// 这样的Terminal Operation
persons.parallelStream().map(person -> person.name).forEach(System.out::println)

```

如何实现并发调用，只需要关注`evaluateParallel` 方法。

`new ForEachTask<>(helper, spliterator, helper.wrapSink(this)).invoke();`

`class ForEachTask<S, T> extends ForkJoinTask<T>`

至此，我们就知道**并发是依靠ForkJoinTask 实现的。**



### 实现-ReduceOp

```java
// 这样的Terminal Operation
persons.parallelStream().map(person -> person.name).collect(Collectors.joining(";"))
```



## ForkJoinPool

> 分治算法。主旨是将大任务分成若干小任务，之后再并行对这些小任务进行计算，最终汇总这些任务的结果。
> 
> 工作窃取算法。避免工作线程由于拆分了任务之后的join等待过程。

### ForkJoinTask

> A ForkJoinTask **is a thread-like entity** that is much  lighter weight than a normal thread.  Huge numbers of tasks and  subtasks may be hosted by a small number of actual threads in a  ForkJoinPool, at the price of some usage limitations. --简单的说，通过线程池，提升并发性能的一种 fork/join实现。
> 
> 
> 
> In the most typical usages, **a fork-join pair act like a call  (fork) and return (join) from a parallel recursive function**.

### 常用配置

- java.util.concurrent.ForkJoinPool.common.parallelism

- java.util.concurrent.ForkJoinPool.common.threadFactory

来源： java.util.concurrent.ForkJoinPool#makeCommonPool





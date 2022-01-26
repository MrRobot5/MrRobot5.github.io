# Tips-Java CAS 使用实例分析

> 并发编程在实际生产应用中，如果使用不当，会有意想不到的诡异问题。
>
> 文章摘取一段Java AtomicLong 在统计功能上的使用，分析并发计数应该注意的点。

## 并发计数代码

```java
/**
 * jetty 服务中，需要统计全局的连接数、请求数量之类的指标。提供了CounterStatistic 类用于统计这些数据。
 * 其中，Statistic 就是借助AtomicLong 来实现total, maximum 数量的并发计数。
 *
 * @from org.eclipse.jetty.util.statistic.CounterStatistic
 */
public class CounterStatistic {

    protected final AtomicLong _max = new AtomicLong();
    protected final AtomicLong _curr = new AtomicLong();

    /**
	 * 计数增加的操作，同时会更新max 的值。
	 * @param delta the amount to add to the count，传入负值就是减少操作
	 */
    public void add(final long delta) {
        long value=_curr.addAndGet(delta);
        
        // max 赋值并没有使用 AtomicLong#getAndSet， why?
        // 因为在并发环境下，只有确定当前的max 是真正的最大值时，才能赋值到max 变量中。
        long oldValue = _max.get();
        // case1：如果第一次 value <= oldValue，那么直接跳过，max 维持不变。
        // case2: 如果第一次 value > oldValue，但是因为并发问题，没有compareAndSet 成功。再比较时，value <= oldValue，则直接跳过。需要考虑重试赋值过程中并发的问题。
        while (value > oldValue) {
            // 如果赋值成功，则说明value 是此刻的最大值。
            if (_max.compareAndSet(oldValue, value))
                break;
            oldValue = _max.get();
        }
    }
    
}

```

## 知识点

### CAS

CAS 全称是 `compare and swap`，是一种用于在多线程环境下实现同步功能的机制。

CAS 是一条 CPU 的原子指令（ cmpxchg 指令），不会造成数据不一致问题。Java Unsafe提供的 CAS 方法（如 compareAndSwapXXX ）底层实现即为 CPU 指令 cmpxchg。

参考：[Java CAS 原理详解](https://www.cnblogs.com/huansky/p/15746624.html)

### Unsafe

Unsafe类使Java语言拥有了类似C语言指针一样操作内存空间的能力。

参考：[Java魔法类：Unsafe应用解析](https://tech.meituan.com/2019/02/14/talk-about-java-magic-class-unsafe.html)


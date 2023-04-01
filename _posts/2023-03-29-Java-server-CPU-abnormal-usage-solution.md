---
layout: post
title:  "Java 服务CPU 使用率高排查思路"
date:   2023-03-29 18:44:52 +0800
categories: jekyll update
---

# Java 服务CPU 使用率高排查思路

> CPU 使用高一般原因是出现代码死循环。
> 
> 寻找到死循环的代码，就需要找对应的 stack。
> 
> 匹配JVM stack,就需要查找CPU 使用率高的进程/线程。
> 
> 遵循上述思路，总结排查步骤。

## 排查步骤

1. 查找java 进程id
   
   ```shell
   # 获取java 进程信息。 eg: 进程id = 12309
   jps -v
   ```

2. 查找 java 进程的线程 CPU 使用率
   
   ```shell
   # -p 用于指定进程，-H 用于获取每个线程的信息
   top -p 12309 -H
   ```

3.  获取java 进程的 stack
   
   ```shell
   jstack -l 12309 > stack.log
   ```

4. 结合上述2 和 3 的结果，通过匹配线程id，获取对应的stack 详情



## jstack 信息

```shell
# jstack 线程详情样例
# http-nio-8080-exec-7 是线程名称，创建线程一般会指定name，便于排查运维
# tid 就是Java 线程id, 16进制表示。
"http-nio-8080-exec-7" #317 daemon prio=5 os_prio=0 tid=0x0000018effd28000 nid=0x2ccc runnable [0x0000007c8f0fb000]
   java.lang.Thread.State: RUNNABLE
        at java.lang.Throwable.fillInStackTrace(Native Method)
        at java.lang.Throwable.fillInStackTrace(Throwable.java:784)
        - locked <0x00000007769c0238> (a java.lang.Throwable)
        at java.lang.Throwable.<init>(Throwable.java:251)
        at ch.qos.logback.classic.spi.LoggingEvent.getCallerData(LoggingEvent.java:258)
        at ch.qos.logback.classic.pattern.FileOfCallerConverter.convert(FileOfCallerConverter.java:22)
        at ch.qos.logback.classic.pattern.FileOfCallerConverter.convert(FileOfCallerConverter.java:19)
        at ch.qos.logback.core.pattern.FormattingConverter.write(FormattingConverter.java:36)
```



## 注意事项

1. 遇到线上故障，摘一台机器，作为后续分析样本。

2. 线上故障解决，滚动重启服务，防止流量突然涌入存活的机器，造成更严重的问题。



















---

layout: post
title:  "snippets-单例写法 🙉"
date:   2021-12-01 18:11:29 +0800
categories: 学习笔记
tags: Spring
---
* content
{:toc}

## 常用写法 double check

**来源：org.springframework.core.convert.ConversionService**

```java
private static volatile DefaultConversionService sharedInstance;

/**
 * Return a shared default ConversionService instance, lazily building it once needed.
 * 
 * @return the shared {@code ConversionService} instance (never {@code null})
 * @since 4.3.5
 */
public static ConversionService getSharedInstance() {
    if (sharedInstance == null) {
        synchronized (DefaultConversionService.class) {
            if (sharedInstance == null) {
                sharedInstance = new DefaultConversionService();
            }
        }
    }
    return sharedInstance;
}
```

## 枚举写法

**来源：com.atomikos.thread.TaskManager**

```java
public enum TaskManager {
    SINGLETON;

    private ThreadPoolExecutor executor;

    private void init() {
        SynchronousQueue<Runnable> synchronousQueue = new SynchronousQueue<Runnable>();
        executor = new ThreadPoolExecutor(0, Integer.MAX_VALUE, new Long(60L),
                TimeUnit.SECONDS, synchronousQueue, new AtomikosThreadFactory());
    }

}
```

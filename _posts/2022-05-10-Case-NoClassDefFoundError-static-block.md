---
layout: post
title:  "Case NoClassDefFoundError案例-static 代码块"
date:   2022-05-10 15:22:06 +0800
categories: jekyll update
---
# NoClassDefFoundError案例-static 代码块

## 问题背景

> 应用为了数据加密，引用了一个加密组件。使用的Maven 依赖，启动应用后，直接报错：`java.lang.NoClassDefFoundError: Could not initialize class com.foo.security.handle.AcesCipherText`
> 
> 一开始错误理解为 `ClassNotFoundException`，以为是包下载、编译的问题，反复clean，update snapshot。
> 
> 后来才发现是 ClassLoader 试图加载类的定义时出现错误，是在加载到类文件之后发生的。

## 源码分析

```java
public final class AcesCipherTextHandle<E> extends BaseTypeHandler<E> {
    public AcesPlainTextHandle() {
    }

    public E getNullableResult(ResultSet rs, String columnName) throws SQLException {
        return AcesCipherTextService.getIns().getResult(rs, columnName);
    }

    static {
        // 没有找到对应的配置文件，导致必要的加密参数为空，直接 throw RuntimeException。结果是Class加载失败。
        // 发生在Class.forName() 调用过程中
        LoadProperties.loadProps();
    }
}
```

## 问题解决和总结

1. 在应用classpath 下增加组件需要的配置文件，保证类加载过程中，上述的静态代码块正常执行。
2. **认真看错误日志**，严谨对待，这样能减少误解引起的不必要浪费时间。

## static 关键字

> A *class initialization block* is a block of statements preceded by the `static` keyword that's introduced into the class's body. 
> 
> When the class loads, these statements are executed.



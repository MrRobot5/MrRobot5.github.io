---
layout: post
title:  "Spring BeanCopier Bug"
date:   2024-06-04 21:43:31 +0800
categories: 实战问题
tags: Spring 动态代理
---

* content
{:toc}

> 使用Spring BeanCopier 拷贝对象过程中，发现了一个Bug。
> 
> 问题版本：3.2.0.RELEASE

## Bug 场景

`BeanCopier` 是一个非常高效的复制工具，因为它在运行时生成字节码来执行复制操作，而不是使用反射。

### ①需要拷贝的类🧲

```java
public static class TargetBean {

    private String name;

    // name's getters and setters

    // 没有 mixed 属性，Introspector 识别为布尔类型的 getter 方法
    public String isMixed() {
        return name.contains("mix");
    }

}
```

### ②拷贝异常❌

```java
// 创建 BeanCopier 实例。
// 作用原理：使用CGlib库生成一个新类，该类的目的是实现Java Bean 之间属性的复制。
// 在匹配和获取 TargetBean setters过程中，出现异常 java.lang.NullPointerException
BeanCopier copier = BeanCopier.create(TargetBean.class, TargetBean.class, false);

// 复制属性
copier.copy(source, target, null);
```

### ③日常日志

```log
Exception in thread "main" java.lang.NullPointerException
        at org.springframework.cglib.core.ReflectUtils.getMethodInfo(ReflectUtils.java:424)
        at org.springframework.cglib.beans.BeanCopier$Generator.generateClass(BeanCopier.java:133)
        at org.springframework.cglib.core.DefaultGeneratorStrategy.generate(DefaultGeneratorStrategy.java:25)
        at org.springframework.cglib.core.AbstractClassGenerator.create(AbstractClassGenerator.java:216)
        at org.springframework.cglib.beans.BeanCopier$Generator.create(BeanCopier.java:90)
        at org.springframework.cglib.beans.BeanCopier.create(BeanCopier.java:50)
```

## 问题分析

> 创建BeanCopier 实例的过程中，会根据TargetBean 遍历所有的 setter方法，尝试找到与之对应的 getter方法。
> 
> 如上述的场景，针对属性“mixed”, 并没有对应的 setter方法，所以报错。
> 
> 为什么 BeanCopier 会出现没有判断 null 的低级错误呢？🙉

### ①Introspector

Java Bean 是一种特殊的 Java 类，**遵循特定的命名规则**，比如属性的命名方式、事件处理方法等。

`Introspector` 类使得开发者能够通过反射机制来分析一个 Java Bean 的属性和方法，而不需要直接与类的代码交互。

```java
// Introspector 识别的命名约定🧲
// 属性的读取方法（getter）
static final String GET_PREFIX = "get";
// 属性的设置方法（setter）
static final String SET_PREFIX = "set";
// 布尔属性的特殊读取方法。对于返回类型为 boolean 的属性，按照习惯，其读取方法可以使用 "is" 前缀而不是 "get"。
static final String IS_PREFIX = "is";
```

根据约定，TargetBean 中的 isMixed 方法会识别为“mixed”属性的读取方法。

### ②BeanCopier

```java
/**
 * 用CGlib库生成一个新类的过程，实现两个Java Bean之间属性的复制。
 * @see org.springframework.cglib.beans.BeanCopier.Generator#generateClass
 */
public void generateClass(ClassVisitor v) {
    Type sourceType = Type.getType(this.source);
    Type targetType = Type.getType(this.target);

    PropertyDescriptor[] getters = ReflectUtils.getBeanGetters(this.source);
    // Bug:  mixed 属性描述符也会返回到 setters集合中。实际上，该属性描述符并没有 WriteMethod。
    // fix: setters = ReflectUtils.getBeanSetters(this.target);
    PropertyDescriptor[] setters = ReflectUtils.getBeanGetters(this.target);
    // 遍历所有的setter方法，尝试找到与之对应的getter方法。
    for(int i = 0; i < setters.length; ++i) {
        PropertyDescriptor setter = setters[i];
        PropertyDescriptor getter = (PropertyDescriptor)names.get(setter.getName());
        if (getter != null) {
            MethodInfo read = ReflectUtils.getMethodInfo(getter.getReadMethod());
            // mixed 属性的描述符（setter）对应的 WriteMethod = null, 所以抛异常。
            MethodInfo write = ReflectUtils.getMethodInfo(setter.getWriteMethod());
            if (compatible(getter, setter)) {
                e.dup2();
                e.invoke(read);
                e.invoke(write);
            }
        }
    }
}
```

### ③导出动态类

可以自定义 ClassFileTransformer， 拦截类的加载过程，并在类被加载到 JVM 之前导出类的字节码。

[使用 java agent 导出动态类](https://github.com/MrRobot5/java-snippet) 🧲

👉生成的动态类路径和 copy 接口实现

<img src="{{ "/images/Snipaste_2024-06-05_11-09-41.png" | prepend: site.baseurl }}" alt="BeanCopier$Generator" style="zoom:50%;" />

## More

其实这个是CGLIB 的bug，从 Spring 3.2 开始，`CGLIB` 的功能被整合进了 Spring。

这个Bug 在Spring 后续版本中已经被修复。✔

不过 cglib-nodep 修复比较慢， 使用cglib-nodep 需要注意这个问题。🎈

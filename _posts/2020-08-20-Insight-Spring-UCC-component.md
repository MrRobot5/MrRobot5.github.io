---

layout: post
title:  "Spring UCC 组件实现思路和改进思考"
date:   2020-08-20 11:12:22 +0800
categories: 源码阅读
tags: Spring

---
* content
{:toc}


> UCC-统一配置中心，实现对应用系统需要实时调整的配置属性进行管理，比如各种开关、阈值、重试次数等。
> 
> Spring-UCC 组件实现思路：基于ZooKeeper，实现配置的保存和分发。通过ZK的节点watch特性，实现管理端修改完配置数据后，每个应用的ZK client 都可以收到变动数据。`然后通过约定的配置，将对应数据同步到 Config Bean 对应的属性。`最终达到实时修改应用配置属性的目的。

### 问题描述

功能开发中，使用UCC 配置了业务阈值用来是否监控报警。结果发现通过UCC管理端修改配置数值后，线上打印的配置一直没有发生变化。按照Spring 常用的、约定的配置方法，不应该出现问题呀。

### Spring-UCC 主要配置与分析

#### 主要配置

```xml
<!-- Spring-UCC 集成启动的核心，通过UccConfigCenter 完成zk client启动、节点检查、节点监听以及应用配置数据的检查和加载 -->
<bean class="com.foo.ucc.client.service.UccConfigCenter">
    <constructor-arg index="0" ref="zkConfig"/>
    <constructor-arg index="1" ref="propertyConfig"/>
</bean>

<!-- 主要功能：当监听的ZK node数据发生变化时，负责完成 propertyConfig 配置属性的重新赋值 -->
<bean id="propertyConfigProcessor" class="com.foo.ucc.client.PropertyConfigProcessor"/>
<bean id="propertyConfig" class="com.foo.ucc.client.config.UccPropertyConfig">
    <property name="processor" ref="propertyConfigProcessor" />
    <property name="keyList">
        <list>
            <!-- 约定配置格式：BeanName.property -->
            <value>configFoo.name</value>
            <value>configFoo.age</value>
        </list>
    </property>
</bean>
```

```java
/**
 * 应用 ucc 配置的开关和阈值
 */
@Data
@Component
public class ConfigFoo {

    private String name;

    /**
     * 不能实时配置生效的属性
     */
    private double age;

}
```

#### 源码实现分析

配置不能实时生效，问题排查有两个方向：**ZK 的通知机制**，**通知数据同步到ConfigFoo 的机制**。

```java
/**
 * ZK 的通知机制
 *
 * UCC 初始化配置过程中，会给具体的配置项（此处抽象为 PathCache）注册对应的监听器
 * 其中PathCache、IZkNodeListener 都是对zookeeper 原生API的包装，使操作使用更加的方便。
 * @From UccConfigCenter
 */
PathCache pathCache = new PathCache(uccClient.getZkClient(), path);

// 典型的观察者设计模式，把监听器集合关联到对应的path，当zk path 发生数据变化时，依赖他的监听器都会得到通知，执行具体的业务逻辑。数据结构： Map<String, Set<IZkNodeListener>> nodeListener
pathCache.addNodeChangedListener(new IZkNodeListener() {
    // 调用链：org.apache.zookeeper.Watcher#process -> fireNodeChangedEvents -> 根据path 获取对应的listener集合 -> listener.handleNodeChange
    public void handleNodeChange(String path, Object data) throws Exception {
        // 通知数据同步到ConfigFoo
        loadConfigOnDataChangeEvent(propertyKey, pathArg, false);
    }
});
```

```java
/**
 * 通知数据同步到ConfigFoo 的机制
 * 
 * 参考上述的UccPropertyConfig 配置，具体的propertyKey 有对应的PropertyConfigProcessor 负责处理zk 变化的数据。关键是propertyKey, 和path。
 * @param propertyKey,根据约定格式，可以得到beanName 和他的field，通过反射调用赋新值
 * @param path，根据path 获取zk的data，即配置的最新业务数值
 * @From PropertyConfigProcessor#process
 */
public boolean process(String propertyKey, String path) {
    String toChangeValue = new String(zookeeper.getData(path, watch, stat));
    List<String> splitList = GuavaUtils.strSplitWithTrim(propertyKey, ".");

    String beanName = splitList.get(0);
    String fieldName = splitList.get(1);
    bean = applicationContext.getBean(beanName);

    // 通过反射调用，给bean.field 赋值。问题出在这里，toChangeValue 在转化为field 定义的类型，源码是通过枚举常用的类型实现的，只支持Integer、String、Boolean。ConfigFoo.age 是double，不支持转换，忽略了。
    return FieldChangeUtils.changeField(toChangeValue, fieldName, bean);
}
```

### 总结和改进方案

#### 问题总结

1. 配置属性定义的double类型，组件不支持类型转换，直接忽略了。UCC配置的数值，通过zk的通知机制，触发了新数据的同步逻辑，但是`组件内置反射工具不支持double赋值，所以新的配置没有生效`。
2. 使用组件要仔细阅读文档，明确功能特性的支持范围，不能想当然的使用。虽然在Spring 概念中，类型转换应该是理所应当的。

#### 改进方案

1. Spring-UCC 组件在ZooKeeper 的封装和应用配置功能的丰富度都可圈可点，有很多值得学习的地方。但是数据的同步更新功能，作为核心的功能和基础的支持，如此简陋，也是非常的遗憾。

2. 改进方案：从Spring 框架实现中拾取类型转换的黑魔法。`可以直接用 DefaultConversionService#convert 替换上述自己实现的反射工具类`。支持的类型丰富、场景多样。

​        

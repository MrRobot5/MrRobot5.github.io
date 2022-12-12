---

layout: post
title:  "笔记 mybatis 参数封装和处理相关方法"
date:   2021-10-20 17:52:14 +0800
categories: jekyll update

---

# 笔记 mybatis 参数封装和处理相关方法

> 清单目的：在使用到mybatis 冷门特性时候，可以快速参考查阅

## 1. ParamNameResolver#getNamedParams

方法入参封装，根据方法参数的个数，有不同的处理方法。

| 参数个数                | 处理方法           | 备注                                          |
| ------------------- | -------------- | ------------------------------------------- |
| 0                   | return null    |                                             |
| 1 （非特殊类型 or @Param） | return 原始入参对象  | 需要特别注意，如果在动态SQL中使用，则不能为String、Integer等简单类型。 |
| >=2                 | return HashMap | name即参数的name，通过@Param指定的name或者JDK反射得到的name。 |

方法中使用到的**方法参数**，是在mybatis 启动过程中加载对应method并解析得到的。需要主要到`@Param` 和`JDK8 Parameter` 对mybatis 解析的影响。

*如果使用JDK8，对于接口的参数，是可以获取到参数编写的命名，否则得到参数name类似"arg0"*

## 2.DefaultSqlSession#wrapCollection

针对第1步中的封装结果，如果是**单个参数的情况**，则需要针对数组和集合进行单独封装。

| 参数类型       | 处理方法                                                 | 备注                |
| ---------- | ---------------------------------------------------- | ----------------- |
| Collection | return HashMap("collection", object)                 | 固定name=collection |
| List       | return HashMap("collection", object, "list", object) | 固定name=list       |
| Array      | return HashMap("array", object)                      | 固定name=array      |

## 3. DynamicSqlSource#getBoundSql

此时，需要根据入参把动态sql转化为StaticSqlSource，再将StaticSqlSource 转换为sql String。

上述参数封装的结果，就是把各种入参对象整合到单个对象里（`DynamicContext`），方便统一读取（`MetaObject`）。

后续的处理中，直接使用DynamicContext 获取参数，不再使用原始的参数。

### ForEachSqlNode 转化为StaticSqlSource示例

foreach 表达式的解析，是把collection拆散的过程，可以理解为把集合类型的参数拆成n个参数。

```sql
# foreach 表达式静态转换示例
# DynamicContext 中会新增（__frch_item_0：id1, __frch_item_1：id2）的参数
# org.apache.ibatis.scripting.xmltags.ForEachSqlNode#apply
select xxx from candy  WHERE id IN ( #{__frch_item_0},  #{__frch_item_1} );
```

### StaticSqlSource 转换为BoundSql

StaticSqlSource 转换为BoundSql，也就是转为真正的SQL的过程。SQL中占位符只存在？符号。

上述的foreach 最终的结果为

```sql
# An actual SQL String
# 占位符对应的参数，存储到 org.apache.ibatis.mapping.BoundSql#parameterMappings
select xxx from candy  WHERE id IN ( ?, ? );
```

## 4. DefaultParameterHandler#setParameters

以BoundSql 为基础，调用java.sql.PreparedStatement#setString，完成JDBC调用。

## 附：关于JDK8 Parameter的使用

从方法中获取参数的命名，是个麻烦的事情，特别是从接口中。JDK8 以后支持这种操作，不过需要编译参数启用。

如果使用maven，那么可以加上如下的配置，启用这个特性。

```xml
<build>
    <plugins>
        <plugin>
            <groupId>org.apache.maven.plugins</groupId>
            <artifactId>maven-compiler-plugin</artifactId>
            <version>3.7.0</version>
            <configuration>
                <source>1.8</source>
                <target>1.8</target>
                <compilerArgs>
                    <arg>-parameters</arg>
                </compilerArgs>
            </configuration>
        </plugin>
    </plugins>
</build>
```

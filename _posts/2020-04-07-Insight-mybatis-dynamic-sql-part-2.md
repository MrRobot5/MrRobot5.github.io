---

layout: post
title:  "Case mybatis 动态sql解析-使用问题"
date:   2020-04-07 21:12:24 +0800
categories: jekyll update

---

# Case mybatis 动态sql解析-使用问题

> part1 主要分析动态sql 参数相关的解析，对于xml-> sql 的过程没有详细分析，此文补上。[part1 GO.](https://blog.csdn.net/tt50335971/article/details/72484023)
> 
> 问题：工作中遇到的一个bug，mybatis 查询有个参数为0，导致拼接的sql异常。



## 问题

```xml
<!--问题sql片段，入参source=0，导致拼接完的sql没有这个条件 -->
<if test="source != null and source != ''">
    and foo.source = #{source,jdbcType=INTEGER}
</if>
```

## xml test表达式解析实现

关键类：`ExpressionEvaluator`、`IfSqlNode`

IfSqlNode 负责解析if 标签的sql片段

ExpressionEvaluator 实现表达式的解析，底层是通过OGNL实现。

上述问题的测试

```java
ExpressionEvaluator evaluator = new ExpressionEvaluator();
// test = true
boolean test = evaluator.evaluateBoolean("source == ''", ImmutableMap.of("source", 0));
```

源码实现

```java
public boolean evaluateBoolean(String expression, Object parameterObject) {
    try {
        Object value = Ognl.getValue(expression, parameterObject);
        if (value instanceof Boolean) return (Boolean) value;
        // 需要特别注意的是，表达式解析也支持返回为数字，如果为0， 则返回false
        if (value instanceof Number) return !new BigDecimal(String.valueOf(value)).equals(BigDecimal.ZERO);
        return value != null;
    } catch (OgnlException e) {
        throw new BuilderException("Error evaluating expression '" + expression + "'. Cause: " + e, e);
    }
}
```

## 问题总结

* mybatis 利用OGNL生成动态sql
* OGNL 对于表达式的解析约定和实现，决定了上述问题的出现
* 代码不能直接copy，要多测试
* 入参传0，也有些另类！！！
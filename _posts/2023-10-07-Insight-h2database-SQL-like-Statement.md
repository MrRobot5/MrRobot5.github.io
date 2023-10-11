---
layout: post
title:  "Insight h2database SQL like 查询"
date:   2023-10-07 13:57:11 +0800
categories: 源码阅读
tags: h2数据库 设计模式
---

* content
{:toc}

> 我们认为的 SQL like 查询和优化技巧，设计的初衷和真正的实现原理是什么。
> 
> 在 h2database SQL like 查询实现类中（CompareLike），可以看到 SQL 语言到具体执行的实现、也可以看到数据库尝试优化语句的过程，以及查询优化的原理。可以做为条件语句的**经典案例去分析**。
> 
> 我们熟知的索引前缀匹配，实现过程和局限可以通过源码体现。
> 
> 文章中的查询不只局限在 Select 语句，包括 Update、Delete。

## SQL like 语句实现

> 根据之前的文章《Insight H2 database 数据查询核心原理》。 condition 执行的结果返回布尔类型，true or false。 
> 
> 任何表达式都可以是 condition， 根据转换规则，都可以转为布尔类型。

**核心方法**： org.h2.expression.CompareLike#getValue

```java
/**
 * 执行 SQL like 表达式，返回 true or false.
 * 假设 SQL like 语句为 NAME like 'bj%' 
 * @see org.h2.expression.CompareLike#getValue
 */
public Value getValue(Session session) {
    // 从当前行（session）获取对应列（left）的值。 left 对应为：NAME (ExpressionColumn)
    Value l = left.getValue(session);
    if (!isInit) {
        // 获取 like 表达式，正常情况下。 right 对应为：bj% (ValueExpression)
        Value r = right.getValue(session);
        String p = r.getString();
        // 解析 like 表达式，方便后续识别和比对。主要是识别和定位通配符。
        initPattern(p, getEscapeChar(e));
    }
    String value = l.getString();
    boolean result;
    if (regexp) {
        // 正则模式匹配
        result = patternRegexp.matcher(value).find();
    } else {
        // SQL Like 模式匹配。 字符循环比对。
        result = compareAt(value, 0, 0, value.length(), patternChars, patternTypes);
    }
    return ValueBoolean.get(result);
}
```

## SQL like 查询优化

> like 查询比较损耗性能，针对特定的情况下，会进行查询优化。
> 
> prepare 阶段，重写查询语句，会彻底替换 Condition 对象。
> 
> 之后，尝试增加索引查询条件，缩小数据遍历的范围。

### ①查询语句重写

**核心方法**： org.h2.expression.CompareLike#optimize

在查询准备阶段（org.h2.command.dml.Select#prepare），如果检测到如下的情况，会进行查询语句重写。

```java
if ("%".equals(p)) {
    // optimization for X LIKE '%': convert to X IS NOT NULL
    return new Comparison(session, Comparison.IS_NOT_NULL, left, null).optimize(session);
}

if (isFullMatch()) {
    // 没有通配符的情况下，约等于等值匹配
    // optimization for X LIKE 'Hello': convert to X = 'Hello'
    Value value = ValueString.get(patternString);
    Expression expr = ValueExpression.get(value);
    return new Comparison(session, Comparison.EQUAL, left, expr).optimize(session);
}
```

### ②增加索引查询条件

> **尝试限定查找范围 (start or end)，而非全表扫描**。
> 
> 比如：select * from city where name like '朝阳%';
> 
> 等同于：select * from city where name >= '朝阳' and name < '朝阴';

**核心方法**：org.h2.expression.CompareLike#createIndexConditions

在查询准备阶段（org.h2.command.dml.Select#prepare），如果支持索引前缀匹配，那么就尝试计算匹配范围，增加索引查询条件，达到减少遍历的目的。

```java
/**
 * like 前缀查询的本质是什么？
 * 拆解匹配查询字符串，把 like 查询，转为对应规律的字符串范围查询。
 * 例如：NAME like 'bj%i' --> NAME >= 'bj' && NAME < 'bk'
 */
public void createIndexConditions(Session session, TableFilter filter) {
    // 使用正则模式查询，索引不生效。 NAME REGEXP '^bj.*'
    if (regexp) {
        return;
    }
    // 非当前表的关联查询语句，索引不生效
    ExpressionColumn l = (ExpressionColumn) left;
    if (filter != l.getTableFilter()) {
        return;
    }

    String p = right.getValue(session).getString();
    initPattern(p, getEscapeChar(e));
    // 非前缀匹配，索引不生效
    // private static final int MATCH(char) = 0, ONE(_) = 1, ANY(*) = 2;
    if (patternLength <= 0 || patternTypes[0] != MATCH) {
        // can't use an index
        return;
    }
    int dataType = l.getColumn().getType();
    if (dataType != Value.STRING && dataType != Value.STRING_IGNORECASE && dataType != Value.STRING_FIXED) {
        // column is not a varchar - can't use the index
        return;
    }
    // 假设查询语句为： NAME like 'bj%i'
    // 从 patternChars(bj%i) 中提取最佳匹配的前缀字符串 bj。
    String end;
    if (begin.length() > 0) {
        // 增加索引查询查询条件 NAME >= 'bj'。以此作为 like 前缀匹配的起始
        filter.addIndexCondition(IndexCondition.get(Comparison.BIGGER_EQUAL, l, ValueExpression.get(ValueString.get(begin))));
        char next = begin.charAt(begin.length() - 1);
        // search the 'next' unicode character (or at least a character that is higher)
        // 根据字符串顺序，尝试找到大于前缀的字符串。以此作为 like 前缀匹配的终止
        for (int i = 1; i < 2000; i++) {
            end = begin.substring(0, begin.length() - 1) + (char) (next + i);
            if (compareMode.compareString(begin, end, ignoreCase) == -1) {
                // 增加索引查询查询条件 NAME < 'bk'。 j 的下一个字符即 k。
                filter.addIndexCondition(IndexCondition.get(Comparison.SMALLER, l, ValueExpression.get(ValueString.get(end))));
                break;
            }
        }
    }
}
```

## 其他

> 上述描述的过程，其中有一些细节，需要单独说明。

### ①通配符模式前缀查找

```java
int maxMatch = 0;
// 存储通配符模式前缀字符串， that is "begin"
StringBuilder buff = new StringBuilder();
// 找到非通配符的前缀字符串。遍历 patternChars ， 遇到非精确字符串， 终止。
while (maxMatch < patternLength && patternTypes[maxMatch] == MATCH) {
    buff.append(patternChars[maxMatch++]);
}
```

### ②索引条件校验

> createIndexConditions 方式是把所有可以转为范围查找的列都加入了索引条件中（org.h2.table.TableFilter#indexConditions）。
> 
> 有些列可能并没有索引，所以，需要在准备阶段（org.h2.table.TableFilter#prepare），剔除无效的索引条件。

```java
/**
 * Prepare reading rows. This method will remove all index conditions that
 * can not be used, and optimize the conditions.
 * @see org.h2.table.TableFilter#prepare
 */
public void prepare() {
    // forget all unused index conditions
    // the indexConditions list may be modified here
    for (int i = 0; i < indexConditions.size(); i++) {
        IndexCondition condition = indexConditions.get(i);
        if (!condition.isAlwaysFalse()) {
            Column col = condition.getColumn();
            if (col.getColumnId() >= 0) {
                if (index.getColumnIndex(col) < 0) {
                    indexConditions.remove(i);
                    i--;
                }
            }
        }
    }
} 
```

## Code Insight 环境

```shell
java -jar h2-1.4.184.jar org.h2.tools.Shell -url "jdbc:h2:~/test;MV_STORE=false" -user sa -password ""
```

```sql
select * from city where name like 'bj%i';

SELECT *
FROM INFORMATION_SCHEMA.INDEXES
WHERE TABLE_NAME = 'CITY';
```

## 总结

- SQL like 模式匹配支持正则表达式和通配符两种。

- 常用的通配符模式采用约定的字符串匹配规则确定每一行数据是否符合要求。

- 正则模式匹配不支持优化，需要遍历目标表的每一行，性能损耗大。

- 使用前缀匹配的通配符模式匹配，尝试增加索引列的区间范围条件，优化扫描区间。

- 熟悉条件筛选的底层原理，趋利避害，达到数据查询的最佳性能。

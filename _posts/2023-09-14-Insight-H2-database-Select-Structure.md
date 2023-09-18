---
layout: post
title:  "Insight H2 database 数据查询核心原理"
date:   2023-09-14 22:41:59 +0800
categories: 源码阅读
tags: h2数据库
---

* content
{:toc}

> 本文目标是：了解查询的核心原理，对比 SQL 查询优化技巧在 h2database 中的落地实现。
> 
> 前提：为了贴近实际实际，本文 Code Insight 基于 BTree 存储引擎。

## 数据查询核心原理

> 数据库实现查询的原理：遍历表/索引，判断是否满足`where`筛选条件，添加到结果集。简单通用。
> 
> 对于选择表还是索引、如何遍历关联表、优先遍历哪个表、怎样提升遍历的效率，这个就是数据库查询复杂的地方。

```java
/**
 * 查询命令实现查询的主要过程
 * @see org.h2.command.dml.Select#queryFlat
 */
private void queryFlat(int columnCount, ResultTarget result, long limitRows) {
    // 遍历单表 or 关联表。topTableFilter 可以简单理解为游标 cursor。
    while (topTableFilter.next()) {
        // 判断是否符合 where 筛选条件
        if (condition == null || Boolean.TRUE.equals(condition.getBooleanValue(session))) {
            Value[] row = new Value[columnCount];
            // 填充select 需要的 columns ①
            for (int i = 0; i < columnCount; i++) {
                Expression expr = expressions.get(i);
                row[i] = expr.getValue(session);
            }
            // 保存符合条件的数据，这个对应 resultSet
            result.addRow(row);
            // 没有 sort 语句的情况下，达到 limitRows， 终止 table scan ②
            if ((sort == null || sortUsingIndex) && limitRows > 0 &&
                    result.getRowCount() >= limitRows) {
                break;
            }
        }
    }
}
```

## Join 查询核心原理

> 基于状态机模式，实现多表嵌套循环遍历。
> 
> 使用的 Join 算法是： Nested Loop Join。
> 
> 状态变迁：BEFORE_FIRST --> FOUND --> AFTER_LAST

```java
/**
 * Check if there are more rows to read.
 * 遍历的数据 row 记录在当前 session 中，随时随地可以获取
 *
 * @return true if there are
 * @see org.h2.table.TableFilter#next
 */
public boolean next() {
    // 遍历结束，没有符合的条件的 row
    if (state == AFTER_LAST) {
        return false;
    } else if (state == BEFORE_FIRST) {
        // cursor 遍历初始化， 如果基于索引的游标，则可以提前锁定数据范围。③
        cursor.find(session, indexConditions);
        if (!cursor.isAlwaysFalse()) {
            // 如果包含 join 表，重置关联表的状态机。
            if (join != null) {
                join.reset();
            }
        }
    } else {
        // state == FOUND || NULL_ROW 的情况
        // 嵌套遍历 join 关联表。这是个递归调用关联表的过程。
        if (join != null && join.next()) {
            return true;
        }
    }
    // 表/索引数据扫描，匹配filterCondition，直到找到符合的 row
    while (true) {
        if (cursor.isAlwaysFalse()) {
            state = AFTER_LAST;
        } else {
            if (cursor.next()) {
                currentSearchRow = cursor.getSearchRow();
                current = null;
                state = FOUND;
            } else {
                state = AFTER_LAST;
            }
        }
        // where 条件判断
        if (!isOk(filterCondition)) {
            continue;
        }
        // 嵌套遍历 join 关联表。主表的每一行 row，需要遍历关联子表一次。④
        if (join != null) {
            join.reset();
            if (!join.next()) {
                continue;
            }
        }
        // check if it's ok
        if (state == NULL_ROW || joinConditionOk) {
            return true;
        }
    }
    state = AFTER_LAST;
    return false;
}
```

## 获取查询数据

> 从遍历的 row 中，获取 select 语句需要的 column 数据。
> 
> 对应的 Cursor 实现是：org.h2.index.PageBtreeCursor

```java
/**
 * 根据 columnId 获取对应的值
 * @see org.h2.table.TableFilter#getValue
 */
public Value getValue(Column column) {
	if (current == null) {
		// 优先从当前遍历的 row 获取数据。
        // 如果是索引中的 row，不会包含所有的行，会有取不到的情况
		Value v = currentSearchRow.getValue(columnId);
		if (v != null) {
			return v;
		}
        // 如果没有，再尝试从原始表 row 存储中获取数据。⑤
        // 对应的实现： currentRow = index.getRow(session, currentSearchRow.getKey());
		current = cursor.get();
		if (current == null) {
			return ValueNull.INSTANCE;
		}
	}
	return current.getValue(columnId);
}
```

## 常用的 SQL 查询优化技巧

> 分别对应上述源代码注释的数字角标。

### ①避免使用 SELECT *：只选择需要的列

如果使用 select *, 即使使用了索引查询。也需要取原数据行的所有数据（⑤）。会进行数据的二次读取，也就是回表查询。影响了性能。

### ②避免使用 ORDER BY, 尽量使用LIMIT

使用 LIMIT：如果只需要部分结果，可以使用 LIMIT 子句限制返回的行数，避免检索整个结果集。

如上源代码，如果没有 Order By，有limit 限制情况下，可以中途结束表遍历。

如果有 Order By 的情况下，肯定要执行完成整个扫描遍历的过程，最终在 result 结果集中再一次进行排序计算。

### ③使用索引：确保表中的列上有适当的索引，以加快查询速度。

如果使用索引，在初始化扫描阶段，会给 cursor 一定的范围，避免全表扫描。极大的缩小的查询范围。

### ④减少连接的表的数量：如果可能，尽量减少查询中的表的数量。

无需多言，嵌套递归查询，理论上是所有表的笛卡尔积。

### ⑤**使用覆盖索引**：一个查询的所有列都包含在索引中。

这样查询可以只扫描索引而不需要回表。例如，如果你的查询是 SELECT id, name FROM users WHERE age = 30，那么在 age, id, name 上创建一个复合索引可以避免回表。

## 其他

### Nested Loop Join

```java
// 用伪代码表示，可以更清晰理解上述 join 遍历的过程
for (r in R) {
    for (s in S) {
        if (r satisfy condition s) {
            output <r, s>;
        }
    }
}
```

### MySQL 中的Nested Loop Join

> MySQL官方文档中提到，MySQL只支持Nested Loop Join这一种join algorithm.
> 
> MySQL resolves all joins using a nested-loop join method. 
> 
> This means that MySQL reads a row from the first table, and then finds a matching row in the second table, the third table, and so on.





---
layout: post
title:  "Insight h2database 执行计划评估以及 Selectivity"
date:   2023-09-18 20:08:09 +0800
categories: 源码阅读 算法
tags: h2数据库
---

* content
{:toc}

> 生成执行计划是任何一个数据库不可缺少的过程。通过本文看执行计划生成原理。
> 
> 最优的执行计划就是寻找最小计算成本的过程。
> 
> 本文侧重 BTree 索引的成本计算的实现 以及 基础概念选择度的分析。

## 寻找最优执行计划

> 找到最佳的索引，实现最少的遍历，得到想要的结果

### 单表查询情况

```java
/**
 * 根据查询条件，获取最佳执行计划.
 *
 * @param masks per-column comparison bit masks, null means 'always false',
 *              see constants in IndexCondition
 * @return the plan item
 * @see org.h2.table.Table#getBestPlanItem
 */
public PlanItem getBestPlanItem(Session session, int[] masks, TableFilter filter, SortOrder sortOrder) {
    // 以扫描索引作为执行计划的默认索引
    PlanItem item = new PlanItem();
    item.setIndex(getScanIndex(session));
    // 表的近似行数 * 10 作为默认成本，最差情况的 Cost 。
    // long cost = 10 * (tableData.getRowCountApproximation() + Constants.COST_ROW_OFFSET);
    item.cost = item.getIndex().getCost(session, null, null, null);
    // 获取 table 包含的所有索引
    ArrayList<Index> indexes = getIndexes();
    if (indexes != null && masks != null) {
        // 跳过扫描索引（上述的 ScanIndex ）
        for (int i = 1, size = indexes.size(); i < size; i++) {
            Index index = indexes.get(i);
            // 计算当前索引的成本， 不同的索引有不同的成本计算公式。
            double cost = index.getCost(session, masks, filter, sortOrder);
            // 记录/更新最小成本的索引，以此作为最佳执行计划
            if (cost < item.cost) {
                item.cost = cost;
                item.setIndex(index);
            }
        }
    }
    return item;
}
```

### 多表查询情况

```java
/**
 * 使用穷举策略寻找最佳执行计划
 * 前提：少于 7 个表关联的情况下。 关联表太多的情况下，会采用随机 + 贪心算法，得出次优的执行计划
 * @see org.h2.command.dml.Optimizer#calculateBestPlan
 */
private void calculateBruteForceAll() {
    TableFilter[] list = new TableFilter[filters.length];
    // 关联表(filters) 排列组合  穷举策略，试算各种组合执行计划的成本
    Permutations<TableFilter> p = Permutations.create(filters, list);
    // 如果组合遍历次数超过 127 次((x & 127) == 0)，或者寻找的耗时超过 cost 的10倍，证明优化过程本末倒置，则停止这个过程。
    for (int x = 0; !canStop(x) && p.next(); x++) {
        testPlan(list);
    }
}
```

## BTree 索引的成本计算

```java
/**
 * 计算 B-tree 索引中搜索数据所需的预估成本。
 * Calculate the cost for the given mask as if this index was a typical
 * b-tree range index. This is the estimated cost required to search one
 * row, and then iterate over the given number of rows.
 *
 * @param masks the search mask. condition.getMask(indexConditions)， 根据查询条件确定是哪种比较（EQUALITY、RANGE、START、END）
 * @param rowCount the number of rows in the index， 数据总行数
 * @see org.h2.index.BaseIndex#getCostRangeIndex
 */
protected long getCostRangeIndex(int[] masks, long rowCount, TableFilter filter, SortOrder sortOrder) {
    rowCount += Constants.COST_ROW_OFFSET;
    long cost = rowCount;
    long rows = rowCount;
    // 总选择度，针对联合索引的情况，计算各个 column 综合参数
    int totalSelectivity = 0;
    // 没有查询条件的情况，预估成本是 rowCount， 等于全表扫描
    if (masks == null) {
        return cost;
    }
    // 遍历索引的 columns， 做两件事：查询条件是否匹配索引列，匹配的成本计算
    for (int i = 0, len = columns.length; i < len; i++) {
        Column column = columns[i];
        int index = column.getColumnId();
        int mask = masks[index];
        if ((mask & IndexCondition.EQUALITY) == IndexCondition.EQUALITY) {
            // 等值比较情况下，如果是 unique 索引，cost 相比以下是最小的。
            if (i == columns.length - 1 && getIndexType().isUnique()) {
                cost = 3;
                break;
            }
            // 动态计算总选择度，查询条件与索引 column 重合度越高，选择越大
            // 为了便于理解，公式还可以改写为：totalSelectivity = totalSelectivity + (100 - totalSelectivity) * column.getSelectivity() / 100;
            // 也就是：总选择度 = 已有的选择度 + 已有的非选择度中再次用 column 选择度计算的增量
            totalSelectivity = 100 - ((100 - totalSelectivity) * (100 - column.getSelectivity()) / 100);
            // 估算当前选择度下的非重复的数据行数（假设索引的选择性是均匀分布的）
            long distinctRows = rowCount * totalSelectivity / 100;
            if (distinctRows <= 0) {
                distinctRows = 1;
            }
            // 选择度越大，这里的 rows，也就是 cost 越小。
            rows = Math.max(rowCount / distinctRows, 1);
            // cost >= 3
            cost = 2 + rows;
        } else if ((mask & IndexCondition.RANGE) == IndexCondition.RANGE) {
            cost = 2 + rows / 4;
            break;
        } else if ((mask & IndexCondition.START) == IndexCondition.START) {
            cost = 2 + rows / 3;
            break;
        } else if ((mask & IndexCondition.END) == IndexCondition.END) {
            cost = rows / 3;
            break;
        } else {
            // 如果索引的 columns 不支持匹配，则直接终止计算。对于联合索引的情况，如果首列不支持匹配，那么认定此索引失效。
            break;
        }
    }
    // 当查询中的 ORDER BY 与索引的排序顺序匹配时，
    // 使用这个索引进行查询通常比使用其他索引更加高效，因此查询优化器会相应地调整这个索引的成本。
    if (sortOrder != null) {
        boolean sortOrderMatches = true;
        int coveringCount = 0;
        int[] sortTypes = sortOrder.getSortTypes();
        for (int i = 0, len = sortTypes.length; i < len; i++) {
            // 匹配计算...
            coveringCount++;
        }
        if (sortOrderMatches) {
            // 当有两个或更多的覆盖索引可供选择时，查询优化器会倾向于选择覆盖更多列的索引。
            // 覆盖更多列的索引 cost 更少来体现。
            cost -= coveringCount;
        }
    }
    return cost;
}
```

## Selectivity

### 概念

> Selectivity is used by the cost based optimizer to calculate the estimated cost of an index.
> 
> Selectivity 100 means values are unique, 10 means every distinct value appears 10 times on average.

### 人工指定 Selectivity

```sql
-- sets the selectivity (1-100) for a column. 
ALTER TABLE TEST ALTER COLUMN NAME SELECTIVITY 100;
```

### 人工更新 Selectivity

```sql
-- Updates the selectivity statistics of tables. 
ANALYZE SAMPLE_SIZE 1000;
```

### 自动更新 Selectivity

> 随着表数据的更新操作，对应列的 Selectivity 也在发生变化。基于累计值 analyzeAuto 来决定什么时候触发Analysis， 也就是更新 Selectivity。 

```java
/**
 * 默认为 2000 ，也就是说，对表进行大约 2000 次更改后，将对每个用户表运行 ANALYZE。
 * 自数据库启动以来，每次运行 ANALYZE 的时间间隔都会加倍。
 * 它不会在本地临时表上运行，也不会在 SELECT 触发器的表上运行。
 * @see org.h2.engine.DbSettings#analyzeAuto
 */
public final int analyzeAuto = get("ANALYZE_AUTO", 2000);
```



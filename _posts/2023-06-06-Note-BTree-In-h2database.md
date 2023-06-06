---
layout: post
title:  "Note BTree In h2database"
date:   2023-06-06 18:03:25 +0800
categories: jekyll update
---

# 笔记 h2database BTree 设计实现与查询优化思考

> h2database 是使用Java 编写的开源数据库，兼容ANSI-SQL89。
> 
> 即实现了常规基于 BTree 的存储引擎，又支持日志结构存储引擎。功能非常丰富（死锁检测机制、事务特性、MVCC、运维工具等），数据库学习非常好的案例。
> 
> 本文理论结合实践，通过BTree 索引的设计和实现，更好的理解数据库索引相关的知识点以及优化原理。

## BTree 实现类

h2database 默认使用的 MVStore 存储引擎，如果要使用 基于 BTree 的存储引擎，需要特别指定（如下示例代码 jdbcUrl）。

以下是常规存储引擎(BTree 结构) 相关的关键类。

- **org.h2.table.RegularTable**

- **org.h2.index.PageBtreeIndex** （SQL Index 本体实现）

- **org.h2.store.PageStore** （存储层，对接逻辑层和文件系统）

BTree 的数据结构可以从网上查到详细的描述和讲解，不做过多赘述。

需要特别说明的是：PageStore。我们数据查询和优化关键的缓存、磁盘读取、undo log都是由 PageStore 完成。可以看到详细的文档和完整的实现。

## BTree add index entry 调用链

> 提供索引数据新增的调用链。同样的，索引的删除和查询都会涉及到，方便 debug 参考。

1. org.h2.command.dml.Insert#insertRows (**Insert SQL 触发数据和索引新增**)

2. org.h2.mvstore.db.RegularTable#addRow (**处理完的数据Row, 执行新增**)

3. org.h2.index.PageBtreeIndex#add (**逻辑层增加索引数据**)

4. org.h2.index.PageDataIndex#addTry (**存储层增加索引数据**)

5. org.h2.index.PageDataLeaf#addRowTry (**存储层新增实现**)

```java
// 示例代码
// CREATE TABLE city (id INT(10) NOT NULL AUTO_INCREMENT, code VARCHAR(40) NOT NULL, name VARCHAR(40) NOT NULL);
public static void main(String[] args) throws SQLException {
    // 注意：MV_STORE=false，MVStore is used as default storage
    Connection conn = DriverManager.getConnection("jdbc:h2:~/test;MV_STORE=false", "sa", "");
    Statement statement = conn.createStatement();
    // CREATE INDEX IDX_NAME ON city(code); 添加数据触发 BTree 索引新增
    // -- SQL 实例化为：IDX_NAME:16:org.h2.index.PageBtreeIndex
    statement.executeUpdate("INSERT INTO city(code,name) values('cch','长春')");
    statement.close();
    conn.close();
}
```

## Code Insight

> 结合上述的示例代码，从索引新增的流程实现来了解BTree 索引的特性以及使用的注意事项。从底层实现分析索引的运行，对 SQL 索引使用和优化有进一步认识。

### 表添加数据

```java
 public void addRow(Session session, Row row) {
    // MVCC 控制机制，记录和比对当前事务的 id
    lastModificationId = database.getNextModificationDataId();
    if (database.isMultiVersion()) {
        row.setSessionId(session.getId());
    }
    int i = 0;
    try {
        // 根据设计规范，indexes 肯定会有一个聚集索引（h2 称之为scan index）。①
        for (int size = indexes.size(); i < size; i++) {
            Index index = indexes.get(i);
            index.add(session, row);
            checkRowCount(session, index, 1);
        }
        // 记录当前 table 的数据行数，事务回滚后会相应递减。
        rowCount++;
    } catch (Throwable e) {
        try {
            while (--i >= 0) {
                Index index = indexes.get(i);
                // 对应的，如果发生任何异常，会移除对应的索引数据。
                index.remove(session, row);
            }
        }
        throw de;
    }
}
```

① 同Mysql InnoDB 数据存储一样， RegularTable 必有，且只有一个聚集索引。以主键(或者隐含自增id)为key, 存储完整的数据。

### 聚集索引添加数据

- 索引中的 key 是查询要搜索的内容，而其值可以是以下两种情况之一：它可以是实际的行（文档，顶点），也可以是对存储在别处的行的引用。在后一种情况下，行被存储的地方被称为 **堆文件（heap file）**，并且存储的数据没有特定的顺序（根据索引相关的）。

- 从索引到堆文件的额外跳跃对读取来说性能损失太大，因此可能希望将被索引的行直接存储在索引中。这被称为聚集索引（clustered index）。

- 基于主键扫描即可唯一确定、并且获取到数据，聚集索引性能比非主键索引少一次扫描

```java
public void add(Session session, Row row) {
    // 索引key 生成 ②
    if (mainIndexColumn != -1) {
        // 如果主键非 long, 使用 org.h2.value.Value#convertTo 尝试把主键转为 long
        row.setKey(row.getValue(mainIndexColumn).getLong());
    } else {
        if (row.getKey() == 0) {
            row.setKey((int) ++lastKey);
            retry = true;
        }
    }

    // 添加行数据到聚集索引 ③
    while (true) {
        try {
            addTry(session, row);
            break;
        } catch (DbException e) {
            if (!retry) {
                throw getNewDuplicateKeyException();
            }
        }
    }
}
```

② 对于有主键的情况，会获取当前 row 主键的值，转为long value。对于没有指定主键的情况，从当前聚集索引属性 lastKey 自增得到唯一 key。

    只有指定主键的情况，才会校验数据重复（也就是索引key 重复，自增 lastKey 是不会有重复值的问题）。

③ 聚集索引 PageDataIndex 按照BTree 结构查找对应的key 位置，按照主键/key 的顺序，将 Row 存储到page 中。非聚集索引 PageBtreeIndex 也是这样的处理流程。

    这其中涉及到三个问题：

1. 如何查找 key 的位置，也就是 BTree 位置的计算？

2. 如何计算 Row （实际数据）存储 Page 中的 offsets？

3. Row 是怎样写入到磁盘中的，何时写入的？

### 索引数据存取实现

- B 树将数据库分解成固定大小的 **块（block）** 或 **分页（page）**，传统上大小为 4KB（有时会更大），并且一次只能读取或写入一个页面。

- 每个页面都可以使用地址或位置来标识，这允许一个页面引用另一个页面 —— 类似于指针，但在硬盘而不是在内存中。（对应h2 database PageBtreeLeaf 和 PageBtreeNode）

- 不同于 PageDataIndex ，PageBtreeIndex 按照 column.value 顺序来存储。添加的过程就是比对查找 column.value，确定在块（block）中offsets 的下标 x。剩下就是计算数据的offset 并存入下标 x 中。

```java
/**
 * Find an entry. 二分查找 compare 所在的位置。这个位置存储 compare 的offset。
 * org.h2.index.PageBtree#find(org.h2.result.SearchRow, boolean, boolean, boolean)
 * @param compare 查找的row, 对应上述示例 compare.value = 'cch'
 * @return the index of the found row
 */
int find(SearchRow compare, boolean bigger, boolean add, boolean compareKeys) {
    // 目前 page 持有的数据量 ④
    int l = 0, r = entryCount;
    int comp = 1;
    while (l < r) {
        int i = (l + r) >>> 1;
        // 根据 offsets[i]，读取对应的 row 数据 ⑤
        SearchRow row = getRow(i);
        // 比大小 ⑥
        comp = index.compareRows(row, compare);
        if (comp == 0) {
            // 唯一索引校验 ⑦
            if (add && index.indexType.isUnique()) {
                if (!index.containsNullAndAllowMultipleNull(compare)) {
                    throw index.getDuplicateKeyException(compare.toString());
                }
            }
        }
        if (comp > 0 || (!bigger && comp == 0)) {
            r = i;
        } else {
            l = i + 1;
        }
    }
    return l;
}
```

④ 每个块（page）entryCount ，两个方法初始化。根据块分配和实例创建初始化，或者 PageStore 读取块文件，从Page Data 解析得到。

⑤ 反序列化过程，从page 文件字节码（4k的字节数组），根据协议读取数据并实例化为 row 对象。参考： org.h2.index.PageBtreeIndex#readRow(org.h2.store.Data, int, boolean, boolean) 。

⑥ 全类型支持大小比对，具体的规则参考：org.h2.index.BaseIndex#compareRows

⑦ 如果数据中存在重复的键值，则不能创建唯一索引、UNIQUE 约束或 PRIMARY KEY 约束。h2database 兼容多种数据库模式，MySQL NULL 非唯一，MSSQLServer NULL 唯一，仅允许出现一次。

```java
private int addRow(SearchRow row, boolean tryOnly) {
    // 计算数据所占字节的长度
    int rowLength = index.getRowSize(data, row, onlyPosition);
    // 块大小，默认 4k
    int pageSize = index.getPageStore().getPageSize();
    // 块文件可用的 offset 获取
    int last = entryCount == 0 ? pageSize : offsets[entryCount - 1];
    if (last - rowLength < start + OFFSET_LENGTH) {
        // 校验和尝试分配计算，这其中就涉及到分割页面生长 B 树的过程 ⑧
    }
    // undo log 让B树更可靠 ⑨
    index.getPageStore().logUndo(this, data);
    if (!optimizeUpdate) {
        readAllRows();
    }

    int x = find(row, false, true, true);
    // 新索引数据的offset 插入到 offsets 数组中。使用 System.arraycopy(x + 1) 来挪动数据。
    offsets = insert(offsets, entryCount, x, offset);
    // 重新计算 offsets，写磁盘就按照 offsets 来写入数据。
    add(offsets, x + 1, entryCount + 1, -rowLength);
    // 追加实际数据 row
    rows = insert(rows, entryCount, x, row);
    entryCount++;
    // 标识 page.setChanged(true);
    index.getPageStore().update(this);
    return -1;
}
```

⑧如果你想添加一个新的键，你需要找到其范围能包含新键的页面，并将其添加到该页面。如果页面中没有足够的可用空间容纳新键，则将其分成两个半满页面，并更新父页面以反映新的键范围分区

⑨为了使数据库能处理异常崩溃的场景，B 树实现通常会带有一个额外的硬盘数据结构：**预写式日志**（WAL，即 write-ahead log，也称为 **重做日志**，即 redo log）。这是一个仅追加的文件，每个 B 树的修改在其能被应用到树本身的页面之前都必须先写入到该文件。当数据库在崩溃后恢复时，这个日志将被用来使 B 树恢复到一致的状态。

## 实践总结

- 查询优化实质上就是访问数据量的优化，磁盘IO 的优化。

- 如果数据全部缓存到内存中，实际上就是计算量的优化，CPU 使用的优化。

- 索引是有序的，实际上就是指块文件内的 offsets 是以数组形式体现的。 **特殊的是**，在h2database 中，offsets数组元素也是有序的（例如：[4090, 4084, 4078, 4072, 4066, 4060, 4054, 4048, 4042]），应该是**方便磁盘顺序读，防止磁盘碎片化**。

- 理论上，聚集索引扫描 IO 比 BTree 索引要多，因为同样的块文件内，BTree 索引 存储的数据量更大，所占的块文件更少。如果一个table 列足够少，聚集索引扫描效率更高。
  
  **建表需要谨慎，每个列的字段长度尽可能的短，来节省页面空间**。

- **合理使用覆盖索引查询，避免回表查询。** 如述示例，`select id from city where code = 'cch'` ，扫描一次 BTree 索引即可得到结果。如果 `select name from city where code = 'cch'`, 需要扫描一次 BTree 索引得到索引key (主键)，再遍历扫描聚集索引，根据 key 得到结果。

- **合理的使用缓存，让磁盘IO 的影响降到最低。** 比如合理配置缓存大小，冷热数据区分查询等。

## 其他知识点

- 分支因子为 500 的 4KB 页面的四层树可以存储多达 256TB 的数据）。（在 B 树的一个页面中对子页面的引用的数量称为 **分支因子（branching factor）**。

## 参考

[ddia/ch3.md B树](https://github.com/Vonng/ddia/blob/master/ch3.md#B%E6%A0%91)

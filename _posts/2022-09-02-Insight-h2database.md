---
layout: post
title:  "Insight h2database 专辑⭐⭐⭐"
date:   2022-09-02 18:17:54 +0800
categories: jekyll update2

---

# Insight h2database 专辑

> 本文作为 Code Insight 目录，梳理 h2 数据库的知识点以及感兴趣的实现细节。
> 
> 作为一个教学演示用的数据库，性能优化肯定不是其优势，重点在协议、SQL规范实现的思路和解决方案上。❌
> 
> **h2 数据库提供DBMS 完整的实现、丰富的特性和其简练的实现**，通过了解其设计思路，举一反三，在日常开发设计、MySQL 数据库深度研究都有借鉴意义。✔
> 
> 核心实现的原理分析会持续更新、补充链接。

## 概览🎯

### ①简介

h2 数据库支持嵌入式（开源产品 demo 演示）和服务器模式，可以使用磁盘存储（B 树索引存储引擎、日志结构存储引擎）或内存数据库，并提供事务支持和多版本并发控制（MVCC）。

同时还提供了一个基于浏览器的控制台应用程序（JavaWeb），支持加密数据库和全文搜索（based on Apache Lucene）等扩展特性。功能非常丰富，使用Java 编写，可以作为学习数据库原理和架构的范例。

### ②相关技术点

1. 数据库文件协议实现
2. 磁盘页存储和缓存交互实现
3. SQL 语法解析器（递归下降分析器）
4. 搜索算法（B 树、R-Tree、LSM、全文搜索、多维搜索）
5. 数据存储结构实现
6. 快照、checkpoint、MVCC 实现
7. ANSI-SQL89 规范实现
8. JDBC 协议实现
9. TCPServer 实现
10. Http Web Server 实现
11. JSP 协议实现

### ③参考信息

1. [H2 Database 官网](https://h2database.com/html/main.html)

2. [H2 使用教程](https://h2database.com/html/tutorial.html) 10min 带你玩转 H2 数据库 😀

3. [H2 支持的SQL 语法](https://h2database.com/html/grammar.html) 增删改查、存储过程、触发器等，兼容 ANSI-SQL89 规范。

4. [H2 特性介绍和原理](https://h2database.com/html/features.html) Code Insight 主要参考资料

## 核心实现✨

> 目录结构参考 [官网介绍架构](https://h2database.com/html/architecture.html) 的Top-down Overview。
> 
> 结合关系型数据库和 DBMS 相关的知识点，理论结合实际，深入理解数据库思想。

### ①JDBC driver.

> org.h2.Driver

### ②Connection/session management.

> org.h2.engine.SessionRemote
> 
> 参考 Database URL Overview URL 连接和配置示例

### ③SQL Parser.

> org.h2.command.Parser
> 
> SQL 语法解释器使用递归下降分析器（recursive-descent），按照语法规则解析输入的文本。有性能问题，优点是易于实现和理解。

### ④Command execution and planning.

> package org.h2.command.dml
> 
> org.h2.expression.Expression
> 
> h2 没有生成查询 IR（中间表示）这一中间步骤，而是直接生成一个命令执行对象。然后对命令对象进行一些优化步骤（org.h2.expression.Expression#optimize），生成更有效的命令。

[Insight H2 database auto increment](./2022-12-02-Insight-H2-database-auto-increment.md)

### ⑤Table/Index/Constraints.

> org.h2.table.RegularTable
> 
> org.h2.mvstore.db.MVTable
> 
> org.h2.index.PageBtreeIndex
> 
> RegularTable 采用常用的数据表实现方案，常见的B Tree 索引结构，聚集索引数据存储等。
> 
> MVTable 是基于新一代的存储引擎 MVStore 实现的数据表实现。

### ⑥Undo log, redo log, and transactions layer.

> Undo log, 撤销日志是每个会话独立的，用于回滚操作或撤销失败的更改。
> 
> redo log, 重做日志也是每个会话独立的，用于在崩溃后恢复数据库。
> 
> transaction log, 事务日志是在所有会话之间共享的(MVCC)，用于记录数据库的所有更改。

### ⑦B-tree engine and page-based storage allocation.

> 基于 B-tree 的存储引擎，使用磁盘页面（块）存储数据。
> 
> B树是一种树状数据结构，用于组织和存储数据，可用于在大量数据集中快速查找和访问数据。针对磁盘存储介质，实现数据快速检索和更新。

[笔记 h2database BTree 设计实现与查询优化思考](./2023-06-06-Note-BTree-In-h2database.md)

### ⑧MVStore storage engine

> MVStore 是一种持久化的、基于日志结构的键值存储。用作新版本 H2 的默认存储引擎。
> 
> H2 数据库官网特有一章节用来描述 [MVStore](https://h2database.com/html/mvstore.html)。
> 
> 这种引擎将修改的数据缓存在内存中，然后在累积足够的修改后，将它们一次性写入磁盘。这种方式可以提高写入性能，特别是对于不支持小随机写入的文件系统和存储系统（如Btrfs），以及SSD。
> 
> 每个修改集合称为一个“chunk”，其中包含了所有被修改的B树的父节点和根节点，以及元数据。
> 
> 为了重用磁盘空间，会压缩具有最少活动数据的chunk。与传统存储引擎相比，这种引擎更简单、更灵活，并且通常需要更少的磁盘操作。

### ⑨Filesystem abstraction.

> org.h2.store.FileStore
> 
> org.h2.mvstore.OffHeapStore
> 
> 文件抽象层，方便存储引擎层进行操作。封装了seek、readFully、write、sync 等方法，屏蔽了具体存储（也可以使用堆外存储）的实现细节。
> 
> ByteBuffer.allocateDirect

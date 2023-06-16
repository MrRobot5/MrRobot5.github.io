---
layout: post
title:  "笔记 Mysql for update 分析及应用"
date:   2022-09-02 16:24:05 +0800
categories: 学习笔记
tags: Mysql 并发编程
---
* content
{:toc}

> for update 应用场景：对需要读写操作（**query data** and **then insert or update** related data within the same transaction）的数据进行加锁，防止其他写操作的影响。把业务并发彻底变为串行。业务操作变安全。

## MySQL Locking Reads

[MySQL :: MySQL 5.7 Reference Manual :: 14.7.2.4 Locking Reads](https://dev.mysql.com/doc/refman/5.7/en/innodb-locking-reads.html)

### LOCK IN SHARE MODE-共享锁

- 多个session(事务) 在没有修改操作时，都可以对当前的数据加共享锁。

- 如果有session 有修改操作，那么加锁会阻塞，一直等待操作session commit后，加锁成功，并且返回最新的数据。

- 这种适用于**对加锁数据只读操作**的场景。文档Example 以parent /child表 级联操作案例来说明应用场景。

### FOR UPDATE-排他锁

- 多个session(事务) ，对当前数据，只有一个可以加锁成功，其余等待（包括LOCK IN SHARE MODE）。

- 这种适用于**对加锁数据进行读写操作**的场景。文档Example 以 counter 累加的案例说明应用场景。

## Locking Read Examples

### 并发自增

```sql
START TRANSACTION;
-- try lock
SELECT counter_field FROM child_codes FOR UPDATE;
-- modify...
UPDATE child_codes SET counter_field = counter_field + 1;
-- release lock
COMMIT;
```

### another deadlock

```sql
START TRANSACTION;
SELECT * FROM child_codes WHERE id = 10567 LOCK IN SHARE MODE;
-- 多个session 在此互相等待，死锁发生
UPDATE child_codes SET name = 'foo' WHERE id = 10567; 
COMMIT;
```

## 总结

- mysql 通过locking reads 机制，解决了并发场景下读写数据不一致的问题。

- 我们比较常用的是 for update。优点是简单，缺点是tps不高。

- 还有其他的控制业务并发的方案，比如乐观锁机制（自旋）。需要根据场景去选用合适的技术方案。

- 如果使用不当，会造成SQL 死锁。又一种死锁的方式😂。

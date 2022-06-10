# 笔记 - Mysql Transaction Isolation Levels 案例

> 使用Mysql 客户端，通过两个客户端执行SQL 来模拟并发。

```sql
-- 查询事务隔离级别 （Transaction Isolation Levels）
SELECT @@GLOBAL.tx_isolation, @@tx_isolation;
```

## SERIALIZABLE

| client1                                                  | client2                                                               | 备注                                                                       |
| -------------------------------------------------------- | --------------------------------------------------------------------- | ------------------------------------------------------------------------ |
| SET TRANSACTION ISOLATION LEVEL SERIALIZABLE;            |                                                                       |                                                                          |
| <br/>START TRANSACTION;                                  | SET TRANSACTION ISOLATION LEVEL SERIALIZABLE; <br/>START TRANSACTION; | 事务开始前才能修改事务隔离级别                                                          |
| UPDATE `country` SET `countrycode`='foo' WHERE  `Id`=13; |                                                                       |                                                                          |
|                                                          | UPDATE `country` SET `countrycode`='foo' WHERE `Id`=13;               | /* SQL错误（1205）：Lock wait timeout exceeded; try restarting transaction */ |
|                                                          | SELECT * FROM `country` WHERE  `Id`=13;                               | /* SQL错误（1205）：Lock wait timeout exceeded; try restarting transaction */ |

注意： 示例中是根据主键，mysql 是行锁，如果update 不是同一行数据，不会发生锁冲突。**如果非索引更新，那么就是表锁，表事务串行。**

## REPEATABLE READ

| client1                                                    | client2                                          | 备注                              |
| ---------------------------------------------------------- | ------------------------------------------------ | ------------------------------- |
| SET TRANSACTION ISOLATION LEVEL REPEATABLE READ;           |                                                  |                                 |
| <br/>START TRANSACTION;                                    | SET TRANSACTION ISOLATION LEVEL REPEATABLE READ; |                                 |
| <br/>START TRANSACTION;                                    |                                                  |                                 |
| UPDATE `country` SET `countrycode`='foo-2' WHERE  `Id`=14; |                                                  |                                 |
|                                                            | SELECT * FROM `country` WHERE  `Id`=14;          | 读写不阻塞。读取的是旧值。                   |
| COMMIT;                                                    |                                                  |                                 |
|                                                            | SELECT * FROM `country` WHERE `Id`=14;           | client2 读取的`countrycode `仍然是旧的。 |

## READ COMMITTED

| client1                                                    | client2                                         | 备注               |
| ---------------------------------------------------------- | ----------------------------------------------- | ---------------- |
| SET TRANSACTION ISOLATION LEVEL READ COMMITTED;            |                                                 |                  |
| <br/>START TRANSACTION;                                    | SET TRANSACTION ISOLATION LEVEL READ COMMITTED; |                  |
| <br/>START TRANSACTION;                                    |                                                 |                  |
| UPDATE `country` SET `countrycode`='foo-3' WHERE  `Id`=14; |                                                 |                  |
|                                                            | SELECT * FROM `country` WHERE  `Id`=14;         | 读取的是旧值。          |
| COMMIT;                                                    |                                                 |                  |
|                                                            | SELECT * FROM `country` WHERE `Id`=14;          | 读取的是client1更新的值。 |

## READ UNCOMMITTED

| client1                                                   | client2                                           | 备注                |
| --------------------------------------------------------- | ------------------------------------------------- | ----------------- |
| SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;         |                                                   |                   |
| <br/>START TRANSACTION;                                   | SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED; |                   |
| <br/>START TRANSACTION;                                   |                                                   |                   |
| UPDATE `country` SET `countrycode`='foo-4' WHERE `Id`=14; |                                                   |                   |
|                                                           | SELECT * FROM `country` WHERE `Id`=14;            | 读取的是client1更新的值。  |
| ROLLBACK;                                                 |                                                   |                   |
|                                                           | SELECT * FROM `country` WHERE `Id`=14;            | 读取的是client1更新前的值。 |

## 总结

事务的隔离级别（access mode）是声明事务间数据可见级别的。

无论什么样的级别，对于同一条数据更新，写锁，肯定是互斥的。

> These
> characteristics set the transaction isolation level or access mode. 
> 
> The
> isolation level is **used for operations on InnoDB tables**. The access
> mode may be specified as of MySQL 5.6.5 and indicates whether
> **transactions operate in read/write or read-only mode**.

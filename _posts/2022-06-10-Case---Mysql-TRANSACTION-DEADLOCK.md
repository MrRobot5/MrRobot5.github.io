---
layout: post
title:  "Case - Mysql TRANSACTION DEADLOCK"
date:   2022-06-10 17:11:10 +0800
categories: jekyll update
---
# Case - Mysql TRANSACTION DEADLOCK

> 一次上线完成后，观察线上日志，发现很多死锁异常（org.springframework.dao.DeadlockLoserDataAccessException）。
> 
> mysql 提示信息：Deadlock found when trying to get lock; try restarting transaction。

## 场景还原

> 这是一次并发插入/更新引发的死锁案例

| 事务1                                                                    | 事务2                                                                    | 备注                         |
| ---------------------------------------------------------------------- | ---------------------------------------------------------------------- | -------------------------- |
| INSERT INTO `country`(countryname, countrycode) VALUES ('Angola','AO') |                                                                        |                            |
|                                                                        | INSERT INTO `country`(countryname, countrycode) VALUES ('Brazil','BR') | 正常执行，相安无事                  |
| UPDATE `country` SET countryname = 'Angola' WHERE countryname = 'AO'   |                                                                        | 阻塞。事务1等待事务2 释放锁            |
|                                                                        | UPDATE `country` SET countryname = 'Brazil' WHERE countryname = 'BR'   | **DEADLOCK**。事务2 等待事务1 释放锁 |

```shell
-- 查询死锁日志
SHOW ENGINE innodb STATUS
```

### 日志

```log
------------------------
LATEST DETECTED DEADLOCK
------------------------
2022-06-02 19:37:26 9ec
*** (1) TRANSACTION:
TRANSACTION 11187331, ACTIVE 5 sec fetching rows
mysql tables in use 1, locked 1
LOCK WAIT 4 lock struct(s), heap size 312, 21 row lock(s), undo log entries 1
UPDATE country SET countryname = 'Angola' WHERE countryname = 'AO'
*** (1) WAITING FOR THIS LOCK TO BE GRANTED:
RECORD LOCKS space id 515 page no 3 n bits 88 index `PRIMARY` of table `test`.`country` trx id 11187331 lock_mode X waiting

*** (2) TRANSACTION:
TRANSACTION 11187330, ACTIVE 5 sec starting index read
mysql tables in use 1, locked 1
UPDATE country SET countryname = 'Brazil' WHERE countryname = 'BR'
*** (2) HOLDS THE LOCK(S):
RECORD LOCKS space id 515 page no 3 n bits 88 index `PRIMARY` of table `test`.`country` trx id 11187330 lock_mode X locks rec but not gap

*** (2) WAITING FOR THIS LOCK TO BE GRANTED:
RECORD LOCKS space id 515 page no 3 n bits 88 index `PRIMARY` of table `test`.`country` trx id 11187330 lock_mode X waiting

*** WE ROLL BACK TRANSACTION (2)
```

## 疑问

**日志怎么看？**

上述的 innodb 日志已经精简过了。

其中列出了死锁相关的两个事务`*** (1) TRANSACTION`。

引发死锁的事务会列出持有的锁 `HOLDS THE LOCK(S)` lock_mode X locks rec but not gap。 这对应的就是insert 语句的加锁。

最后，`WE ROLL BACK TRANSACTION (2)`



**死锁是怎么发生的？**

从上述场景已经可以看出，死锁就是因为资源互相等待引起的。

事务2需要X锁，但肯定申请不到。事务1已经在申请X锁，并且是等待过程中，需要事务2 释放X锁（非gap）。



**为什么上述的insert 并没有互斥wait ?** 参考Mysql 官网文档：

> [`INSERT`](https://dev.mysql.com/doc/refman/8.0/en/insert.html "13.2.6 INSERT Statement") sets an exclusive lock on the inserted row. This lock is an index-record lock, not a next-key lock (that is, there is no gap lock) and does not prevent other sessions from inserting into the gap before the inserted row.



## 问题总结

上述的场景，是因为update 锁全表，X锁需要升级，导致互相等待死锁。如果update 是根据主键进行更新，就可以解决。

经常见到的其他死锁案例，通常是业务事务执行时间长，导致的。可以通过队列**减小并发度**，或者**缩小事务的执行时间**，或者把引起锁竞争的**资源后置到事务最后**（快速结束事务，释放锁）。



## Mysql 锁知识

[MySQL :: 15.7.5.1 An InnoDB Deadlock Example](https://dev.mysql.com/doc/refman/8.0/en/innodb-deadlock-example.html)

[MySQL 锁表后快速解决方法 及 MySQL中的锁 | 天道酬勤](https://weikeqin.com/2019/09/05/mysql-lock-table-solution/)

[MySQL :: 15.7.3 Locks Set by Different SQL Statements in InnoDB](https://dev.mysql.com/doc/refman/8.0/en/innodb-locks-set.html)

[mysql并发插入死锁_StarJava_的博客-CSDN博客_mysql 并发插入死锁](https://blog.csdn.net/qq_35425070/article/details/109782896)





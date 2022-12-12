---
layout: post
title:  "mysql windows 服务配置"
date:   2019-12-06 17:37:49 +0800
categories: jekyll update
---
## mysql windows 服务配置

### 删除旧服务

```shell
## 以管理员身份运行bash
mysqld --remove mysql
```

## 新增服务

```shell
mysqld --install mysql5 --defaults-file=D:\\service-experiment\\mysql-5.6.33-win32\\my.ini
```

## 问题

1. 启动失败，原因：ini配置文件中添加了slowlog 的配置，但是没有创建对应的日志路径，导致启动报错
   
   > [ERROR] Could not open D:\service-experiment\mysql-5.6.33-win32\data\log\mysql_slow_query.log for logging (error 2). Turning logging off for the whole duration of the MySQL server process. To turn it on again: fix the cause, shutdown the MySQL server and restart it.

2. 启动失败，原因：彻底删除了data文件夹，导致mysql内置的数据库找不到，无法启动
   
   > [ERROR] Fatal error: Can't open and lock privilege tables: Table 'mysql.user' doesn't exist

3. 
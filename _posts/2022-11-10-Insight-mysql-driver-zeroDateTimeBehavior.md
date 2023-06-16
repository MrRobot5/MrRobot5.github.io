---

layout: post
title:  "Mysql driver zeroDateTimeBehavior 实现原理"
date:   2022-11-10 15:18:48 +0800
categories: 源码阅读
tags: Mysql
---
* content
{:toc}


## 使用 Mysql driver 遇到的问题

```log
java.sql.SQLException: Value '0000-00-00 00:00:00' can not be represented as java.sql.Timestamp
    at com.mysql.jdbc.SQLError.createSQLException(SQLError.java:861)
    at com.mysql.jdbc.ResultSetRow.getTimestampFast(ResultSetRow.java:947)
    at com.mysql.jdbc.ResultSetImpl.getTimestampInternal(ResultSetImpl.java:5921)
```

## 问题解决

jdbcUrl 声明 `zeroDateTimeBehavior=convertToNull`即可。

`jdbc:mysql://localhost:3306/test?useUnicode=true&characterEncoding=utf8&autoReconnect=true&allowMultiQueries=true&useSSL=true&zeroDateTimeBehavior=convertToNull`

## Code Insight

根据上述的异常日志，可以直接找到异常的出处。

```java
/**
 * @see com.mysql.jdbc.ResultSetRow#getTimestampFast
 */
protected Timestamp getTimestampFast(...) throws SQLException {

    try {
        // 标识是否 '0000-00-00 00:00:00'
        boolean allZeroTimestamp = true;
        // 标识是否为时间格式， 时间是允许 '00:00:00'
        boolean onlyTimePresent = false;
        // check 数据格式
        for (int i = 0; i < length; i++) {
            byte b = timestampAsBytes[offset + i];

            if (b == ' ' || b == '-' || b == '/') {
                onlyTimePresent = false;
            }

            if (b != '0' && b != ' ' && b != ':' && b != '-' && b != '/' && b != '.') {
                allZeroTimestamp = false;

                break;
            }
        }

        if (!onlyTimePresent && allZeroTimestamp) {
            if (ConnectionPropertiesImpl.ZERO_DATETIME_BEHAVIOR_CONVERT_TO_NULL.equals(conn.getZeroDateTimeBehavior())) {
                // 如果连接指定 convertToNull，遇到 allZeroTimestamp 直接返回 null
                return null;
            } else if (ConnectionPropertiesImpl.ZERO_DATETIME_BEHAVIOR_EXCEPTION.equals(conn.getZeroDateTimeBehavior())) {
                // 默认配置 exception， 遇到 allZeroTimestamp 就会抛出上述的异常
                throw SQLError.createSQLException("Value '" + StringUtils.toString(timestampAsBytes) + "' can not be represented as java.sql.Timestamp",
                        SQLError.SQL_STATE_ILLEGAL_ARGUMENT, this.exceptionInterceptor);
            }

            // We're left with the case of 'round' to a date Java _can_ represent, which is '0001-01-01'.
            return rs.fastTimestampCreate(null, 1, 1, 1, 0, 0, 0, 0);
        }
    }
}
```

## Mysql JDBC Connection 配置

连接所有的配置是以 com.mysql.jdbc.ConnectionPropertiesImpl.ConnectionProperty 体现的。包括  **allowableValues** defaultValue sinceVersion 关键信息。

```java
private StringConnectionProperty zeroDateTimeBehavior = new StringConnectionProperty("zeroDateTimeBehavior", ZERO_DATETIME_BEHAVIOR_EXCEPTION,
            new String[] { ZERO_DATETIME_BEHAVIOR_EXCEPTION, ZERO_DATETIME_BEHAVIOR_ROUND, ZERO_DATETIME_BEHAVIOR_CONVERT_TO_NULL },
            Messages.getString("ConnectionProperties.zeroDateTimeBehavior",
                    new Object[] { ZERO_DATETIME_BEHAVIOR_EXCEPTION, ZERO_DATETIME_BEHAVIOR_ROUND, ZERO_DATETIME_BEHAVIOR_CONVERT_TO_NULL }),
            "3.1.4", MISC_CATEGORY, Integer.MIN_VALUE);
```

## 总结

mysql driver 对于异常日期数据的处理，可以借鉴到应用程序的开发中。

首先，需要考虑到异常数据对程序的影响，如果无法继续，需要抛出异常；

然后，针对异常数据，提供声明容错的的方案；提升系统稳定性。

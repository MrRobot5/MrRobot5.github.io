---
layout: post
title:  "MybatisPlus logic-delete 工作原理"
date:   2022-09-01 10:19:58 +0800
categories: 源码阅读
tags: MybatisPlus Mybatis
---

* content
{:toc}

使用MybatisPlus 过程中，发现有逻辑删除的内置功能，比较好奇，引出此次的Code Insight。
注意：逻辑删除是设置针对全局的。

## 使用示例
```yaml
mybatis-plus:
  check-config-location: fals
  # 这个是 Mybatis 的配置
  configuration:
    auto-mapping-unknown-column-behavior: partial
    cache-enabled: false
    call-setters-on-nulls: true
    map-underscore-to-camel-case: true
  # 这个是MybatisPlus 的配置
  global-config:
    db-config:
      logic-delete-field: isDelete
      # 逻辑删除全局值（默认 1、表示已删除）
      logic-delete-value: 1
      logic-not-delete-value: 0
```

## 相关类

com.baomidou.mybatisplus.core.config.GlobalConfig 插件的配置项， 对应上述的配置

com.baomidou.mybatisplus.annotation.TableLogic  表字段逻辑处理注解（逻辑删除）

com.baomidou.mybatisplus.core.metadata.TableFieldInfo 数据库表字段信息

## StackTrace

**initLogicDelete**:316, TableFieldInfo 
**initTableFields**:319, TableInfoHelper
**initTableInfo**:144, TableInfoHelper 
inspectInject:53, AbstractSqlInjector 
parserInjector:133, MybatisMapperAnnotationBuilder
parse:123, MybatisMapperAnnotationBuilder 
**addMapper**:83, MybatisMapperRegistry
bindMapperForNamespace:432, XMLMapperBuilder

```java
/**
 * 逻辑删除初始化
 *
 * @param dbConfig 数据库全局配置
 * @param field    字段属性对象
 */
private void initLogicDelete(...) {
    /* 获取注解属性，逻辑处理字段 */
    TableLogic tableLogic = field.getAnnotation(TableLogic.class);
    if (null != tableLogic) {
        // ...
    } else if (!existTableLogic) {
        // 'isDelete'
        String deleteField = dbConfig.getLogicDeleteField();
        if (StringUtils.isNotBlank(deleteField) && this.property.equals(deleteField)) {
            // 0
            this.logicNotDeleteValue = dbConfig.getLogicNotDeleteValue();
            this.logicDeleteValue = dbConfig.getLogicDeleteValue();
            this.logicDelete = true;
        }
    }
}
```

```java
/**
 * 应用场景
 * 根据ID 查询一条数据(MappedStatement 模板)
 * 自动追加逻辑删除条件（AND is_delete = 0）
 */
public class SelectById extends AbstractMethod {

    @Override
    public MappedStatement injectMappedStatement(Class<?> mapperClass, Class<?> modelClass, TableInfo tableInfo) {
        // SELECT ％s FROM ％s WHERE ％s=#{％s} ％s 最后一个参数：逻辑删除条件
        SqlMethod sqlMethod = SqlMethod.SELECT_BY_ID;
        SqlSource sqlSource = new RawSqlSource(configuration, String.format(sqlMethod.getSql(),
            sqlSelectColumns(tableInfo, false),
            tableInfo.getTableName(), tableInfo.getKeyColumn(), tableInfo.getKeyProperty(),
            // " AND " + logicDeleteFieldInfo.getColumn() + "=" + logicDeleteFieldInfo.getLogicNotDeleteValue();
            tableInfo.getLogicDeleteSql(true, true)), Object.class);
        return this.addSelectMappedStatementForTable(mapperClass, getMethod(sqlMethod), sqlSource, tableInfo);
    }
}
```

## 总结

- MybatisPlus 和tk.Mybatis 针对@Table 处理思路一样。在初始化过程中，会缓存表的相关信息，方便后续拼装SQL 使用。`logic-delete` 就是应用在初始化过程中。

- 

- MybatisPlus 直接在 Mybatis 的源码上修改，简单粗暴👍

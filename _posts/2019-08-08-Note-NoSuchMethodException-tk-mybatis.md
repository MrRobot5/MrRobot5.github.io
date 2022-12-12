---
layout: post
title:  "Insight NoSuchMethodException-tk.mybatis集成Spring Boot 问题"
date:   2019-08-08 22:01:46 +0800
categories: jekyll update
---

# Insight NoSuchMethodException-tk.mybatis集成Spring Boot 问题

## 问题

        在使用 tk.mybatis组件的过程中，调用 insertList()，报错如题。

表面意思是：没有找到 SpecialProvider 默认构造方法，SpecialProvider 实例化失败。

实际上是：insertList 的 `ProviderSqlSource `没有替换 的 `DynamicSqlSource`，mybatis 直接使用ProviderSqlSource 中的 SpecialProvider 进行解析使用，导致的异常。

## 问题分析

        tk.mybatis 组件提供的 `tk.mybatis.mapper.common.Mapper` 是用于**通用的DAO 方法的增强**，不用重复的写增删改查的代码，后续简称 Mapper。

        tk.mybatis 利用mybatis ProviderSqlSource 的特性，通过将模板进行渲染，生成对应mybatis dynamic xml，实现基础增删改查方法的增强。

        如上述的问题，**MappedStatement 的 ProviderSqlSource 本来应该是在初始化过** **程中渲染和替换为 DynamicSqlSource, 由于某种原因，没有执行**。最终导致调用insertList()， 直接使用ProviderSqlSource 的SpecialProvider 解析sql，报错。

## 解决方法

        通过源代码分析，`MapperAutoConfiguration `提供自定义的机制，可以手动配置特定的接口，主动进行渲染和替换。

        如下配置，声明特殊的接口，让tk.mybatis 完成ProviderSqlSource 到 DynamicSqlSource 的替换。**完成增强方法的初始化。**

```yaml
mapper:
  mappers: [tk.mybatis.mapper.common.special.InsertListMapper, tk.mybatis.mapper.common.Mapper]
```

> 涉及到版本
> 
> mybatis.version:3.4.4
> mapper.version:3.4.2
> mybatis-spring.version:1.3.1
> mybatis-spring-boot.version:1.3.0
> spring-boot.version:1.5.4.RELEASE



## Code Insight

### 关键类

1. com.github.pagehelper.autoconfigure.MapperAutoConfiguration
   
   > tk.mybatis 增强方法的解析和替换实现

2. org.mybatis.spring.boot.autoconfigure.MybatisAutoConfiguration
   
   > mybatis Mapper 扫描和配置实现

3. tk.mybatis.mapper.mapperhelper.MapperHelper
   
   > 模板方法识别、加载、解析、渲染、替换的实现，核心

4. tk.mybatis.mapper.mapperhelper.MapperTemplate
   
   > 增删改查模板。

5. org.apache.ibatis.annotations.InsertProvider
   
   > mybatis 动态sql 的一种特性。我们常用的是xml 动态sql。可以与 org.apache.ibatis.annotations.Insert 对比研究。

### 增强方法渲染和替换的主要逻辑

```java
public class MapperAutoConfiguration {

    @PostConstruct
    public void addPageInterceptor() {
        // 通用Mapper 功能核心实现类 mapperHelper
        MapperHelper mapperHelper = new MapperHelper();
        // 如果指定了mappers，则注册继承 mappers接口的bean
        if (properties.getMappers().size() > 0) {
            for (Class mapper : properties.getMappers()) {
                //提前初始化MapperFactoryBean,注册mappedStatements
                applicationContext.getBeansOfType(mapper);
                mapperHelper.registerMapper(mapper);
            }
        } else {
            // 如果没有指定，则默认注册继承 tk.mybatis.mapper.common.Mapper 接口的bean
            applicationContext.getBeansOfType(Mapper.class);
            mapperHelper.registerMapper(Mapper.class);
        }

        // 重新设置模板方法的 SqlSource，即从ProviderSqlSource 替换为DynamicSqlSource
        // 从java 配置转化为可执行的 xml
        for (SqlSessionFactory sqlSessionFactory : sqlSessionFactoryList) {
            mapperHelper.processConfiguration(sqlSessionFactory.getConfiguration());
        }
    }
}
```

### 另外一种情况

如果直接报错：java.lang.InstantiationException **tk.mybatis.mapper.provider.base.BaseInsertProvider**。那就需要查看编写的Mapper 所在的package 是否在指定的MapperScan 范围内。

这种情况一般是：显示声明@tk.mybatis.spring.annotation.MapperScan ，需要排查这一项。

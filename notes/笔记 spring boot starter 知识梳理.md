# 笔记 spring boot starter 知识梳理

## 示例

[pagehelper](https://github.com/pagehelper)/**[pagehelper-spring-boot](https://github.com/pagehelper/pagehelper-spring-boot)**

## 关键要素

### ①auto-configure Module

- auto-configure class

- META-INF/spring.factories

### ②starter Module

- pom.xml (用于依赖引入和auto-configure 引入)

## 关键类

- org.springframework.context.annotation.Configuration

- org.springframework.boot.context.properties.EnableConfigurationProperties

## 调试和排查

①对照上述的关键要素，看是否有缺失

②检查是否有加载 spring.factories 

**org.springframework.core.io.support.SpringFactoriesLoader**

③开启 DEBUG 日志，Spring Boot 会输出 **AUTO-CONFIGURATION REPORT** 根据 `Negative matches` 判断原因。

org.springframework.boot.autoconfigure.logging.ConditionEvaluationReportMessage

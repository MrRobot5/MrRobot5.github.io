---
layout: post
title:  "Insight Spring Boot booting 原理(EnableAutoConfiguration)"
date:   2021-04-23 17:22:03 +0800
categories: jekyll update
---
# Insight Spring Boot booting 原理(EnableAutoConfiguration)

> springboot boot spring 的方案除了前一篇文章提到的，通过 SpringApplicationRunListener 暴露spring 框架启动的阶段，为spring 容器的初始化各种事件的扩展提供方案。
> 
> 另外一个boot spring 的方案就是 `auto-configuration`，通过个各种starter，提供各种EnableAutoConfiguration 接口的实现，将对应的特性注册到spring容器。

## springboot auto-configuration 原理

首先，spring 框架支持以@Configuration 注解的形式配置Bean，以@Import 引入并注册Bean。`springboot 自定义对应的ImportSelector`，将各种starter 提供的各种@Configuration 配置类引入到spring 容器中。

然后，基于spring的Condition 机制，通过`扩展@Conditional，提供更加丰富、具体的选择判断的功能`，支持根据当前classpath或者spring 容器的情况判断是否注册Bean。最终只会有效合法的Bean 注册到spring 容器中。

接下来，针对上述描述的过程，从springboot 入手，逐步分析关键注解的作用。

## insight springboot @EnableAutoConfiguration

```java
// EnableAutoConfiguration 的作用就是引入自定义ImportSelector，识别和引入configuration
@Import(EnableAutoConfigurationImportSelector.class)
public @interface EnableAutoConfiguration {
}
```

借助SpringFactoriesLoader 提供的通用工厂模式机制，springboot 可以加载到classpath 下的configuration classes。

```java
// @see AutoConfigurationImportSelector#selectImports
public String[] selectImports(AnnotationMetadata annotationMetadata) {
    // find auto configuration classes in META-INF/spring.factories
    List<String> configurations = getCandidateConfigurations(annotationMetadata, attributes);
    configurations = removeDuplicates(configurations);
    configurations = sort(configurations, autoConfigurationMetadata);
    Set<String> exclusions = getExclusions(annotationMetadata, attributes);
    configurations.removeAll(exclusions);
    configurations = filter(configurations, autoConfigurationMetadata);
    fireAutoConfigurationImportEvents(configurations, exclusions);
    return configurations.toArray(new String[configurations.size()]);
}
```

## insight spring @Conditional

相当于TypeFilter 增强版，通过自定义编程的方式进行判断和筛选bean definition 。

springboot 扩展的注解：@ConditionalOnBean、@ConditionalOnClass、@ConditionalOnProperty 等

```java
/**
 * Determine if an item should be skipped based on @Conditional annotations.
 * 
 * @see ConditionEvaluator#shouldSkip
 */
public boolean shouldSkip(AnnotatedTypeMetadata metadata, ConfigurationPhase phase) {
    // 规则：无条件=默认符合
    if (metadata == null || !metadata.isAnnotated(Conditional.class.getName())) {
        return false;
    }
    // 解析@Conditional 并初始化conditions
    List<Condition> conditions = new ArrayList<Condition>();
    for (String[] conditionClasses : getConditionClasses(metadata)) {
        for (String conditionClass : conditionClasses) {
            Condition condition = getCondition(conditionClass);
            conditions.add(condition);
        }
    }
    // 根据conditions 判断是否matches
    for (Condition condition : conditions) {
        if (requiredPhase == null || requiredPhase == phase) {
            if (!condition.matches(this.context, metadata)) {
                return true;
            }
        }
    }

    return false;
}
```

## insight spring Configuration annotations

> 自从spring 3.x开始，spring 支持以java 代码的形式配置容器。
> 
> 关键的注解：@Configuration  @Bean @Import  @ComponentScans @PropertySources

`@Configuration` 类似spring XML configuration 的作用，加载配置文件、BeanDefinition等，因此应该在容器初始化初期进行。对应的处理类：ConfigurationClassPostProcessor，也就是BeanFactoryPostProcessor。

*注意：上述的处理类实现了BeanDefinitionRegistryPostProcessor 接口，这个比标准的BeanFactoryPostProcessor 更早的调用和执行。*

### 注册ConfigurationClassPostProcessor

```java
public AnnotatedBeanDefinitionReader(BeanDefinitionRegistry registry, Environment environment) {
    this.registry = registry;
    this.conditionEvaluator = new ConditionEvaluator(registry, environment, null);
    // 注册配置处理器，spring annotation特性核心支持
    AnnotationConfigUtils.registerAnnotationConfigProcessors(this.registry);
}
```

### ConfigurationClassPostProcessor 处理逻辑

类比xml configuration，@Configuration class 相当于某一个xml 文件。

处理逻辑分为两部分：

1. 解析class内部的注解（类比xml文件的标签）
2. 解析class 引入的class（类比xml 文件引入的其他xml文件配置）

处理逻辑的两个核心类：

1. ConfigurationClassParser，解析Configuration class。
2. ConfigurationClassBeanDefinitionReader，判断、注册BeanDefinitions。

```java
// @see ConfigurationClassPostProcessor#processConfigBeanDefinitions
public void processConfigBeanDefinitions(BeanDefinitionRegistry registry) {

    // Parse each @Configuration class
    ConfigurationClassParser parser = new ConfigurationClassParser(
            this.metadataReaderFactory, this.problemReporter, this.environment,
            this.resourceLoader, this.componentScanBeanNameGenerator, registry);

    Set<BeanDefinitionHolder> candidates = new LinkedHashSet<BeanDefinitionHolder>(configCandidates);
    Set<ConfigurationClass> alreadyParsed = new HashSet<ConfigurationClass>(configCandidates.size());
    do {
        // 解析@Configuration class，对class 声明的@PropertySources、@ComponentScans、@ImportResource、@Bean、@Import 进行处理。
        parser.parse(candidates);
        parser.validate();

        // Read the model and create bean definitions based on its content
        if (this.reader == null) {
            this.reader = new ConfigurationClassBeanDefinitionReader(
                    registry, this.sourceExtractor, this.resourceLoader, this.environment,
                    this.importBeanNameGenerator, parser.getImportRegistry());
        }
        // 根据Conditional 判断是否注册到容器中
        this.reader.loadBeanDefinitions(configClasses);
        alreadyParsed.addAll(configClasses);
        // 判断是否有新引入的@Configuration class... 继续加载、解析、处理。
    }
    while (!candidates.isEmpty());
}
```

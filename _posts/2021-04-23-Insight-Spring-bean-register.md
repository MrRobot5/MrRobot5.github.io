---

layout: post
title:  "Insight Spring 重复 Bean 注册的过程"
date:   2021-04-23 18:18:12 +0800
categories: 源码阅读
tags: Spring
---
* content
{:toc}

> 疑问：在业务工程代码梳理过程中，发现竟然存在xml 和 注解两种方式配置相同beanName，但是不同的Class。竟然能正常启动发布。理论上beanName 是唯一的，是怎么回事。
> 
> Insight Spring版本：3.2.0.RELEASE

## 明确的前提

1. Spring Bean在容器中的唯一标识是`beanName`。对应到xml bean标签是id，对应到注解中是默认属性value。

2. xml 文件内，是不允许配置多个相同id 的Bean。Ide 会提示，同时启动也会报错 `SAXParseException：There are multiple occurrences of ID value 'xxx'.`

3. 基于注解的Bean 定义，是不允许配置多个相同value 的Bean。自动扫描注册的过程中，启动报错 `ConflictingBeanDefinitionException`: Annotation-specified bean name 'xxx' for bean class [com.Foo] conflicts with existing, `non-compatible bean definition of same name` and class [com.Too]

4. Bean注册是面向BeanFactory 层次的操作。简单的说是存储在Map中。
   
   ```java
   /** Map of bean definition objects, keyed by bean name */
   private final Map<String, BeanDefinition> beanDefinitionMap = new ConcurrentHashMap<String, BeanDefinition>(64);
   ```

## xml bean标签定义Bean注册实现

```java
/**
 * xml bean 标签解析实现, 生成BeanDefinition，并注册到BeanFactory
 * 通过源码可以看到，从解析到注册，是没有唯一校验beanName，是否能注册成功，就完全依赖the registry。
 *
 * 源码：DefaultBeanDefinitionDocumentReader#processBeanDefinition
 */
protected void processBeanDefinition(Element ele, BeanDefinitionParserDelegate delegate) {
    BeanDefinitionHolder bdHolder = delegate.parseBeanDefinitionElement(ele);
    if (bdHolder != null) {
        bdHolder = delegate.decorateBeanDefinitionIfRequired(ele, bdHolder);
        try {
            // Register the given bean definition with the given bean factory. 直接调用，没有校验。
            BeanDefinitionReaderUtils.registerBeanDefinition(bdHolder, getReaderContext().getRegistry());
        }
        catch (BeanDefinitionStoreException ex) {
            // ...
        }
    }
}
```

## 自动扫描Bean注册实现

```java
/**
 * 扫描指定的包路径, 生成bean definitions，并注册到BeanFactory
 * 注意：checkCandidate 会对beanName 进行唯一性校验，Bean兼容判断。如果判断已存在兼容的BeanDefinition,则不再注册。
 *
 * @see ClassPathScanningCandidateComponentProvider#findCandidateComponents
 * 源码：org.springframework.context.annotation.ClassPathBeanDefinitionScanner#doScan
 */
protected Set<BeanDefinitionHolder> doScan(String... basePackages) {
    for (String basePackage : basePackages) {
        Set<BeanDefinition> candidates = findCandidateComponents(basePackage);
        for (BeanDefinition candidate : candidates) {
            String beanName = this.beanNameGenerator.generateBeanName(candidate, this.registry);
            // ......
            // 注意checkCandidate 的作用：beanName唯一性校验(上述的ConflictingBeanDefinitionException，就是此处出现的)；Bean 兼容判断（如果是非扫描Bean，则默认兼容!!!）。
            if (checkCandidate(beanName, candidate)) {
                BeanDefinitionHolder definitionHolder = new BeanDefinitionHolder(candidate, beanName);
                registerBeanDefinition(definitionHolder, this.registry);
            }
        }                        
    }
    return beanDefinitions;
}
```

## Bean注册到容器的校验

BeanFactory 有个配置`allowBeanDefinitionOverriding`,默认true，是支持重复注册的。

```java
/**
 * Register a new bean definition with this registry.
 * @throws BeanDefinitionStoreException 如果beanDefinition.validate()失败，或者禁止覆盖状态下重复beanName注册
 * 
 * @see RootBeanDefinition
 * @see ChildBeanDefinition
 */
public void registerBeanDefinition(String beanName, BeanDefinition beanDefinition) throws BeanDefinitionStoreException {
    // ......
    synchronized (this.beanDefinitionMap) {
        Object oldBeanDefinition = this.beanDefinitionMap.get(beanName);
        // 唯一性校验，如果allowBeanDefinitionOverriding，那么会重复注册，替换原有beanDefinition。默认支持。
        if (oldBeanDefinition != null) {
            if (!this.allowBeanDefinitionOverriding) {
                throw new BeanDefinitionStoreException(beanDefinition.getResourceDescription(), beanName,
                        "Cannot register bean definition [" + beanDefinition + "] for bean '" + beanName +
                        "': There is already [" + oldBeanDefinition + "] bound.");
            }
        }
        this.beanDefinitionMap.put(beanName, beanDefinition);
    }

    resetBeanDefinition(beanName);
}
```

## 实例case 分析

根据上述两种注册实现，实例分析配置的注册过程。

```xml
<!-- case1: 先配置自动扫描。先注册Foo，再注册Woo，最终暴露的Bean 是Woo -->
<!-- 包路径下存在beanName="foo"的Class(com.service.Foo) -->
<context:component-scan base-package="com.service.*" />
<!-- xml 中直接定义Bean，beanName="foo" -->
<bean id="foo" class="com.service.Woo"></bean>
```

```xml
<!-- case2: 先配置xml bean。先注册Woo，自动扫描发现同名兼容Bean，跳过Foo，最终暴露的Bean 是Woo -->
<!-- xml 中直接定义Bean，beanName="foo" -->
<bean id="foo" class="com.service.Woo"></bean>
<!-- 包路径下存在beanName="foo"的Class(com.service.Foo) -->
<context:component-scan base-package="com.service.*" />
```

这样的话，xml bean 配置的优先级是高于自动扫描的bean。

## 结论

结合上述的分析，Spring 在多个xml配置相同Bean，或者自动扫描和xml混合Bean配置的情况下，默认是允许相同beanName 多次出现的。默认可以理解为，`最终解析到的BeanDefinition，会覆盖掉之前相同beanName 的所有BeanDefinition`。

通过上述分析，可以发现`成熟框架在配置细节上都做的非常完善`。对于兼容性（支持多种bean注册、支持重复配置）、扩展性（支持overwrite）、一致性（注册结果和配置顺序无关）的设计和实现，都是值得我们在日常开发中借鉴和思考的。

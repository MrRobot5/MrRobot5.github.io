---
layout: post
title:  "Spring @Value 默认值配置解析实现"
date:   2020-03-06 18:17:43 +0800
categories: 源码阅读
tags: Spring
---
* content
{:toc}

## 起因

最近接手的项目，配置项实在是多。主要使用Spring @Value 注入，很多是固化下来的配置，但也不能彻底写死，以备临时调整。

现在的做法是，直接把固化的配置以默认值表达式形式配置到代码中。

**约定大于配置** 配置表达式类似于`@Value("${foo.skill.switch:false}")`

这个默认值是语法还是自定义实现，需要看看原理

## 参考类

org.springframework.beans.factory.support.DefaultListableBeanFactory#doResolveDependency

org.springframework.util.PropertyPlaceholderHelper#parseStringValue

[Insight spring @Value 注入处理](https://blog.csdn.net/tt50335971/article/details/52599760)


## 解析实现

```java
/**
 * 对该方法进行递归调用，解析配置值
 * 直至解析到值（解析到默认值），或者抛出异常（IllegalArgumentException("Could not resolve placeholder XXX')）
 * new PropertyPlaceholderHelper("${", "}", ":", false);
 */
protected String parseStringValue() {
    // Recursive invocation, parsing placeholders contained in the placeholder key.
    placeholder = parseStringValue(placeholder, placeholderResolver, visitedPlaceholders);
    // Now obtain the value for the fully resolved key...
    String propVal = placeholderResolver.resolvePlaceholder(placeholder);
    // 默认值placeholder 解析实现
    if (propVal == null && this.valueSeparator != null) {
        int separatorIndex = placeholder.indexOf(this.valueSeparator);
        if (separatorIndex != -1) {
            String actualPlaceholder = placeholder.substring(0, separatorIndex);
            // 默认值截取
            String defaultValue = placeholder.substring(separatorIndex + this.valueSeparator.length());
            // 递归解析，spring 想的太周全了
            propVal = placeholderResolver.resolvePlaceholder(actualPlaceholder);
            if (propVal == null) {
                propVal = defaultValue;
            }
        }
    } else {
        throw new IllegalArgumentException("Could not resolve placeholder '" + placeholder + "'" + " in value \"" + value + "\"");
    }
    
}
    
```


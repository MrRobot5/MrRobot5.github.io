---

layout: post
title:  "Insight Spring @Value 配置默认值解析过程"
date:   2020-03-06 18:17:43 +0800
categories: 源码阅读 实战问题
tags: Spring

---

* content
{:toc}

## 背景

最近接手的项目，配置项实在是多。使用 Spring @Value 注入配置。大部分配置项是固定的，但也不能彻底写死，以备临时调整。

简化配置的思路是：根据**改动的频率**，把固化的配置以默认值表达式形式配置到代码中。从而减少散落在maven、properties、动态配置平台的配置项。

**约定大于配置** 配置表达式类似于`@Value("${foo.skill.switch:false}")`

但是这个默认值是语法还是自定义实现，需要看看原理。

## 另外一个问题

多人开发的工程，经常会遇到配置缺失导致应用启动失败。

在Spring框架中，如果你想要忽略无法解析的占位符，以避免抛出异常，你可以在配置属性解析时设置 ignoreUnresolvablePlaceholders 属性为true。

### 👉配置示例

```java
// 当你设置了ignoreUnresolvablePlaceholders为true后，如果Spring遇到无法解析的占位符，它将不会抛出异常，而是会保留原始的占位符字符串。
@Bean
public static PropertySourcesPlaceholderConfigurer propertyConfigurer() {
    PropertySourcesPlaceholderConfigurer configurer = new PropertySourcesPlaceholderConfigurer();
    configurer.setIgnoreUnresolvablePlaceholders(true);
    return configurer;
}
```

## Code Insight

```java
/**
 * 对该方法进行递归调用，解析配置值
 * 直至解析到值（解析到默认值），或者抛出异常（IllegalArgumentException("Could not resolve placeholder XXX')）
 * new PropertyPlaceholderHelper("${", "}", ":", false);
 * @see org.springframework.util.PropertyPlaceholderHelper#parseStringValue
 */
protected String parseStringValue(String value, PlaceholderResolver placeholderResolver, Set<String> visitedPlaceholders) {

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
    } else if (this.ignoreUnresolvablePlaceholders) {
        // Proceed with unprocessed value.
        // 如果 Spring 遇到无法解析的占位符，它将不会抛出异常，而是会保留原始的占位符字符串。
        startIndex = buf.indexOf(this.placeholderPrefix, endIndex + this.placeholderSuffix.length());
	}else {
        // 既没有默认配置，也没有启用忽略找不到的配置项，抛异常，启动失败。❌
        throw new IllegalArgumentException("Could not resolve placeholder '" + placeholder + "'" + " in value \"" + value + "\"");
    }

}
```

## 参考

org.springframework.beans.factory.support.DefaultListableBeanFactory#doResolveDependency

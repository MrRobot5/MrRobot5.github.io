---
layout: post
title:  "Insight Yaml in Spring Boot"
date:   2022-12-06 17:33:49 +0800
categories: jekyll update
---
# Insight Yaml in Spring Boot

## 遇到的问题

​        在使用 Spring Boot 配置工程时，发现并没有按照预期解析。疑问：**是yaml 的解析规则还是 Spring Boot 解析规则？**

```yaml
# yaml 配置
alias:
  52: s52-online

# springboot 解析完成的key-value
# alias[52] -> s-52-online
```

## Spring Boot 对yaml properties的处理

```java
/**
 * YamlProcessor to create a Map containing the property values.
 * @see org.springframework.boot.env.YamlPropertySourceLoader.Processor#process
 */
public Map<String, Object> process() {
    final Map<String, Object> result = new LinkedHashMap<String, Object>();
    process(new MatchCallback() {
        // loadYaml完成后的object 强制转换为 map数据结构
        public void process(Properties properties, Map<String, Object> map) {
            // 拍平map数据结构,最终得到的是 property values
            result.putAll(getFlattenedMap(map));
        }
    });
    return result;
}
```

首先，processor 会针对yaml 读取完的结果进行处理，主要就是把number keys 转为string keys。

```java
// 得到的数据：{alias={[52]=s-52-online}}
private Map<String, Object> asMap(Object object) {
    // YAML can have numbers as keys
    for (Entry<Object, Object> entry : map.entrySet()) {
        Object key = entry.getKey();
        if (key instanceof CharSequence) {
            result.put(key.toString(), value);
        }
        else {
            // It has to be a map key in this case
            result.put("[" + key.toString() + "]", value);
        }
    }
    return result;
}
```

然后，再把map 拍平，得到最终的the property values。

```java
private void buildFlattenedMap(Map<String, Object> source, String path) {
    for (Entry<String, Object> entry : source.entrySet()) {
        String key = entry.getKey();
        if (StringUtils.hasText(path)) {
            // 针对上述number keys的key，直接追加到path，得到的就是 alias[52]
            if (key.startsWith("[")) {
                key = path + key;
            }
            else {
                key = path + '.' + key;
            }
        }
        // ... value 拍平处理，理论上只有String, Map, Collection
    }
}
```

## yaml 文件读取浅析

yaml 是一种文件格式的规范，[YAML Version 1.1](http://yaml.org/spec/1.1/)。

java 读取yaml使用到的第三方库：snakeyaml。[SnakeYAML Engine Documentation](https://bitbucket.org/asomov/snakeyaml-engine/wiki/Documentation)。

snakeyaml 是根据YAML规范实现的。

### YAML 基本概念

[Processing YAML Information](http://yaml.org/spec/1.1/#id859109)

**Representation Graph相关：**

Nodes: YAML *nodes* have *content* of one of three *kinds*: scalar, sequence, or mapping.

**处理相关：**

**Parse** : *Parsing* is the inverse process of presentation, it takes a stream of characters and produces a series of events. 

**Compose** : *Composing* takes a series of serialization events and produces a representation graph.

**Construct** : The final input process is *constructing* native data structures from the YAML representation.

### snakeyaml 关键实现

```java
// yaml load file
new Composer(new ParserImpl(new StreamReader(new UnicodeReader(input))), new Resolver());
```

第三方库实现针对规范中的定义进行了具体的实现，对功能进行了清晰明确的划分。

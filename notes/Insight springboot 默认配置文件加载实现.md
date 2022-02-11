# Insight springboot 默认配置文件加载实现

## 引子

> 通常使用spring框架，我们需要手动指定配置文件
> 
> springboot 是怎么实现的？

## springboot 配置文件加载简介

> Spring Boot allows you to externalize your configuration so you can work with the same application code in different environments. 
> 
> You can use properties files, YAML files, environment variables and command-line arguments to externalize configuration. 
> 
> Spring Boot uses a very particular `PropertySource` order that is designed to allow `sensible overriding of values`. 
> 
> 参考：https://docs.spring.io/spring-boot/docs/1.5.15.RELEASE/reference/htmlsingle/#boot-features-external-config

springboot 基本包含所有配置的形式，自带的配置文件、默认的配置文件、命令行入参、运行容器的环境变量、工程指定的配置文件。all in one，服务不可谓不周到，并且根据约定习惯，提供合理的加载顺序和覆盖机制。

配置文件的格式支持key-value、yaml、json。

spring 的黑魔法总是很多，本文主要探究`application-{profile}.properties`的加载实现。

## 调用链

SpringApplication#run()
**SpringApplication#prepareEnvironment()**
SpringApplicationRunListeners#environmentPrepared()
SimpleApplicationEventMulticaster#multicastEvent()
**ConfigFileApplicationListener#onApplicationEnvironmentPreparedEvent()**
ConfigFileApplicationListener#postProcessEnvironment()
ConfigFileApplicationListener#addPropertySources()

## application-{profile}.properties的加载实现

通过嵌套循环，尝试按照如下的规则加载符合的配置文件。

1. 遍历所有的profiles
2. 遍历所有约定的路径 outside of your packaged jar、packaged inside your jar 
3. 遍历所有约定的文件名，默认application
4. 遍历所有约定文件的格式，[properties, xml, yml, yaml]

```java
// The default profile for these purposes is represented as null. We add it
// last so that it is first out of the queue (active profiles will then
// override any settings in the defaults when the list is reversed later).
this.profiles.add(null);

// 使用while的原因：随着配置文件的解析，可能会有新的profiles 增加，保证所有的profiles 都会遍历到
while (!this.profiles.isEmpty()) {
    Profile profile = this.profiles.poll();
    // [file:./config/, file:./, classpath:/config/, classpath:/]
    for (String location : getSearchLocations()) {
        if (!location.endsWith("/")) {
            // location is a filename already, so don't search for more
            // filenames
            load(location, null, profile);
        }
        else {
            // 默认application
            for (String name : getSearchNames()) {
                // 尝试加载不同后缀、不同profile的配置文件
                load(location, name, profile);
            }
        }
    }
    this.processedProfiles.add(profile);
}

addConfigurationProperties(this.propertiesLoader.getPropertySources());
```

## 使用ApplicationListener 实现加载的思考

> 通过查看源码，发现ApplicationEventMulticaster 分发事件的时候，支持异步调用，这样的话，`配置文件注册到容器中是随机的`，这样不会影响到约定的配置文件顺序吗？
> 
> 使用ApplicationListener 有什么好处？

### 支持异步的原因

文档中有说明：By default, all listeners are invoked in the calling thread. This allows `the danger of a rogue listener blocking the entire application`, but adds minimal overhead. Specify an alternative task executor to have listeners executed in different threads, for example from a thread pool.

同时：文档也指出如果使用线程池异步分发，需要注意的点。However, note that asynchronous `execution will not participate in the caller's thread context` (class loader, transaction association) unless the TaskExecutor explicitly supports this.

**综合分析**，如有必要才需要启用线程池。该机制仅限于作用在容器的运行层次，不同于我们应用功能层次，性能层面不用特别关注。

### 配置文件顺序的保障

通过强制指定注册的位置，保证我们读取配置列表的顺序永远一致！

```java
if (existingSources.contains(DEFAULT_PROPERTIES)) {
    existingSources.addBefore(DEFAULT_PROPERTIES, configurationSources);
}
else {
    existingSources.addLast(configurationSources);
}
```

### springboot SpringApplicationRunListeners设计

ApplicationListener  属于spring 框架的概念。在springboot 框架中发挥非常重要的作用。

基于ApplicationListener  的机制，springboot 可以在托管spring 容器初始化过程中，暴露出每个阶段，`为更丰富的集成和自动化扩展提供可能性`。如：本文的配置文件自动加载、数据库脚本的自动执行等等。

和本文主题没有直接关系，暂且不做详细分析。

## 总结

通过分析默认配置文件解析的实现，发现spring boot框架为了自适应和智能，做了非常多的工作。简约而不简单。

对于多场景配置文件的支持，兼容约定配置的设计，以及配置文件规则约定的实现和解析，都是值得揣摩和反复思考的。

框架对于具体需求的实现、兼容性、扩展性的设计，对于我们日常应用开发都有很大的借鉴意义。

## 扩展

### 其他格式/类型配置文件解析器

json格式的配置加载实现：org.springframework.boot.env.SpringApplicationJsonEnvironmentPostProcessor

properties配置文件加载实现：org.springframework.boot.env.PropertiesPropertySourceLoader

yaml 配置文件加载实现：org.springframework.boot.env.YamlPropertySourceLoader

### 配置项在 spring 容器中的应用

```java
/**
 * spring 容器把加载到的配置项，解析并注入到组件中。
 */
protected <T> T getProperty(String key, Class<T> targetValueType, boolean resolveNestedPlaceholders) {
    // 循环遍历上述的加载的配置集合
    for (PropertySource<?> propertySource : this.propertySources) {
        Object value = propertySource.getProperty(key);
        // if find, then stop
        if (value != null) {
            if (resolveNestedPlaceholders && value instanceof String) {
                value = resolveNestedPlaceholders((String) value);
            }
            // Convert the given value to the specified target type, if necessary.
            return convertValueIfNecessary(value, targetValueType);
        }
    }
    return null;
}
```

### 配置项在应用中的使用方式

1. 注入使用 `@Value("${local.mail.sender}")`

2. 配置组使用，基于 springboot 提供的配置机制，以配置对象的形式，直接使用。 `@ConfigurationProperties(prefix = "app.mail")`

3. 直接使用配置。
   
   ```java
   @Slf4j
   @Component
   public class PropertyUtil implements EnvironmentAware {
   
       private static Environment configuration;
   
       public static String getConfiguration(String key) {
           String value = "";
           if (configuration != null) {
               value = (String) configuration.getProperty(key);
           }
           return value;
       }
   
       @Override
       public void setEnvironment(Environment environment) {
           configuration = environment;
       }
   
   }
   ```

### 关联的黑魔法

类型转换 org.springframework.core.convert.ConversionService

松散匹配  org.springframework.boot.bind.RelaxedDataBinder

​                      org.springframework.boot.bind.RelaxedNames

### springboot 启动的timing

参考 org.springframework.boot.SpringApplicationRunListeners

springboot 对spring的封装的粒度，约等于org.springframework.web.context.ContextLoaderListener。对spring框架的机制没有任何侵入和污染。

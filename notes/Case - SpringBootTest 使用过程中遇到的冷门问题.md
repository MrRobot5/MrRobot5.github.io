# Case - SpringBootTest 使用过程中遇到的冷门问题

## 问题描述

使用SpringBootTest 测试DAO 逻辑时，直接报错：`java.lang.NoSuchMethodException: tk.mybatis.mapper.provider.base.BaseSelectProvider.<init>()`

从异常日志分析，是 tk.mybatis 的增强方法初始化问题。可是，启动工程调用该DAO 方法，是正常执行的，那么问题是出在哪呢？

```java
@Slf4j
@RunWith(SpringRunner.class)
@SpringBootTest(classes = WebApplication.class)
public class ApplicationTests {

    @Autowired
    private DictionaryMapper dictionaryMapper;

    @Test
    public void baseMapperTest() {
        int count = dictionaryMapper.selectCount(null);
        Assert.assertTrue(count > 0);
    }

}
```

同时，测试目录下，还有一个空的SpringBootApplication，主要是用于纯Spring 容器的一些逻辑测试（不加载RPC接口、DAO， 不初始化Redis 等） 

/src/test/java/com/foo/EmptyApplication.java

```java
@Slf4j
@SpringBootApplication(scanBasePackages = "com.foo.service", exclude = {RedisAutoConfiguration.class, MybatisAutoConfiguration.class, RPCAutoConfiguration.class})
public class EmptyApplication {

}
```

## 问题分析

### tk.mybatis 的异常

关于tk.mybatis 增强类初始化异常的问题，可以直接翻看之前的笔记可以解决。[这里](https://mrrobot5.github.io/notes/NoSuchMethodException-tk.mybatis.mapper.provider.SpecialProvider 分析.html)。

现在的问题是，只有在SpringBootTest 运行单测方法才会异常。推测是SpringBootTest 某种机制，导致MapperAutoConfiguration 没有loadClass 或者没有执行。

### MapperAutoConfiguration 检测

通过查看DEBUG 日志，发现MapperAutoConfiguration 正常load，只是因为不符合匹配条件，没有注册到Spring 容器，所以没有正常执行初始化。

```yml
 MapperAutoConfiguration:
   Did not match:
	 - @ConditionalOnBean (types: org.apache.ibatis.session.SqlSessionFactory; SearchStrategy: all) did not find any beans (OnBeanCondition)
```

通过源码，我们可以看到，明明指定了加载顺序，为什么会匹配失败？

```java
@ConditionalOnBean(SqlSessionFactory.class)
@AutoConfigureAfter(MybatisAutoConfiguration.class)
public class MapperAutoConfiguration {
}
```

### EnableAutoConfiguration 加载顺序

根据之前的Insight 笔记，可以直接跳到 org.springframework.boot.autoconfigure.**EnableAutoConfigurationImportSelector#getCandidateConfigurations**

通过断点调试分析，发现上述提到的**EmptyApplication 也load 到容器中了，由于配置了exclusions，直接剔除了MybatisAutoConfiguration**。容器中的EnableAutoConfiguration 组件集合是两个SpringBootApplication 扫描结果的合并。这样看来，确实是**没法保障初始化顺序**。

那么问题又来了，我们的SpringBootTest 明确指定了启动配置类，为什么EmptyApplication 也会掺和进来？

### SpringBootApplication 加载过程

通过源码分析，springboot 是以WebApplication 作为启动类。

但是，由于EmptyApplication 属于 Configuration，在初始化过程中，正常加载到容器中。这时候容器中就存在两个 SpringBootApplication。自动配置等组件也是这两个 Application 共同扫描的集合。

#### 关键信息

1. SpringBootApplication 声明并启用了EnableAutoConfiguration。

2. EnableAutoConfiguration 是通过EnableAutoConfigurationImportSelector 来实现的。

3. 上述EnableAutoConfiguration 加载就是EnableAutoConfigurationImportSelector 执行扫描导入实现的。

#### 相关的源码逻辑

```java
/**
 * Build and validate a configuration model based on the registry of
 * Configuration classes.
 * @see org.springframework.context.annotation.ConfigurationClassPostProcessor#processConfigBeanDefinitions
 */
public void processConfigBeanDefinitions(BeanDefinitionRegistry registry) {

	// Parse each @Configuration class
	ConfigurationClassParser parser = new ConfigurationClassParser(
			this.metadataReaderFactory, this.problemReporter, this.environment,
			this.resourceLoader, this.componentScanBeanNameGenerator, registry);

	do {
		// parse 过程中，引入EmptyApplication。由于EmptyApp 指定exclude MybatisAutoConfiguration，在两次排序合并后，添加到了最后。打乱了 EnableAutoConfiguration 的顺序。
		parser.parse(candidates);
		parser.validate();
	}
}
```

## 总结

- 最复杂的问题，原因总是很简单。

- 这个问题与环境没有关系，与 SpringBootTest 也没有关系，是 SpringBoot 加载机制的问题。

- 工程里尽量不要写多个 SpringBootApplication ，避免不必要的麻烦。目前使用的版本：spring-boot-autoconfigure-1.5.10.RELEASE
  
  
  
  

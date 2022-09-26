# Insight Spring profile及应用

> 监控、动态配置等辅助功能，在开发和测试场景中，并不需要。但是会在spring 启动加载过程中拖慢启动速度，开发、自测效率也受影响。
> 
> 方案：配置spring profile，排除这些配置文件。在开发环境中，只加载关注的配置。

## profile 使用示例

```xml
<?xml version="1.0" encoding="UTF-8"?>
<beans xmlns="http://www.springframework.org/schema/beans"
    xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" 
    xsi:schemaLocation="http://www.springframework.org/schema/beans http://www.springframework.org/schema/beans/spring-beans.xsd" 
    profile="!speed">
	<!-- 开发环境不需要的配置 -->
	<!-- 例如：缓存，连接redis io操作 -->
	<!-- 例如：mq 消费，连接broker io操作 -->
</beans>


```

```java
@Configuration
public class AppConfig {

    @Bean("dataSource")
    @Profile("development") 
    public DataSource standaloneDataSource() {
        return new EmbeddedDatabaseBuilder()
            .setType(EmbeddedDatabaseType.HSQL)
            .addScript("classpath:com/bank/config/sql/schema.sql")
            .addScript("classpath:com/bank/config/sql/test-data.sql")
            .build();
    }

    @Bean("dataSource")
    @Profile("production") 
    public DataSource jndiDataSource() throws Exception {
        Context ctx = new InitialContext();
        return (DataSource) ctx.lookup("java:comp/env/jdbc/datasource");
    }
}
```

JVM 配置 `-Dspring.profiles.active="speed,profile2"`



## Code Insight

> Bean definition profiles provide a mechanism in the core container that allows for registration of different beans in different environments. 

[Bean Definition Profiles](https://docs.spring.io/spring-framework/docs/current/reference/html/core.html#beans-definition-profiles) 文档

### ①XML Bean Definition Profiles

关键类：org.springframework.beans.factory.xml.DefaultBeanDefinitionDocumentReader

```java
/**
 * 解析并注册beans 标签下声明的bean。 Since:3.1
 */
protected void doRegisterBeanDefinitions(Element root) {

	if (this.delegate.isDefaultNamespace(root)) {
		// "profile"
		String profileSpec = root.getAttribute(PROFILE_ATTRIBUTE);
		if (StringUtils.hasText(profileSpec)) {
			// profile 格式解析，支持分隔符",; "
			String[] specifiedProfiles = StringUtils.tokenizeToStringArray(
					profileSpec, BeanDefinitionParserDelegate.MULTI_VALUE_ATTRIBUTE_DELIMITERS);
			// 判断profile 是否激活，如果不符合快速失败，直接return
			if (!getReaderContext().getEnvironment().acceptsProfiles(specifiedProfiles)) {
				if (logger.isInfoEnabled()) {
					logger.info("Skipped XML bean definition file due to specified profiles [" + profileSpec + "] not matching: " + getReaderContext().getResource());
				}
				return;
			}
		}
	}
	
	// 正常解析和注册 bean
	preProcessXml(root);
	parseBeanDefinitions(root, this.delegate);
}
```



### ②@Profile

注解可以在类和方法上使用。

```java
// Spring condition match 特性实现选择性加载, Since:4.0
@Conditional(ProfileCondition.class)
public @interface Profile {

	/**
	 * The set of profiles for which the annotated component should be registered.
	 */
	String[] value();

}
```



## 总结

- profile 思想应用广泛，常见的还有maven profile。

- spring profile 提供一整套环境切换的方案，更加简化了工程治理。

- 



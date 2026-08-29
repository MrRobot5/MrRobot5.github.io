---
layout: post
title:  "Spring Inter-bean injection 实现原理"
date:   2023-04-04 10:50:53 +0800
categories: 源码阅读
tags: Spring 设计模式 动态代理
---
* content
{:toc}


> Spring 基于 Java 配置方式，在Bean 有依赖配置的情况下，可以直接写成方法调用。框架背后的原理（magic🎭）是怎样的？
> 
> Injecting Inter-bean Dependencies 有哪些使用误区？

## Injecting Inter-bean Dependencies

[官方文档](https://docs.spring.io/spring-framework/docs/5.2.23.RELEASE/spring-framework-reference/core.html#beans-java-injecting-dependencies)

```java
@Configuration
public class AppConfig {

    @Bean
    public BeanOne beanOne() {                                    
         // dependency is as simple as having one bean method call another
         // 表面上是方法的直接调用，实际上是 Spring constructor injection
         // beanTwo 方法的调用，背后是 Spring Bean 创建和初始化的过程。
         return new BeanOne(beanTwo());
    }

    @Bean
    public BeanTwo beanTwo() {
        // 虽然是new instance, 但是多次调用 beanTwo 方法，得到的是同一个 instance
        // singleton scope by default
        return new BeanTwo();
    }
}
```

## 使用误区

1. 有的开发者不理解 Inter-bean injection 的原理，理解为方法直接调用。会人工调用诸如 afterPropertiesSet 这样bean 初始化的方法，这样是没有必要的。

2.  只有在 @Configuration 配置的类里，Inter-bean injection 才生效。

3.  As of Spring 3.2, CGLIB classes have been repackaged under `org.springframework.cglib`。 这些代码没有注释，需要去 CGLIB 查看。

4. @Configuration 类里的方法不能为private 或者 final，CGLIB 生成的继承类的规则限制。**防止出现不生效的情况，Spring 会强制校验**。
   
   ```text
   Configuration problem: @Bean method 'beanTwo' must not be private or final; change the method's modifiers to continue
   ```

## Code Insight

### ①实现原理

        容器启动时，对所有 @Configuration 注解的类进行动态代理（增强）。拦截类中的方法，对于 @Bean 注解的方法，会作为 factory-bean 方式对待，**方法直接调用转化为 bean 获取的过程(get or create_and_get)**。

        动态代理使用 CGLIB 实现。

### ②关键类

- org.springframework.context.annotation.ConfigurationClassEnhancer 动态代理 @Configuration 类。

- org.springframework.context.annotation.ConfigurationClassPostProcessor 发起代理（增强）的入口。**postProcessBeanFactory**

### ③Source Code

        经过上述的分析，源码查看侧重在 net.sf.cglib.proxy.MethodInterceptor。

```java
/**
 * 拦截 @Bean 注解的方法，替换为 Bean 相关的操作（scoping and AOP proxying）。
 * @see ConfigurationClassEnhancer
 * @from org.springframework.context.annotation.ConfigurationClassEnhancer.BeanMethodInterceptor
 */
private static class BeanMethodInterceptor implements MethodInterceptor, ConditionalCallback {

	@Override
	@Nullable
	public Object intercept(Object enhancedConfigInstance, Method beanMethod, Object[] beanMethodArgs,
				MethodProxy cglibMethodProxy) throws Throwable {
		// 从proxy 获取BeanFactory。代理类有个属性 $$beanFactory 持有 BeanFactory 实例。
		ConfigurableBeanFactory beanFactory = getBeanFactory(enhancedConfigInstance);
		String beanName = BeanAnnotationHelper.determineBeanNameFor(beanMethod);

		// Determine whether this bean is a scoped-proxy
		if (BeanAnnotationHelper.isScopedProxy(beanMethod)) {
			String scopedBeanName = ScopedProxyCreator.getTargetBeanName(beanName);
			if (beanFactory.isCurrentlyInCreation(scopedBeanName)) {
				beanName = scopedBeanName;
			}
		}

		// To handle the case of an inter-bean method reference, we must explicitly check the
		// container for already cached instances.

		// 常规获取 Bean, beanFactory.getBean(beanName)
		return resolveBeanReference(beanMethod, beanMethodArgs, beanFactory, beanName);
	}

}
```

        bean 构造和初始化，使用 method 定义的方法来实现。

```java
/**
 * Read the given BeanMethod, registering bean definitions
 * with the BeanDefinitionRegistry based on its contents.
 * @from org.springframework.context.annotation.ConfigurationClassBeanDefinitionReader
 */
private void loadBeanDefinitionsForBeanMethod(BeanMethod beanMethod) {
	ConfigurationClass configClass = beanMethod.getConfigurationClass();
	MethodMetadata metadata = beanMethod.getMetadata();
	String methodName = metadata.getMethodName();

	// 获取 method @Bean 注解配置
	AnnotationAttributes bean = AnnotationConfigUtils.attributesFor(metadata, Bean.class);
	Assert.state(bean != null, "No @Bean annotation attributes");

	// Consider name and Register aliases...

	ConfigurationClassBeanDefinition beanDef = new ConfigurationClassBeanDefinition(configClass, metadata);
	beanDef.setResource(configClass.getResource());
	beanDef.setSource(this.sourceExtractor.extractSource(metadata, configClass.getResource()));

	if (metadata.isStatic()) {
		// static @Bean method 不依赖 configClass instance, 可以直接初始化为bean
		if (configClass.getMetadata() instanceof StandardAnnotationMetadata) {
			beanDef.setBeanClass(((StandardAnnotationMetadata) configClass.getMetadata()).getIntrospectedClass());
		}
		else {
			beanDef.setBeanClassName(configClass.getMetadata().getClassName());
		}
		beanDef.setUniqueFactoryMethodName(methodName);
	}
	else {
		// instance @Bean method 🎈🎈🎈
		beanDef.setFactoryBeanName(configClass.getBeanName());
		beanDef.setUniqueFactoryMethodName(methodName);
	}
	// beanDef.setAttribute...
	this.registry.registerBeanDefinition(beanName, beanDefToRegister);
}
```

## 总结

- Spring 框架为了使用的方便，尽可能的隐藏了实现细节。让开发更加方便。

- 因为隐藏了技术细节，对于诸如上述的 Inter-bean dependency 配置方式，开发者可能会误解，会显示调用框架的接口。

- 这次分析AOP 的使用场景，又一次加深了动态代理的理解，眼前一亮。

- **通过AOP 方式对Bean-Method 代理，可以用 cache 使用的角度去理解**。如果存在，从 beanFactory cache 获取并返回；如果不存在，则根据 Bean-Method 去创建bean, 并put 到beanFactory cache， 再返回。✨

















































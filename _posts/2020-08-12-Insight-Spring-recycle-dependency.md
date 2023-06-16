---
layout: post
title:  "Spring 循环依赖及解决方案"
date:   2020-08-12 16:48:47 +0800
categories: 源码阅读
tags: Spring

---
* content
{:toc}

## 问题场景

> 遇到的问题：项目中需要用到策略模式，把策略实现以集合的形式注入到Service 中。因为要强制校验策略的顺序，所以采用的是构造器注入，简单明了。结果Spring 启动失败，`Is there an unresolvable circular reference?`。

## 分析

首先，查看Spring启动异常的日志，throw BeanCurrentlyInCreationException

```java
/**
 * Exception thrown in case of 引用了当前正在创建中的bean.
 * Typically happens when constructor autowiring matches the currently constructed bean.
 * 直接指明出现在构造器注入时发生
 */
public class BeanCurrentlyInCreationException extends BeanCreationException {
}
```

然后，根据异常日志提示的信息，可以梳理出依赖的关系链，aService 构造器注入的策略bService，bService 实现业务注入cService，而cService注入了aService。

需要特别强调的是：**循环依赖和Spring 创建Bean 的顺序有严格的关系**。例如：AService、CService 类的顺序随着ClassPath扫描后，自然的就是先创建AService Bean。如果CService 先扫描到，那么就不会出现 BeanCurrentlyInCreationException。所以`深入的分析，循环依赖问题和操作系统的文件系统或者xml 配置的顺序都有关系`。

> 2个解决方案：
>
> 1. 策略集合采用属性Setter注入，单独写@PostConstruct 初始化方法，完成策略顺序的校验和打印。替换掉构造器注入的写法。这个方案比较直接。
>
> 2. 指定Spring容器创建Bean的顺序，保证cService在aService 之前创建，这样就解耦了循环依赖。详细解释如下分析可知。
>
>    ```java
>    // 强制指定Spring 容器先创建CService。这样可以通过earlySingletonExposure 方案解决循环
>    @DependsOn(value = "cService")
>    @Service
>    public class AService {
>    
>        private CService cService;
>    
>        @Autowired
>        public AService(CService cService) {
>            this.cService = cService;
>        }
>    }
>    
>    @Service
>    public class CService {
>    
>        @Autowired
>        private AService aService;
>    
>    }
>    
>    ```
>
>    

## Insight与总结

文章主要记录查看源码的思路，和总结，便于后续方便查阅。

具体的循环依赖源码实现分析，参考：[彻底理解SpringIOC、DI-这篇文章就够了](https://juejin.im/post/6844903715602694152)、[图解Spring解决循环依赖♻️](https://juejin.im/post/6844904122160775176)

### Insight 方法

Spring对于循环依赖的处理，如果从设计的原因去看，阅读源码可能会清晰一下。如果直接入手看源码，可能会比较绕、困惑很多。一是循环依赖是个循环调用、递归的过程，静态阅读或者动态调试都会比较复杂；另外一个是由于Spring丰富的功能设计，不能非常直接的看到循环依赖核心的实现方案。

一种Insight 方法是：直接`BeanCurrentlyInCreationException`打断点，查看全部的调用链，从中分析出现循环依赖的原因。属于逆向的看源码。

一种Insight方法是：先分析为什么出现循环依赖，如果要解决循环依赖需要做哪些设计。再结合博客的讲解（Spring 文档没有找到对循环依赖设计思路的描述），提纲挈领的去阅读源码。属于正向设计思路的看源码。

### 总结

* Spring支持循环依赖(`resolving a circular reference`)，只限定在singleton 模式下，prototype不支持。
* 在Spring容器初始化过程中，依赖注入的主角是Bean，而非原始的对象。Bean 的初始化是分步骤的、框架可控制的，而原始的对象的初始化是JDK层级的。一定要清楚循环依赖的方案主角是Bean，而非原始对象。`默认 bean初始化是可以通过拆解初始化步骤解耦循环，如果是构造器注入，则把循环依赖拉低到JDK层级，不可控无法实现。`
* Bean的初始化步骤：resolveBeanClass➡createBeanInstance➡earlySingletonExposure➡populateBean。参考：*org.springframework.beans.factory.support.AbstractAutowireCapableBeanFactory#doCreateBean*
* 如果是构造器注入，相当于把原始对象初始化托管给了Spring，`想要得到原始对象，肯定是要构造器执行完成后`。Spring 托管构造器后，需要的构造器参数由Spring find，如果Spring检测到循环依赖后，自然就终止了初始化过程。对应到源码就是createBeanInstance，该方法没有执行完，没有earlySingletonExposure
* 如果是Setter依赖注入，getBean()使用默认初始化的方式，createBeanInstance得到`原始对象暴露给Spring容器`。因为是singleton 模式，`全局唯一的引用，支持提前赋值（注入）到其他bean 对象中`。原始对象的setter注入由populateBean完成。通过拆分bean 的instantiate、set/inject 步骤，并且把singleton 引用提前缓存到全局变量中，这样即使是循环依赖也可以提前得到初始化中的原始对象。即使`概念意义的Bean没有初始化完成`，也不会出现循环依赖无法解决的情况。
* 提前得到注入的原始对象，依赖的是Spring 容器singleton 三级缓存，详见参考中的代码片段。

## 源码参考

### bean 初始化默认方式

```java
/**
 * Instantiate the given bean using its default constructor.
 * 默认的初始化bean 的实现，
 * 简单描述为：return new BeanWrapper(Foo.class.getConstructor().newInstance())
 * @From AbstractAutowireCapableBeanFactory
 */
protected BeanWrapper instantiateBean(final String beanName, final RootBeanDefinition mbd) {
	try {
		Object beanInstance;
		final BeanFactory parent = this;
		// 对象instantiate。根据BeanDefinition 获取bean Class的信息，解析默认的构造函数，通过反射得到对象
		// Spring在此处也应用了策略模式，增加扩展性的同时，也降低了阅读的流畅性。
		beanInstance = getInstantiationStrategy().instantiate(mbd, beanName, parent);
		// 将原始的对象包装为Bean，暴露给Spring容器。包装的目的是：方便对原始对象做各种转换和操作。
		BeanWrapper bw = new BeanWrapperImpl(beanInstance);
		initBeanWrapper(bw);
		return bw;
	}
	catch (Throwable ex) {
		throw new BeanCreationException(mbd.getResourceDescription(), beanName, "Instantiation of bean failed", ex);
	}
}

```



### 循环依赖的检测

```java
/**
 * Mark this bean as currently in creation, even if just partially.
 * 如果全局变量singletonsCurrentlyInCreation 已经包含beanName，证明发生了循环/递归调用。SetAndChek
 * @From DefaultSingletonBeanRegistry
 */
protected void beforeSingletonCreation(String beanName) {
	if (!this.inCreationCheckExclusions.containsKey(beanName) &&
			this.singletonsCurrentlyInCreation.put(beanName, Boolean.TRUE) != null) {
		throw new BeanCurrentlyInCreationException(beanName);
	}
}
```



### singletonObject 三级缓存

```java
/**
 * Return the (raw) singleton object registered under the given name.
 * <p>Checks already instantiated singletons and also allows for an early
 * reference to a currently created singleton (resolving a circular reference).
 * 如下singletonObjects、earlySingletonObjects、singletonFactories 属于DefaultSingletonBeanRegistry 全局变量，充当一二三级缓存
 */
protected Object getSingleton(String beanName, boolean allowEarlyReference) {
    // 首先从singletonObjects 获取对应已注册的bean
	Object singletonObject = this.singletonObjects.get(beanName);
	if (singletonObject == null && isSingletonCurrentlyInCreation(beanName)) {
		synchronized (this.singletonObjects) {
            // 然后从earlySingletonObjects 取已注册未完成初始化的bean。that is not fully initialized yet
			singletonObject = this.earlySingletonObjects.get(beanName);
			if (singletonObject == null && allowEarlyReference) {
                // 最后从singletonFactories 取可提前获得但未注册的bean。that is none registered yet
				ObjectFactory<?> singletonFactory = this.singletonFactories.get(beanName);
				if (singletonFactory != null) {
					singletonObject = singletonFactory.getObject();
					this.earlySingletonObjects.put(beanName, singletonObject);
					this.singletonFactories.remove(beanName);
				}
			}
		}
	}
	return (singletonObject != NULL_OBJECT ? singletonObject : null);
}

```


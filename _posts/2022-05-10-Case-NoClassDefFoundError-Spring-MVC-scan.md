---
layout: post
title:  "Case NoClassDefFoundError 案例-Spring MVC 扫描Controller"
date:   2022-05-10 16:57:19 +0800
categories: jekyll update
---
# NoClassDefFoundError 案例-Spring MVC 扫描Controller

## 错误信息

> org.springframework.beans.factory.BeanCreationException: 
> 
> Error creating bean with name 'fooController': 
> 
> **Failed to introspect bean class** [com.foo.FooController] for lookup method metadata: could not find class that it depends on; 
> 
> nested exception is java.lang.**NoClassDefFoundError**: com/foo/Result

## 错误分析

```java
// 该方法的返回类型 ResponseResult extend Result
@RequestMapping("/getList")
public ResponseResult<Foo> getList(@RequestBody Query params){
	//...
}
```

根据错误提示，在代码中并没有找到 *Result* 类直接使用。

再进一步看日志，*introspect bean* 出现的问题，推测是进行反射的操作异常。

通过查看方法的返回类型，其父类就是Result，但是在当前的工程中，并没有引入对应的maven 依赖。

**结果就是编译通过，但是运行时异常。**

## 错误解决

引入需要的jar 到当前的工程（classpath）。

## 源码分析

上述提到的*introspect bean* 过程，在Spring 中的相关源码

```java
// org.springframework.beans.factory.annotation.AutowiredAnnotationBeanPostProcessor
public Constructor<?>[] determineCandidateConstructors(Class<?> beanClass, final String beanName) {

	// Let's check for lookup methods here..
	if (!this.lookupMethodsChecked.contains(beanName)) {
		try {
            // Spring 初次缓存beanClass 的相关method。
			ReflectionUtils.doWithMethods(beanClass, new ReflectionUtils.MethodCallback() {
				@Override
				public void doWith(Method method) {
					// ...
				}
			});
		}
        // 本次的异常打印日志
		catch (NoClassDefFoundError err) {
			throw new BeanCreationException(beanName, "Failed to introspect bean class [" + beanClass.getName() +
					"] for lookup method metadata: could not find class that it depends on", err);
		}
		this.lookupMethodsChecked.add(beanName);
	}
}
```





















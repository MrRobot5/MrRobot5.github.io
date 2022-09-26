# 笔记-Mybatis Interceptor

## How to use

```java
@Intercepts({@Signature(
        type= Executor.class,
        method = "update",
        args = {MappedStatement.class ,Object.class})})
public class ExamplePlugin implements Interceptor {
    @Override
    public Object intercept(Invocation invocation) throws Throwable {
        // implement pre-processing if needed
        Object returnObject = invocation.proceed();
        // implement post-processing if needed
        return returnObject;
    }
}
```

[Intercepts (mybatis 3.5.11 API)](https://mybatis.org/mybatis-3//apidocs/org/apache/ibatis/plugin/Intercepts.html)

## Mybatis 处理层四大组件

> 支持四大组件的处理拦截，实际使用拦截器主要是 Executor。即上述的 @Intercepts.type

1. ParameterHandler

2. StatementHandler

3. Executor 

4. ResultSetHandler

## Interceptor 配置和解析

```java
private void pluginElement(XNode parent) throws Exception {
	if (parent != null) {
		for (XNode child : parent.getChildren()) {
			String interceptor = child.getStringAttribute("interceptor");
			Properties properties = child.getChildrenAsProperties();
			Interceptor interceptorInstance = (Interceptor) resolveClass(interceptor).getDeclaredConstructor().newInstance();
			interceptorInstance.setProperties(properties);
			configuration.addInterceptor(interceptorInstance);
		}
	}
}
```

## 拦截器原理

```java
/**
 * Executor 初始化，同时进行插件增强。 
 * @see org.apache.ibatis.session.Configuration#newExecutor()
 */
public Executor newExecutor(Transaction transaction, ExecutorType executorType) {
	Executor executor = new SimpleExecutor(this, transaction);
	if (cacheEnabled) {
		executor = new CachingExecutor(executor);
	}
	// 基于JDK Proxy, executor 是经过各个interceptor 层层代理后的结果
	// 代理生成是通过 Plugin.wrap(Object target, Interceptor interceptor) 完成的
	executor = (Executor) interceptorChain.pluginAll(executor);
	return executor;
}


public class Plugin implements InvocationHandler {

	public static Object wrap(Object target, Interceptor interceptor) {
		// 解析@Intercepts ，得到期望拦截的组件和方法
		Map<Class<?>, Set<Method>> signatureMap = getSignatureMap(interceptor);
		Class<?> type = target.getClass();
		Class<?>[] interfaces = getAllInterfaces(type, signatureMap);
		// 如果有匹配拦截器的组件和方法，那么就进行代理。 例如： Executor.update()
		if (interfaces.length > 0) {
			return Proxy.newProxyInstance(
					type.getClassLoader(),
					interfaces,
					// 关键实现，关注target 和 interceptor
					new Plugin(target, interceptor, signatureMap));
		}
		return target;
	}

	@Override
	public Object invoke(Object proxy, Method method, Object[] args) throws Throwable {
		try {
			Set<Method> methods = signatureMap.get(method.getDeclaringClass());
			if (methods != null && methods.contains(method)) {
				// 通过 interceptor 把参数暴露出去，代码增强在interceptor 完成。
				return interceptor.intercept(new Invocation(target, method, args));
			}
			return method.invoke(target, args);
		} catch (Exception e) {
			throw ExceptionUtil.unwrapThrowable(e);
		}
	}
}
```

## 其他-JDK Proxy

```java
public static Object newProxyInstance(ClassLoader loader, Class<?>[] interfaces, InvocationHandler h) throws IllegalArgumentException {
	
	/*
	 * Look up or generate the designated proxy class.
	 * Return the cached copy or create the proxy class via the ProxyClassFactory
	 * Generate the specified proxy class via ProxyGenerator
	 */
	Class<?> cl = getProxyClass0(loader, intfs);

	/*
	 * Invoke its constructor with the designated invocation handler.
	 * InvocationHandler 作为构造入参，生成代理实例
	 */
	try {
		final Constructor<?> cons = cl.getConstructor(constructorParams);
		return cons.newInstance(new Object[]{h});
	}
}

```



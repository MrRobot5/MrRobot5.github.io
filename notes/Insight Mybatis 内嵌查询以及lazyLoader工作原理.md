# Insight Mybatis 内嵌查询以及lazyLoader工作原理

## Mybatis内嵌查询示例

```xml
<resultMap id="detailResultMap" type="com.foo.model.FooBase">
	<id column="id" property="id" jdbcType="INTEGER" />
	<result column="name" property="name" jdbcType="VARCHAR" />
    <!-- 通过内嵌查询，实现类似Hibernate 级联查询的功能，支持延时查询-->
	<collection property="detailList" column="id" javaType="java.util.ArrayList"
		ofType="com.foo.model.FooDetail"
		select="com.foo.dao.FooDetailMapper.selectByBaseId" fetchType="lazy"/> 
</resultMap>
```



## 内嵌查询工作原理

### nested query xml 解析

> 关键信息：`ResultMapping#nestedQueryId`

```java
/**
 * mybatis 解析resultMap childNodes
 *
 * @see  org.apache.ibatis.builder.xml.XMLMapperBuilder#buildResultMappingFromContext
 */
private ResultMapping buildResultMappingFromContext(XNode context, Class<?> resultType, List<ResultFlag> flags) throws Exception {
    // 关键属性select, 对应 ResultMapping#nestedQueryId
    // Tips: 后续调用applyCurrentNamespace() 检测和补充查询方法的namespace，检测符号“.”
    String nestedSelect = context.getStringAttribute("select");
    // 注意，内嵌query 和内嵌resultMap 的两种使用方法，彼此互斥。
    String nestedResultMap = context.getStringAttribute("resultMap",
        processNestedResultMappings(context, Collections.<ResultMapping> emptyList()));
    // 懒加载属性，默认 configuration.isLazyLoadingEnabled() = false。
    boolean lazy = "lazy".equals(context.getStringAttribute("fetchType", configuration.isLazyLoadingEnabled() ? "lazy" : "eager"));
    
}

```

### nested query 执行过程

> 嵌套查询的过程：先执行主查询，在返回结果ResultSet 匹配到ResultMap过程中，发现有nestedQuery，就会再次发起查询（或者lazy模式下，缓存查询的对象、方法和参数，必要的时候发起查询）

#### 方法执行调用链

- org.apache.ibatis.executor.statement.PreparedStatementHandler#query
- org.apache.ibatis.executor.resultset.DefaultResultSetHandler#handleResultSets
- org.apache.ibatis.executor.resultset.DefaultResultSetHandler#handleRowValues
- org.apache.ibatis.executor.resultset.DefaultResultSetHandler#handleRowValuesForSimpleResultMap
- org.apache.ibatis.executor.resultset.DefaultResultSetHandler#getRowValue
- org.apache.ibatis.executor.resultset.DefaultResultSetHandler#applyPropertyMappings
- org.apache.ibatis.executor.resultset.DefaultResultSetHandler#getPropertyMappingValue

#### nested query 执行

```java
private Object getNestedQueryMappingValue(ResultSet rs, MetaObject metaResultObject, ResultMapping propertyMapping, ResultLoaderMap lazyLoader, String columnPrefix) throws SQLException {
    final String nestedQueryId = propertyMapping.getNestedQueryId();
    final MappedStatement nestedQuery = configuration.getMappedStatement(nestedQueryId);
    final Object nestedQueryParameterObject = prepareParameterForNestedQuery(rs, propertyMapping, nestedQueryParameterType, columnPrefix);
    Object value = null;
    // 首先判断查询的参数不能为空
    if (nestedQueryParameterObject != null) {
        final Class<?> targetType = propertyMapping.getJavaType();
        // 扩展 DeferredLoad 缓存机制，本次不做解读
        if (executor.isCached(nestedQuery, key)) {
            executor.deferLoad(nestedQuery, metaResultObject, property, key, targetType);
            value = DEFERED;
      } else {
            // 延时加载委托类ResultLoader，保存必要的查询信息，用于嵌套查询使用
            // 必要的信息对应的是, BaseExecutor#query(MappedStatement, Object, RowBounds, ResultHandler, CacheKey, BoundSql)
            final ResultLoader resultLoader = new ResultLoader(configuration, executor, nestedQuery, nestedQueryParameterObject, targetType, key, nestedBoundSql);
            if (propertyMapping.isLazy()) {
                lazyLoader.addLoader(property, metaResultObject, resultLoader);
                value = DEFERED;
            } else {
                // 正常情况下，非延时，直接发起查询。BaseExecutor.query(...)
                value = resultLoader.loadResult();
            }
        }
    }
    return value;
}

```



## lazyLoader工作原理

> mybatis 延时查询原理：在将结果集转化为值对象时，会对映射到的属性进行实例化操作。借助动态代理，会将lazyLoader 作为属性添加到值对象中。真正对该值对象读取操作时，代理类拦截并发起真正的数据库查询。
>
> `注意：仅限嵌套查询才有延时查询的概念。`

#### 关键类

- org.apache.ibatis.executor.loader.ResultLoaderMap
- org.apache.ibatis.executor.loader.ResultLoader

#### 值对象的实例化和代理过程

```java
/**
 * @see  org.apache.ibatis.executor.resultset.DefaultResultSetHandler#createResultObject
 */
private Object createResultObject(ResultSetWrapper rsw, ResultMap resultMap, ResultLoaderMap lazyLoader, String columnPrefix) throws SQLException {
	// 值对象实例化，constructor.newInstance()
	Object resultObject = createResultObject(rsw, resultMap, constructorArgTypes, constructorArgs, columnPrefix);
	if (resultObject != null && !hasTypeHandlerForResultObject(rsw, resultMap.getType())) {
		final List<ResultMapping> propertyMappings = resultMap.getPropertyResultMappings();
		for (ResultMapping propertyMapping : propertyMappings) {
			// 检测到存在嵌套查询，并且需要延时加载，对原对象进行代理操作。
			if (propertyMapping.getNestedQueryId() != null && propertyMapping.isLazy()) {
                // proxy.callback = lazyLoader, 拦截getSet方法，在realObject 读写之前，结束延时的状态。
				resultObject = configuration.getProxyFactory().createProxy(resultObject, lazyLoader, configuration, objectFactory, constructorArgTypes, constructorArgs);
				break;
			}
		}
	}
	this.useConstructorMappings = resultObject != null && !constructorArgTypes.isEmpty(); 
	return resultObject;
}

```



```java
/**
 * 借助查询委托类resultLoader，查询得到的结果，赋值到realObject，达到延时替换的目的。
 * @see  org.apache.ibatis.executor.loader.ResultLoaderMap.LoadPair#load
 */
public void load(final Object userObject) throws SQLException {
	this.metaResultObject.setValue(property, this.resultLoader.loadResult());
}
```



## 参考

[Insight Mybatis 内嵌resultMap工作原理](./Insight Mybatis 内嵌resultMap工作原理.md)


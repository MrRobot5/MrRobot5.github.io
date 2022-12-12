---

layout: post
title:  "Insight Mybatis 内嵌resultMap工作原理"
date:   2020-09-11 18:46:39 +0800
categories: jekyll update

---

# Insight Mybatis 内嵌resultMap工作原理

## 疑问

```xml
<!--
    如下的Mybatis 配置，collection 是如何工作的，对于SQL查询的数据结果集，在Mybatis 映射生成对象时，怎样组装的？
-->
<resultMap id="viewResultMap" type="com.mybatis.model.CityView">
    <result column="pid" jdbcType="INTEGER" property="pId"/>
    <result column="name" jdbcType="VARCHAR" property="countryName"/>
    <collection property="citys" resultMap="moreResultMap"/>
</resultMap>
```

## Insight 总结

1. 对于使用的ResultMap， 在查询完成后，映射处理时，会判断是否有内嵌（`resultMap.hasNestedResultMaps()`），从而确定执行哪种匹配映射策略。
2. `与collection 相似的还有association` 标签，都是一样的作为内嵌映射进行处理。
3. 内嵌映射的处理思路，类似于在内存中做group by 聚合操作。以viewResultMap 的property 集合作为主键，对原始数据集进行聚合操作，数据的最终明细体现在内嵌的collection 或者 association 中。
4. 上述的resultMap 数据结构可以用 `new LinkedHashMap<K, List<V>>()` 描述， Mybatis 也是基于这样的结构进行操作。
5. Mybatis 该功能实现阅读、理解的障碍是，这个`内嵌映射是个递归处理的过程`，如果单纯看源码实现，就很容易陷入其中。如果能先带着猜想，通过设计思路的验证去阅读，会清晰很多。

## Code Insight

关键类：`org.apache.ibatis.executor.resultset.DefaultResultSetHandler`

```java
/**
 * 内嵌结果集处理整体逻辑：
 * 遍历ResultSet，借助全局变量 nestedResultObjects，以主数据为全局唯一主键，处理带有内嵌配置的结果集。类似于在内存中做group by 聚合操作。
 * 具体的数据映射，对象构造，内嵌递归处理，参考 getRowValue()
 */
private void handleRowValuesForNestedResultMap() throws SQLException {
    // 遍历ResultSet
    while (shouldProcessMoreRows(resultContext, rowBounds) && rsw.getResultSet().next()) {
        final ResultMap discriminatedResultMap = resolveDiscriminatedResultMap(rsw.getResultSet(), resultMap, null);
        // 构造主数据的唯一主键，这个主键会缓存在全局 nestedResultObjects
        final CacheKey rowKey = createRowKey(discriminatedResultMap, rsw, null);
        // 根据resultSet 构造主数据，或者构造内嵌数据，追加到主数据
        rowValue = getRowValue(rsw, discriminatedResultMap, rowKey, null, partialObject);
        // putIfAbsent 操作
        Object partialObject = nestedResultObjects.get(rowKey);
        if (partialObject == null) {
            storeObject(resultHandler, resultContext, rowValue, parentMapping, rsw.getResultSet());
        }
    }
}
```

```java
/**
 * 功能逻辑：resultSet 转化为 instance 策略实现。内嵌映射递归检测、处理。
 *
 * @partialObject 如果为null，说明是父对象的初始化过程
 * 如果非null，说明是内嵌对象的初始化过程
 */
private Object getRowValue() {
    // 内嵌对象的初始化过程
    if (partialObject != null) {
        final MetaObject metaObject = configuration.newMetaObject(rowValue);
        // 为了明确知道递归调用的阶段，需要借助ancestorObjects 来暂存对应的对象实例。递归完后remove。
        putAncestor(rowValue, resultMapId);
        applyNestedResultMappings(rsw, resultMap, metaObject, columnPrefix, combinedKey, false);
        ancestorObjects.remove(resultMapId);
    } else {
        // 父对象的初始化过程
        final ResultLoaderMap lazyLoader = new ResultLoaderMap();
        // 1. constructor.newInstance() 
        rowValue = createResultObject(rsw, resultMap, lazyLoader, columnPrefix);
        if (rowValue != null && !hasTypeHandlerForResultObject(rsw, resultMap.getType())) {
            final MetaObject metaObject = configuration.newMetaObject(rowValue);
            boolean foundValues = this.useConstructorMappings;
            // 2. 根据resultSet 赋值给 newInstance
            foundValues = applyPropertyMappings(rsw, resultMap, metaObject, lazyLoader, columnPrefix) || foundValues;
            putAncestor(rowValue, resultMapId);
            // 3. 检测是否有内嵌查询，如果有，则追加。递归调用，直到所有的内嵌查询查询完成。
            // 内嵌数据追加到主数据的逻辑：instantiateCollectionPropertyIfAppropriate -> 内嵌查询getRowValue() -> linkObjects
            foundValues = applyNestedResultMappings(rsw, resultMap, metaObject, columnPrefix, combinedKey, true) || foundValues;
            ancestorObjects.remove(resultMapId);
            foundValues = lazyLoader.size() > 0 || foundValues;
            rowValue = foundValues || configuration.isReturnInstanceForEmptyRow() ? rowValue : null;
        }
        if (combinedKey != CacheKey.NULL_CACHE_KEY) {
            // 4. 缓存rowValue，保证集合数据唯一
            nestedResultObjects.put(combinedKey, rowValue);
        }
    }
}
```

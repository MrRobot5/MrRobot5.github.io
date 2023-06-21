---
layout: post
title:  "Mybatis 配置差异引发的问题"
date:   2023-06-21 15:32:20 +0800
categories: 实战问题
tags: Mybatis 问题分析
---

* content
{:toc}

我就是把功能代码从 A 工程 copy 到 B 工程，怎么就报错了呢？

## 问题场景

代码功能：从数据库查询数据集合，翻译枚举字段 `signStatus`。运行到第4行报错。

```java
// 使用 Mybatis 查询数据集合 ①
List<SomeData> data = fooMapper.selectList(someParam);
for (SomeData item : data) {
    // throw NullPointerException ②
    model.setSignStatusDesc(SignStatusEnum.getDescByValue(item.getSignStatus()));
}

@Data
public class SomeData {

    /**
     * 签到状态，默认值为 0 🎈
     */
    private Integer signStatus = 0;

}

// 枚举翻译类，接收参数类型 int ③
public static String getDescByValue(int value){
    for (SignStatusEnum signStatusEnum : SignStatusEnum.values()){
        if (value == signStatusEnum.getValue()) {
            return signStatusEnum.getDesc();
        }
    }
    return "";
}
```

① Mybatis 对应的 SQL 查询到的数据，`sign_status` 字段确实是 null

② Mybatis 组装完的对象 item，调用枚举翻译类转中文时，报错 NullPointerException

③ 翻译方法的入参为原始类型 int, item.getSignStatus() 返回类型为 Integer ，会自动拆箱，null 值拆箱，就会触发 NullPointerException。

---

代码在 A 工程里，运行正常，并没有报错。到 B 工程里，signStatus 默认值被覆盖为 null, **那是什么问题** ❓

## Code Insight

经过上述的分析和排查，相同的代码和数据，唯一的区别是运行的工程环境不同。

那问题应该就处在 Mybatis ORM 的处理阶段。

根据之前 Code Insight 记录【[Mybatis 内嵌 resultMap 工作原理](./2020-09-11-Insight-Mybatis-inline-resultMap.md)】，直接定位到返回类初始化的源码。

```java
/**
 * PROPERTY MAPPINGS
 *
 * @param metaObject MyBatis 框架包装类，方便处理对象属性的读写操作。
 * @see DefaultResultSetHandler#applyPropertyMappings(ResultSetWrapper, ResultMap, MetaObject, ResultLoaderMap, String)
 */
private boolean applyPropertyMappings(ResultSetWrapper rsw, ResultMap resultMap, MetaObject metaObject, ResultLoaderMap lazyLoader, String columnPrefix) throws SQLException {
	// Mybatis 动态SQL resultMap 映射集合
	final List<ResultMapping> propertyMappings = resultMap.getPropertyResultMappings();
	for (ResultMapping propertyMapping : propertyMappings) {
		if (propertyMapping.isCompositeResult()
				|| (column != null && mappedColumnNames.contains(column.toUpperCase(Locale.ENGLISH)))
				|| propertyMapping.getResultSet() != null) {
			// 获取数据库对应列的值
			Object value = getPropertyMappingValue(rsw.getResultSet(), metaObject, propertyMapping, lazyLoader, columnPrefix);
			// 赋值操作，此处有 CallSettersOnNulls 配置判断 ④
			if (value != null || (configuration.isCallSettersOnNulls() && !metaObject.getSetterType(property).isPrimitive())) {
				// gcode issue #377, call setter on nulls (value is not 'found')
				metaObject.setValue(property, value);
			}
		}
	}
	return foundValues;
}
```

 ④ 如果 select sign_status 有值，那么就赋值到 signStatus，替换默认值 0。如果启用 CallSettersOnNulls 配置，属性类型非原始类，**即使是 null, 也会赋值到 signStatus**。

## Mybatis CallSettersOnNulls

根据上述的源码分析，应该是 CallSettersOnNulls 配置的影响。在 B 工程中，确实有这个配置，删除该配置项，代码运行正常。

参考资料：

[MyBatis 3 | 配置](https://mybatis.org/mybatis-3/zh/configuration.html#%E8%AE%BE%E7%BD%AE%EF%BC%88settings%EF%BC%89)

[issue #377, call setter on nulls, correct in 3.4.0 but error in 3.4.1-3.4.5 · Issue #1175 · mybatis/mybatis-3 · GitHub](https://github.com/mybatis/mybatis-3/issues/1175)



## 总结

- 这次的代码迁移触发了一个小概率问题，也了解 Mybatis CallSettersOnNulls 配置的工作机制。

- 框架增减配置，影响全局。需要详细了解作用原理，并谨慎评估影响面，充分测试。

- 关于数据的默认值，理论上应该是定义在数据库的表结构定义中。上述案例 SQL 为关联查询，默认值定义在模型类中。

- 关于枚举类翻译遇到自动拆箱 NullPointerException，不止一次。业务数据的类型定义应该保持一致，避免此类不必要的问题。

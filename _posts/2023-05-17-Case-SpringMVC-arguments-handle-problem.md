---
layout: post
title:  "Case SpringMVC 不同参数处理机制引发的问题"
date:   2023-05-17 18:46:33 +0800
categories: jekyll update
---

# Case SpringMVC 不同参数处理机制引发的问题

> 这个问题非常有趣，不是SpringMVC 的问题，是使用了两种请求方式暴露出来的。

## 问题场景

功能模块中，提供两个 Http 服务。一个是列表查询（application/json 请求），一个是列表导出（表单请求）。运行发现新增的参数，同样的 Http 请求，一个有值，一个没有🙄

****

代码如下：

```java
/**
 * application/json 请求
 * @param param RequestResponseBodyMethodProcessr 处理 HttpServletRequest 参数
 */
@PostMapping(value = "query")
public ResponseResult<Page<SomeData>> queryByCondition(@RequestBody SomeParam param){
}

/**
 * application/x-www-form-urlencoded 请求
 * @param param ServletModelAttributeMethodProcessor 处理 HttpServletRequest 参数
 */
@PostMapping(value = "export")
public void exportExcel(SomeParam param) {
}


public class SomeParam {

    // 这个是原有的，有 get set 方法
    private String field1;

    // 这个是新增的，没有get set 方法 🎈。 问题就出在这里。
    private String field2;

}
```

## Insight RequestResponseBodyMethodProcessor

> 处理 Http Body 的数据。解析注解 RequestBody 的参数。
> 
> 针对 MimeType 为 application/json 的请求，按照json 格式进行反序列化。
> 
> 默认参数处理器 MappingJackson2HttpMessageConverter

string 反序列化为对象，使用的是 com.fasterxml.jackson.databind.ObjectMapper。

上述工程中，对 ObjectMapper 开启 private 属性检测。新增的属性可以正常反序列化。

```java
ObjectMapper mapper = new ObjectMapper();
mapper.setVisibility(PropertyAccessor.ALL, Visibility.NONE);
mapper.setVisibility(PropertyAccessor.FIELD, Visibility.ANY);
```

参考： [Jackson - Decide What Fields Get (De)Serialized | Baeldung](https://www.baeldung.com/jackson-field-serializable-deserializable-or-not)

如果没有 setter 方法，jackson 会操作 field 来完成赋值。

```java
/**
 * This concrete sub-class implements property that is set directly assigning to a Field.
 */
public final static class FieldProperty extends SettableBeanProperty {

    @Override
    public final void set(Object instance, Object value) throws IOException {
        try {
            _field.set(instance, value);
        } catch (Exception e) {
            _throwAsIOE(e, value);
        }
    }
}
```

## Insight ServletModelAttributeMethodProcessor

> 自定义 Class 参数解析
> 
> 通过解析 request parameters, 用来构造和初始化对应的方法入参。
> 
> 主要通过 ServletRequestDataBinder.bind(request) 来完成。

```java
/**
 * Apply given property values to the target object.
 * By default, unknown fields will be ignored.
 * 
 * @see org.springframework.validation.DataBinder#applyPropertyValues
 */
protected void applyPropertyValues(MutablePropertyValues mpvs) {
	try {
		// Bind request parameters onto target object.
		// 默认使用 BeanWrapperImpl.setPropertyValue()
		getPropertyAccessor().setPropertyValues(mpvs, isIgnoreUnknownFields(), isIgnoreInvalidFields());
	}
	catch (PropertyBatchUpdateException ex) {
		// Use bind error processor to create FieldErrors.
	}
}
```

```java
public void setPropertyValues(PropertyValues pvs, boolean ignoreUnknown, boolean ignoreInvalid) throws BeansException {
    // 通过遍历 request parameters 来尝试对 target 进行赋值
	List<PropertyValue> propertyValues = (pvs instanceof MutablePropertyValues ? 			((MutablePropertyValues) pvs).getPropertyValueList() : Arrays.asList(pvs.getPropertyValues()));
	for (PropertyValue pv : propertyValues) {
		try {
			// etPropertyValue 使用 JDK 的 Introspector 来进行序列化操作。
            // 没有setter 方法，自然没法赋值。
			setPropertyValue(pv);
		}
	}
}
```

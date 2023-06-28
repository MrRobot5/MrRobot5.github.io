---
layout: post
title:  "SpringMVC DataBinder 和 Spring Type Conversion 知识点梳理"
date:   2017-07-29 18:39:51 +0800
categories: 学习笔记
tags: SpringMVC
---

* content
{:toc}

通过 **SpringMVC Date 参数实例化**的配置实例，梳理和分析类型转换在 Spring 框架中的实现过程。

## 关键类🎯

> Spring 内置的类型转换实现组件，可以通过以下接口追溯

- org.springframework.core.convert.converter.Converter

- java.beans.PropertyEditor

- **org.springframework.beans.TypeConverterDelegate** Spring 内部类型转换工具类

- org.springframework.core.convert.support.GenericConversionService 类型转换器默认实现，可以直接注入使用。



## SpringMVC Web DataBinder

> Spring MVC 层组件。相对于原始的 servlet 开发，帮助开发人员轻松地处理 Web 请求和响应。 [Spring Web MVC DataBinder](https://docs.spring.io/spring-framework/docs/5.2.24.RELEASE/spring-framework-reference/web.html#mvc-ann-initbinder) 。

### 功能

1. 数据绑定（Bind request parameters to a model object.）

2. 类型转换 （把字符串类型的请求值转换为 controller 方法所需的数据类型），对应 java.beans.PropertyEditor#setAsText

3. 格式化 (Format model object values as `String` values)， 对应 java.beans.PropertyEditor#getAsText

### 配置示例

#### 1️⃣限定 Controller 类型转换配置

```java
@Controller
public class FormController {                
    
    @InitBinder 
    public void initBinder(WebDataBinder binder) {
        SimpleDateFormat dateFormat = new SimpleDateFormat("yyyy-MM-dd");
        dateFormat.setLenient(false);
        // 支持 “2017-06-28” 字符串转为 Date 对象
        binder.registerCustomEditor(Date.class, new CustomDateEditor(dateFormat, false));
    }

}
```

#### 2️⃣全局类型转换配置

```java
// SpringMVC 注解配置 ①
@Configuration
@EnableWebMvc
public class WebConfig implements WebMvcConfigurer {

    // 注册全局的数据转换器和格式化 ②
    @Override
    public void addFormatters(FormatterRegistry registry) {
        // ...
    }
}
```

① xml 配置 `<mvc:annotation-driven conversion-service="myConversionService"/>`

② interface `FormatterRegistry` extends `ConverterRegistry` 支持 field formatting、type conversion。



## Spring Type Conversion

> Spring Core 通用功能。[type conversion](https://docs.spring.io/spring-framework/docs/5.2.24.RELEASE/spring-framework-reference/core.html#core-convert) 。
> 
> `GenericConversionService` is the general-purpose implementation suitable for use in most environments. 

### 配置示例

```java
public StringToDate implements Converter<String, Date> {
	
	@Override
	public Date convert(String source) {
		if (StringUtils.isEmpty(source)) {
			return null;
		}
		try {
			DateFormat format = new SimpleDateFormat(DEFAULT_DATETIME_PATTERN);
			return format.parse(source);
		} catch (ParseException e) {
		}
	}
}
```

 

## 类型转换核心实现

### 1️⃣ SpringBoot 注册 ConversionService

> 为了方便 SpringMVC 配置， SpringBoot 提供类型转换 `WebConversionService`， 该类继承 GenericConversionService。

```java
/**
 * SpringBoot 为 MVC 环境提供 ConversionService
 * @see org.springframework.boot.autoconfigure.web.servlet.WebMvcAutoConfiguration.EnableWebMvcConfiguration
 */
@Bean
@Override
public FormattingConversionService mvcConversionService() {
	// 通过 spring.mvc.dateFormat 可以直接设置日期格式
	WebConversionService conversionService = new WebConversionService(this.mvcProperties.getDateFormat());
	// 注册用户自定义的 formatters、converters. 
	// 参考上述的 org.springframework.web.servlet.config.annotation.WebMvcConfigurer#addFormatters
	addFormatters(conversionService);
	return conversionService;
}
```

### 2️⃣类型转换流程

```java
/**
 * 根据配置优先级，尝试转为 requiredType 类型的数据
 * @see org.springframework.beans.TypeConverterDelegate#convertIfNecessary
 */
public <T> T convertIfNecessary(@Nullable String propertyName, @Nullable Object oldValue, @Nullable Object newValue, @Nullable Class<T> requiredType, @Nullable TypeDescriptor typeDescriptor) throws IllegalArgumentException {

	// Custom editor for this type?
	PropertyEditor editor = this.propertyEditorRegistry.findCustomEditor(requiredType, propertyName);

	// No custom editor but custom ConversionService specified?
	ConversionService conversionService = this.propertyEditorRegistry.getConversionService();
	if (editor == null && conversionService != null && newValue != null && typeDescriptor != null) {
		TypeDescriptor sourceTypeDesc = TypeDescriptor.forObject(newValue);
		if (conversionService.canConvert(sourceTypeDesc, typeDescriptor)) {
			try {
				return (T) conversionService.convert(newValue, sourceTypeDesc, typeDescriptor);
			}
			catch (ConversionFailedException ex) {
				// fallback to default conversion logic below
				conversionAttemptEx = ex;
			}
		}
	}
	// Try to apply some standard type conversion rules if appropriate.
	return (T) convertedValue;
}

```



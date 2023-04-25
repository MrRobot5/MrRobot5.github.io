---
layout: post
title:  "笔记 Jquery ajax 相关配置和请求处理"
date:   2023-04-25 11:10:16 +0800
categories: jekyll update
---

# 笔记 Jquery ajax 相关配置和请求处理

## 使用示例

```javascript
// 使用Jquery 发送 json 数据
$.ajax({
    url: "some.php",
    type: "POST",
    dataType:"json",
    contentType:"application/json",
    data: JSON.stringify({ name: "John", location: "Boston" }),
    success: function (msg) {
        alert( "Data Saved: " + msg );
    }
});
```

## contentType

```javascript
// 默认类型 from ajaxSettings
// 遵从业界规范，如果使用 curl --data，默认也是 Content-Type: application/x-www-form-urlencoded
contentType: "application/x-www-form-urlencoded; charset=UTF-8",
```

## data

- 数据（object）默认按照表单传参格式（key/value 键值对）来序列化数据。

- 如果后台接收 json 格式数据，需要调用 JSON.stringify() 处理为 string。

- object 如果不处理为string，会按照 object.toString() 来处理。发送的数据是：[object Object]

- Get 请求，参数会追加到URL。**Post 请求，数据通过请求体 (body) 发送到服务端。**

```java
// Convert data if not already a string
// processData 默认 true
// jQuery.param 处理的数据会调用 encodeURIComponent encoded
if ( s.data && s.processData && typeof s.data !== "string" ) {
    s.data = jQuery.param( s.data, s.traditional );
}

// 序列化结果： a=bc&d=e%2Cf
$.param({ a: "bc", d: "e,f" })
// 序列化结果： a%5B%5D=1&a%5B%5D=2， 也就是 a[]=1&a[]=2
$.param({ a: [1,2] })
```

## transpart

> `XMLHttpRequest` (XHR) objects are used to interact with servers. 
> 
> You can retrieve data from a URL without having to do a full page refresh. This enables a Web page to update just part of a page without disrupting what the user is doing.

```javascript
// 使用 jqXHR 包装真正的 xhr, 把xhr 的事件包装为一些事件和接口，方便开发
jQuery.ajaxSettings.xhr = function() {
    try {
        return new window.XMLHttpRequest();
    } catch ( e ) {}
};
```

## dataType converters

> Jquery 对于指定的 dataType, 会尝试进行反序列化的转换。
> 
> 支持的类型包括：html json xml script
> 
> 数据类型转换在 `function ajaxConvert` 完成。

```javascript
// Data converters. Http 请求返回的文本，可以根据 dataType 和支持，进行转换
// 配置格式约定：Keys separate source (or catchall "*") and destination types with a single space
converters: {

	// Convert anything to text
	"* text": String,

	// Text to html (true = no transformation)
	"text html": true,

	// Evaluate text as a json expression。 常用的 json ,就是这样处理的。🎈
	"text json": JSON.parse,

	// Parse text as xml
	"text xml": jQuery.parseXML,
	
	"text script": function( text ) {
		jQuery.globalEval( text );
		return text;
	}
},
```

## timeout

```javascript
// Timeout 配置，通过定时器实现
if ( s.async && s.timeout > 0 ) {
    // 发起请求前，添加一个定时器，到期发起取消操作
    timeoutTimer = window.setTimeout( function() {
        // jqXHR 作为包装类，真正的XHR 命名为 transport。包装类可以提供更加丰富的接口，流程可控。
        jqXHR.abort( "timeout" );
    }, s.timeout );
}

// 无论请求结果怎样，都会调用 done(), 会移除定时器
// Clear timeout if it exists
if ( timeoutTimer ) {
    window.clearTimeout( timeoutTimer );
}
```

## 其他-网络验证

> 关于Jquery 数据传递，浏览器数据传输的疑问，可以通过 Curl 发送请求，查看具体的HTTP 协议数据格式来确认。

```bash
# 描述: use the curl command with –data and –data-raw options to send text over a POST request:
$ website="https://webhook.site/5610141b-bd31-4940-9a83-1db44ff2283e"

# used the –trace-ascii option to trace the requests and capture the trace logs in the website-data.log and website-data-raw.log files.
$ curl --data "simple_body" --trace-ascii website-data.log "$website"
$ curl --data-raw "simple_body" --trace-ascii website-data-raw.log "$website"

# 结果：website-data-raw.log:0083: Content-Type: application/x-www-form-urlencoded
$ grep --max-count=1 Content-Type website-data-raw.log website-data.log
```

参考：[How to Post Raw Body Data With cURL | Baeldung](https://www.baeldung.com/curl-post-raw-body-data)

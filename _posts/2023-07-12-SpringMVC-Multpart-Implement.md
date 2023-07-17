---
layout: post
title:  "SpringMVC 文件上传相关源码梳理"
date:   2023-07-12 19:00:36 +0800
categories: 源码阅读
tags: SpringMVC Servlet SpringBoot
---

* content
{:toc}

记录 SpringMVC 文件上传相关源码梳理

# 示例代码

```java
@Controller
public class FileUploadController {

    @PostMapping("/form")
    public String handleFormUpload(@RequestParam("name") String name,
            @RequestParam("file") MultipartFile file) {

        if (!file.isEmpty()) {
            byte[] bytes = file.getBytes();
            // store the bytes somewhere
            return "redirect:uploadSuccess";
        }
        return "redirect:uploadFailure";
    }
}
```

# Commons FileUpload

[Form-based File Upload in HTML 定义](https://www.ietf.org/rfc/rfc1867.txt)，Commons FileUpload 是该定义的实现。

[Using FileUpload](https://commons.apache.org/proper/commons-fileupload/using.html)

# tomcat-embed-core

> SpringBoot 项目中引用了 `tomcat-embed-core` ，这个包内部打包了 Commons FileUpload。从 web 容器层提供了文件上传的支持。

```java
/**
 * 调用 Commons FileUpload， 实现 http 提交文件的解析
 * 对应上述using 教程的 The simplest case
 * @see org.apache.catalina.connector.Request#parseParts
 */
private void parseParts(boolean explicit) {

    // Create a new file upload handler
    DiskFileItemFactory factory = new DiskFileItemFactory();
    try {
        factory.setRepository(location.getCanonicalFile());
    } catch (IOException ioe) {
        parameters.setParseFailedReason(FailReason.IO_ERROR);
        partsParseException = ioe;
        return;
    }
    factory.setSizeThreshold(mce.getFileSizeThreshold());

    ServletFileUpload upload = new ServletFileUpload();
    upload.setFileItemFactory(factory);
    upload.setFileSizeMax(mce.getMaxFileSize());
    upload.setSizeMax(mce.getMaxRequestSize());

}
```

# SpringMVC 处理流程

## StandardServletMultipartResolver

> Auto-configuration for multi-part uploads.

```java
protected void doDispatch(HttpServletRequest request, HttpServletResponse response) throws Exception {
    boolean multipartRequestParsed = false;
    try {
        ModelAndView mv = null;
        Exception dispatchException = null;

        try {
            // 判断当前的请求是否为文件上传。如果是，当前的request 转为 multipart request。
            // 如果不是，返回入参的 request。
            processedRequest = checkMultipart(request);
            multipartRequestParsed = (processedRequest != request);
            // 处理当前的请求...
        }
    } finally {
        // Clean up any resources used by a multipart request.
        if (multipartRequestParsed) {
            // 简单来讲，就是 request.getParts().delete();
            cleanupMultipart(processedRequest);
        }
    }
}
```

# SpringBoot 配置

```yaml
spring:  
  servlet:
    multipart:
      # max-file-size specifies the maximum size permitted for uploaded files. The default is 1MB
      max-file-size: 32MB
      max-request-size: 32MB
```

## MultipartAutoConfiguration

> Auto-configuration for multi-part uploads.
> 
> @see org.springframework.boot.autoconfigure.web.servlet.MultipartAutoConfiguration

MultipartAutoConfiguration 负责注册 StandardServletMultipartResolver Bean。

DispatcherServlet 初始化过程中会尝试获取该 Bean。

```java
/**
 * DispatcherServlet 初始化 multipartResolver。如果能获取到bean，支持文件上传解析，否则不支持。
 * @see org.springframework.web.servlet.DispatcherServlet#initStrategies
 */
private void initMultipartResolver(ApplicationContext context) {
    try {
        this.multipartResolver = context.getBean(MULTIPART_RESOLVER_BEAN_NAME, MultipartResolver.class);
    }
}
```

```java
/**
 * Max file size
.* 如果不配置 max-file-size，默认为 1MB，来源于此
 * @see org.springframework.boot.autoconfigure.web.servlet.MultipartProperties
 */
private DataSize maxFileSize = DataSize.ofMegabytes(1);
```

## StringToDataSizeConverter

> 配置文件解析，字符串“32MB” 转为 DataSize 对象。

org.springframework.boot.convert.StringToDataSizeConverter

```java
/**
 * DataSize 格式定义。
 * ^ $匹配字符串的开头和结尾，严格匹配整个字符串。
 * ([+\\-]?\\d+) 匹配一个可选的正负号后跟着一或多个数字
 * ([a-zA-Z]{0,2}) 匹配零到两个字母（大小写不限）
 */
Pattern.compile("^([+\\-]?\\d+)([a-zA-Z]{0,2})$");
```

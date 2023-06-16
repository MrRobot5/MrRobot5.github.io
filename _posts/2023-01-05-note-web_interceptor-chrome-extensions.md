---
layout: post
title:  "web 请求拦截方案和 chrome extensions"
date:   2023-01-05 11:54:21 +0800
categories: 学习笔记
tags: chrome
---
* content
{:toc}

## 案例-浏览器请求增加自定义 Header

在项目开发过程中，需要给 web 请求统一添加 Header,  后端会根据是否有自定义Header 决定是否是超管权限。方便开发和线上调试。

通过使用 Chrome 插件，**可以给每个 web 请求添加自定义 Header**，并且不会影响正常工程代码。

插件名称：Modify-http-headers。 

```java
/**
 * 后端示意代码
 * 超管功能，登录PIN 替换，用于特殊场景的调试。 org.springframework.web.servlet.HandlerInterceptor
 */
@Slf4j
public class AuthInterceptor extends HandlerInterceptorAdapter {

    /**
     * 超管PIN header，仅用于调试
     */
    private static final String SUPER_PIN_HEADER = "super-pin";

    @Override
    public boolean preHandle(HttpServletRequest request, HttpServletResponse response, Object handler) throws Exception {
        String superPin = request.getHeader(SUPER_PIN_HEADER);
        // 如果Http 请求有自定义 Header， 并且当前用户属于超管， 可以进行登录用户替换。
        if (StringUtils.isNotBlank(superPin) && inWhiteList(getCurrentPin(request))) {
            AuthContext context = new AuthContext();
            context.setPin(superPin);
            setAuthContext(context);
        }
        return true;
    }
}
```

## web 请求拦截方案

- 代码中编写， Jquery/ axios 都支持拦截器。 
  
  > 可以根据不同的运行环境，决定是否添加自定义的Header。
  > 
  > 不建议这种方式，对代码有污染，还有安全隐患。

- Fiddler
  
  > 非常方便的Http 拦截代理工具。

- Chrome extensions
  
  > 浏览器插件实现功能注入和增强。借助 Chrome 提供的丰富API，可以实现各种想要的特性。

- Chrome Source Override 
  
  > 本地调试很方便 [使用Chrome开发者工具overrides实现不同环境本地调试](https://blog.csdn.net/weixin_43834227/article/details/109161756)

## Chrome extensions

> Extensions are software programs, built on web technologies (such as HTML, CSS, and JavaScript) that enable users to customize the Chrome browsing experience.
> 
> **enhance the browsing experience**✨

### ①插件开发相关

    插件开发教程 [Chrome Extension development basics - Chrome Developers](https://developer.chrome.com/docs/extensions/mv3/getstarted/development-basics/)

    API 能力总览 [Chrome Extension development overview - Chrome Developers](https://developer.chrome.com/docs/extensions/mv3/devguide/)

    官方案例 [Extensions - Chrome Developers](https://developer.chrome.com/docs/extensions/)

    ❤注意事项

- manifest.json 是必备文件，用来声明和定义插件。

- 根据插件的需求，Chrome 插件分为Content scripts、Service worker、The popup 形式。

- permission 声明非常重要。使用对应的API 能力，需要在manifest声明对应的权限。

- 快速打开插件管理 `chrome://extensions`

- 可以使用console 和 开发者工具调试插件问题

- 

    🧡插件推荐的工程结构

<img src="{{ "/images/structuring_chrome_extension.png" | prepend: site.baseurl }}" alt="structuring_chrome_extension" style="zoom:50%;" />

### ②chrome.webRequest

> Use the `chrome.webRequest` API to observe and analyze traffic and to intercept, block, or modify requests in-flight.
> 
> 上述案例拦截 web 请求，添加自定义 header 就是通过调用`chrome.webRequest` API 实现。
> 
> [chrome.webRequest - Chrome Developers](https://developer.chrome.com/docs/extensions/reference/webRequest/)

```javascript
// 上述案例使用的插件 Modify-http-headers， 核心实现。
chrome.webRequest.onBeforeSendHeaders.addListener(function(details){
    var headerInfo = JSON.parse(localStorage['salmonMHH']);
    for (var i = 0; i < headerInfo.length; i++) {
        details.requestHeaders.push({name: headerInfo[i].name, value: headerInfo[i].value});
    }
    return {requestHeaders: details.requestHeaders};
}, filter, ["blocking", "requestHeaders"]); "requestHeaders"]);
```



### ③The service worker（后台服务）

> The extension service worker handles and listens for browser events. 
> 
> There are many types of events, such as navigating to a new page, removing a bookmark, or closing a tab. It can use all the Chrome APIs, but it cannot interact directly with the content of web pages; 
> 
> that’s the job of content scripts.

上述案例的插件就是这种类型。通过监听 web 请求事件，来完成 Http 请求的修改。

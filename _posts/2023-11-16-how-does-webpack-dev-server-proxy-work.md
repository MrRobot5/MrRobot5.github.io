---
layout: post
title:  "Insight webpack-dev-server proxy 工作原理"
date:   2023-11-16 16:13:46 +0800
categories: 源码阅读
tags: 架构设计 nodeJs
---

* content
{:toc}


## 背景

在使用 vue 本地开发前后端功能时，发现配置的代理不能正确的请求到后端服务。

通过观察 nodeJs 日志，发现代理 path rewrite 的路径有问题。

借此阅读 webpack-dev-server 源码，了解其工作原理。

## devServer proxy 配置案例

前端 vue 工程的 vue.config.js 代理配置如下：

```javascript
module.exports = {
  devServer: {
    proxy: {
      // 转发到稳定的线上服务
      '/someApi': {
        target: "online.foo.com",
        changeOrigin: true,
        pathRewrite: {
          '^/someApi': ''
        }
      },
      // 转发到开发中的服务。
      // 由于 devServer 路由规则，导致前端发起的 /someApiExtend/something 请求，并没有转发到 development.foo.com。
      '/someApiExtend': {
        target: "development.foo.com",
        changeOrigin: true,
        pathRewrite: {
          '^/someApiExtend': ''
        }
      }
    }
  }
}
```

> /someApiExtend/something 请求被 '/someApi' 优先处理，Rewrite to 的请求解析为：Extend/something。 直接提示 404。❌

## webpack-dev-server

> Serves a webpack app. 提供开发环境服务
> 
> Updates the browser on changes. 热编译和部署

### ①相关文档

[webpack-dev-server](https://github.com/webpack/webpack-dev-server) 可用于快速开发应用程序。请查阅 [开发指南](https://webpack.docschina.org/guides/development/) 开始使用。

[devServer.proxy 文档](https://webpack.docschina.org/configuration/dev-server/#devserverproxy)

其中提到了使用到 http-proxy-middleware 软件包。

通过源码分析可以看到集成使用的方式

### ②实现原理

```javascript
/**
   * 根据 options 解析集成的组件，注册 express web应用中。
   * @returns {void}
   * @see 核心实现源码文件 lib\Server.js
   */
  setupMiddlewares() {
    /**
     * @type {Array<Middleware>} 需要的组件集合
     */
    let middlewares = [];

    // 简单case, 如果配置了压缩，则初始化并加入到组件集合。最终注册到 express。 express.use(compression())
    // compress is placed last and uses unshift so that it will be the first middleware used
    if (this.options.compress) {
      const compression = require("compression");
      middlewares.push({ name: "compression", middleware: compression() });
    }
    // 如上的 compress， 引入并初始化代理配置 createProxyMiddleware
    if (this.options.proxy) {
      const { createProxyMiddleware } = require("http-proxy-middleware");

      const getProxyMiddleware = (proxyConfig) => {
        // It is possible to use the `bypass` method without a `target` or `router`.
        // However, the proxy middleware has no use in this case, and will fail to instantiate.
        if (proxyConfig.target) {
          const context = proxyConfig.context || proxyConfig.path;

          return createProxyMiddleware(
            /** @type {string} */ (context),
            proxyConfig
          );
        }
      };

      /**
       * 遍历 devServer.proxy 配置，并初始化为 proxyMiddleware对象，添加到组件合集里。
       */
      /** @type {ProxyConfigArray} */
      (this.options.proxy).forEach((proxyConfigOrCallback) => {
        // 代理配置集合，
        let proxyConfig = typeof proxyConfigOrCallback === "function" ? proxyConfigOrCallback() : proxyConfigOrCallback;

        let proxyMiddleware = (getProxyMiddleware(proxyConfig));

        middlewares.push({
          name: "http-proxy-middleware",
          // 通过 handler 初始化配置，简单来说，就是调用 getProxyMiddleware(proxyConfig)
          middleware: handler,
        });
      });
    }

    // 把组件集合注册到 express web 应用中
    middlewares.forEach((middleware) => {
      /** @type {import("express").Application} */
      (this.app).use(middleware.middleware);
    });

  }
```

### ③ devServer.proxy 解析流程

1. 首先，判断是否启用 proxy， 并引入 `http-proxy-middleware` 组件

2. 然后，遍历 devServer.proxy 集合配置，生成对应的代理配置对象

3. 最后，把 proxy 配置对象（proxyMiddleware）注册到 `express` web 应用中

## http-proxy-middleware

> The one-liner node.js http-proxy middleware for connect, express, next.js

### ①使用示例

> 方便理解 webpack-dev-server 集成 http-proxy-middleware 软件包的过程

```javascript
const express = require('express');
const { createProxyMiddleware } = require('http-proxy-middleware');

const app = express();

app.use(
  '/api',
  createProxyMiddleware({
    target: 'http://www.example.org/secret',
    changeOrigin: true,
  }),
);
```

### ②path 匹配规则

1. '/' matches any path, all requests will be proxied.

2. '/api' matches paths starting with `/api` ✔ 遇到的疑问，此刻得以解答。

[Context matching 文档](https://www.npmjs.com/package/http-proxy-middleware?activeTab=readme#context-matching)

## 总结

1. webpack-dev-server 基于 express web 框架实现的一个便于开发环境的 Sever

2. devServer.proxy 功能是其中一个特性，通过 http-proxy-middleware 实现

3. proxy 配置path 的规则，参考 Context matching 即可。

4. webpack-dev-server 的代码结构和实现，对于架构设计具有很大的借鉴意义。👍



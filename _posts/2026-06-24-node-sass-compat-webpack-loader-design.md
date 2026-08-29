---
layout: post
title: "node-sass 兼容问题与 webpack loader 的巧妙设计"
date: 2026-06-24 18:11:00 +0800
categories: 实战问题
tags: Webpack Node.js
mermaid: true
---

* content
{:toc}

> 在维护一个老前端工程时，本地 `npm run dev` 突然无法启动。追根溯源，发现是 **node-sass@6.0.1** 在 Apple Silicon (M1/M2) 架构上报错。替换为 dart-sass 后，又因为代码中使用了已被废弃的 `/deep/` 深度选择器语法而编译失败。
>
> 目标很明确：❌ 不修改已有工程的源码和配置，通过 webpack loader 的巧妙编排，实现本地服务的无痛启动。
>
> 最终方案是：在 `sass-loader` 之后注入 `string-replace-loader`，将 `/deep/` 替换为 `::v-deep`，并借此机会深入理解 webpack loader 的设计哲学。

## 异常场景

### 工程配置

该工程是一个基于 Vue 2.x 的老项目，构建工具使用 webpack 4，样式处理器配置如下：

```javascript
// webpack.config.js 片段
{
  test: /\.scss$/,
  use: [
    'vue-style-loader',
    'css-loader',
    'sass-loader'  // 内部依赖 node-sass
  ]
}
```

```json
// package.json 片段
{
  "dependencies": {
    "node-sass": "^6.0.1"
  }
}
```

### 异常表现

在新的 MacBook Pro (M1 Pro, arm64) 上执行 `npm install` 时，`node-sass` 安装阶段直接报错：

```text
Error: Node Sass does not yet support your current environment: OS X Unsupported architecture (arm64)
```

🙉 错误信息非常直接：当前操作系统架构为 arm64，而 node-sass@6.0.1 的预编译二进制包仅支持 x64。这是一个**架构级别的硬兼容性问题**，无法通过简单的降级或升级 Node.js 版本解决。

## 场景复现

### ① node-sass 安装失败

node-sass 是一个 Node.js 到 libsass 的绑定库，libsass 使用 C++ 编写。发布时，node-sass 会针对特定平台（OS + 架构 + Node 版本）提供预编译的 `.node` 二进制文件。

```text
Downloading binary from https://github.com/sass/node-sass/releases/download/v6.0.1/
darwin-arm64-83_binding.node
Cannot download "https://github.com/sass/node-sass/releases/download/v6.0.1/darwin-arm64-83_binding.node"
```

❌ 查看 [node-sass release 页面](https://github.com/sass/node-sass/releases)，v6.0.1 的 release assets 中仅有 `darwin-x64` 包，没有 `darwin-arm64`。

### ② dart-sass 编译报错

既然 node-sass 不支持 arm64，自然的替代方案是使用 **dart-sass**（即 `sass` 包）。dart-sass 是 Sass 的官方实现，纯 JavaScript/ Dart 编译，没有原生依赖，跨平台支持极好。

```bash
npm uninstall node-sass
npm install sass --save-dev
```

然而项目启动后，编译阶段报错：

```text
SassError: expected selector.
/deep/ .some-class
^
```

❌ 原因是：工程源码中大量使用了 Vue 的 `/deep/` 深度选择器语法，而 **dart-sass 2.0+ 已完全废弃 `/deep/`，仅支持 `::v-deep`**。这导致大量的 `.scss` 文件无法通过编译。

## 问题分析

### node-sass 的架构绑定

node-sass 的核心问题在于其**强平台绑定**的设计。它依赖 libsass（C++ 库），必须通过 node-gyp 编译或在发布时提供预编译二进制文件。这种架构在平台迁移期（如 x86_64 → arm64）会暴露严重的兼容性缺陷：

```
node-sass → libsass (C++) → 平台特定二进制 → 强绑定 OS + CPU 架构 + Node ABI 版本
```

🎈 相比之下，dart-sass 是 Sass 官方推荐的实现，使用 Dart 编译为 JavaScript（或原生可执行文件），完全脱离平台二进制依赖，是未来趋势。node-sass 本身也已于 2020 年被官方标记为废弃（deprecated）。

### /deep/ 的废弃历程

`/deep/` 原本是 CSS Shadow DOM 规范中的 `>>>` 选择器的别名，Vue 在 scoped CSS 中借用它来实现样式穿透。但 CSS 工作组已废弃 `/deep/`，Sass 编译器随之跟进：

| 版本 | 行为 |
|------|------|
| libsass (node-sass) | 仍支持 `/deep/` 作为普通选择器 |
| dart-sass < 1.23 | 支持，但发出 deprecation warning |
| dart-sass ≥ 2.0 | ❌ 完全废弃，编译报错 |

🎈 问题的矛盾点在于：**源码是旧的，但构建工具必须升级**。修改所有源码中的 `/deep/` 为 `::v-deep` 虽然可行，但会引入大量无意义的 diff，且可能触发其他老浏览器兼容问题。最好的方案是在编译阶段做"兼容转换"。

## 解决方案

### ① 替换为 dart-sass

首先，卸载 node-sass，安装 dart-sass：

```bash
npm uninstall node-sass
npm install sass --save-dev
```

✔ 此时 `sass-loader` 会自动探测并使用 `sass` 包（dart-sass），无需修改 `webpack.config.js` 中的 loader 名称。

### ② string-replace-loader 配置

接下来，引入 `string-replace-loader`，在 sass 编译之前（从源码角度看，是 loader 链的右侧）将 `/deep/` 替换为 `::v-deep`：

```bash
npm install string-replace-loader --save-dev
```

```javascript
// webpack.config.js 修改后
{
  test: /\.scss$/,
  use: [
    'vue-style-loader',
    'css-loader',
    {
      loader: 'sass-loader',
      options: {
        // 可根据需要配置 additionalData 等
      }
    },
    {
      loader: 'string-replace-loader',
      options: {
        search: '/deep/',
        replace: '::v-deep',
        flags: 'g'  // 全局替换
      }
    }
  ]
}
```

🎈 关键点：webpack loader 的**执行顺序是从右到左，从下到上**。数组右侧的 loader 先执行，处理最原始的源码；处理后的结果向左传递。因此将 `string-replace-loader` 放在 `sass-loader` 的**右侧（即数组中的下方/后面）**，它会在 sass 编译之前先执行文本替换。

> 另一种等价的配置方式（使用 `enforce: 'post'` 或 webpack chain 的 `after`）：
> ```javascript
> // vue.config.js 中使用 webpack-chain
> config.module
>   .rule('scss')
>   .use('string-replace-loader')
>   .loader('string-replace-loader')
>   .after('sass-loader') // 确保在 sass-loader 之后执行（数组右侧）
>   .options({
>     search: '/deep/',
>     replace: '::v-deep',
>     flags: 'g'
>   });
> ```
> `after('sass-loader')` 会将 `string-replace-loader` 插入到 `sass-loader` 的后面（数组的右侧），符合从右到左的执行顺序。

### ③ loader 顺序验证

为了验证 loader 的调用顺序，可以通过以下方式确认：

```javascript
// 自定义一个 debug loader 验证执行顺序
const debugLoader = {
  loader: 'string-replace-loader',
  options: {
    search: '/deep/',
    replace: '::v-deep',
    flags: 'g'
  }
};

// 执行顺序：string-replace-loader → sass-loader → css-loader → vue-style-loader
// 即：先替换文本，再编译 sass，再处理 css，最后注入样式
```

✔ 验证通过后，工程可以正常启动，所有 `/deep/` 语法在编译阶段被静默替换，源码无需任何改动。

## 扩展：webpack loader 的设计思想

本次问题能够优雅解决，核心得益于 webpack loader 的精妙设计。下面从三个维度展开分析。

### ① 链式调用与从右到左执行

webpack loader 的配置是一个数组，但执行顺序并非直觉上的从左到右，而是**从右到左，从后往前**：

```
use: [A, B, C]
执行顺序：C → B → A
```

🎈 这种设计暗合了**函数组合（Function Composition）**的数学直觉。如果每个 loader 是一个函数 `f(resource)`，那么整个 loader 链等价于：

```javascript
const result = A(B(C(source)));
```

即最右侧的 loader 先接触原始资源，经过层层转换后，最左侧的 loader 输出最终结果给 webpack 的模块系统。这种设计使得：

- **源码预处理**（如替换、转译）放在右侧，先执行；
- **后处理**（如样式注入、资源打包）放在左侧，最后执行。

本案例中的 loader 执行顺序如下：

```mermaid
graph LR
    A[原始源码] --> B[string-replace-loader]
    B --> C[sass-loader]
    C --> D[css-loader]
    D --> E[vue-style-loader]
    E --> F[最终输出]

    style B fill:#e1f5fe,stroke:#01579b
    style C fill:#e1f5fe,stroke:#01579b
    style D fill:#e1f5fe,stroke:#01579b
    style E fill:#e1f5fe,stroke:#01579b
```

### ② 单一职责与管道模式

每个 loader 只负责一种转换，这是**单一职责原则（SRP）**的典型实践：

| Loader | 职责 |
|--------|------|
| `string-replace-loader` | 纯文本替换，不解析 AST |
| `sass-loader` | 将 Sass/SCSS 编译为 CSS |
| `css-loader` | 解析 CSS 中的 `@import` 和 `url()`，处理模块化 |
| `vue-style-loader` | 将 CSS 注入 DOM 的 `<style>` 标签 |

🎈 这种管道模式（Pipeline Pattern）的好处是：loader 之间**完全解耦**。`string-replace-loader` 不需要知道 Sass 语法，只需要按字符串规则替换；`sass-loader` 也不需要关心源码中是否包含 `/deep/`，它只负责编译标准的 SCSS。每个组件专注做好一件事，通过标准接口（字符串输入 → 字符串输出）串联起来。

### ③ loader 的本质：内容转换函数

从源码层面看，一个 loader 本质上是一个符合特定签名的 JavaScript 函数：

```javascript
/**
 * webpack loader 的标准接口
 * @see webpack/lib/NormalModuleLoaderContext.js
 * @param {string|Buffer} source 模块源码内容
 * @returns {string|Buffer} 转换后的内容
 */
module.exports = function(source) {
  // 对 source 进行任意转换
  const result = source.replace(//deep\//g, '::v-deep');
  return result;
};
```

🎈 这意味着 loader 拥有**极大的灵活性**：

- 它可以是无状态的纯函数（如 `string-replace-loader`）；
- 也可以是有状态的（通过 `this` 上下文访问 webpack 的 loader API）；
- 甚至可以是异步的（通过 `this.async()` 回调）。

webpack 只关心输入输出契约，不关心内部实现，这正是 loader 生态能够蓬勃发展的根本原因。

## 总结

- **node-sass 的 arm64 兼容问题**是原生绑定库的共性问题，dart-sass 作为纯 JS 实现是更现代的替代方案。
- **不修改源码**的前提下，通过 `string-replace-loader` 在编译阶段做语法兼容，是一种低侵入、可回滚的优雅方案。
- **webpack loader 从右到左的执行顺序**是函数组合思想的工程体现，理解这一点是正确配置 loader 链的关键。
- **单一职责 + 管道模式**使得 loader 生态高度解耦、可扩展，每个 loader 只需关注一种转换，通过编排解决复杂问题。
- 老工程的维护艺术往往不在于重写，而在于找到**基础设施层面的兼容层**，让旧代码在新环境中继续稳定运行。⭐

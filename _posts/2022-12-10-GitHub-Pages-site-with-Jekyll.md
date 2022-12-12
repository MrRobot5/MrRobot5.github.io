---

layout: post
title:  "笔记-Github Pages搭建个人主页"
date:   2022-12-10 00:35:46 +0800
categories: jekyll update

---

# 笔记-Github Pages搭建个人主页

> 一切要从 Testing your GitHub Pages site locally with Jekyll 说起。跟着官方教程认真学习一番。
> 
> 尝试不同的技术栈，并且可以让个人主页更加的定制化。

## 环境准备

> Jekyll is a Ruby Gem（Ruby 模块）。
> 
> 需要在本地调试验证，需要环境准备，否则直接跳过。

[Jekyll on Windows](https://jekyllrb.com/docs/installation/windows/) 先安装Ruby，再下载 Jekyll 模块。

- 一定要选择 Ruby+Devkit 版本。

- 安装Jekyll 命令 `gem install jekyll bundler`

## Jekyll HelloWorld

> Jekyll is a static site generator with built-in support for GitHub Pages.

    创建Jekyll 工程命令 `jekyll new --skip-bundle .` 类似于 vue init； django-admin startproject。会准备一个site 框架。

    其中，_posts 就是我们文章源文件的目录。服务运行时，会把markdown 文件转为 html 文件。

    最后，原始的Jekyll 工程需要做些修改，才能适用于github-pages。操作参考步骤9-10。[creating-a-github-pages-site-with-jekyll](https://docs.github.com/cn/pages/setting-up-a-github-pages-site-with-jekyll/creating-a-github-pages-site-with-jekyll)

```shell
# Run. 浏览器访问：http://localhost:4000
bundle install
bundle exec jekyll serve
```

    

## GitHub Pages repository

- 必须命名为 `<user>.github.io`

- 存储库必须是公共的。如果改为 private,  Github Pages 访问404。

- GitHub Pages 站点是使用 GitHub Actions 工作流生成和部署的。工作流是默认的，**不用做任何修改**。

- 可以通过查询 workflow run history 和日志来排查问题

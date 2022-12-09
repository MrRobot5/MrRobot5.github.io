---
layout: post
title:  "尝试 QUARKUS - elasticsearch-quickstart"
date:   2020-08-25 16:36:03 +0800
categories: jekyll update
---
## 尝试 QUARKUS - elasticsearch-quickstart

> QUARKUS 框架, 用于构建云原生的应用。大体类似Spring 的Java框架，又不同常规的Java 框架，提供Native 、Reactive特性。除了提供一揽子的应用开发解决方案，更大的突破在于编译后轻量应用、高性能应用，RedHat出品。
>
> elasticsearch-quickstart 功能点：使用表单添加元素，并且在列表中更新。 浏览器和服务器之间的所有信息都被格式化为JSON。 元素存储在Elasticsearch中。

### 工程搭建

文档非常详细，可操作性强。直接跟着[指导文档](https://quarkus.io/guides/elasticsearch)步骤，就可以完成Quarkus 应用的构建。

> **Tips:**
>
> 使用IDEA 启动Quarkus 应用，不像SpringBoot 之类的，有main 函数启动类。需要依靠Maven 命令，可以将命令配置为启动项，在IDEA 的Run/Debug Configurations，配置对应的Maven 快捷启动。
>
> *点击左上角"+"图标添加一个Maven配置如左边栏，在右边栏中的Command line中填入"compile quarkus:dev"，点击OK*

### 遇到的问题

1. 构建工程报错。[ERROR] No implementation for org.eclipse.aether.RepositorySystem was bound. while locating io.quarkus.maven.CreateProjectMojo。
	解决办法: `根据指导文档，升级Maven 3.6.2+`，使用IDE同理。如果是IDEA, 用新下载的Maven代替自带的。

2. 使用IDEA Download Sources报错。Unable to import maven project。
	解决办法：查看IDEA 运行日志， Help ==》 Show Log in Explorer 查看具体的报错日志。
	errors: No implementation for org.apache.maven.model.path.PathTranslator was bound. 原因是IDEA版本和新版本的Maven不兼容导致的，如果是要Download Maven Sources，可以暂时先替换为原来的自带Maven，保证Sources 成功下载。`呃，Quarkus 对版本的要求还是比较苛刻`，这点在Java框架不常见。
	
3.  [Debug 方法](https://blog.csdn.net/chen978616649/article/details/104027358)。需要使用Remote 连接应用，达到调试目的。

  


### 总结

* Quarkus 框架目前的生态非常丰富，`快速指导文档包含了各种中间件的示例`。常用的中间件的集成和使用都可以从这里查到。

* Quarkus 框架`推荐JDK 11+和 GraalVM`，JDK8 后续会废弃和禁止。

* 直观的感受是和现在用的框架开发模式很像，学习理解和转换的成本很低。`开发使用的API都是EJB 规范定义的`。

* Quarkus 框架启动非常快，dev模式下，`修改完即生效，开发效率高`。不用依赖JRebel 啦。

* Quarkus `支持native模式编译`，可以直接生成docker image，没有尝试。参考：src/main/docker/Dockerfile.native

* 现有的Docker技术，从另外一个层次完成了跨平台的目的。JVM的目的在Cloud 技术栈里，已经没有那么大的作用，如果提供native 的模式，确实可以`对Java应用达到各方面的“轻量化”`。

  

### 参考文档

1. [Maven:Unable to import maven project: See logs for details](https://www.cnblogs.com/wpbxin/p/11771002.html)
2. [框架介绍，详细的搭建指导【中文】](https://juejin.im/post/6854573209434456072)
3. [Quarkus 上手体验](https://zhuanlan.zhihu.com/p/144175495)


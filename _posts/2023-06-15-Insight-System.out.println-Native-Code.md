---
layout: post
title:  "Insight System"
date:   2023-06-15 20:58:03 +0800
categories: jekyll update
---

# Insight System.out.println() 控制台打印实现

> 最近看到一个开源项目/公开课 [CS5411/4411 at Cornell](https://www.cs.cornell.edu/courses/cs4411/2022fa/schedule/)，关于如何实现一个操作系统。突然对 Java 中native 调用比较感兴趣。
> 
> 特意选择 System.out.println() 与操作系统的交互来了解OS System Call 实现过程。

## System.out 初始化

> System 使用 PrintStream 打印信息，Java 中的文件流使用的包装者模式，真正调用输出流是 FileDescriptor.out。

```java
// System.out 初始化，包括 stdIn, stdOut, stdErr
FileOutputStream fdOut = new FileOutputStream(FileDescriptor.out);
setOut0(newPrintStream(fdOut, props.getProperty("sun.stdout.encoding")));
```

更多详细解读 [System源码浅析- initializeSystemClass(initProperties)](https://blog.csdn.net/DramaLifes/article/details/124756610)

## FileDescriptor out

> FileDescriptor 是 Java I/O库中的一种抽象，用于表示打开的文件、套接字或其他数据源句柄，不依赖具体的操作系统特性🎯。以下会分析 Windows 系统的实现。

```java
/**
 * 标准输出流对象(In Java)/句柄(In Windows), 对应的是控制台。
 */
public static final FileDescriptor out = standardStream(1);

// set 是 native 方法，依赖具体的操作系统实现（native code）
private static native long set(int d);

private static FileDescriptor standardStream(int fd) {
    FileDescriptor desc = new FileDescriptor();
    desc.handle = set(fd);
    return desc;
}
```

## Java Native 桥接操作系统

> 这里查询的 OpenJdk 基于 Windows 操作系统的实现源码。[src 下载地址](https://hg.openjdk.org/jdk8/jdk8/jdk/) 🎯。
> 
> 直接调用 Windows API 获取控制台输入缓冲区的句柄

```c
/*
 * 用途：Java_java_io_FileDescriptor_set 赋值标准设备 stdIn, stdOut, stdErr
 * @see java/io/io_util_md.h
 */
#define SET_HANDLE(fd) \
if (fd == 0) { \
    return (jlong)GetStdHandle(STD_INPUT_HANDLE); \
} else if (fd == 1) { \
    // 标准输出设备， GetStdHandle是一个Windows API函数。
    return (jlong)GetStdHandle(STD_OUTPUT_HANDLE); \
} else if (fd == 2) { \
    return (jlong)GetStdHandle(STD_ERROR_HANDLE); \
} else { \
    return (jlong)-1; \
} \
```

## GetStdHandle 函数

> GetStdHandle 函数提供了一种机制，用于检索与进程关联的标准输入 (STDIN)、标准输出 (STDOUT) 和标准错误 (STDERR) 句柄。 
> 
> GetStdHandle 返回的句柄可供需要在控制台中进行读取或写入的应用程序使用。
> 
> 在控制台创建过程中，系统将创建这些句柄。如上述 native 获取方式。🧲

[GetStdHandle 函数 - Windows Console | Microsoft Learn](https://learn.microsoft.com/zh-cn/windows/console/getstdhandle) 文档

| 值                                   | 含义                                 |
| ----------------------------------- | ---------------------------------- |
| **STD_INPUT_HANDLE**`((DWORD)-10)`  | 标准输入设备。 最初，这是输入缓冲区 `CONIN$` 的控制台。  |
| **STD_OUTPUT_HANDLE**`((DWORD)-11)` | 标准输出设备。 最初，这是活动控制台屏幕缓冲区 `CONOUT$`。 |
| **STD_ERROR_HANDLE**`((DWORD)-12)`  | 标准错误设备。 最初，这是活动控制台屏幕缓冲区 `CONOUT$`。 |

## Windows API demo

```c
#include<windows.h>

/**
 * 不用stdio.h能在控制台输出信息吗？
 * 在Windows下，可以直接使用Windows API来完成. 使用 GetStdHandle WriteConsole 函数来在控制台输出信息
 * https://www.cnblogs.com/jisuanjizhishizatan/p/16149561.html
 */
int main(){
    const char *str="Use <windows.h> to output in C++.\n";
    HANDLE handle=GetStdHandle(STD_OUTPUT_HANDLE);
    WriteConsole(handle,str,strlen(str),NULL,NULL);
    return 0;
}
```

注意事项：

- Window 环境编译C/C++ 可以使用 GCC 编译器。一般是安装 MinGW 插件。由于安装过 Ruby, 使用的是附带的 `C:\Programs\Ruby27-x64\msys64\mingw64\bin`。

- 编译上述的代码 `gcc console.c -o console.exe`

- 使用 cmd 命令行工具，使用 git bash 打印会有问题，非 Windows 原生组件获取不到控制台句柄。❌

## 总结

- JVM 的存在，方便了跨平台开发，另外以方便也屏蔽了操作系统底层的一些对接。

- 从 Java SDK 到 native 实现的探索，举一反三，其他特性的 native 实现按图索骥。🙉

- 对于基础 API 的原理探索，在使用和调优上会更有目的和方向。

- 越接近底层，越接近真相。

# 笔记 - Java 值传递以及相关的知识点

## Java 值传递典型例子

```java
/**
 * str 变量持有的是 String 对象的内存地址。传递到函数中时，形参str2 是str 值拷贝（内存地址）。
 * 由于String 类的特殊性，重新赋值就相当于给str2 赋值新的内存地址。和原有的str 没有关系。
 * 
 * 运行结果：“字符串修改后:zhangsan”
 */
public class TestStr {
    public static void main(String[] args) {
        String str = "zhangsan";
        changeStr(str);
        System.out.println("字符串修改后:"+str);
    }

    /**
     * @param str2 函数的形参是被调用时所传实参的副本。引用类型，对应的value 是地址副本
     */
    private static void changeStr(String str2) {
        // 相当于 str2 = new String("lisi");
        str2 = "lisi";
    }
}
```

## 相关名词和概念

### 值传递(pass by value) 

> 值传递(pass by value)：在调用函数时，将实际参数复制一份传递到函数中，这样在函数中对参数进行修改，就不会影响到原来的实际参数；
>
> When a parameter is pass-by-value, the caller and the callee method operate on two different variables which are copies of each other. **Any changes to one variable don't modify the other.**
>
> It means that while calling a method, **parameters passed to the callee method will be clones of original parameters.** Any modification done in callee method will have no effect on the original parameters in caller method.

### 引用传递(pass by reference)

> 引用传递(pass by reference): 在调用函数时，将实际参数的地址直接传递到函数中。这样在函数中对参数进行的修改，就会影响到实际参数；
>
> When a parameter is pass-by-reference, **the caller and the callee operate on the same object.**
>
> It means that when a variable is pass-by-reference, **the unique identifier of the object is sent to the method.** Any changes to the parameter’s instance members will result in that change being made to the original value.

### values and references

在 Java 中，原始类型变量（ Primitive variables ）存储的就是实际的值，非原始变量存储的引用变量（ reference variables ）（指向它们所引用的对象的地址 the addresses of the objects）。

值和引用都存储在堆栈内存中 （ Both values and references are stored in the stack memory ）。



## 其他编程语言的例子

### JavaScript 值传递

> ECMAScript中所有函数的参数都是按值传递的。- 《JavaScript高级程序设计》

```javascript
var name = 'zhangsan';
function setName (n) {
    n = 'lisi';
    console.log(n);     //output: lisi
}
setName(name);
console.log(name);      //output: zhangsan
```

### C++ 引用传递

```c++
#include<iostream>
using namespace std;
void change(int &i) {
	i = i+2;
}

int main() {
	int i = 0;
	cout << "Value of i before change is :" << i << endl;
	change(i);
	cout << "Value of i now is :" << i << endl;
}
```

使用方式

```shell
$ g++ change.cpp -o change
$ ./change
```



## 参考

- [JAVA：值传递和引用传递_SummerOfFoam的博客-CSDN博客](https://blog.csdn.net/SummerOfFoam/article/details/109570841)
- [JS中的值传递 - 知乎](https://zhuanlan.zhihu.com/p/29291240)
- [Pass-By-Value as a Parameter Passing Mechanism in Java | Baeldung](https://www.baeldung.com/java-pass-by-value-or-pass-by-reference)


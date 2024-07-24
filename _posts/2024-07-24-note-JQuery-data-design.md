---
layout: post
title:  "JQuery-data-设计分析"
date:   2024-07-24 15:08:37 +0800
categories: 学习笔记
tags: JQuery
---

* content
{:toc}

> JQuery 的data 功能可以动态的存取数据，不用频繁的操作DOM。
> 
> 在事件处理程序之间传递数据非常有用。

## JQuery Data

> JQuery 定义一个 `Data` 构造函数。默认实例化两个 `Data` 对象（dataUser、dataPriv）供功能使用。🎈
> 
> 数据的存取实现，就是通过 Data 来定义和实现。

### ①get 方法

```javascript
function Data() {
    // 每次实例化 Data 对象时，都会生成一个唯一的 expando 属性值。
    this.expando = jQuery.expando + Data.uid++;
}

// 通过设置原型对象，定义 Data 实例共享的方法和属性。
Data.prototype = {

    /**
     * 数据获取
     * @param {*} owner 对应到 data功能，就是 Dom 对象
     * @param {*} key 可以为空, 如果不指定，获取 owner 绑定的所有数据。
     * @returns 
     */
    get: function( owner, key ) {
        return key === undefined ?
            // 类似于 owner[ this.expando ]
            this.cache( owner ) :
            // 如果存在 expando 属性值，则返回 owner[ this.expando ][ camelCaseKey ] 的值
            owner[ this.expando ] && owner[ this.expando ][ jQuery.camelCase( key ) ];
    }
}
```

## ② data 方法

> 抽象定义和初始化 Data 对象后，使用dataUser 操作Dom 存取数据变的很方便。
> 
> 同时兼容了HTML5 data-* 特性，读取数据后类型转换并同步到 dataUser 中。

```javascript
/**
 * 扩展 jQuery 实例方法，扩展后的方法可以在所有 jQuery 对象实例上调用。例如：$('p').data('someData');
 * 对比：jQuery.extend。用于扩展 jQuery 构造函数的静态方法或属性。$.data(elem, 'someData')
 */
jQuery.fn.extend( {

    /**
     * 从dom 对象存取数据。value 有值是set 操作，无值是get 操作
     * @param {*} key 数据key
     * @param {*} value 允许为空
     * @returns 
     */
    data: function( key, value ) {
        var elem = this[ 0 ];

        return access( this, function( value ) {
            var data;

            // get 操作
            if ( elem && value === undefined ) {
                data = dataUser.get( elem, key );
                if ( data !== undefined ) {
                    return data;
                }

                // 兼容 HTML5 custom data-* attrs
                // 如果获取到 data-* 字符串，会尝试进行类型转换，或者json 反序列化
                data = dataAttr( elem, key );
                if ( data !== undefined ) {
                    return data;
                }

                // We tried really hard, but the data doesn't exist.
                return;
            }

            // set 操作
            this.each( function() {
                dataUser.set( this, key, value );
            } );
        }, null, value, arguments.length > 1, null, true );
    }
})
```

### ③ 字符串类型转换

> 类型转换方便了取值后的操作，同时 JavaScript 类型的隐含转换也需要注意。🎈

```javascript
// 用于匹配一个完整的 JSON 对象或数组。
// 1. 以 `{` 开头，以 `}` 结尾，中间可以包含任意字符。
// 2. 以 `[` 开头，以 `]` 结尾，中间可以包含任意字符。
var rbrace = /^(?:\{[\w\W]*\}|\[[\w\W]*\])$/;

/**
 * 尝试对字符串类型转换
 * @param {*} data HTML5 data-* attribute
 * @returns 
 */
function getData(data) {
    if (data === "true") {
        return true;
    }

    if (data === "false") {
        return false;
    }

    if (data === "null") {
        return null;
    }

    // 检查 data 是否是一个数字的字符串的技巧
    // 如果是数字，则返回true。 如果非数字， +data 结果为 NaN。
    if (data === +data + "") {
        // 需要特别注意，+data 将空字符串 "" 转换为数字 0。
        return +data;
    }

    if (rbrace.test(data)) {
        return JSON.parse(data);
    }

    return data;
}
```

## JQuery expando 设计

> `JQuery.expando` 是 jQuery 用来在 DOM 元素或其他对象上存储数据的一个独特属性。

## 简化示例

```java
var elem = document.getElementById("example");

// jQuery 内部会做类似的操作
elem["jQuery123456789"] = {
    "myData": "someValue"
};

// 获取数据
var data = elem["jQuery123456789"]["myData"];
console.log(data); // 输出 "someValue"
```

### 设计分析

#### 数据隔离/避免冲突

`JQuery.expando` 是一个唯一的字符串（通常是由 jQuery 生成的一个带有前缀和随机数的字符串），确保它在所有元素和对象上都是唯一的。这可以避免与其他属性或数据键发生冲突。

```javascript
// Unique for each copy of jQuery on the page
expando: "jQuery" + ( version + Math.random() ).replace( /\D/g, "" ),
```

#### 性能优化

直接在元素或对象上存储数据（而不是使用全局数据存储）可以提高性能。访问和修改元素上的属性通常比通过全局数据存储更快，因为它减少了查找和管理的开销。
---
layout: post
title:  "算法 Spring中的算法-占位符查找"
date:   2022-05-18 15:18:13 +0800
categories: jekyll update
---
## 算法 Spring中的算法-占位符查找

```java
/**
- 查找占位符匹配的后缀索引。
- 因为Spring支持嵌套的占位符表示，所以配对的查找是这个方法核心要解决的
- 逻辑：遍历字符串buf，匹配遇到的占位符前缀和后缀，如果是配套的后缀，则返回索引。
- 因为有嵌套占位符的情况，需要一个临时的变量记录内嵌占位符的出现次数，通过成对匹配的计算（出现前缀加1，出现后缀减1），防止错误返回内嵌占位符的后缀索引。
- @param buf 配置字符串，比如：${foo:${defaultFoo}}
- @param startIndex 占位符在 buf中的index，初始值 = buf.indexOf("${");
*/
private int findPlaceholderEndIndex(CharSequence buf, int startIndex) {
    int index = startIndex + this.placeholderPrefix.length();
    // 嵌套的占位符出现次数标识变量，出现前缀加1，出现后缀减1。
    int withinNestedPlaceholder = 0;
    while (index < buf.length()) {
        // 检测后缀，两种情况
        if (StringUtils.substringMatch(buf, index, this.placeholderSuffix)) {
            // 1. 该后缀属于内嵌占位符，继续遍历
            if (withinNestedPlaceholder > 0) {
                withinNestedPlaceholder--;
                index = index + this.placeholderSuffix.length();
            }
            // 2. 目标占位符的后缀
            else {
                return index;
            }
        }
        // 检测前缀，证明遇到的了内嵌占位符
        else if (StringUtils.substringMatch(buf, index, this.simplePrefix)) {
            withinNestedPlaceholder++;
            index = index + this.simplePrefix.length();
        }
        else {
            index++;
        }
    }
    return -1;
}
```

```java
/**
 * Test whether the given string matches the given substring
 * at the given index.
 * 思路：以被查询的字符串，循环匹配每个字符，遇到不符合直接返回不匹配。
 * 匹配查找和数据库的join 查询，小表驱动大表有异曲同工之处
 * @param str the original string (or StringBuilder)
 * @param index the index in the original string to start matching against
 * @param substring the substring to match at the given index
 */
public static boolean substringMatch(CharSequence str, int index, CharSequence substring) {
    // 遍历 toFind 字符串
    for (int j = 0; j < substring.length(); j++) {
        int i = index + j;
        // 如果原字符串不包含（长度不够）或者字符不匹配，立即失败
        if (i >= str.length() || str.charAt(i) != substring.charAt(j)) {
            return false;
        }
    }
    return true;
}
```

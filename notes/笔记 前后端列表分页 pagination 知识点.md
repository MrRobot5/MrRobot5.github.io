# 笔记 前后端列表分页 pagination 知识点

> 分页是 web application 开发最常见的功能。在使用不同的框架和工具过程中，发现初始行/页的定义不同，特意整理记录。

## 数据库分页

### ①MySQL LIMIT

语法：[LIMIT {[*offset*,] *row_count*}]

`LIMIT row_count` is equivalent to `LIMIT 0, row_count`.

**The offset of the initial row is 0 (not 1)**

参考：[MySQL :: MySQL 5.7 Reference Manual :: 13.2.9 SELECT Statement](https://dev.mysql.com/doc/refman/5.7/en/select.html)

## 后端分页

> 后端分页，简单讲，就是数据库的分页。 对于mysql 来讲，就是上述 offset row_count 的计算过程。

### ①pagehelper

```java
/**
 * 计算起止行号  offset
 * @see com.github.pagehelper.Page#calculateStartAndEndRow
 */
private void calculateStartAndEndRow() {
    // pageNum 页码，从1开始。 pageNum < 1 , 忽略计算。
    this.startRow = this.pageNum > 0 ? (this.pageNum - 1) * this.pageSize : 0;
    this.endRow = this.startRow + this.pageSize * (this.pageNum > 0 ? 1 : 0);
}
```

```java
/**
 * 计算总页数 pages/ pageCount。 
 */
public void setTotal(long total) {
    if (pageSize > 0) {
        pages = (int) (total / pageSize + ((total % pageSize == 0) ? 0 : 1));
    } else {
        pages = 0;
    }
}
```

SQL 拼接实现： com.github.pagehelper.dialect.helper.MySqlDialect

### ②spring-data-jdbc

关键类：

**org.springframework.data.domain.Pageable**

org.springframework.data.web.PageableDefault

```java
/**
 * offset 计算，不同于pagehelper， page 页码从0 开始。 default is 0
 * @see org.springframework.data.domain.AbstractPageRequest#getOffset
 */
public long getOffset() {
    return (long)this.page * (long)this.size;
}

/*
 * 使用 Math.ceil 实现。
 * @see org.springframework.data.domain.Page#getTotalPages()
 */
@Override
public int getTotalPages() {
    return getSize() == 0 ? 1 : (int) Math.ceil((double) total / (double) getSize());
}
```

```java
/**
 * offset 计算，不同于pagehelper， page 页码从0 开始。
 * @see org.springframework.data.jdbc.core.convert.SqlGenerator#applyPagination
 */
private SelectBuilder.SelectOrdered applyPagination(Pageable pageable, SelectBuilder.SelectOrdered select) {
    // 在spring-data-relation, Limit 抽象为 SelectLimitOffset 
    SelectBuilder.SelectLimitOffset limitable = (SelectBuilder.SelectLimitOffset) select;
    // To read the first 20 rows from start use limitOffset(20, 0). to read the next 20 use limitOffset(20, 20).
    SelectBuilder.SelectLimitOffset limitResult = limitable.limitOffset(pageable.getPageSize(), pageable.getOffset());

    return (SelectBuilder.SelectOrdered) limitResult;
}
```

spring-data-commons 提供 mvc 层的分页参数处理器

```java
/**
 * Annotation to set defaults when injecting a {@link org.springframework.data.domain.Pageable} into a controller method. 
 *
 * @see org.springframework.data.web.PageableDefault
 */
@Documented
@Retention(RetentionPolicy.RUNTIME)
@Target(ElementType.PARAMETER)
public @interface PageableDefault {

    /**
     * The default-size the injected {@link org.springframework.data.domain.Pageable} should get if no corresponding
     * parameter defined in request (default is 10).
     */
    int size() default 10;

    /**
     * The default-pagenumber the injected {@link org.springframework.data.domain.Pageable} should get if no corresponding
     * parameter defined in request (default is 0).
     */
    int page() default 0;
}
```

MVC 参数处理器： org.springframework.data.web.PageableHandlerMethodArgumentResolver

## 前端分页

### ①thymeleaf - 模板引擎

> **Thymeleaf** is a modern server-side Java template engine for both web and standalone environments.

```html
<!-- spring-data-examples\web\example\src\main\resources\templates\users.html-->
<nav>
  <!-- class样式 bootstrap 默认的分页用法-->
  <ul class="pagination" th:with="total = ${users.totalPages}">
    <li th:if="${users.hasPrevious()}">
      <a th:href="@{/users(page=${users.previousPageable().pageNumber},size=${users.size})}" aria-label="Previous">
        <span aria-hidden="true">«</span>
      </a>
    </li>
    <!-- spring-data-examples 分页计算从0 开始， /users?page=0&size=10 -->
    <!-- 生成页码列表 ①②③④ -->
    <li th:each="page : ${#numbers.sequence(0, total - 1)}"><a th:href="@{/users(page=${page},size=${users.size})}" th:text="${page + 1}">1</a></li>
    <li th:if="${users.hasNext()}">
      <a th:href="@{/users(page=${users.nextPageable().pageNumber},size=${users.size})}" aria-label="Next">
        <span aria-hidden="true">»</span>
      </a>
    </li>
  </ul>
</nav>
```

### ②element-ui 前端框架

```javascript
// from node_modules\element-ui\packages\pagination\src\pagination.js
// page-count 总页数，total 和 page-count 设置任意一个就可以达到显示页码的功能；
computed: {
  internalPageCount() {
    if (typeof this.total === 'number') {
      // 页数计算使用 Math.ceil
      return Math.max(1, Math.ceil(this.total / this.internalPageSize));
    } else if (typeof this.pageCount === 'number') {
      return Math.max(1, this.pageCount);
    }
    return null;
  }
},

/**
 * 起始页计算。 page 页码从1 开始。
 */
getValidCurrentPage(value) {
  value = parseInt(value, 10);

  const havePageCount = typeof this.internalPageCount === 'number';

  let resetValue;
  if (!havePageCount) {
    if (isNaN(value) || value < 1) resetValue = 1;
  } else {
    // 强制赋值起始值 1
    if (value < 1) {
      resetValue = 1;
    } else if (value > this.internalPageCount) {
      // 数据越界，强制拉回到PageCount
      resetValue = this.internalPageCount;
    }
  }

  if (resetValue === undefined && isNaN(value)) {
    resetValue = 1;
  } else if (resetValue === 0) {
    resetValue = 1;
  }

  return resetValue === undefined ? value : resetValue;
},
```

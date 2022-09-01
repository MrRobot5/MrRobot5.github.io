# 漫游 Redis *SORT/GET* combination

## 缘起

阅读Retwis-J（Redis版本的Twitter ）设计文档过程中，对于Redis join 方案的实现比较感兴趣，因此记录下SORT/GET 的神奇用法。以备不时之需。

## Retwis-J 设计方案

> A common problem with any store is dealing efficiently with normalized data. 
>
> A simple approach would be simply iterate through the list and load each post one by one but clearly this is not efficient as it means a lot of (slow) IO activity between the application and the database.
>
> The best solution in such cases it to use the *SORT/GET* combination which allows data to be loaded based on its key - more information [here](http://redis.io/commands/sort). SORT/GET can be seen as the equivalent of RDBMS *join*. 

## SORT/GET combination 使用说明

在某些情况下，获取实际对象而不是它们的ID(object_1、object_2和object_3)更有用。

可以使用以下命令，根据列表中的元素获取外部数据：`SORT mylist BY weight_* GET object_*`

获取外部hash 字段数据的命令：`SORT mylist BY weight_*->fieldname GET object_*->fieldname`。通过`->`来标识hash key 和hash 字段。

**命令例子**

```shell
redis> lpush timeline 1 2 3
redis> lrange timeline 0 -1
1) "3"
2) "2"
3) "1"

redis> set post_1 10
redis> set post_2 20
redis> set post_3 30
redis> sort a get o_*
1) "10"
2) "20"
3) "30"

redis> set foo_1 100
redis> set foo_2 200
redis> set foo_3 300
redis> sort timeline get post_* get foo_*
1) "10"
2) "100"
3) "20"
4) "200"
5) "30"
6) "300"
```

## Retwis-J join示例

> Method `convertPidsToPosts` shows how these classes can be used load the posts by executing a *join* over a hash.

Spring Data provides support for the *SORT/GET* pattern through its `sort` method and the `SortQuery` and `BulkMapper` interface for querying and mapping the bulk result back to an object. 

```java
// spring-data-redis 提供的StringRedisTemplate 支持上述sort 的combination 操作
// String pid = "pid:*->";
SortQuery<String> query = SortQueryBuilder.sort(key).noSort().get(pidKey).get(pid + uid).get(pid + content).get(pid + replyPid).get(pid + replyUid).get(pid + time).limit(range.begin, range.end).build();

```

```java
// 查询结果处理
BulkMapper<WebPost, String> hm = new BulkMapper<WebPost, String>() {
	@Override
	public WebPost mapBulk(List<String> bulk) {
		Map<String, String> map = new LinkedHashMap<String, String>();
		Iterator<String> iterator = bulk.iterator();
		// 对应上述SORT/GET 命令的结果集，通过遍历得到对应的结果
		String pid = iterator.next();
		map.put(uid, iterator.next());
		map.put(content, iterator.next());
		map.put(replyPid, iterator.next());
		map.put(replyUid, iterator.next());
		map.put(time, iterator.next());

		return convertPost(pid, map);
	}
};
List<WebPost> sort = template.sort(query, hm);

```



## 参考

[Spring Data Redis - Retwis-J](https://docs.spring.io/spring-data/data-keyvalue/examples/retwisj/current/#retwisj:design)

[SORT key](https://redis.io/commands/sort)

[Redis sort命令详解](https://cloud.tencent.com/developer/article/1491232)

[Tutorial: Design and implementation of a simple Twitter clone using PHP and the Redis key-value store](https://redis.io/topics/twitter-clone)


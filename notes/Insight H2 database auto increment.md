# Insight H2 database auto increment

## 起因

最近排查线上问题发现业务 Table 自增id 不连续，进一步发现是事务回滚造成。

```sql
-- 上述问题示例。 这样的情况就导致 main_table 自增id 并不连续/出现空挡。
START TRANSACTION;
-- 执行成功，自增id 已分配
INSERT INTO main_table VALUES (?, ?, ?);
-- 执行失败，事务 rollback
INSERT INTO sub_table VALUES (?, ?, ?);
```

那么，自增id 在数据库中是什么样的机制？可以从 H2 数据库实现方案获得启发。



## auto_increment Example

```sql
-- h2 auto_increment 建表语句
create table test(id bigint auto_increment, name varchar(255));
insert into test(name) values('hello');
insert into test(name) values('world');
select * from test;
```

通过打开 H2 数据库文件，可以看到 test 建表语句是**按照H2 dalect 翻译的**。可以看到H2 数据库的**auto_increment 是通过 SEQUENC 实现的**。

```java
CREATE CACHED TABLE PUBLIC.TEST(
 ID BIGINT DEFAULT (NEXT VALUE FOR PUBLIC.SYSTEM_SEQUENCE_620D39CD) NOT NULL NULL_TO_DEFAULT SEQUENCE PUBLIC.SYSTEM_SEQUENCE_620D39CD,
 NAME VARCHAR(255)
)
```



## SEQUENCE Example

官方文档 [create_sequence](https://h2database.com/html/commands.html#create_sequence) ✨

```sql
-- Sequence can produce only integer values.
CREATE SEQUENCE SEQ_ID;
CREATE SEQUENCE SEQ2 AS INTEGER START WITH 10;
```

**Used values are never re-used, even when the transaction is rolled back.**



## Code Insight

### ①相关的类

org.h2.command.dml.Insert

org.h2.expression.SequenceValue

org.h2.schema.Sequence



### ②主要实现原理

creat table 实例化过程

```java
// @see org.h2.command.ddl.CreateTable#update
for (Column c :data.columns) {
    // 如果列定义为 auto_increment， 需要进行dialet 翻译。
	if (c.isAutoIncrement()) {
		int objId = getObjectId();
        // 
		c.convertAutoIncrementToSequence(session, getSchema(), objId, data.temporary);
	}
}

```

```java
/**
 * Convert the auto-increment flag to a sequence that is linked with this
 * table.
 *
 * @see org.h2.table.Column#convertAutoIncrementToSequence
 */
public void convertAutoIncrementToSequence(Session session, Schema schema, int id, boolean temporary) {
	// 生成唯一的 sequenceName
	while (true) {
		ValueUuid uuid = ValueUuid.getNewRandom();
		String s = uuid.getString();
		s = s.replace('-', '_').toUpperCase();
		sequenceName = "SYSTEM_SEQUENCE_" + s;
		if (schema.findSequence(sequenceName) == null) {
			break;
		}
	}
	// Sequence 实例化，实现自增生成唯一数据
	Sequence seq = new Sequence(schema, id, sequenceName, start, increment);
	if (temporary) {
		seq.setTemporary(true);
	} else {
		// CREATE SEQUENCE, 数据库 Schema 持久化
		session.getDatabase().addSchemaObject(session, seq);
	}
	setAutoIncrement(false, 0, 0);
	// 把Sequence 包装为表达式片段
	SequenceValue seqValue = new SequenceValue(seq);
	setDefaultExpression(session, seqValue);
	setSequence(seq);
}
```

Insert 过程

```java
// 遍历 Table 的 columns 和 参数Expression， 执行值填充
for (int i = 0; i < columnLen; i++) {
	Column c = columns[i];
	int index = c.getColumnId();
	// 获取 Value Expression
	Expression e = expr[i];
	if (e != null) {
		try {
			// 如果是SequenceValue， 生成自增数字
			Value v = c.convert(e.getValue(session));
			newRow.setValue(index, v);
		} catch (DbException ex) {
			throw setRow(ex, x, getSQL(expr));
		}
	}
}
```

### ③自增计算

```java
/**
 * Get the next value for this sequence.
 *
 * @param session the session
 * @return the next value
 */
public synchronized long getNext(Session session) {
	// valueWithMargin 计算， flush 过程...
	long v = value;
	value += increment;
	return v;
}
```

## 总结

- H2 database 是java 编写的数据库，简单易懂，对于数据库实现原理是个很好参考。

- 通过阅读数据库的实现，对于应用开发帮助很大，可以适当的扬长避短。

- 对于SQL 规范，每种数据库都有对应的实现方式，dalect。













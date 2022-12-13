---
layout: post
title:  "笔记 分布式事务-XA模式与atomikos框架浅析"
date:   2021-11-30 17:58:34 +0800
categories: jekyll update
---
# 笔记 分布式事务-XA模式与atomikos框架浅析



> 最近在看 H2 数据库的实现原理，竟然支持 XA 协议。正好顺路对分布式事务温习下，感觉无用的知识又增加了。
>
> 通过学习分布式事务的解决方案，积累分布式设计和开发的经验，举一反三。
>
> 国内使用较多的 mysql ，在 XA 协议的支持上一般，同时两阶段提交的方案在性能上和实现上都有一定的困难，因此可以称之为“无用的知识”。另一方面，从 atomikos 商业版的定价上看，真正的大公司才用得起，一般公司用不起也没必要这么用。
>
> 行业内比较实用的方案：事务消息+最终一致性。

## 分布式事务-XA模式

- XA 协议是由 X/Open 组织提出的分布式事务处理规范，主要定义了事务管理器 TM 和局部资源管理器 RM 之间的接口。

- 分布式事务的两阶段提交是把整个`事务提交分为 prepare 和 commit` 两个阶段。

  *第一阶段，事务协调者向事务参与者发送 prepare 请求，事务参与者收到请求后，如果可以提交事务，回复 yes，否则回复 no。*

  *第二阶段，如果所有事务参与者都回复了 yes，事务协调者向所有事务参与者发送 commit 请求，否则发送 rollback 请求。*

- JTA实现分布式事务的两个阶段。

  *第一阶段首执行 XA 开启、执行 sql、XA 结束三个步骤，之后直接执行 XA prepare。*

  *第二阶段执行 XA commit/rollback。*

- 使用XA 模式前提是：数据库对 XA 协议的支持。atomikos、seata、[bitronix](https://github.com/bitronix)是作为`全局的调度者`的角色参与到方案中。

- seata 是阿里推出的一款开源分布式事务解决方案，目前有 AT、TCC、SAGA、XA 四种模式。

## atomikos 框架浅析

### atomikos TransactionsEssentials

> Manage your distributed transactions and protect your mission critical data.
>
> 轻量、开源、免费、收费版本（ExtremeTransactions）提供技术支持（**14500 €**/year）。
>
> 轻量是指不依赖应用服务器（Websphere、Jboss）。

<img src="{{ "/images/TransactionsEssentials.png" | prepend: site.baseurl }}" alt="TransactionsEssentials" style="zoom:50%;" />

### Insight atomikos 事务管理

insight 思路是顺着 javax.transaction.xa.XAResource 定义的接口来看协调者做了哪些工作。主要侧重XA Api操作步骤，涉及到XA 协议的状态管理、嵌套事务等实现，不在此处关注。

#### 事务开启

参考：com.atomikos.datasource.xa.XAResourceTransaction#resume

关键类：

- **com.atomikos.icatch.Participant** （XAResourceTransaction）

*A participant for (distributed) two-phase commit of composite transactions. Implementations can be added as a 2PC participant in the icatch kernel*

- **com.atomikos.jdbc.AtomikosConnectionProxy**

*拦截 JdbcConnection 的操作，根据操作选择纳入协调器管理、开启XA事务或者阻止在XA事务中直接commit等。*

注意：不同于普通的 Jdbc 事务，JTA的事务开启并不是在 AbstractPlatformTransactionManager#doBegin 方法中调用。设想多个数据源，到底是应该开启哪个的事务，只有真正发生 Jdbc 操作时，才会判断并开启XA事务，同时把该数据源纳入到协调器中。

#### 事务提交（两阶段提交）

根据执行情况分为 prepare + commit、 prepare + rollback、 rollback。

参考： com.atomikos.icatch.jta.UserTransactionImp#commit

关键类：

- **com.atomikos.icatch.CompositeTransaction**

*Represents a nested part of a global composite transaction. 委托协调器发起事务的提交。*

- **com.atomikos.icatch.imp.CoordinatorImp**

```java
protected void terminate(boolean commit) throws Exception {
    synchronized (fsm_) {
        if (commit) {
            if (participants_.size() <= 1) {
                // 如果只涉及到单数据库的操作，那么简化为普通的jdbc操作，直接commit
                commit(true);
            } else {
                // 对多个participant 发起prepare操作，第一阶段协调
                int prepareResult = prepare();
                // make sure to only do commit if NOT read only
                if (prepareResult != Participant.READ_ONLY)
                    commit(false);
            }
        } else {
            // 或者直接回滚，应用逻辑出错，不需要协调
            rollback();
        }
    }
}

```

- **com.atomikos.icatch.imp.ActiveStateHandler**

```java
protected int prepare() throws Exception {
	Vector<Participant> participants = getCoordinator().getParticipants();
	CoordinatorStateHandler nextStateHandler = null;
	// 省略其他判断...
	try {
		getCoordinator().setState(TxState.PREPARING);
		result = new PrepareResult(participants.size());
		Enumeration<Participant> enumm = participants.elements();
        // 分别对 Participant 发起prepare(), 默认是同步提交，可以启用线程池异步发起prepare()
		while (enumm.hasMoreElements()) {
			Participant p = (Participant) enumm.nextElement();
			PrepareMessage pm = new PrepareMessage(p, result);
			// 省略其他判断...
			getPropagator().submitPropagationMessage(pm);
		} // while

		result.waitForReplies();
		boolean voteOK = result.allYes();
		if (!voteOK) {
			try {
				rollbackWithAfterCompletionNotification(new RollbackCallback() {
					public void doRollback() {
						rollbackFromWithinCallback(true, false);
					}
				});
			}
		}
	} catch (RuntimeException runerr) {
		throw new SysException("Error in prepare: " + runerr.getMessage(), runerr);
	}

	return ret;
}

```



#### Spring 事务管理适配

常用的事务管理器，**DataSourceTransactionManager**， for a single JDBC DataSource。

JTA事务管理器，JtaTransactionManager，This transaction manager is appropriate for handling distributed transactions, i.e. transactions that span multiple resources, and for controlling transactions on application server resources (e.g. JDBC DataSources available in JNDI) in general.



### SpringBoot-atomikos-demo

github

[分布式事务详解——SpringBoot+Atomikos篇](https://www.jianshu.com/p/c803fa4827b7)


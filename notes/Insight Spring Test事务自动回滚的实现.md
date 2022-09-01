# Insight Spring Test 事务自动回滚的实现

## 测试环境事务控制的意义

- 避免测试用例的数据持久化的影响。需要事务控制回滚，还原场景，这样测试用例可以重复使用。（tests  changes to the state may affect future tests）
- 我们的业务逻辑需要事务控制，测试环境也要同样的模拟。

## 测试环境-事务控制demo

```java
/**
 * 只需要测试类添加@Transactional， 保证所有的测试方式都有事务控制，并且执行完成后自动回滚。
 * 参考 https://docs.spring.io/spring-framework/docs/4.3.13.RELEASE/spring-framework-reference/htmlsingle/#testcontext-tx-enabling-transactions
 */
@RunWith(SpringRunner.class)
@ContextConfiguration(classes = TestConfig.class)
@Transactional
public class HibernateUserRepositoryTests {
    
    @Test
    public void createUser() {
        // track initial state in test database:
        final int count = countRowsInTable("user");

        User user = new User(...);
        repository.save(user);

        // Manual flush is required to avoid false positive in test
        sessionFactory.getCurrentSession().flush();
        assertNumUsers(count + 1);
        // 方法执行完成后，insert user 会自动回滚，不会在数据库中添加脏数据
    }
    
}
```

## 源码实现

### 自动回滚的原理

Spring 采用容器注入的方式，`在Junit 测试框架的基础上`，引入TestExecutionListener 的概念，方便拓展自定义的事件。

事务控制就是基于这样的设计，通过`实现TestExecutionListener  接口，达到事务特性增强的目的`。

```java
/**
 * 支持Spring Test 事务控制实现的TestExecutionListener
 * 
 * @see org.springframework.test.context.transaction.TransactionalTestExecutionListener
 */
public class TransactionalTestExecutionListener extends AbstractTestExecutionListener {
    
    /**
     * 如果是以事务的形式运行，那么会在测试方法执行前，开启事务
     * 前提条件：有@Transactional 注解，并且容器中配置了TransactionManager。SpringBoot 不用考虑，使用Spring 框架的需要检查下是否有这个配置 <tx:annotation-driven transaction-manager="transactionManager"/>
     */
    public void beforeTestMethod(TestContext testContext) throws Exception {
		final Method testMethod = testContext.getTestMethod();
		// 如果是@NotTransactional，直接跳过
		if (testMethod.isAnnotationPresent(NotTransactional.class)) {
			return;
		}

        // 检测当前的方法或者类是否需要事务、是否有配置TransactionManager
		PlatformTransactionManager tm = null;
		if (transactionAttribute != null) {
			tm = getTransactionManager(testContext, transactionAttribute.getQualifier());
		}
		// 获取到tm，开启事务。按照惯例，缓存事务对象，方便afterTestMethod 进行事务继续操作。
		if (tm != null) {
			TransactionContext txContext = new TransactionContext(tm, transactionAttribute);
			runBeforeTransactionMethods(testContext);
            // 复习下开启事务的过程：Check settings、check propagation、Acquire Connection、setAutoCommit(false)、Bind the session holder to the thread
			startNewTransaction(testContext, txContext);
			this.transactionContextCache.put(testMethod, txContext);
		}
	}
    
    public void afterTestMethod(TestContext testContext) throws Exception {
		Method testMethod = testContext.getTestMethod();
		
		// If the transaction is still active...
		TransactionContext txContext = this.transactionContextCache.remove(testMethod);
		if (txContext != null && !txContext.transactionStatus.isCompleted()) {
			try {
                // rollback or commit
				endTransaction(testContext, txContext);
			}
			finally {
				runAfterTransactionMethods(testContext);
			}
		}
	}
    
}  

```

### TestExecutionListener  注入的原理

在测试容器启动过程中，会检测当前的测试类是否有指定 TestExecutionListeners。如果没有就采用默认的TestExecutionListeners。

```java
/**
 * Determine the default TestExecutionListener classes.
 * 默认的TestExecutionListeners：
 * ServletTestExecutionListener
 * DependencyInjectionTestExecutionListener
 * TransactionalTestExecutionListener 就是本人啦！
 * @see org.springframework.test.context.TestContextManager
 */
protected Set<Class<? extends TestExecutionListener>> getDefaultTestExecutionListenerClasses() {
	Set<Class<? extends TestExecutionListener>> defaultListenerClasses = new LinkedHashSet<>();
	for (String className : DEFAULT_TEST_EXECUTION_LISTENER_CLASS_NAMES) {
		try {
			defaultListenerClasses.add((Class<? extends TestExecutionListener>) getClass().getClassLoader().loadClass(className));
		} catch (Throwable t) {
			
		}
	}
	return defaultListenerClasses;
}

```



## 涉及到注解

- @Transactional 启用事务控制必要注解。测试环境下，如果加在类上就全部生效，加载方法上只有方法生效。
- @TransactionConfiguration 配置事务测试的条件，如果有多个transactionManager 实例，需要这个注解。
- @BeforeTransaction @AfterTransaction 用于测试类的`方法注解，不受事务控制`。
- @NotTransactional 标识测试的方法不受事务控制，等同于上述的注解。
- @Rollback `自定义标识测试的方法是否要回滚`，用来避免默认情况下回滚的操作。



## 总结

- Spring 托管一切，集成一切，包罗万象。各种集成的方案和实现都值得借鉴。
- 了解Spring Test 事务控制的原理，可以更好的编写测试用例，提升工作效率。
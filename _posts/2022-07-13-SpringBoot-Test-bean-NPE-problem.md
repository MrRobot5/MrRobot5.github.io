---
layout: post
title:  "SpringBoot Test bean 使用 NPE 诡异问题"
date:   2022-07-13 17:57:33 +0800
categories: jekyll update
---
# SpringBoot Test NPE 诡异问题引发的cglib 机制探索

> 近期，在使用SpringBoot Test 单测验证service 逻辑过程中，发现service “注入”的mapper 竟然是null, 导致业务方法NPE。
> 
> 之前的单测一直是这样的，是因为SpringBoot 版本问题，导致注入失败么？

## NPE 案例代码

```java
@Slf4j
@RunWith(SpringJUnit4ClassRunner.class)
@SpringBootTest
public class FooServiceProcessTest {

    /**
     * 诡异的问题就在这里，serviceProcess 注入并没有问题。
     * serviceProcess 的属性mapper 是null
     */
    @Autowired
    private FooServiceProcess serviceProcess;

    /**
     * 测试更新关联关系操作
     * cascadeUpdateFoo 方法中，是通过this.fooMapper.update() 方式编写的。
     * 需要测试的方法是private ,为了方便，直接用反射调用的。就是因为这个非常规使用，导致个诡异问题出现
     */
    @Test
    void cascadeUpdateFoo() throws InvocationTargetException, IllegalAccessException {
        Method method = ReflectionUtils.findMethod(serviceProcess.getClass(), "cascadeUpdateFoo", FooParam.class);
        ReflectionUtils.makeAccessible(method);
        FooParam param = new FooParam();
        param.setId(180L);
        param.setName("foo");
        param.setUpdateUser("foo");
        method.invoke(serviceProcess, param);
    }

}
```

## NPE 问题排查

1. 从报错日志和直观的判断，mapper 为null，可能的问题是Mybatis 或者Mybatis 插件扫描，加载出了问题。通过查看ApplicationContext， mapper 是存在的，况且**注入使用的是@Autowired，如果容器没有mapper，启动就会报错**。

2. 然后就是从spring-test 去排查，**是否会存在父子容器注入替换的问题**。之前在排查SpringMVC 就遇到过这种问题。

3. 参考上述代码，`FooServiceProcess `可以正常注入，追查容器的初始化或者注入线索的意义就不太大了。那就从单测代码上追查。

4. 通过debug， 发现真正的问题。serviceProcess 实例并非原始的对象，是经过cglib 动态代理过的proxy。**如果是调用private 方法，调用的就是这个proxy 的方法，自然会出现NPE 的问题。**

## cglib 代理调用验证

> 通过上述的排查和分析，这个问题和SpringBoot 并没有关系。
> 
> **问题出在cglib 动态代理类的调用方式和继承机制上**，通过编写测试类HotPot，再按照上述的反射调用private 方法，即可复现。

```java
/**
 * private, cglib can't enhance...<br/>
 * this 是指proxy, getMaterial() 则调用了目标instance.getMaterial(), 是可以正常返回的。<br/>
 * 打印结果：<br/>
 * x.y.simple.HotPot$$EnhancerByCGLIB$$23f73db0
 * intercept method--class x.y.simple.HotPot.getMaterial
 * this material is china., need heat
 */
private void prepare() {
    System.out.println(this.getClass().getName());
    System.out.println("this material is " + this.getMaterial() + ", need heat");
}

/**
 * 同样是无法代理的private, this 是proxy, material 是proxy 实例的属性，所以是null<br/>
 * 打印结果：<br/>
 * the material null need wash, after used
 */
private void finish () {
    System.out.println("the material " + this.material + " need wash, after used");
}

/**
 * public 方法，proxy.toString, 拦截后，变为目标instance.toString()<br/>
 * 打印结果：<br/>
 * x.y.simple.HotPot
 * HotPot{temperature=99.9, material='china.'}
 */
@Override
public String toString() {
    System.out.println(this.getClass().getName());
    return "HotPot{temperature=" + this.temperature + ", material='" + this.material + '\'' + '}';
}
```

代码库： https://github.com/MrRobot5/sample-base-more

## 总结

- 不要使用非常规的写法，不常用的功能或者api，遇到问题的概率会大很多。

- 这次的问题深入追查后，是cglib 代理的问题，是**java 继承理论知识的充分表现**。

- **越是离奇诡异的问题，原因越是简单和直白。但是排查弯路总是要走的，经验就是这么来的。**

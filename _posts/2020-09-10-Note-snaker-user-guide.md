---

layout: post
title:  "笔记 snaker 使用指导和设计浅析"
date:   2020-09-10 18:31:01 +0800
categories: jekyll update

---

# snaker 使用指导和设计浅析

## snaker 介绍

Snaker是一个基于Java的`开源工作流引擎`，适用于企业应用中常见的业务流程。本着轻量、简单、灵巧理念设计，定位于简单集成，多环境支持。

流程引擎源码(oscgit):
http://git.oschina.net/yuqs/snakerflow

演示应用源码(oscgit):
http://git.oschina.net/yuqs/snaker-web

插件源码(oscgit):
http://git.oschina.net/yuqs/snaker-designer

### 为什么用snaker

* 超轻量，只需要7张表，即可开始业务流程的驱动使用。相比于JBPM、Activti十几张表，上手和使用的难度很低。对于典型的工作流程编排，并且场景不是非常复杂，可以考虑引入 snaker。
* 源码设计、编写非常规范，易懂、易改造。对于学习工作流原理或者二次开发，都很友好。
* 不足之处也有很多，支持场景不够丰富，部分功能不够稳定，云功能等。

## snaker 使用指导

如果了解activiti、jbpm，那么理解、使用snaker可以平滑过渡。API的使用方式和流程模型的定义基本相同。

如果没有接触过工作流，对于snaker 简洁的流程模型的定义格式，以及丰富的示例，也能很快入手。

### 官方示例参考

* snaker-core 源码工程test
  
  > 主要提供流程引擎的组件和功能点的测试、API使用用例。
  > 
  > 提供全部支持的流程模型测试用例，可以在 snakerflow\snaker-core\src\test\resources\test 路径下找到

* snaker-spring 源码工程test
  
  > spring 集成示例

* snaker-web 源码工程
  
  > 完整的工作流程应用实例。业务使用、集成snaker，完全可以参考该工程配置。
  > 
  > 技术栈：SpringMVC + shiro + Hibernate + snaker + raphael.js + mysql

### 流程设计器

snaker提供Eclipse 插件、`web 流程设计器`。

web 流程设计器提供在线设计、编辑和保存流程模型。参考snaker-web，设计完的流程模型可以直接部署到应用中使用。

`基于 raphael.js 开发`的web设计器和流程可视化显示。

#### 注意事项

拖拽工具栏，根据业务需求编制即可。需要注意的是，transaction 组件使用，先点击源节点，再点击目的节点，即可完成连接。

具体的节点属性配置，在弹出的表单配置即可。

也可以在生成的xml 流程模型文件中修改属性，重新上传即可实现刷新、覆盖。

### 应用开发API使用方式

应用开发主要使用流程引擎接口API，服务对象只用于流程引擎的调用，不应该直接调用低层的API。

#### 获取工作流引擎

```java
// api集成方式，构造SnakerEngine对象
SnakerEngine engine = new Configuration().buildSnakerEngine();
```

```xml
// spring集成方法，通过配置注入的方式构造SnakerEngine对象
<bean class="org.snaker.engine.spring.SpringSnakerEngine">
    <property name="processService" ref="processService"/>
    <property name="orderService" ref="orderService"/>
    <property name="taskService" ref="taskService"/>
    <property name="queryService" ref="queryService"/>
    <property name="managerService" ref="managerService"/>
</bean>
```

#### 部署流程模型

```java
// 根据文件输入流，部署流程定义。
engine.process().deploy(StreamHelper.getStreamFromClasspath("test/task/simple/process.snaker"))
```

#### 启动流程实例

```java
// 根据流程定义ID，操作人ID，参数列表启动流程实例
Order order = engine.startInstanceById(processId, operator, args);
// 根据流程名称启动流程实例
Order order = engine.startInstanceByName(name, version, operator);
```

#### 查询任务

```java
// 历史任务查询
engine.query().getHistoryTasks(new Page<HistoryTask>(), new QueryFilter().setOperator("foo"));
// 查询当前责任人的任务
engine.query().getActiveTasks(new Page<Task>(), new QueryFilter().setOperator("foo"));
// 根据当前用户查询待办任务列表
engine.query().getWorkItems(page, new QueryFilter().setOperator("foo"));
```

#### 执行任务

```java
// 根据流程定义ID，系统调用、执行任务
List<Task> tasks = engine.query().getActiveTasks(new QueryFilter().setOrderId(order.getId()));
for(Task task : tasks) {
    engine.executeTask(task.getId(), "foo", args);
}
// 根据任务提交请求，执行任务。args 可以认同为提交的表单内容。
engine.executeTask(task.getId(), "foo", args);
```

### snaker-web 使用指导

web工程 内置提供了‘请假流程测试’、‘借款申请流程’，可以直接使用。

IDEA 添加jetty 运行配置，启动即可。

访问 http://localhost:8080/snaker-web/login ，使用admin 用户登录即可使用所有的功能。

#### 业务流程集成示例

业务流程如果简单，可以直接把业务数据存在流程实例的变量中。如果复杂业务，可以在业务表中增加order_id、task_id 来支持业务流引擎的集成。`业务表属于应用层，流程表属于服务层，高层依赖底层，底层不能耦合高层`。表设计千万注意。

‘借款申请流程’发起申请，可以参考，作为样本代码使用。

## snaker 设计浅析

整体的设计思路和activiti、jbpm 相似。snaker 基于轻量的方向，只有流程引擎驱动相关的表，只提供经典的工作流特性。

> 工作流管理系统(Workflow Management System, WfMS)是一个软件系统，它`完成工作量的定义和管理`，并按照在系统中`预先定义好的工作流逻辑进行工作流实例的执行`。工作流管理系统不是企业的业务系统，而是为企业的业务系统的运行提供了一个软件的支撑环境。

###流程引擎

#### 定义的对象

* Process 流程定义、流程模型实体类
* Order 流程工作单实体类（一般称为流程实例）
* Task 任务实体类
* TaskActor 任务参与者实体类
* NodeModel 节点元素（存在输入输出的变迁），特别注意 CustomModel

#### 提供的Service对象

* IProcessService 流程模型服务。提供的功能：保存流程定义、根据流程模型文件部署流程、根据主键ID获取流程定义对象
* IOrderService 流程实例服务。提供的功能：根据流程定义创建流程实例、添加全局变量、完成流程实例、终止流程实例
* ITaskService 任务服务。提供的功能：创建任务、添加删除参与者、完成任务、撤回任务、回退任务、提取任务
* IQueryService 流程相关的查询服务。提供的功能：分页查询流程实例、任务、历史流程实例、任务参与者
* IManagerService 管理服务接口,用于流程管理控制服务委托管理时限控制。

### 功能实现

#### 任务驱动实现

```java
public List<Task> executeTask(String taskId, String operator, Map<String, Object> args) {
    // 1.完成当前任务，并且构造执行对象
    Execution execution = execute(taskId, operator, args);
    ProcessModel model = execution.getProcess().getModel();
    if(model != null) {
        // 反查当前任务，对应在流程定义中的节点
        NodeModel nodeModel = model.getNode(execution.getTask().getTaskName());
        // 2.该任务对应的节点模型执行（根据路由策略，递归调用，驱动调用的核心设计！）
        nodeModel.execute(execution);
    }
    return execution.getTasks();
}
```

#### 流程定义文件的保存

snker 的流程模型是以字节码的形式存在数据库中的。

#### 流程定义版本支持

如果是根据processId 查询，那么对应的版本就是固定的。

如果是根据processName 查询，那么应该查询最新的版本的流程定义。

```java
// 根据name获取process对象
public Process getProcessByVersion(String name, Integer version) {
    if(version == null) {
        // select max(version) from wf_process  where name = ?
        version = access().getLatestProcessVersion(name);
    }
    if(version == null) {
        version = 0;
    }
    // select * from wf_process  where 1=1  and name in(?) and version = ? order by name asc 
    List<Process> processs = access().getProcesss(null, new QueryFilter().setName(name).setVersion(version));
    return processs.get(0);
}
```

# AXI3 Interconnect UVM Driver设计SPEC

editor：Codex / 项目讨论结论整理  
date：2026-09-07  
版本号：v3-draft

## 迭代记录

| 版本 | 日期 | 迭代原因 | 迭代内容 |
|---|---|---|---|
| v3-draft | 2026-09-07 | 先明确Driver组件必须完成的功能边界，再逐项讨论具体实现 | 文档重构为“总体实现框架”和“具体实现细节”两部分；保留ALWAYS/RANDOM/SCRIPTED三种READY模式 |
| v2-draft | 2026-09-06 | Driver依赖的单端口interface已经实现 | 确认Master/Slave Driver的clocking视角和接口参数 |
| v1-draft | 2026-09-04 | 基于请求/响应分离的transaction设计Driver | 初步整理Driver并发、outstanding、交织和reset问题 |

## 1. 文档目的

本文档定义三主三从AXI3 Interconnect验证环境中`axi_m_driver`和`axi_s_driver`需要实现的功能。

文档分为两部分：

1. 第一部分定义Driver“要完成什么”，包括需要支持的AXI机制、通道驱动时序和组件边界。该部分是后续实现必须满足的总体框架。
2. 第二部分记录Driver“具体怎样实现”。线程、队列、`item_done()`、对象快照、调度算法、reset清理和SystemVerilog/UVM语法等内容，在后续逐项讨论并确认后补充。

本文档与以下文档配合使用：

- 总体环境基线：[detail_testplan.md](../detail_testplan.md)。
- transaction定义：[transaction_spec.md](./transaction_spec.md)。
- 总体验证计划：[framework_sepc.md](../framework_sepc.md)。
- 单端口interface：`dv/tb/axi_if.sv`。

发生冲突时，请求/响应字段及约束以`transaction_spec.md`为准，Driver组件边界以本文档最新确认内容为准。

# 第一部分：Driver总体实现框架

## 2. Driver总体划分

验证环境包含两类Driver：

```text
axi_m_driver
    模拟DUT上游的一个AXI Master
    消费axi_req_item
    驱动AW/W/AR请求并接收B/R响应

axi_s_driver
    模拟DUT下游的一个reactive AXI Slave
    消费axi_rsp_item
    接收AW/W/AR请求并驱动B/R响应
```

每个Driver实例只绑定一个物理AXI端口。三主三从环境分别实例化三个Master Driver和三个Slave Driver，Driver内部不直接操作三端口数组。

## 3. 两类Driver的共同要求

### 3.1 AXI握手要求

- 每个通道只在`VALID && READY`的时钟沿完成一次传输。
- 发送方不能等待READY拉高后才产生VALID。
- `VALID=1 && READY=0`期间，VALID和对应payload必须保持稳定。
- AW、W、B、AR、R是五个独立通道，Driver不能假定它们在同一周期握手。
- 一个通道发生stall时，不能无条件阻塞其他无依赖关系的通道。
- VALID握手完成后，Driver才能撤销VALID或切换到下一个payload。

### 3.2 Transaction使用要求

- Master Driver根据`axi_req_item`驱动请求。
- Slave Driver根据`axi_rsp_item`驱动响应。
- VALID、READY、WLAST和RLAST不作为transaction随机字段。
- WID、WLAST、BID、RID和RLAST由Driver根据transaction内容派生。
- Driver不能重新随机化、静默修改或丢弃sequence提供的item。
- transaction中的delay/gap描述开始发送前的等待意图，不改变AXI握手规则。

### 3.3 Interface访问要求

- Master Driver使用单端口interface的`m_drv_cb/m_drv_mp`。
- Slave Driver使用单端口interface的`s_drv_cb/s_drv_mp`。
- Driver通过clocking block驱动和采样信号，避免与DUT在同一边沿发生竞争。
- 上游Master Driver使用4-bit原始ID；下游Slave Driver使用8-bit扩展ID。
- 非有效周期payload默认驱动为0，不能用`X/Z`作为正常空闲值。

### 3.4 组件职责边界

Driver负责将事务稳定地转换为接口信号，但不负责：

- 预测DUT地址路由和仲裁结果。
- 判断DUT功能是否正确。
- 使用Driver意图代替Monitor的真实握手结果。
- 向scoreboard提供功能actual。
- 采样functional coverage。
- 实现reference model或DUT内部FIFO模型。

实际发生的总线事务必须由Monitor根据接口握手重建。

## 4. Master Driver需要实现的内容

### 4.1 信号控制范围

Master Driver主动驱动：

```text
AWID/AWADDR/AWLEN/AWSIZE/AWBURST/AWVALID
WID/WDATA/WSTRB/WLAST/WVALID
ARID/ARADDR/ARLEN/ARSIZE/ARBURST/ARVALID
BREADY/RREADY
```

Master Driver采样：

```text
AWREADY/WREADY/ARREADY
BID/BRESP/BVALID
RID/RDATA/RRESP/RLAST/RVALID
```

### 4.2 请求接收和分流

Master Driver从sequencer取得`axi_req_item`，根据`dir`区分读写：

- 写请求交给AW和W通道处理。
- 读请求交给AR通道处理。
- Driver需要允许后续请求继续进入，从而支持多笔outstanding。
- AW、W和AR必须能够独立推进并在同一周期并行工作。

### 4.3 AW写地址机制

Master Driver需要：

- 根据`addr_delay`控制AW请求开始时间。
- 把`id/addr/len/size/burst`映射到AW通道。
- 拉高AWVALID并保持payload，直到AWREADY完成握手。
- 允许AW先于W、晚于W或与W并行发送。

### 4.4 W写数据机制

Master Driver需要：

- 根据`w_start_delay`和`wbeat_gap[]`控制写数据发送节奏。
- 支持1～16个W beat。
- 使用`req.id`产生WID。
- 使用`wdata[]/wstrb[]`逐拍驱动WDATA/WSTRB。
- 只在最后一个beat产生WLAST。
- 支持AXI3不同WID写数据交织。
- 保持相同WID的事务和beat顺序。
- 当前beat遇到WREADY背压时，保持当前WID和payload，不能切换到其他事务。

### 4.5 AR读地址机制

Master Driver需要：

- 根据`addr_delay`控制AR请求开始时间。
- 把`id/addr/len/size/burst`映射到AR通道。
- 拉高ARVALID并保持payload，直到ARREADY完成握手。
- AR通道可以与AW、W通道并行工作。

### 4.6 B/R响应接收机制

Master Driver需要：

- 独立控制BREADY和RREADY。
- 在B握手时识别一笔写请求完成。
- 在R握手时接收每个读数据beat，并在RLAST握手时识别一笔读请求完成。
- 支持不同ID响应乱序和不同RID读数据交织。
- 同ID响应按照请求接受顺序关联。
- 为outstanding流控维护必要的完成信息。
- 是否向Master sequence返回独立`axi_rsp_item`，留到第二部分讨论。

### 4.7 Master侧outstanding机制

Master Driver需要支持每个端口：

```text
最多4笔读outstanding
最多4笔写outstanding
读写分别统计
```

达到配置上限后停止发出新的同方向请求，同时继续接收已有请求的B/R响应。具体采用credit、计数器还是其他结构，在第二部分确定。

### 4.8 Master侧READY模式

BREADY和RREADY分别支持：

- `ALWAYS_READY`：无主动响应背压。
- `RANDOM_READY`：随机产生响应接收延迟和背压。
- `SCRIPTED_READY`：按照测试指定的确定性周期窗口控制READY。

BREADY和RREADY必须独立配置，不能因为一个响应通道阻塞而停止另一个通道。

## 5. Slave Driver需要实现的内容

### 5.1 信号控制范围

Slave Driver主动驱动：

```text
AWREADY/WREADY/ARREADY
BID/BRESP/BVALID
RID/RDATA/RRESP/RLAST/RVALID
```

Slave Driver采样：

```text
AWID/AWADDR/AWLEN/AWSIZE/AWBURST/AWVALID
WID/WDATA/WSTRB/WLAST/WVALID
ARID/ARADDR/ARLEN/ARSIZE/ARBURST/ARVALID
BREADY/RREADY
```

### 5.2 AW/W/AR请求接收机制

Slave Driver需要独立控制AWREADY、WREADY和ARREADY，对DUT下游请求施加或解除背压。

三个READY信号分别支持：

- `ALWAYS_READY`：reset释放后持续允许请求握手，用于smoke和无背压测试。
- `RANDOM_READY`：随机延迟或随机高低周期，用于一般背压和压力测试。
- `SCRIPTED_READY`：按照预设周期窗口拉高或拉低，用于定向场景和问题复现。

注意事项：

- 三个READY模式可以分别配置，不能强制同步变化。
- READY可以在VALID到来前拉高。
- WREADY不能以AW已经握手作为拉高前提，需要支持W先于AW被接收。
- READY控制来自Slave agent配置和容量状态，不属于`axi_rsp_item`。
- 验证环境响应容量不足时，可以强制拉低相应READY，避免自身队列溢出。

### 5.3 Reactive响应链路

Slave侧响应遵循以下因果关系：

```text
Slave Driver控制AW/W/AR READY
        ↓
DUT请求完成真实握手
        ↓
Slave Monitor重建请求
        ↓
Reactive Slave sequence生成axi_rsp_item
        ↓
Slave Driver驱动B或R响应
```

Slave Driver不能根据尚未握手的请求或Master sequence意图提前生成响应。

### 5.4 B写响应机制

Slave Driver需要：

- 根据写方向`axi_rsp_item`驱动BID和BRESP。
- 根据`rsp_delay`控制BVALID开始时间。
- BVALID拉高后保持BID/BRESP，直到BREADY握手。
- 原样返回下游8-bit扩展ID。
- 同ID写响应保序，不同ID写响应允许乱序。
- 只对已经完整接收写地址和全部写数据的请求产生B响应。

### 5.5 R读响应机制

Slave Driver需要：

- 根据读方向`axi_rsp_item`逐拍驱动RID/RDATA/RRESP。
- 根据`rsp_delay`控制第一个R beat的开始时间。
- 根据`rbeat_gap[]`控制相邻R beat间隔。
- 根据`len`在最后一个beat产生RLAST。
- RVALID拉高后保持当前beat，直到RREADY握手。
- 支持不同RID读数据按beat交织。
- 相同RID保持请求顺序和beat顺序。

### 5.6 Slave响应调度和容量

Slave Driver需要：

- 允许B和R通道并行工作。
- 保存尚未发送的B/R响应计划。
- 支持不同ID响应顺序调整。
- 防止响应缓存无界增长。
- 在容量不足时与READY控制协调，对新请求施加背压。

具体队列深度、响应选择算法以及容量状态由谁维护，在第二部分讨论。

## 6. Reset和空闲行为

reset期间Master Driver需要驱动：

```text
AWVALID=0
WVALID=0
ARVALID=0
BREADY=0
RREADY=0
```

reset期间Slave Driver需要驱动：

```text
AWREADY=0
WREADY=0
ARREADY=0
BVALID=0
RVALID=0
```

两类Driver都需要：

- 清除或终止reset前未完成的驱动活动。
- reset期间不产生新的有效请求或响应。
- reset释放后等待规定的clocking event再恢复工作。
- 不自动重放已经部分握手的事务。
- 与Monitor、Tracker和Scoreboard采用一致的reset边界。

内部队列如何清理、已取得item如何完成、是否通知sequence等问题，在第二部分讨论。

## 7. Driver总体注意事项

- 不把READY控制字段加入`axi_req_item`或`axi_rsp_item`。
- 不把VALID作为transaction随机字段。
- 不使用固定等待若干周期代替真实READY握手。
- 不在VALID stall期间重新仲裁或切换payload。
- 不把所有ID的请求或响应放入单一全局FIFO强制同序。
- 不用Driver内部对象作为scoreboard的实际观察结果。
- 不因实现outstanding而异步修改sequence仍可能复用的对象。
- 不让reset造成sequencer握手永久挂起。
- 不让随机READY策略破坏容量保护和reset优先级。

# 第二部分：Driver具体实现细节

## 8. 本部分使用方式

本部分用于记录第一部分各项能力的具体实现方案。每个问题经过讨论后，应补充：

1. 最终采用的方案。
2. 放弃的备选方案及原因。
3. 使用的SystemVerilog/UVM结构或语法。
4. 对象、线程和队列的所有权关系。
5. reset和异常路径处理。
6. 实现时需要避免的问题。
7. 对应的最小验证方法和验收条件。

未讨论确认的内容不在本SPEC中提前指定具体实现，避免总体功能要求与暂定代码方案混在一起。

## 9. 已确认的实现原则

当前已经确认：

- 使用`axi_m_driver`和`axi_s_driver`两个独立组件。
- 每个Driver实例只对应一个单端口interface。
- Master Driver消费`axi_req_item`，Slave Driver消费`axi_rsp_item`。
- Driver统一通过interface clocking block访问总线。
- Slave侧AWREADY、WREADY、ARREADY继续支持`ALWAYS_READY`、`RANDOM_READY`和`SCRIPTED_READY`三种模式，并且三个通道可以独立配置。
- Master侧BREADY、RREADY复用相同的三种模式概念，并且两个通道独立配置。
- READY模式属于agent配置/策略，不属于transaction。
- Monitor采样的实际握手是scoreboard和coverage的数据来源。

三种READY模式内部怎样计数、什么时候开始随机延时、READY拉高后保持多久以及SCRIPTED脚本怎样表达，仍属于待讨论实现细节。

## 10. 后续需要逐项讨论的问题

| 编号 | 实现问题 | 当前状态 |
|---|---|---|
| D1 | Master/Slave Driver的类参数、typedef、config和virtual interface类型 | 待讨论 |
| D2 | sequencer与Driver的连接类型以及`get_next_item/item_done`时机 | 待讨论 |
| D3 | transaction是否需要clone，独立快照保存哪些字段 | 待讨论 |
| D4 | Master请求如何分发给AW/W/AR以及多个通道如何共享上下文 | 待讨论 |
| D5 | Driver长期线程的划分、启动、同步和退出方式 | 待讨论 |
| D6 | `addr_delay/w_start_delay/wbeat_gap`的精确定义和计数方法 | 待讨论 |
| D7 | `rsp_delay/rbeat_gap`的精确定义和计数方法 | 待讨论 |
| D8 | 三种READY模式的配置字段、状态变化和容量门控优先级 | 模式已确认，细节待讨论 |
| D9 | Master读写outstanding的计数、限制和释放方式 | 待讨论 |
| D10 | W交织的候选保存、选择和stall锁定方法 | 待讨论 |
| D11 | Master侧B/R响应关联以及是否返回response给sequence | 待讨论 |
| D12 | Slave侧同ID保序、不同ID乱序和R交织调度方法 | 待讨论 |
| D13 | Slave请求接收容量与AW/W/AR READY之间的协调方式 | 待讨论 |
| D14 | reset时线程停止、VALID/READY复位、队列清理和item处理 | 待讨论 |
| D15 | 超时、错误报告、日志verbosity和内部状态检查 | 待讨论 |
| D16 | Driver分阶段实现顺序及每阶段smoke测试 | 待讨论 |

## 11. 后续讨论记录模板

后续每确认一个问题，在本部分新增或更新对应小节：

```text
### Dx：问题名称

目标：
最终方案：
采用原因：
关键语法/数据结构：
时序说明：
reset处理：
需要避免的问题：
验收方法：
```

在第二部分完成前，第一部分作为Driver功能设计和组件职责的当前基线。

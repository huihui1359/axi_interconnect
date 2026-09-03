# AXI3 Interconnect UVM验证框架设计决策SPEC

editor：Codex / 项目讨论结论整理
date：2026-09-04
版本号：v1

## 迭代记录

| 版本 | 日期 | 迭代原因 | 迭代内容 |
|---|---|---|---|
| v1 | 2026-09-04 | 将验证架构、transaction、约束、Driver职责等阶段性讨论沉淀为统一实现依据 | 汇总已经确认的架构边界、请求/响应对象设计、场景分工、已完成代码和后续实施顺序 |

## 1. 文档目的

本文档总结三主三从AXI3 Interconnect验证环境搭建过程中已经重点讨论并确认的工程决策，同时记录当前已经完成的代码和后续实现边界。

本文档不替代完整验证计划和transaction详细设计：

- 项目功能范围和测试点以[axi3_interconnect_testplan.md](./axi3_interconnect_testplan.md)为依据。
- 请求和响应事务的字段、约束及代码行为以[transaction_spec.md](./transaction_spec.md) v3为依据。
- 本文档作为验证框架搭建阶段的总体设计决策和状态基线。

原Testplan第5.1节仍记录了请求、响应混合在一个sequence item中的早期建议。该部分已经被本次讨论修订；发生冲突时，以本文档和`transaction_spec.md` v3的请求/响应分离设计为准。

## 2. DUT和验证范围基线

| 项目 | 当前基线 |
|---|---|
| 上游端口 | 3个Master，M0～M2 |
| 下游端口 | 3个Slave，S0～S2 |
| 协议范围 | 赛题裁剪后的AXI3数据传输子集 |
| 地址宽度 | 32 bit |
| 数据宽度 | 32 bit |
| 上游ID宽度 | 4 bit |
| 下游扩展ID宽度 | 当前为8 bit |
| `AWLEN/ARLEN` | 4 bit，编码值为`beats-1` |
| 最大burst长度 | 16 beats |
| outstanding | 每个Master最多4笔读和4笔写，分别统计 |
| 顺序要求 | 同ID保序，不同ID允许乱序 |
| 交织要求 | 支持AXI3写数据交织和读数据交织 |
| 4KB规则 | 正常burst不得跨4KB |

当前地址映射为：

| 目标 | 地址范围 |
|---|---|
| S0 | `0x0000_0000～0x0000_0FFF` |
| S1 | `0x0000_2000～0x0000_2FFF` |
| S2 | `0x0000_4000～0x0000_4FFF` |
| Default | 其他未映射地址，期望返回DECERR |

验证首先采用黑盒端到端方法。Reference model和scoreboard根据外部接口实际握手独立计算期望，不能读取DUT内部grant、select、FIFO指针或状态机生成expected。后续可以用bind assertion增加灰盒定位能力，但不能改变黑盒判定结果。

## 3. 验证环境总体架构

已确认的目标架构如下：

```text
axi_base_test
└── axi_env
    ├── mst_agent[0:2]                     active
    │   ├── axi_m_sequencer
    │   ├── axi_m_driver
    │   └── axi_m_monitor
    ├── slv_agent[0:2]                     reactive active
    │   ├── axi_s_sequencer
    │   ├── axi_s_driver
    │   └── axi_s_monitor
    ├── axi_virtual_sequencer
    ├── axi_xbar_ref_model
    ├── axi_arbiter_checker
    ├── axi_outstanding_order_tracker
    ├── axi_scoreboard
    └── axi_funcov

tb_top
├── axi_interface
├── DUT
├── clock/reset
└── axi_protocol_assertions
```

### 3.1 Agent划分决策

- 每个agent只对应一个物理AXI端口，不在agent内部同时处理三个Master或三个Slave。
- 三个Master agent均为active agent，分别拥有sequencer、driver和monitor。
- 三个Slave agent为reactive active agent，也分别拥有sequencer、driver和monitor。
- Master driver在DUT上游侧驱动请求并控制响应READY。
- Slave driver在DUT下游侧驱动请求READY，并根据响应计划驱动B/R响应。
- 两侧monitor只采样实际握手，不能使用Driver意图代替真实接口行为。

### 3.2 数据流和组件边界

| 组件 | 核心职责 | 明确不负责的内容 |
|---|---|---|
| Sequence | 产生事务场景和定向组合 | 驱动VALID/READY、维护scoreboard状态 |
| Driver | 将事务稳定地驱动到接口 | 地址译码、功能比较、coverage采样 |
| Monitor | 采集真实握手并重建事务 | 根据sequence意图补造传输 |
| Reference model | 预测路由、ID关联和协议语义 | 读取DUT内部仲裁状态 |
| Arbiter checker | 判断候选请求中谁应先被服务 | 完整payload数据比较 |
| Outstanding tracker | 跟踪深度、ID顺序和完成关系 | 驱动接口 |
| Scoreboard | 端到端比较、丢失/重复/串扰检查 | 控制激励时序 |
| Assertion | 检查周期级协议规则 | 替代transaction合法生成约束 |

## 4. Transaction对象决策

### 4.1 请求和响应分离

当前采用两个核心事务对象：

```text
axi_req_item    一笔完整读请求或写请求burst
axi_rsp_item    与已接收请求对应的一笔B响应或完整R响应burst
```

不再使用请求与响应混合的`axi_seq_item`。主要原因是：

- AXI请求和响应的发生时间及生命周期不同。
- 一笔请求可能在多个周期以后才收到响应。
- 每个Master允许多笔outstanding。
- 不同ID允许乱序响应，同ID需要按顺序匹配。
- Driver提前`item_done()`后，sequence可能复用原对象句柄。
- 在原请求对象上异步填写响应容易造成并发修改和对象归属混乱。

请求完成握手以后应保持为稳定快照；响应到达时创建独立响应对象，并按照端口、方向和ID与outstanding请求匹配。

### 4.2 请求事务内容

`axi_req_item`包含：

- 请求方向：`dir`。
- 地址通道属性：`id/addr/len/size/burst`。
- 写payload：`wdata[]/wstrb[]`。
- 请求时序意图：`addr_delay/w_start_delay/wbeat_gap[]`。

一个请求对象只表示一个端口上的一个burst，不包含三组端口数组，也不保存interface信号、virtual interface或DUT内部状态。

写通道派生关系为：

```text
WID   = req.id
WLAST = (beat_index == req.len)
```

### 4.3 响应事务内容

`axi_rsp_item`包含：

- 与请求关联的非随机字段：`dir/id/len`。
- 读响应：`rdata[]/rresp[]`。
- 写响应：`bresp`。
- 响应时序：`rsp_delay/rbeat_gap[]`。

reactive Slave sequence先复制请求关联信息，再随机化响应payload和时序。`RLAST`由Slave driver根据`len`和beat index派生，不作为独立随机字段。

响应类通过`ID_WIDTH`参数同时支持：

- 上游4-bit原始ID响应对象。
- 下游8-bit扩展ID响应对象。

当前请求模型没有exclusive access属性，因此响应随机约束不产生EXOKAY。

### 4.4 两个事务是否足够

`axi_req_item`和`axi_rsp_item`已经足够开始搭建sequencer、driver、monitor、agent、environment和基础scoreboard，不需要继续创建新的驱动型sequence item。

同一类型可以在激励和功能观察路径复用：

| 位置 | 使用对象 |
|---|---|
| Master sequence到Master driver | `axi_req_item` |
| Slave monitor重建下游请求 | 参数化的`axi_req_item` |
| Slave response sequence到Slave driver | `axi_rsp_item` |
| Master侧收集返回响应 | 参数化的`axi_rsp_item` |

以后是否增加以下观察对象，由实际检查需求决定，不是当前框架的前置条件：

- `axi_channel_obs`：记录一次AW/W/B/AR/R握手、端口、方向、cycle和4-state接口值。
- `axi_txn_obs`：保存monitor/tracker匹配完成的完整端到端事务。

基础scoreboard也可以直接接收请求流和响应流，在内部完成匹配，不强制要求`axi_txn_obs`。

## 5. Transaction与信号时序的边界

### 5.1 不放入transaction的信号

以下内容不是事务随机字段：

- `AWVALID/AWREADY`
- `WVALID/WREADY`
- `BVALID/BREADY`
- `ARVALID/ARREADY`
- `RVALID/RREADY`
- `WLAST/RLAST`
- interface句柄和DUT内部状态

Transaction描述“发送什么”及“开始发送前希望等待多少周期”；Driver负责“怎样按照AXI协议完成握手”。

### 5.2 Driver必须保证的行为

- VALID不能依赖READY才拉高。
- VALID拉高且尚未握手时，VALID和payload必须保持稳定。
- AW与W使用独立发送时序，允许AW先发、W先发或并行发送。
- 读请求使用AR通道；写请求分别调度AW和W通道。
- WID和WLAST从请求内容派生，不能再次随机化。
- Slave driver从响应对象派生BID/RID/RLAST。
- Driver不能重新随机化、静默修正或丢弃sequence提供的item。
- Driver不负责判断DUT功能是否正确。

如果Driver在响应返回前调用`item_done()`并把请求保存到内部队列，必须先clone/copy，再保存独立快照。当前事务保留`uvm_field_*`自动化注册，以支持`copy/clone/compare/print`。

## 6. Transaction约束决策

### 6.1 基础约束的职责

正常transaction的基础约束负责生成协议合法且内部一致的请求：

- 合法`size`和burst类型。
- WRAP长度只能为2、4、8、16 beats，对应`len=1/3/7/15`。
- WRAP首地址按单beat字节数对齐。
- 写数据、WSTRB和beat gap数组长度为`len+1`。
- 读请求不携带写payload数组。
- 正常随机INCR burst不跨4KB。
- WSTRB不得在当前beat非法byte lane上置位。

约束不是接口检查器，但正常随机激励不能依靠assertion来过滤大量由验证环境自身产生的非法请求。

### 6.2 WSTRB处理决策

全0 WSTRB是合法AXI写传输，基础transaction允许全0、部分有效和全部有效的合法WSTRB。

`calc_legal_wstrb_mask()`保留为请求类的`local`函数。它不是面向Driver或checker的公开协议检查函数，只为`c_wstrb`计算窄传输、非对齐传输以及不同burst beat对应的合法byte lane。

如果删除该函数及约束，随机WSTRB会在窄传输和非对齐场景中频繁越过合法lane。将这部分计算分散到每个sequence也会造成重复实现，因此当前决定保留该内部辅助函数。

### 6.3 已移除的内容

请求对象已经移除：

- `allow_unaligned`
- `force_4k_cross`
- `allow_zero_wstrb`
- `addr_region`
- `data_pattern`
- `rdata[]/rresp[]/bresp`
- `txn_uid/port_index`
- 面向检查的4KB、对齐和beat地址公开函数
- `post_randomize()`数据pattern处理

删除这些内容的原则是：基础事务保持正常协议合法；特殊场景由sequence描述；响应使用独立对象；接口违规由assertion/checker观察真实信号后报告。

## 7. Test、Sequence、Transaction分工

### 7.1 Test

Test负责：

- 创建和配置环境。
- 设置agent active/passive模式、backpressure策略和超时。
- 选择并启动virtual sequence或端口sequence。
- 控制测试结束和检查队列是否排空。

Test不负责逐字段构造每个AXI请求。

### 7.2 Sequence

Sequence负责描述具体激励场景，例如：

- 访问S0/S1/S2/Default地址区域。
- 对齐或合法非对齐传输。
- 全0、全1、walking-1或地址相关数据。
- 指定WSTRB模式。
- 单Master或多Master并发。
- outstanding深度、ID组合、乱序和交织场景。
- 定向错误响应和跨4KB负向输入。

合法场景优先使用基础transaction加inline constraint；场景选择不通过打开或关闭transaction内部协议规则完成。

### 7.3 跨4KB负向场景

正常请求的4KB约束永久有效。跨4KB负向sequence不调用正常`randomize()`，而是直接完整填写一笔只违反4KB规则的请求，并自行设置动态数组。

该测试需要：

- 保证除4KB外的其他属性合法。
- Driver忠实发送请求，不重新随机化或丢弃。
- 对输入侧预期触发的4KB assertion进行定向waiver或expected-failure处理。
- 保持DUT输出侧检查开启。
- 检查请求未被转发到正常Slave，并检查DUT返回DECERR。

## 8. Monitor、Scoreboard与Assertion边界

### 8.1 Monitor

- 只在`VALID && READY`时采样通道事件。
- 写请求需要根据AW上下文和WID/WLAST重建。
- 读响应需要根据RID/RLAST重建。
- Monitor产生的对象表示实际观察值，不继承Driver未发生的意图。

复用`axi_req_item`作为观察对象时，`addr_delay/w_start_delay/wbeat_gap[]`不属于功能payload。Scoreboard必须逐字段比较协议内容，或者后续将这些自动化字段设置为`UVM_NOCOMPARE`，不能直接把激励delay作为DUT功能比较项。

### 8.2 Scoreboard和Tracker

- 按端口、方向和ID保存outstanding上下文。
- 同ID按照请求接受顺序匹配。
- 不同ID允许按照实际返回顺序匹配。
- 不能使用全局先入先出队列强制所有ID同序。
- 写数据路由根据已接受AW地址以及Master/WID上下文预测，不能照搬当前RTL的`WID[3:2]`选Slave行为。
- 检查地址、数据、WSTRB、ID、RESP、LAST、路由、丢失、重复和串扰。

### 8.3 Assertion

后续独立assert文件负责周期级协议检查，至少包括：

- VALID等待READY期间的payload稳定性。
- AW/AR属性、WRAP、SIZE和4KB合法性。
- WLAST/RLAST与beat数量一致。
- B/R响应必须依赖已接受请求。
- B/R stall期间ID、RESP、DATA和LAST稳定。
- reset期间及释放后的接口行为。

多outstanding、同ID保序、不同ID乱序、地址译码和端到端数据正确性主要由tracker/reference model/scoreboard完成，不塞进单笔transaction的函数中。

## 9. 当前已完成工作

### 9.1 文档

- 已读取并整理历史交互：[conversation_handoff_summary.md](./conversation_handoff_summary.md)。
- 已确认完整验证计划：[axi3_interconnect_testplan.md](./axi3_interconnect_testplan.md)。
- 已完成请求/响应详细设计：[transaction_spec.md](./transaction_spec.md) v3。
- 已生成本文档，作为当前验证框架设计决策和进度基线。

### 9.2 代码

```text
dv/
├── common/
│   └── axi_types_pkg.sv
└── env/
    ├── axi_env_pkg.sv
    ├── axi_req_item.sv
    └── axi_rsp_item.sv
```

已经完成：

- AXI方向、burst、response等公共enum和默认宽度定义。
- 独立请求事务及正常请求合法性约束。
- 独立响应事务及响应payload、时序约束。
- 请求/响应对象的UVM factory注册和字段自动化。
- 环境package中的正确include顺序。
- 删除旧的请求/响应混合`axi_seq_item.sv`。

### 9.3 已完成验证

当前事务代码已使用Questa UVM 1.1d完成编译和最小随机化验证：

- 500轮随机读写请求和对应响应均成功求解。
- 写请求和读响应动态数组尺寸正确。
- 正常随机INCR请求满足4KB约束。
- 响应不随机产生EXOKAY。
- 请求和响应对象的clone/compare通过。
- 编译结果为0 errors、0 warnings。

临时仿真文件和work库已经清理，没有作为项目代码保留。

## 10. 尚未完成的工作

当前完成的是新`dv`验证环境的transaction基础，不代表完整UVM环境已经建立。以下组件尚待实现：

- AXI interface及clocking block/modport。
- Master/Slave agent配置对象和总环境配置。
- Master/Slave sequencer。
- Master/Slave driver及READY/backpressure策略。
- 上下游五通道monitor和事务重建逻辑。
- 三组Master/Slave agent和`axi_env`。
- virtual sequencer及基础sequence/test。
- reference model、outstanding tracker、arbiter checker和scoreboard。
- protocol assertions、functional coverage和回归测试。

仓库中旧`uvm_tb`目录的历史环境不能视为新`dv`框架已经完成；后续实现应按本文档和当前Testplan重新建立职责清晰的组件，必要时仅参考其接口连接方式。

## 11. 建议的下一步实施顺序

按照自底向上的搭建方式，建议顺序为：

1. 定义新环境使用的AXI interface、clocking block和端口方向。
2. 定义Master/Slave agent配置及统一`axi_env_cfg`。
3. 实现请求/响应sequencer类型。
4. 实现单端口Master driver，先支持单拍读写，再扩展burst和并发通道。
5. 实现单端口reactive Slave driver和最简单OKAY响应路径。
6. 组装Master/Slave agent和三主三从env，跑通基础smoke。
7. 实现上下游monitor和请求/响应重建。
8. 加入基础protocol assertions。
9. 实现route reference model、outstanding tracker和scoreboard。
10. 最后扩展仲裁、乱序、交织、负向测试和覆盖率。

进入Driver设计前仍需具体确定内部线程、队列、`item_done()`时机、响应返回方式和reset清队列策略，但这些实现细节不得改变本文档已经确认的transaction职责边界。

## 12. 当前阶段完成判定

当前transaction阶段的完成条件已经满足：

- 请求和响应对象职责分离。
- 正常随机请求具有基础协议合法性约束。
- 特殊场景与协议约束职责分离。
- Driver、Monitor、Assertion和Scoreboard边界明确。
- 两个事务通过独立编译、随机化和对象操作验证。

下一阶段可以直接开始interface、配置对象和Driver框架设计，不需要先新增其他驱动事务类型。

# AXI3 Interconnect Transaction 设计规范

editor：Codex / 项目讨论结论整理
date：2026-09-04
版本号：v3

## 迭代记录

| 版本 | 日期 | 为什么迭代 | 迭代内容 |
|---|---|---|---|
| v3 | 2026-09-04 | 请求和响应生命周期不同，且AXI支持多笔outstanding和不同ID乱序返回，不适合异步修改同一个对象 | 将原`axi_seq_item`拆分为`axi_req_item`和`axi_rsp_item`；从请求对象中移除响应、地址区域、数据模式和调试字段，并删除协议检查类辅助函数；新增独立响应payload及响应时序约束 |
| v2 | 2026-09-04 | 区分正常transaction的协议约束与sequence的场景控制，避免通过item开关关闭正常协议规则 | 删除对齐、跨4KB和全0 WSTRB控制开关；正常item永久满足4KB规则，合法定向场景由inline constraint选择，跨4KB负向场景由专用sequence直接构造 |
| v1 | 2026-09-03 | 首次将Testplan中的事务建模要求落地 | 定义transaction字段、约束、辅助方法、代码目录和验收标准 |

## 1. 文档目的

本文档定义三主三从AXI3 Interconnect验证环境中请求、响应transaction的职责、字段、约束、时序语义及文件组织方式，是`axi3_interconnect_testplan.md`中事务建模部分的落地设计。

本次实现采用请求和响应分离的模型。请求对象在完成请求握手后保持不变；返回响应使用新对象表示，再通过端口和ID与outstanding请求匹配。这样可以避免sequence复用对象、Driver并发线程以及不同ID乱序响应造成的数据覆盖。

## 2. 代码目录约定

```text
dv/
├── common/
│   └── axi_types_pkg.sv       公共常量、enum和typedef
└── env/
    ├── axi_env_pkg.sv         环境package入口及文件编译顺序
    ├── axi_req_item.sv        Master请求事务
    ├── axi_rsp_item.sv        Slave响应计划/返回响应事务
    ├── axi_env_cfg.sv         后续：环境配置
    ├── axi_m_agent.sv         后续：Master agent
    ├── axi_m_driver.sv        后续：Master driver
    ├── axi_m_monitor.sv       后续：Master monitor
    ├── axi_s_agent.sv         后续：Slave agent
    ├── axi_s_driver.sv        后续：Slave driver
    ├── axi_s_monitor.sv       后续：Slave monitor
    ├── axi_channel_obs.sv     后续：通道握手观察对象
    ├── axi_txn_obs.sv         后续：monitor重建的完整事务
    ├── axi_xbar_ref_model.sv  后续：路由参考模型
    └── axi_scoreboard.sv      后续：端到端scoreboard
```

公共协议类型在`dv/common/axi_types_pkg.sv`中定义。编译时先编译该package，再编译`axi_env_pkg.sv`；后者依次include请求和响应事务。使用者通过`import axi_env_pkg::*;`访问事务类型。

原`axi_seq_item.sv`已经删除，不再保留请求与响应混合的兼容类，避免新代码继续使用旧模型。

## 3. 对象划分与数据流

| 对象 | 主要生产者 | 主要消费者 | 表示内容 |
|---|---|---|---|
| `axi_req_item` | Master sequence | Master driver | 一个Master端口发起的一笔完整读或写burst请求 |
| `axi_rsp_item` | reactive Slave sequence；也可由Master侧响应收集逻辑产生 | Slave driver；请求sequence | 与一笔已接收请求对应的B或完整R burst响应 |
| `axi_channel_obs` | monitor | tracker/checker/coverage | 一次AW/W/B/AR/R实际握手，保留接口观测值 |
| `axi_txn_obs` | monitor重建逻辑 | reference model/scoreboard | 根据实际握手匹配完成的端到端完整事务 |

典型生命周期如下：

```text
axi_req_item创建并驱动
        ↓
请求完成握手，按端口、方向和ID登记outstanding
        ↓
独立axi_rsp_item返回
        ↓
按端口和ID匹配请求与响应
        ↓
monitor/tracker生成axi_txn_obs供scoreboard检查
```

请求与响应分开并不意味着所有位置都必须同时创建四种对象。`axi_channel_obs`和`axi_txn_obs`在实现monitor与scoreboard时再增加。

## 4. `axi_req_item`设计

### 4.1 基本原则

- 一个请求对象只表示一个Master端口上的一笔完整burst。
- 对象保存请求payload和发送时序意图，不保存virtual interface、DUT内部状态或三组端口信号数组。
- `VALID/READY`不是随机字段，由Driver按照协议驱动。
- 响应数据不写回请求对象；请求进入Driver内部并发队列前需要保留稳定快照。

### 4.2 参数和字段

| 类别 | 字段 | 随机 | 含义 |
|---|---|---|---|
| 参数 | `ADDR_WIDTH` | 否 | 地址宽度，默认32 |
| 参数 | `DATA_WIDTH` | 否 | 数据宽度，默认32 |
| 参数 | `ID_WIDTH` | 否 | 上游原始ID宽度，默认4 |
| 参数 | `LEN_WIDTH` | 否 | `AxLEN`宽度，默认4 |
| 请求属性 | `dir` | 是 | `AXI_READ`或`AXI_WRITE` |
| 请求属性 | `id` | 是 | 请求ID |
| 请求属性 | `addr` | 是 | burst首地址 |
| 请求属性 | `len` | 是 | AXI编码值，实际beat数为`len+1` |
| 请求属性 | `size` | 是 | 每beat字节数的编码 |
| 请求属性 | `burst` | 是 | FIXED、INCR或WRAP |
| 写payload | `wdata[]` | 是 | 每个W beat的数据 |
| 写payload | `wstrb[]` | 是 | 每个W beat的字节有效掩码 |
| 请求时序 | `addr_delay` | 是 | AW/AR首次拉高VALID前的等待周期数 |
| 请求时序 | `w_start_delay` | 是 | W通道开始发送前的独立等待周期数 |
| 请求时序 | `wbeat_gap[]` | 是 | 每个W beat发送前的空闲周期数 |

Master driver根据`dir`将统一属性映射到AW或AR通道。正常写请求中：

```text
WID   = req.id
WLAST = (beat_index == req.len)
```

`addr_delay`和`w_start_delay`独立，使Driver能够产生AW先于W、W先于AW以及二者并行的场景。delay仅在对应VALID拉高前生效；VALID拉高后必须保持VALID及payload直到握手。

### 4.3 请求约束

请求类保留“生成正常合法事务”所必需的约束：

- `size`不超过数据总线支持的最大传输字节数；当前32-bit数据宽度下合法值为0、1、2。
- `burst`只允许FIXED、INCR、WRAP。
- WRAP的`len`只能为1、3、7、15，首地址按单beat字节数对齐。
- 写请求的`wdata[]`、`wstrb[]`和`wbeat_gap[]`长度均为`len+1`；读请求中三者为空。
- 每个WSTRB只能在对应beat合法byte lane上置位；全0 WSTRB仍然合法。
- 通过`randomize()`生成的正常INCR请求不得跨4KB边界。
- burst类型、长度、传输宽度和delay具有基础随机分布。

地址映射区域和数据pattern已经从transaction删除。访问S0/S1/S2/Default、全0/全1/walking-1等场景由相应sequence通过inline constraint或赋值实现，reference model仍以实际接口地址和数据为准。

### 4.4 保留的方法

| 方法 | 用途 |
|---|---|
| `beat_count()` | 返回请求beat数`len+1`，供Driver循环使用 |
| `convert2string()` | 输出精简的请求调试信息 |
| `calc_legal_wstrb_mask()` | 私有约束辅助函数，仅用于计算WSTRB合法lane |

原来的`bytes_per_beat()`、`beat_address()`、公开`legal_wstrb_mask()`、`burst_is_4k_legal()`、`calc_address_is_aligned()`、`calc_burst_is_4k_legal()`和`post_randomize()`已经删除。协议检查不再依赖transaction中的检查函数。

## 5. `axi_rsp_item`设计

### 5.1 基本原则

一个响应对象表示一笔写响应B，或者一笔完整读响应R burst。响应必须来源于已经接受的请求，不能自行产生不匹配的ID、方向或读burst长度。

`dir`、`id`和`len`是非随机关联字段。reactive response sequence应先从已接收请求复制它们，再调用`randomize()`生成响应payload和响应时序：

```text
rsp.dir = req.dir
rsp.id  = req.id
rsp.len = req.len
rsp.randomize()
```

对于下游Slave agent，`ID_WIDTH`应配置为DUT下游扩展ID宽度；对于上游Master侧返回对象，则使用上游原始ID宽度。

### 5.2 字段

| 类别 | 字段 | 随机 | 含义 |
|---|---|---|---|
| 关联信息 | `dir` | 否 | 关联请求方向 |
| 关联信息 | `id` | 否 | 关联请求ID |
| 关联信息 | `len` | 否 | 读响应beat数依据 |
| 读响应 | `rdata[]` | 是 | 每个R beat的数据 |
| 读响应 | `rresp[]` | 是 | 每个R beat的响应码 |
| 写响应 | `bresp` | 是 | 写响应码 |
| 响应时序 | `rsp_delay` | 是 | B或第一个R beat开始发送前的等待周期数 |
| 响应时序 | `rbeat_gap[]` | 是 | 相邻R beat之间的空闲周期数 |

读响应满足：

```text
rdata.size()     = len + 1
rresp.size()     = len + 1
rbeat_gap.size() = len
```

`rbeat_gap[i]`表示第`i`个R beat与第`i+1`个R beat之间的间隔。写响应的读数组为空。`RLAST`由Slave driver根据数组末尾派生，不作为事务字段：

```text
RLAST = (beat_index == rsp.len)
```

### 5.3 响应约束

- 当前请求模型不包含exclusive access，因此响应不随机产生`EXOKAY`。
- `rresp[]`和`bresp`允许OKAY、SLVERR、DECERR，默认提高OKAY权重。
- `rsp_delay`和`rbeat_gap[]`默认以短延迟为主，并保留少量长延迟。
- READY由接收方agent的策略控制，不属于响应item。

Slave response sequence可以用inline constraint覆盖默认响应分布。例如普通memory Slave固定返回OKAY；错误注入sequence可指定某个R beat返回SLVERR。

## 6. Sequence、Driver和响应匹配分工

- Test负责配置环境、选择并启动sequence。
- Master sequence创建`axi_req_item`，并用inline constraint描述地址区域、对齐方式、数据pattern等场景。
- Master driver只负责将请求映射到AW/W/AR通道，不重新随机化事务。
- reactive Slave sequence根据Slave monitor实际接收的请求创建`axi_rsp_item`。
- Slave driver根据响应对象驱动B/R通道，并由`id`和`len`派生BID/RID/RLAST。
- outstanding tracker按端口、方向和ID匹配请求和响应；同ID按接受顺序匹配，不同ID允许乱序。
- monitor观察结果进入scoreboard，不以Driver内部对象代替真实接口采样。

如果Master driver在请求完全返回前就调用`item_done()`并缓存请求，必须clone/copy请求后再入队，不能继续持有sequence可能复用的原始句柄。返回给sequence时应创建独立`axi_rsp_item`，而不是修改原请求。

## 7. 定向与负向场景

- 对齐传输：sequence调用`req.randomize()`并inline约束地址按`1<<size`对齐。
- 非对齐传输：sequence选择FIXED/INCR、`size>0`并inline约束地址非对齐。
- 指定地址区域：sequence直接约束`addr`落入S0/S1/S2/Default范围。
- 指定数据pattern：sequence在随机化后填写或inline约束`wdata[]`。
- 跨4KB负向传输：不调用正常请求的`randomize()`，由专用sequence完整赋值，保证除目标4KB违规外其他属性合法。

直接赋值构造负向请求不会自动创建动态数组，sequence必须自行填写`wdata[]`、`wstrb[]`和`wbeat_gap[]`。

## 8. Transaction约束与Assertion边界

Transaction约束用于生成合法、内部一致的正常激励；assertion/checker用于检查接口上真实发生的行为。两者不能互相替代。

后续独立assert文件至少检查：

- VALID拉高且未握手时，VALID和payload保持稳定。
- AW/AR属性合法，WRAP长度和对齐合法，正常burst不跨4KB。
- WLAST/RLAST与实际beat数量一致。
- B响应只在对应写请求/写数据被接受后发生，R响应只对应已接受的AR。
- B/R响应stall期间ID、RESP、DATA和LAST保持稳定。
- reset期间及reset释放后的通道行为符合约定。

多outstanding、同ID保序、不同ID乱序、地址译码、ID扩展恢复和端到端数据正确性属于tracker/reference model/scoreboard检查，不放入单笔transaction函数。

## 9. UVM对象操作

- 两个对象均注册UVM factory。
- 当前使用`uvm_field_*`自动化字段的`copy/clone/compare/print`。
- Driver异步保存请求或响应时，应clone/copy后保存独立快照。
- 随机激励字段使用2-state `bit`；后续monitor观察对象应使用能够保留X/Z的4-state类型。

## 10. 验收标准

1. 大量随机读写请求均可求解。
2. 写请求数组长度始终为`len+1`，读请求写数组为空。
3. 正常随机INCR请求均满足4KB规则。
4. WRAP长度和首地址对齐合法。
5. 每个WSTRB不超出对应beat的合法byte lane，且允许全0 WSTRB。
6. 读响应数组为`len+1`，R beat间隔数组为`len`；写响应读数组为空。
7. 响应ID、方向和读长度在随机化后保持与请求一致。
8. 当前响应模型不产生EXOKAY。
9. 两种事务的`clone/copy/compare/print`行为正确。
10. 定向sequence可以生成指定区域、数据pattern、对齐/非对齐和跨4KB负向请求。

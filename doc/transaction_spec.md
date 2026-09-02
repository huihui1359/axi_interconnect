# AXI3 Interconnect Transaction 设计规范

editor：Codex / 项目讨论结论整理  
date：2026-09-03  
版本号：v1

## 1. 文档目的

本文档定义三主三从AXI3 Interconnect验证环境中transaction对象的职责、字段、约束、派生方法、时序控制语义及文件组织方式。本文档是`axi3_interconnect_testplan.md`中事务建模部分的落地设计。

当前实现首先服务于上游active Master agent。Slave响应计划、monitor通道观察对象和完整观察事务在后续阶段使用独立类型实现，不把所有角色塞进同一个sequence item。

## 2. 代码目录约定

后续验证代码统一放在`dv`目录下：

```text
dv/
├── common/
│   └── axi_types_pkg.sv       公共常量、enum和typedef
└── env/
    ├── axi_env_pkg.sv         环境package入口及文件编译顺序
    ├── axi_seq_item.sv        Master请求sequence item
    ├── axi_env_cfg.sv         后续：环境配置
    ├── axi_m_agent.sv         后续：Master agent
    ├── axi_m_driver.sv        后续：Master driver
    ├── axi_m_monitor.sv       后续：Master monitor
    ├── axi_s_agent.sv         后续：Slave agent
    ├── axi_s_driver.sv        后续：Slave driver
    ├── axi_s_monitor.sv       后续：Slave monitor
    ├── axi_slave_rsp_item.sv  后续：Slave响应计划
    ├── axi_channel_obs.sv     后续：通道握手观察对象
    ├── axi_txn_obs.sv         后续：monitor重建的完整事务
    ├── axi_xbar_ref_model.sv  后续：路由参考模型
    └── axi_scoreboard.sv      后续：端到端scoreboard
```

公共协议类型只能在`dv/common/axi_types_pkg.sv`中定义一次。UVM组件和与环境实现直接相关的对象放在`dv/env`中。编译时必须先编译`axi_types_pkg.sv`，再编译`axi_env_pkg.sv`；`axi_env_pkg.sv`按照依赖顺序include `axi_seq_item.sv`及后续环境类，使用者通过`import axi_env_pkg::*;`访问这些类型。

## 3. 对象划分

验证环境采用以下对象边界：

| 对象 | 生产者 | 消费者 | 表示内容 |
|---|---|---|---|
| `axi_seq_item` | Master sequence | Master driver | 一个Master发起的一笔完整读或写burst |
| `axi_slave_rsp_item` | 后续reactive response sequence | Slave driver | 对已实际接收请求的响应计划 |
| `axi_channel_obs` | monitor | ref model/checker/coverage | 一次AW/W/B/AR/R实际握手 |
| `axi_txn_obs` | monitor重建逻辑 | scoreboard | 根据实际握手重建的完整事务 |

上述内容是四种类型，不表示每发起一笔请求都必须同时创建四个对象。当前只实现`axi_seq_item`；观察对象由monitor按实际握手按需创建。

## 4. `axi_seq_item`语义

### 4.1 基本原则

- 一个Master agent只处理一个上游端口。
- 一个`axi_seq_item`只表示该端口的一笔完整burst。
- item中不得出现保存三个Master或三个Slave的`[0:2]`信号数组。
- item保存事务payload和发送时序意图，不保存virtual interface或DUT内部状态。
- `VALID/READY`握手行为由driver实现，不作为item随机字段。

### 4.2 参数

| 参数 | 默认值 | 含义 |
|---|---:|---|
| `ADDR_WIDTH` | 32 | 地址宽度 |
| `DATA_WIDTH` | 32 | 数据宽度 |
| `ID_WIDTH` | 4 | 上游原始ID宽度 |
| `LEN_WIDTH` | 4 | `AxLEN`宽度 |

不得通过`DATA_WIDTH/8`或`DATA_WIDTH/4`推导ID和LEN宽度。当前项目的`AxLEN`固定为4 bit，编码值表示`beats-1`。

### 4.3 请求字段

| 字段 | 随机 | 含义 |
|---|---|---|
| `dir` | 是 | 读或写 |
| `id` | 是 | 上游4-bit原始ID |
| `addr` | 是 | burst首地址 |
| `len` | 是 | AXI编码值，实际beat数为`len+1` |
| `size` | 是 | 每beat字节数编码，合法值0/1/2 |
| `burst` | 是 | FIXED/INCR/WRAP |

统一字段由Master driver根据`dir`映射到AW或AR通道。避免同时保存两套可能互相矛盾的AW和AR属性。

### 4.4 写数据字段

| 字段 | 随机 | 含义 |
|---|---|---|
| `wdata[]` | 是 | 每个W beat的数据 |
| `wstrb[]` | 是 | 每个W beat的字节有效掩码 |

写事务满足：

```text
wdata.size() = len + 1
wstrb.size() = len + 1
```

正常事务不单独随机化`WID`和`WLAST`：

```text
WID   = item.id
WLAST = (beat_index == item.len)
```

### 4.5 响应结果字段

`rdata[]`、`rresp[]`和`bresp`为非随机字段，可供Master driver在需要向sequence返回response时填写。它们不能代替monitor观察结果进入scoreboard。

### 4.6 时序控制字段

| 字段 | 含义 |
|---|---|
| `addr_delay` | item进入driver发送队列后，AW或AR开始发送前等待的完整周期数 |
| `w_start_delay` | item进入driver发送队列后，W通道开始发送前独立等待的完整周期数 |
| `wbeat_gap[]` | 每个W beat允许开始发送前的空闲周期数 |

`addr_delay`与`w_start_delay`必须独立解释，使driver能够生成AW先于W、W先于AW及二者并行的场景。

delay只在对应VALID尚未拉高时生效。一旦VALID拉高，driver必须忽略后续delay变化，并保持VALID及payload直到握手。

BREADY和RREADY属于整个返回通道的策略，不属于某一笔item，后续放入Master agent配置或独立ready控制策略中。

### 4.7 激励生成辅助字段

| 字段 | 含义 |
|---|---|
| `addr_region` | 生成S0/S1/S2/Default区域地址的提示 |
| `data_pattern` | 随机、全0、全1、walking-1或地址相关写数据 |
| `allow_unaligned` | 是否允许FIXED/INCR产生合法非对齐首地址 |
| `force_4k_cross` | 是否专门强制生成跨4KB负向事务 |
| `allow_zero_wstrb` | 是否允许全0写掩码 |

`addr_region`只是sequence随机化提示。Reference model和scoreboard必须忽略该提示，根据实际`addr`重新完成地址译码。

## 5. 约束设计

### 5.1 基本属性

- `size`只能为0、1、2，分别表示1、2、4 bytes。
- `burst`只能为FIXED、INCR、WRAP。
- `len`为4 bit，实际支持1～16 beats。
- WRAP的beat数只能为2、4、8、16，即`len=1/3/7/15`。
- WRAP首地址必须按单beat字节数对齐。
- `allow_unaligned=0`时，所有burst首地址按单beat字节数对齐。

### 5.2 4KB规则

普通随机事务必须满足4KB规则；`force_4k_cross=1`时必须生成跨4KB事务。

- INCR：`aligned_start[11:0] + beats * bytes_per_beat <= 4096`。
- FIXED：单beat的全部有效byte lane位于同一4KB页。
- WRAP：完整回绕区域位于同一4KB页。

跨4KB负向模式只改变激励生成，不定义DUT expected；DUT的`DECERR`期望仍由独立reference model预测。

### 5.3 WSTRB规则

每个`wstrb[i]`只能在该beat允许的byte lane上置位。合法lane由首地址、SIZE、BURST和beat index共同决定。

默认不允许全0 WSTRB；专门测试可在randomize前设置`allow_zero_wstrb=1`。约束只保证WSTRB合法，不强制每个beat使用全部合法lane，因此可以覆盖部分字节写。

### 5.4 随机分布

默认分布需要提高以下场景的命中率：

- 单beat和16-beat。
- INCR burst。
- 32-bit全字传输。
- 0～3周期短延迟，同时保留少量长延迟。
- S0/S1/S2均衡访问，并保留较低比例Default访问。

定向sequence可使用inline constraint覆盖默认分布，但不得关闭基础协议合法性约束；协议负向测试除外。

## 6. 派生方法

`axi_seq_item`提供以下纯计算方法：

| 方法 | 用途 |
|---|---|
| `beat_count()` | 返回`len+1` |
| `bytes_per_beat()` | 返回`1<<size` |
| `beat_address(index)` | 计算FIXED/INCR/WRAP指定beat地址 |
| `legal_wstrb_mask(index)` | 计算指定写beat允许的byte lane |
| `burst_is_4k_legal()` | 判断当前burst是否满足4KB规则 |

这些方法不计算目标Slave、扩展ID、仲裁winner或DUT固定延迟。

## 7. 不属于transaction的行为

以下内容必须由driver、virtual sequence、monitor、tracker或checker实现，不能放入单个item约束：

- VALID/READY握手和stall期间稳定性。
- 每Master最多4读、4写outstanding。
- 同ID保序、不同ID乱序。
- 多WID写数据交织和多RID读数据交织。
- Master之间的并发、竞争及round-robin顺序。
- DUT地址译码、ID扩展恢复和Default响应。
- DUT FIFO、grant、select或内部状态。

## 8. 对象操作要求

- 必须注册UVM factory。
- 必须支持`copy/clone/compare/print`。
- Driver在提前调用`item_done()`并将请求放入内部队列前必须clone item。
- `post_randomize()`只生成明确的派生数据模式，不得静默修正非法协议属性。
- 生成字段使用2-state `bit`，避免随机激励无意产生X/Z；monitor观察对象后续使用能够保留X/Z的类型。

## 9. 验收标准

在连接driver之前，transaction至少通过以下独立检查：

1. 大量随机读写item均可求解。
2. 写数组长度始终为`len+1`，读事务写数组为空。
3. 正常事务均满足4KB规则。
4. WRAP长度、起始对齐和beat地址正确。
5. 每个WSTRB不超出合法byte lane。
6. S0/S1/S2/Default地址约束正确。
7. `force_4k_cross=1`能够稳定生成跨4KB事务。
8. `clone/copy/compare/print`结果正确。
9. 不同seed能够覆盖预期LEN、SIZE、BURST、区域和delay分布。

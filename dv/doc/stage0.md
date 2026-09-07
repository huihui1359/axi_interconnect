# AXI3 Interconnect UVM验证环境Stage 0执行工单

editor：Codex / 项目讨论结论整理  
date：2026-09-08  
状态：待审核，审核通过前不得实施  

## 1. 文档目的

本文档是[stage.md](./stage.md)中“Stage 0：公共基础和组件契约”的详细执行工单，规定Stage 0需要实现的内容、实现边界和验收方法。

Stage 0的目标不是产生可驱动DUT的完整UVM环境，而是完成后续Driver、Monitor、Agent和Scoreboard共同依赖的类型、配置、接口契约、对象生命周期规则及独立编译基础。Stage 0审核通过后才能开始实施；实施完成并通过本文第二部分验收后，才能进入Stage 1。

本文中的Stage表示项目实施阶段，不是UVM的`build_phase`、`connect_phase`或`run_phase`。

## 2. Stage 0范围

### 2.1 纳入范围

- 公共AXI参数、枚举和typedef。
- `axi_req_item`和`axi_rsp_item`事务模型确认及必要修正。
- 单端口`axi_if`、clocking block和modport确认及必要修正。
- 参数化Master/Slave agent配置对象和环境配置对象。
- 参数化Master/Slave sequencer类型。
- 不同ID宽度对应的virtual interface类型。
- transaction快照、对象所有权和生命周期规则。
- `get_next_item()`、`item_done()`和未来response返回的接口契约。
- 后续Driver长期线程、队列和信号驱动所有权的架构约定。
- delay/gap字段的精确定义。
- reset基础边界。
- package、include顺序、独立文件列表和Stage 0最小测试框架。

### 2.2 不纳入范围

Stage 0不得实现以下内容：

- `axi_m_driver`或`axi_s_driver`类，包括没有总线行为的空Driver骨架。
- Master/Slave Monitor及通道采样逻辑。
- Master/Slave Agent及其connect逻辑。
- DUT接口bridge和三主三从环境组装。
- READY策略的运行状态机。
- AW、W、AR、B、R通道驱动或接收行为。
- burst发送、通道stall、outstanding、乱序和交织调度。
- tracker、reference model、scoreboard、assertion和functional coverage实现。

### 2.3 当前实现基线

开始Stage 0实施前，仓库中已有：

- `dv/common/axi_types_pkg.sv`。
- `dv/env/axi_req_item.sv`。
- `dv/env/axi_rsp_item.sv`。
- `dv/env/axi_env_pkg.sv`。
- `dv/tb/axi_if.sv`。

这些文件属于Stage 0的输入基线，但仍需按照本工单重新检查。仓库中的旧`uvm_tb`环境不是新`dv`环境的实现基线，只能作为历史参考，Stage 0不得从中直接继承旧transaction、interface或组件类型。

# 第一部分：Stage 0实现内容

## 3. S0-01：整理公共AXI类型和项目参数

### 3.1 实现目标

由`axi_types_pkg`统一提供后续环境使用的协议枚举和项目默认参数，其他组件不得重复声明等价类型或使用无含义的数字代替公共枚举。

### 3.2 实现要求

- 保留地址宽度32、数据宽度32和LEN宽度4的当前默认值。
- 区分以下ID宽度：
  - 上游Master端口原始ID宽度为4。
  - 下游Slave端口扩展ID宽度为8。
- 定义Master数量和Slave数量，当前均为3。
- 保留`axi_dir_e`、`axi_burst_e`和`axi_resp_e`作为协议公共类型。
- 保留地址区域和数据pattern枚举供后续sequence/reference model使用，但Driver不得依赖这些场景枚举产生协议行为。
- 定义统一的READY模式枚举：

```text
ALWAYS_READY
RANDOM_READY
SCRIPTED_READY
```

- Stage 0只定义READY模式类型；具体字段、概率、周期窗口和运行状态机在后续Stage实现。
- 参数名称应明确区分通用默认ID宽度、Master ID宽度和Slave ID宽度，避免4-bit与8-bit类型被误用。

### 3.3 预期产物

- 更新后的公共类型package。
- 一份供config、sequencer、interface和后续组件共同使用的唯一类型定义。

## 4. S0-02：确认请求和响应Transaction

### 4.1 `axi_req_item`职责

- 一个对象表示一个Master端口发起的一笔完整读或写burst请求。
- 对象只保存请求payload和发送时序意图。
- `VALID`、`READY`、`WID`和`WLAST`不作为随机字段。
- `WID`由Driver使用`id`派生；`WLAST`由Driver使用`len`和当前beat编号派生。
- 写请求的`wdata[]`、`wstrb[]`和`wbeat_gap[]`长度为`len+1`；读请求对应数组为空。
- 保留正常请求所需的SIZE、WRAP、4KB边界和WSTRB合法lane约束。
- 保留`beat_count()`和`convert2string()`。

### 4.2 `axi_rsp_item`职责

- 一个对象表示一笔B写响应或一笔完整R读响应burst。
- `dir`、`id`和`len`是与已接收请求关联的非随机字段。
- `BID`、`RID`和`RLAST`不作为独立随机字段，由Driver根据响应对象派生。
- 读响应的`rdata[]`和`rresp[]`长度为`len+1`，`rbeat_gap[]`长度为`len`。
- 写响应的读数组为空。
- READY不属于响应transaction。
- 当前正常响应不随机产生EXOKAY。

### 4.3 实现要求

- 两类transaction继续采用宽度参数化设计。
- factory注册必须适用于参数化类型。
- 所有动态数组必须参与正确的copy、clone、compare和print操作。
- Driver不得重新随机化、静默修改或丢弃sequence提供的item。
- Stage 0只修正与既有SPEC不一致的问题，不向transaction加入尚未确认的Driver内部状态。

## 5. S0-03：确认单端口Interface契约

### 5.1 实现目标

`axi_if`继续表示一个物理AXI端口，为Master Driver、Slave Driver、Monitor和DUT连接提供方向明确且无采样竞争的访问视角。

### 5.2 实现要求

- Interface继续参数化`ADDR_WIDTH`、`DATA_WIDTH`、`ID_WIDTH`和`LEN_WIDTH`。
- 上游端口使用4-bit ID specialization，下游端口使用8-bit ID specialization。
- `m_drv_cb`只允许Master Driver驱动AW/W/AR请求及BREADY/RREADY。
- `s_drv_cb`只允许Slave Driver驱动AWREADY/WREADY/ARREADY及B/R响应。
- `mon_cb`只能采样，不得驱动任何接口信号。
- 保留DUT上游Slave视角和下游Master视角modport。
- Driver clocking block统一采用：

```systemverilog
default input #1step output #0;
```

- Monitor clocking block统一采用：

```systemverilog
default input #1step;
```

- Interface只传播ACLK和ARESETn，不主动产生reset、VALID或READY。
- 非法宽度参数应在仿真开始时给出明确fatal信息。
- `axi_if.sv`保持独立编译单元，不得include到`axi_env_pkg`内部。

## 6. S0-04：实现参数化Agent配置对象

### 6.1 Master Agent配置

新增参数化`axi_m_agent_cfg`，参数至少包括：

```text
ADDR_WIDTH
DATA_WIDTH
ID_WIDTH
LEN_WIDTH
```

配置对象至少保存：

- `uvm_active_passive_enum is_active`。
- `int unsigned port_index`。
- 与当前参数完全匹配的`m_drv_mp` virtual interface句柄。
- 与当前参数完全匹配的`mon_mp` virtual interface句柄。
- BREADY和RREADY模式字段，默认`ALWAYS_READY`。
- 读、写outstanding配置上限，Stage 1默认均限制为1；后续Stage再启用更大数值。

### 6.2 Slave Agent配置

新增参数化`axi_s_agent_cfg`，参数至少包括：

```text
ADDR_WIDTH
DATA_WIDTH
ID_WIDTH
LEN_WIDTH
```

配置对象至少保存：

- `uvm_active_passive_enum is_active`。
- `int unsigned port_index`。
- 与当前参数完全匹配的`s_drv_mp` virtual interface句柄。
- 与当前参数完全匹配的`mon_mp` virtual interface句柄。
- AWREADY、WREADY和ARREADY模式字段，默认`ALWAYS_READY`。

响应容量和SCRIPTED READY脚本对象暂不加入，留到对应机制确定后实现。

### 6.3 配置对象共同要求

- config类采用全参数化方案，不使用固定宽度的非参数化替代类。
- 在config类中为Driver和Monitor virtual interface定义清晰的局部typedef。
- config对象通过factory注册。
- 构造函数设置安全默认值，不在构造函数中访问`uvm_config_db`。
- config对象只保存配置和句柄，不启动线程、不驱动总线。
- `port_index`仅用于配置映射和日志，不允许后续Driver用它索引全局interface数组。

## 7. S0-05：实现参数化环境配置对象

### 7.1 实现目标

新增参数化`axi_env_cfg`，统一保存三组Master agent配置和三组Slave agent配置，但不直接保存供Driver访问的全局interface数组。

### 7.2 实现要求

- 环境配置参数至少包括：

```text
ADDR_WIDTH
DATA_WIDTH
M_ID_WIDTH
S_ID_WIDTH
LEN_WIDTH
NUM_MASTERS
NUM_SLAVES
```

- 默认参数对应当前项目的32-bit地址、32-bit数据、4-bit上游ID、8-bit下游ID以及三主三从。
- 环境配置分别保存Master配置对象数组和Slave配置对象数组。
- 每个子配置对象具有唯一的`port_index`。
- 环境配置负责聚合配置，不负责创建Agent、连接TLM端口或驱动总线。
- 后续`tb_top`和test负责把六个interface实例精确写入对应配置；不得使用会让多个Agent取得同一interface的宽泛通配路径。

## 8. S0-06：实现参数化Sequencer类型

### 8.1 Master Sequencer

- 新增参数化`axi_m_sequencer`。
- 请求类型必须是相同参数specialization的`axi_req_item`。
- response类型接口预留为相同DATA/ID/LEN参数的`axi_rsp_item`。
- 类中不加入总线驱动、响应匹配或outstanding状态。

### 8.2 Slave Sequencer

- 新增参数化`axi_s_sequencer`。
- sequence item类型必须是相同参数specialization的`axi_rsp_item`。
- Stage 0不实现reactive请求FIFO和Monitor连接；相关数据链路在后续Stage结合Monitor和Agent设计。

### 8.3 共同要求

- sequencer通过parameterized factory宏注册。
- sequencer只提供类型正确的sequence—Driver通信端点。
- Stage 0不创建Driver，因此本阶段不建立`seq_item_port`连接。

## 9. S0-07：确定Transaction快照和对象所有权

后续组件必须遵循以下所有权规则：

1. Sequence创建并拥有原始item，在`finish_item()`返回前不得复用或修改该对象。
2. Driver通过`get_next_item()`取得原始item后，必须在异步保存前执行clone/copy，形成独立快照。
3. 快照成功进入Driver内部上下文或队列后，Driver调用一次`item_done()`。
4. `item_done()`不等待AW/W/AR全部握手，也不等待B/R响应返回。
5. `item_done()`完成后，Driver不得继续依赖sequence原始对象句柄。
6. Driver拥有快照和内部上下文的生命周期；AW/W等worker只共享上下文句柄，不拥有sequence原始对象。
7. Monitor每次发布新观察对象；任何需要跨时间保存对象的订阅者必须保存独立副本。
8. Tracker和Scoreboard不得读取Driver内部上下文作为总线actual。
9. reset清理Driver内部快照时，不得修改或重新发送sequence原始对象。

## 10. S0-08：确定`item_done()`和Master Response基础策略

### 10.1 已确定内容

- Master Driver未来采用“接收并保存快照后立即`item_done()`”的流水化策略。
- 每个请求只允许调用一次`item_done()`。
- B或RLAST返回后不得再次调用`item_done()`。
- 如果未来向Master sequence返回响应，必须创建独立`axi_rsp_item`。
- 异步响应应使用UVM response通道，并使用请求的sequence/transaction ID完成路由。
- 不得把响应字段写回`axi_req_item`。
- Monitor/Tracker仍是scoreboard实际响应的数据源，Driver response不能代替真实接口观察。

### 10.2 待讨论标记S0-OPEN-01

以下问题按项目讨论要求保留待定：

```text
Master Driver默认是否向Master sequence返回独立axi_rsp_item？
```

Stage 0必须预留类型接口，但不得擅自决定默认开启、默认关闭或配置可选。该问题应在实现Master响应关联前完成讨论。无论最终选择哪种方式，都不得改变本节10.1已经确定的对象分离和`item_done()`原则。

## 11. S0-09：确定Driver长期线程和队列架构

Stage 0只确定架构，不创建Driver类或线程代码。

### 11.1 Master Driver规划

最终Master Driver至少划分为以下独立职责：

- 请求接收和快照线程：从sequencer取得请求，建立快照和上下文。
- 请求分发逻辑：根据`dir`把写请求交给AW/W路径，把读请求交给AR路径。
- AW worker：唯一驱动AWVALID和AW payload。
- W worker：唯一驱动WVALID和W payload。
- AR worker：唯一驱动ARVALID和AR payload。
- B接收/READY worker：唯一驱动BREADY并采样B响应。
- R接收/READY worker：唯一驱动RREADY并采样R响应。
- reset协调逻辑：以最高优先级控制输出复位和内部状态清理。

写请求只建立一个共享请求上下文，AW和W worker引用同一上下文并分别维护通道完成状态；不能复制成两个彼此无法关联的独立事务。

### 11.2 Slave Driver规划

最终Slave Driver至少划分为以下独立职责：

- 响应item接收和快照线程。
- 响应分发逻辑：写响应进入B路径，读响应进入R路径。
- AWREADY worker：唯一驱动AWREADY。
- WREADY worker：唯一驱动WREADY。
- ARREADY worker：唯一驱动ARREADY。
- B worker：唯一驱动BVALID和B payload。
- R worker：唯一驱动RVALID和R payload。
- reset协调逻辑：以最高优先级控制输出复位和内部状态清理。

### 11.3 共同原则

- 一个接口信号只能有一个长期worker作为正常运行时驱动者。
- AW、W、B、AR、R五通道不得由一个串行线程强制依次完成。
- VALID已经拉高后，当前worker必须锁定payload直到握手或reset。
- 后续outstanding和交织通过扩展上下文队列、候选选择和调度状态实现，不推翻信号所有权。
- reset不得依赖多个线程同时对同一信号写值；具体协调方法在Driver实现工单中确定。

## 12. S0-10：确定Delay和Gap计数语义

### 12.1 通用计数规则

- delay/gap单位为对应interface clocking block的完整时钟周期。
- 只在ARESETn有效且对应上下文具备发送资格时计数。
- `N=0`表示worker取得一个可调度上下文后的第一个可工作clocking event即可拉高VALID。
- `N=1`表示先经历一个保持VALID为0的完整可工作周期，在下一个clocking event拉高VALID。
- VALID拉高后无论READY如何变化，delay/gap计数均已结束，不能重新计数。
- reset期间不计数；reset发生后旧事务终止，释放后不得从旧计数值继续。

### 12.2 请求时序

- `addr_delay`从AW或AR上下文进入对应worker并具备调度资格后开始计数。
- 写请求的AW和W计数彼此独立，W不得等待AW握手后才开始计数。
- `w_start_delay`从写请求进入W发送路径并具备调度资格后开始计数。
- `wbeat_gap[0]`表示在`w_start_delay`结束后、第一拍WVALID拉高前的附加空闲周期。
- 对于`i>0`，`wbeat_gap[i]`从第`i-1`拍W完成握手后的下一个可工作周期开始计数。

### 12.3 响应时序

- `rsp_delay`从Slave Driver成功保存`axi_rsp_item`快照并使其具备B或R发送资格后开始计数。
- 写响应只使用`rsp_delay`控制BVALID首次拉高时间。
- 读响应使用`rsp_delay`控制第一拍RVALID首次拉高时间。
- `rbeat_gap[i]`表示第`i`拍R握手完成后到第`i+1`拍RVALID拉高前的空闲周期。
- `rbeat_gap[]`不包含第一拍，因此其长度为`len`。

## 13. S0-11：确定Reset基础边界

### 13.1 Reset期间接口行为

Master Driver后续必须驱动：

```text
AWVALID=0
WVALID=0
ARVALID=0
BREADY=0
RREADY=0
所有主动payload=0
```

Slave Driver后续必须驱动：

```text
AWREADY=0
WREADY=0
ARREADY=0
BVALID=0
RVALID=0
所有主动payload=0
```

### 13.2 Reset边界规则

- ARESETn为低时，reset优先于READY策略、delay/gap和正常通道状态。
- reset期间不得取得或产生新的有效总线事务。
- reset前未完成的事务、部分burst、outstanding记录和通道锁不得自动重放。
- reset释放后至少经过一个clocking event的空闲边界，再允许正常工作线程恢复。
- Driver、Monitor、Tracker和Scoreboard必须采用同一reset边界清除各自状态。
- Stage 0只确定行为契约；线程退出、队列flush、已取得item处理和mid-reset实现留到对应组件工单进一步展开。

## 14. S0-12：确定组件职责边界

| 组件 | Stage 0确定的职责 |
|---|---|
| Test/Sequence | 选择场景、生成请求或响应意图，不直接代表实际总线结果 |
| Driver | 后续将item稳定转换为接口信号，不预测DUT结果 |
| Monitor | 后续只根据`VALID && READY`真实握手产生观察对象 |
| Tracker | 后续按端口、方向和ID保存并关联outstanding上下文 |
| Reference Model | 后续计算路由、ID变换和功能期望 |
| Scoreboard | 后续比较expected与Monitor actual，判断DUT功能 |
| Assertion | 后续检查周期级AXI协议和reset行为 |
| Coverage | 后续采样实际场景覆盖，不改变激励或检查结果 |

必须遵守：

- Driver内部对象不能作为scoreboard actual。
- Monitor不能使用Driver意图补齐接口上没有握手的数据。
- Scoreboard不负责驱动READY或产生Slave响应。
- READY属于agent配置和Driver策略，不属于请求或响应transaction。
- 地址路由、仲裁预测和DUT内部FIFO模型不进入Driver。

## 15. S0-13：建立Package和独立编译框架

### 15.1 计划文件组织

Stage 0实施后，新`dv`环境至少具备以下组织：

```text
dv/
├── common/
│   └── axi_types_pkg.sv
├── env/
│   ├── axi_env_pkg.sv
│   ├── axi_req_item.sv
│   ├── axi_rsp_item.sv
│   ├── axi_m_agent_cfg.sv
│   ├── axi_s_agent_cfg.sv
│   ├── axi_env_cfg.sv
│   ├── axi_m_sequencer.sv
│   └── axi_s_sequencer.sv
├── tb/
│   ├── axi_if.sv
│   └── stage0_tb.sv
└── sim/
    ├── stage0.f
    └── Makefile
```

具体测试类可以放入独立test package；如果实施时增加对应目录，必须保持测试代码与可复用环境代码分离。

### 15.2 编译顺序

编译顺序固定为：

```text
1. uvm_pkg和uvm_macros
2. dv/common/axi_types_pkg.sv
3. dv/tb/axi_if.sv
4. dv/env/axi_env_pkg.sv
5. Stage 0 test package
6. dv/tb/stage0_tb.sv
```

`axi_env_pkg.sv`内部include顺序固定为：

```text
1. axi_req_item.sv
2. axi_rsp_item.sv
3. axi_m_agent_cfg.sv
4. axi_s_agent_cfg.sv
5. axi_env_cfg.sv
6. axi_m_sequencer.sv
7. axi_s_sequencer.sv
```

### 15.3 编译框架要求

- 新`dv`编译入口不得引用旧`uvm_tb`中的环境文件。
- Stage 0测试不需要例化完整AXI Interconnect DUT。
- 编译和测试命令应能够从干净工作目录重复运行。
- 编译日志和测试日志应与源码目录分离。
- Stage 0不得为了通过编译而加入空Driver、空Monitor或虚假TLM连接。

# 第二部分：Stage 0验收方案

## 16. 验收总体要求

Stage 0验收分为文档一致性、静态编译、transaction、interface、config和sequencer六类。所有测试应使用新`dv`编译入口，不得依赖旧`uvm_tb`环境提供功能。

验收结果必须满足：

- 编译退出码为0。
- 仿真退出码为0。
- 无非预期`UVM_ERROR`、`UVM_FATAL`或SystemVerilog fatal。
- 每项测试输出明确的PASS/FAIL总结。
- 未通过项不得通过降低日志级别、关闭检查或跳过测试规避。

## 17. A0-01：文档和职责一致性审核

### 17.1 审核内容

- 核对本工单是否覆盖`stage.md`中全部Stage 0预期内容。
- 核对transaction字段和约束是否符合`transaction_spec.md`。
- 核对Driver总体职责是否符合`driver_spec.md`。
- 核对interface方向、ID宽度和reset规则是否符合`detail_testplan.md`。
- 核对Stage 0没有提前包含Stage 1及后续功能。
- 核对所有待讨论内容都使用显式OPEN标记，没有隐藏的“实现时再决定”。

### 17.2 通过条件

- 文档之间不存在相互冲突的字段、方向或职责定义。
- 除`S0-OPEN-01`外，不存在影响Stage 0实施的未决架构问题。
- `S0-OPEN-01`已经预留兼容类型接口，不阻塞Stage 0编译框架。

## 18. A0-02：独立编译验收

### 18.1 测试内容

- 使用`dv/sim/stage0.f`编译公共类型、interface、环境package和Stage 0测试顶层。
- 从不包含旧编译产物的目录执行一次完整编译。
- 检查package和include顺序。
- 检查所有参数化class均能被解析和factory注册。

### 18.2 通过条件

- 新`dv`环境可以独立编译。
- 文件列表中不存在`uvm_tb`路径。
- 不依赖隐式编译顺序才能通过。
- 无重复package、重复class、未定义类型或virtual interface类型不匹配错误。

## 19. A0-03：Transaction验收

### 19.1 随机化测试

至少执行：

- 1000笔4-bit ID读请求。
- 1000笔4-bit ID写请求。
- 1000笔8-bit ID读响应。
- 1000笔8-bit ID写响应。

检查：

- `len`与动态数组尺寸一致。
- 读请求的写数组为空。
- 写响应的读数组为空。
- WRAP长度和首地址对齐合法。
- 正常INCR请求不跨4KB。
- WSTRB没有超出当前beat合法lane。
- 响应不会随机产生EXOKAY。
- 响应randomize后`dir/id/len`保持关联值不变。

### 19.2 对象操作测试

对读写请求和读写响应分别执行：

- `copy()`。
- `clone()`。
- `compare()`。
- `print()`或`convert2string()`。

修改副本动态数组中的元素后，原对象内容必须保持不变，以证明不存在动态数组浅复制问题。

### 19.3 参数检查测试

- 对4-bit和8-bit ID specialization分别创建对象并检查`$bits(id)`。
- 对合法DATA_WIDTH参数创建对象不得报错。
- 对零宽度、非整字节或非2次幂DATA_BYTES等非法参数，应在独立负向测试中产生预期fatal。

## 20. A0-04：Interface验收

### 20.1 实例化检查

Stage 0测试顶层实例化：

```text
3个ADDR=32、DATA=32、ID=4、LEN=4的Master侧axi_if
3个ADDR=32、DATA=32、ID=8、LEN=4的Slave侧axi_if
```

### 20.2 检查内容

- 检查地址、数据、ID、LEN和WSTRB位宽。
- 检查`m_drv_mp`、`s_drv_mp`和`mon_mp`能够以预期类型声明virtual interface。
- 检查Master Driver视角和Slave Driver视角不存在方向颠倒。
- 检查Monitor modport没有任何输出信号。
- 检查interface没有主动产生VALID、READY和reset。
- 使用独立负向编译或仿真测试检查非法参数报告。

### 20.3 通过条件

- 六个interface实例参数正确。
- 所有modport和clocking block类型可被对应config接收。
- 不存在隐式ID截断或扩展。

## 21. A0-05：Config和Virtual Interface验收

### 21.1 Factory和默认值

- 使用factory创建Master配置、Slave配置和环境配置。
- 检查active/passive、READY模式和outstanding字段的默认值。
- 检查环境配置默认创建或持有3个Master配置位置和3个Slave配置位置。
- 检查六个子配置的`port_index`唯一且范围正确。

### 21.2 Interface映射

- 把3个4-bit interface分别赋给3个Master配置。
- 把3个8-bit interface分别赋给3个Slave配置。
- 分别设置Driver视角和Monitor视角句柄。
- 使用精确组件路径完成`uvm_config_db::set/get`测试。
- 检查每个接收者取得的配置对象和端口编号正确。

### 21.3 错误场景

- 未配置virtual interface时，配置校验契约必须能够识别空句柄。
- Master/Slave或4-bit/8-bit interface不得通过隐式类型转换错误互换。
- 禁止用`"*"`将同一个端口配置广播给全部Agent的实现方式通过审核。

## 22. A0-06：Sequencer类型验收

### 22.1 测试内容

- factory创建4-bit ID的Master sequencer。
- factory创建8-bit ID的Slave sequencer。
- 编译检查Master sequencer的REQ类型为对应`axi_req_item`。
- 编译检查Master sequencer预留的RSP类型为对应`axi_rsp_item`。
- 编译检查Slave sequencer的item类型为对应`axi_rsp_item`。
- 创建最小空sequence验证类型能够完成start/finish流程，但不连接Driver、不驱动interface。

### 22.2 通过条件

- sequencer parameter specialization和factory注册无错误。
- 4-bit与8-bit item不能连接到不匹配的sequencer类型。
- 测试没有借助空Driver绕过Stage边界。

## 23. A0-07：Stage边界验收

检查Stage 0变更集合，确认没有新增以下实现：

- Driver `run_phase`和通道驱动task。
- Monitor采样线程和analysis port数据发布。
- Agent组件及sequencer—Driver连接。
- DUT bridge和完整`tb_top`连接。
- READY运行状态机。
- outstanding、乱序和交织队列。
- scoreboard、reference model或coverage功能。

允许的测试代码仅用于验证Stage 0公共基础，不得被包装成正式组件行为。

## 24. Stage 0完成条件

只有同时满足以下条件，Stage 0才能标记完成：

1. 本工单已经审核并冻结。
2. S0-01～S0-13全部实施完成。
3. A0-01～A0-07全部通过。
4. 新`dv`环境能够独立编译和运行Stage 0测试。
5. 公共类型、transaction、interface、config和sequencer之间参数一致。
6. 对象所有权、`item_done()`、delay/gap、reset和组件职责已有明确书面契约。
7. 没有提前实现Stage 1或后续Stage功能。
8. 所有非预期编译告警、UVM错误和fatal均已处理。
9. 验收结果和已知限制已经记录。

Stage 0完成后，Stage 1可以直接依据本文确定的类型、配置、对象所有权和线程边界，实现组件最小能力及独立测试支架，而不再重新设计Stage 0公共契约。

## 25. 审核记录

| 审核项 | 状态 | 说明 |
|---|---|---|
| Stage 0范围 | 待审核 |  |
| 公共类型和参数化方案 | 待审核 | 采用组件全参数化方案 |
| Transaction和interface契约 | 待审核 |  |
| Config和sequencer方案 | 待审核 |  |
| 对象所有权和`item_done()` | 待审核 |  |
| Delay/gap语义 | 待审核 |  |
| Reset边界 | 待审核 |  |
| 验收方案 | 待审核 |  |
| S0-OPEN-01 Master response默认行为 | 待讨论 | 仅预留类型接口 |

审核通过前，本工单中的Stage 0实现内容不得施行。

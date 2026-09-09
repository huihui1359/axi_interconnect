# AXI3 Interconnect UVM验证环境Stage 0执行工单

editor：Codex / 项目讨论结论整理

date：2026-09-08

实施日期：2026-09-09

状态：已审核，Stage 0已实施并通过基础验收

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
- 上下游ID宽度不同来自当前DUT的真实接口定义，不是验证环境自行增加：
  - `rtl/axi_interconnect.v`中`WIDTH_ID=4`，因此`M_AXI_AWID/WID/BID/ARID/RID`均为4位。
  - 下游使用`WIDTH_SID=WIDTH_CID+WIDTH_ID=8`，因此`S_AXI_AWID/WID/BID/ARID/RID`均为8位。
  - RTL把路由信息、来源Master信息和原始4-bit ID组合为下游扩展ID；下游Slave返回BID/RID时必须原样返回全部8位，由Interconnect恢复并路由到对应上游Master。
  - 因此不能把上下游interface统一固定为4位，否则会截断DUT用于响应路由和ID恢复的信息。
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
- 上游端口使用4-bit ID specialization，下游端口使用8-bit ID specialization；二者复用同一个参数化`axi_if`定义，不复制成两份interface源码。
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

### 6.4 Config数量及其与Package的关系

Stage 0只规划三种config class类型，不规划第四种config：

```text
axi_m_agent_cfg    Master agent单端口配置类型，后续创建3个对象
axi_s_agent_cfg    Slave agent单端口配置类型，后续创建3个对象
axi_env_cfg        环境聚合配置类型，通常创建1个对象并持有上述6个子配置
```

`axi_env_pkg.sv`不是第四个config。它是SystemVerilog package入口，用于统一import公共类型并include/export环境中的class定义。cfg class源文件会通过`axi_env_pkg.sv`编入`axi_env_pkg`命名空间，但package本身不能代替运行期config对象，原因如下：

- package中的变量属于全局静态状态，不能自然表示六个端口各自不同的配置实例。
- 每个agent需要取得只属于本端口的virtual interface、端口编号和READY策略，不能共同读写一个全局配置变量集合。
- `uvm_config_db`传递的是按组件层次分发的值或对象句柄；独立config对象能够被factory创建、检查、打印和按实例传递。
- 如果Driver直接访问package全局配置，会把单端口组件耦合到三主三从全局结构，破坏组件复用和独立测试。

因此采用“package负责类型组织，config对象负责运行期配置”的分工；不在`axi_env_pkg.sv`中定义共享的运行期配置变量来替代三种config class。

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
//????tracker为什么需要这个组件？
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
│   ├── axi_env_cfg.sv
│   ├── axi_req_item.sv
│   ├── axi_rsp_item.sv
│   ├── master/
│   │   ├── axi_m_agent_cfg.sv
│   │   ├── axi_m_sequencer.sv
│   │   ├── axi_m_driver.sv       后续Stage创建
│   │   ├── axi_m_monitor.sv      后续Stage创建
│   │   └── axi_m_agent.sv        后续Stage创建
│   └── slave/
│       ├── axi_s_agent_cfg.sv
│       ├── axi_s_sequencer.sv
│       ├── axi_s_driver.sv       后续Stage创建
│       ├── axi_s_monitor.sv      后续Stage创建
│       └── axi_s_agent.sv        后续Stage创建
├── tb/
│   ├── axi_if.sv
│   └── stage0_tb.sv
└── sim/
    ├── stage0.f
    └── Makefile
```

Master agent专属组件统一放入`dv/env/master/`，Slave agent专属组件统一放入`dv/env/slave/`。transaction同时被多个角色使用，`axi_env_cfg`属于环境级聚合对象，因此继续放在`dv/env/`根目录。Stage 0只创建两个子目录中的cfg和sequencer文件，不提前创建图中标记为“后续Stage创建”的Driver、Monitor和Agent文件。

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
3. master/axi_m_agent_cfg.sv
4. slave/axi_s_agent_cfg.sv
5. axi_env_cfg.sv
6. master/axi_m_sequencer.sv
7. slave/axi_s_sequencer.sv
```

### 15.3 编译框架要求

- 新`dv`编译入口不得引用旧`uvm_tb`中的环境文件。
- Stage 0测试不需要例化完整AXI Interconnect DUT。
- 编译和测试命令应能够从干净工作目录重复运行。
- 编译日志和测试日志应与源码目录分离。
- Stage 0不得为了通过编译而加入空Driver、空Monitor或虚假TLM连接。

# 第二部分：Stage 0验收方案

## 16. 验收总体要求

Stage 0尚未实现Driver、Monitor、Agent和端到端小环境，因此本阶段只进行必要的基础验收，目标是确认公共契约已经确定、类型能够正确编译、后续组件具备可用的基础接口。

Stage 0不进行协议功能、随机压力或多端口连接的完整验证。所有验收使用新`dv`编译入口，不得依赖旧`uvm_tb`环境提供功能。

## 17. A0-01：文档和职责审核

- 核对本工单覆盖`stage.md`中全部Stage 0内容。
- 核对transaction、interface和Driver职责与已有SPEC一致。
- 核对上游4-bit ID、下游8-bit扩展ID以及对应参数化关系正确。
- 核对对象所有权、`item_done()`、delay/gap和reset基础边界已经明确。
- 核对Stage 0没有提前包含Stage 1及后续功能。
- 保留的待讨论问题必须使用明确的OPEN标记，且不得阻塞Stage 0基础类型实现。

## 18. A0-02：独立编译验收

- 使用`dv/sim/stage0.f`编译公共类型、interface、transaction、config、sequencer和Stage 0最小测试顶层。
- 确认package及include顺序正确。
- 确认4-bit Master和8-bit Slave两组参数化类型均可编译。
- 确认参数化config和sequencer能够完成factory注册和对象创建。
- 文件列表中不存在`uvm_tb`路径。
- 编译和最小测试运行结束时无非预期`UVM_ERROR`、`UVM_FATAL`或SystemVerilog fatal。

## 19. A0-03：基础对象Smoke验收

本阶段只做少量确定性smoke，不进行大规模随机回归：

- 分别创建一个读请求、一个写请求、一个读响应和一个写响应。
- 对请求和响应各执行一次randomize，确认基本约束可以求解且数组尺寸正确。
- 对包含动态数组的请求和响应各执行一次clone/compare，确认副本可用且不会与原对象共享动态数组内容。
- 实例化一个4-bit Master interface和一个8-bit Slave interface，确认其能够赋给对应config中的virtual interface类型。
- 创建Master agent cfg、Slave agent cfg和env cfg，检查关键默认值与端口配置数量。
- 创建Master和Slave sequencer，确认REQ/RSP类型specialization正确。

## 20. A0-04：Stage边界和完成检查

检查Stage 0变更集合，确认没有新增以下实现：

- Driver `run_phase`和通道驱动task。
- Monitor采样线程和analysis port数据发布。
- Agent组件及sequencer—Driver连接。
- DUT bridge和完整`tb_top`连接。
- READY运行状态机。
- outstanding、乱序和交织队列。
- scoreboard、reference model或coverage功能。

Stage 0满足以下条件即可完成：

1. 本工单已经审核并冻结。
2. S0-01～S0-13已经实施完成。
3. 文档审核、独立编译和基础对象smoke均通过。
4. 新`dv`环境能够在不引用旧`uvm_tb`的情况下独立编译。
5. 公共类型、transaction、interface、config和sequencer参数一致。
6. 没有提前实现Stage 1或后续Stage功能。
7. 验收结果和待讨论项已经记录。

## 21. 后续Stage再验证的内容

以下内容不作为Stage 0完成门槛，在对应组件或小环境搭建后验证：

- 大规模transaction随机化和约束覆盖。
- 非法参数及预期fatal负向测试。
- 三组Master和三组Slave的完整virtual interface映射。
- `uvm_config_db`完整层次路径和六端口防串接检查。
- Driver与sequencer的实际连接及`item_done()`行为。
- Interface五通道方向、握手、stall和reset行为。
- Monitor采样、transaction重建和analysis port数据流。
- burst、delay/gap、outstanding、乱序和交织功能。
- 端到端Scoreboard、assertion和functional coverage。

这些测试应随着Stage 1组件测试支架、Stage 2单端口小环境以及后续功能Stage逐步加入回归。

## 22. 审核记录

| 审核项 | 状态 | 说明 |
|---|---|---|
| Stage 0范围 | 已通过 | 未实现Driver、Monitor或Agent |
| 公共类型和参数化方案 | 已通过 | 采用组件全参数化方案 |
| Transaction和interface契约 | 已通过 | 复用现有参数化实现 |
| Config和sequencer方案 | 已通过 | 已实现并通过factory创建smoke |
| 对象所有权和`item_done()` | 已通过 | 契约已确定，行为测试留到Stage 1 |
| Delay/gap语义 | 已通过 | 契约已确定，行为测试留到Stage 3 |
| Reset边界 | 已通过 | 基础契约已确定，行为测试留到后续Stage |
| 验收方案 | 已通过 | 独立编译和基础对象smoke通过 |
| S0-OPEN-01 Master response默认行为 | 待讨论 | 仅预留类型接口 |

### 22.1 实施与验收记录

- 使用QuestaSim 10.6c和预编译UVM 1.1d执行`dv/sim/Makefile`中的`make run`。
- 从清理后的构建目录重新完成一次编译和仿真，确认编译入口可重复执行。
- 编译结果：0 error，0 warning。
- UVM smoke结果：`STAGE0_PASS`，0 UVM warning，0 UVM error，0 UVM fatal。
- 新`dv`文件列表没有引用旧`uvm_tb`环境。
- `S0-OPEN-01`继续保留，不影响进入Stage 1。

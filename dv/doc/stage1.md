# AXI3 Interconnect UVM验证环境Stage 1执行工单

editor：Codex / 项目讨论结论整理

date：2026-09-13（2026-09-15同步当前实现与运行结果）

状态：已审核冻结；Stage 1A和Stage 1B均已实施并通过；当前代码结构、QuestaSim入口和审核结果已同步

## 1. 文档目的

本文档是[stage.md](./stage.md)中“Stage 1：基础组件和单端口最小纵向闭环”的详细执行工单，同时记录Stage 1冻结后的实际代码结构、当前连接方式、定向事务和运行审核结果。若工单早期描述与“当前实现”小节存在差异，以当前仓库代码和本文最新实施记录为准。

Stage 1在Stage 0公共契约基础上完成两层工作：

1. Stage 1A：实现Driver、Monitor、sequence、Agent和基础比较组件的最小能力，并分别建立不依赖正式对端组件的独立测试支架。
2. Stage 1B：使用已经通过组件级验收的组件连接真实AXI Interconnect DUT，建立M0到S0的单端口、单笔、单拍、无主动背压请求—响应闭环。

Stage 1A通过后才能进入Stage 1B。只有两个内部验收门槛全部通过，Stage 1才算完成。

本文中的Stage表示项目实施阶段，不是UVM的`build_phase`、`connect_phase`或`run_phase`。

## 2. Stage 1范围

### 2.1 Stage 1A纳入范围

- 定义Monitor发布的参数化五通道握手观察事件。
- 实现Master Driver的单笔、单拍读写能力。
- 实现Slave Driver的单笔B响应和单拍R响应能力。
- Master侧BREADY/RREADY采用`ALWAYS_READY`。
- Slave侧AWREADY/WREADY/ARREADY采用`ALWAYS_READY`。
- 建立Master Driver中可继续扩展的AW、W、AR发送路径及B、R接收路径。
- 建立Slave Driver中可继续扩展的AW、W、AR接收控制路径及B、R发送路径。
- 实现Master Monitor和Slave Monitor的五通道单次握手采样能力。
- 实现Slave Monitor的单拍读写请求重建输出。
- 实现最简单的Master单拍读写sequence和Slave reactive response sequence。
- 实现Master Agent和Slave Agent的active/passive组装及连接。
- 实现基础事件比较组件和测试级检查逻辑。
- 建立Master Driver、Slave Driver、Monitor、Agent、sequence和比较组件的独立测试支架。
- 实现Stage 0中已经冻结的clone/copy、对象所有权和`item_done()`契约。
- 实现基础reset行为和最小协议检查。

### 2.2 Stage 1B纳入范围

- 建立Stage 1专用DUT测试顶层和信号级bridge。
- 连接一个4-bit ID的上游Master interface到DUT M0端口。
- 连接一个8-bit ID的下游Slave interface到DUT S0端口。
- 将DUT其余上游和下游端口确定性置为空闲。
- 在测试层组装一个Master Agent和一个reactive Slave Agent。
- 完成Slave Monitor到Slave sequencer请求FIFO再到Slave Driver的响应因果链路。
- 建立最小端到端事件比较和ID检查路径。
- 跑通M0到S0的单拍写请求和B响应。
- 跑通M0到S0的单拍读请求和R响应。
- 验证上游4-bit原始ID、下游8-bit扩展ID及返回上游后的ID恢复。
- 完成基础phase、objection、统一timeout、reset启动和仿真退出流程。

### 2.3 明确不纳入范围

Stage 1不得实现以下能力：

- `len>0`的burst发送或重建。
- `addr_delay`、`w_start_delay`、`wbeat_gap[]`、`rsp_delay`或`rbeat_gap[]`的运行时计数机制。
- `RANDOM_READY`或`SCRIPTED_READY`运行策略。
- 大于1的读写outstanding。
- 不同ID响应乱序。
- 不同WID写数据交织或不同RID读数据交织。
- 正式outstanding/order Tracker。
- 完整地址路由Reference Model。
- 完整三主三从`axi_env`和virtual sequencer。
- round-robin仲裁Checker。
- 最终系统级Scoreboard。
- memory model。
- 完整protocol assertion集合。
- functional coverage和随机压力回归。

### 2.4 当前实现快照

当前Stage 1代码已经形成可独立编译和运行的单端口DUT闭环：

- 公共参数位于`dv/common/axi_types_pkg.sv`：地址32 bit、数据32 bit、上游ID 4 bit、下游ID 8 bit、LEN 4 bit，物理DUT为三主三从。
- `dv/env`保留可参数化的item、channel event、cfg、Driver、Monitor、Sequencer、Agent、`axi_env`和基础event comparator。
- 当前测试环境把`axi_env`特化为一个Master Agent和一个Slave Agent；物理顶层只把这两个Agent连接到DUT的M0和S0。
- `dv/tb/tb.sv`统一产生10 ns时钟和低有效reset，例化真实`axi_interconnect`，完成接口bridge、cfg传递和`run_test()`调用。
- `dv/tc`保留`axi_base_test`、`axi_write_test`和`axi_read_test`；Stage 1A独立测试支架在审核完成后已删除。
- `sim/Makefile`和`sim/sim.f`是当前唯一的QuestaSim编译仿真入口，生成物存放在`sim/work`。

当前保留的定向事务均为`len=0`的单拍INCR事务：

| Test | 上游请求 | 下游响应 | 端到端检查 |
|---|---|---|---|
| `axi_write_test` | ID=`4'h5`，ADDR=`32'h0000_0080`，DATA=`32'hDEAD_BEEF`，STRB=`4'hF` | BID使用扩展ID，BRESP=`OKAY` | AW/W/B各匹配1次 |
| `axi_read_test` | ID=`4'h5`，ADDR=`32'h0000_0100` | RID使用扩展ID，RDATA=`32'hCAFE_BABE`，RRESP=`OKAY`，RLAST=1 | AR/R各匹配1次 |

Stage 0曾使用QuestaSim 10.6c和UVM 1.1d完成独立对象smoke；其一次性测试入口在目录收敛后未保留，因此当前日常审核以Stage 1真实DUT闭环为准。旧`uvm_tb`及其他历史testbench不进入当前`sim.f`。

# 第一部分：Stage 1基础验证框架和TLM连接

## Stage 1基础验证框架连接图

### Stage 1整体结构

Stage 1使用同一组正式Driver、Monitor、Sequencer和Agent完成两层验证：Stage 1A中用独立pin-level测试支架验证组件本身，Stage 1B中撤去pin-level对端并连接真实AXI Interconnect DUT。

```text
                         axi_write_test / axi_read_test
                              extends axi_base_test
                                      │
                                axi_test_env env
┌──────────────────── axi_m_agent[0] ────────────────────┐
│ Master sequence → m_sequencer → axi_m_driver          │
│                                      │ m_drv_mp        │
│ axi_m_monitor ←──────── mon_mp ──────┤                 │
│       │ upstream channel_ap           │                 │
└───────┼───────────────────────────────┼─────────────────┘
        │                               ▼
        │                         [4-bit m_if]
        │                               ⇅ explicit HDL bridge
        │                       [DUT M_AXI_*[0]]
        │                               ⇅
        │                        AXI Interconnect
        │                               ⇅
        │                       [DUT S_AXI_*[0]]
        │                               ⇅ explicit HDL bridge
        │                         [8-bit s_if]
        │                               │
        │  ┌──────────────── axi_s_agent[0] ───────────────────────────────┐
        │  │                   ├── mon_mp → axi_s_monitor                 │
        │  │                   │              ├ channel_ap ───────────────┼────┐
        │  │                   │              └ req_ap → request FIFO    │    │
        │  │                   │                            │ FIFO get     │    │
        │  │                   │                            ▼              │    │
        │  │                   │                  reactive sequence       │    │
        │  │                   │                            │ start_item   │    │
        │  │                   │                            ▼              │    │
        │  │                   │                      s_sequencer ┐        │    │
        │  │                   └── s_drv_mp ⇄ axi_s_driver ⇄ pull ┘        │    │
        │  └───────────────────────────────────────────────────────────────┘    │
        │                                                                    │
        ▼ upstream_export                              downstream_export ◄────┘
                ┌───────────────────────────────────────────────────┐
                │ stage1_e2e_checker                                │
                │ request: upstream expected → downstream actual    │
                │ response: downstream expected → upstream actual   │
                └───────────────────────────────────────────────────┘

DUT未启用端口：M_AXI_*[1:2]和S_AXI_*[1:2]由Stage 1顶层确定性置空。
```

最终Stage 1B框图只呈现`stage1_e2e_checker`。`pin_peer_checker`和`axi_basic_event_comparator`属于Stage 1A独立组件测试支架，不进入最终DUT闭环。

组件归属关系为：

```text
axi_m_agent[0]
├── m_sequencer
├── axi_m_driver
└── axi_m_monitor

axi_s_agent[0]
├── s_sequencer（同时持有请求analysis FIFO和response seq_item_export）
├── axi_s_driver
└── axi_s_monitor

axi_base_test
└── axi_test_env env
    ├── axi_m_agent[0]
    ├── axi_s_agent[0]
    └── stage1_e2e_checker
```

`tb.sv`只创建物理interface、DUT和`env_cfg`。`axi_base_test`从`uvm_config_db`取得同一个`env_cfg`并创建`axi_test_env`；具体的`axi_write_test`或`axi_read_test`继承base test，只配置并启动本用例所需的Master sequence和Slave reactive sequence。

### Stage 1A组件独立测试连接

Stage 1A不例化真实DUT，各正式组件分别使用独立测试对端：

```text
Master Driver unit：
Master sequence → m_sequencer → axi_m_driver → m_if → pin-level Slave peer + pin_peer_checker

Slave Driver unit：
Direct response sequence → s_sequencer → axi_s_driver → s_if → pin-level Master peer + pin_peer_checker

Master Monitor unit：
pin-level waveform source + expected event → m_if → axi_m_monitor
                                                └── channel_ap → axi_basic_event_comparator

Slave Monitor unit：
pin-level waveform source + expected event/request → s_if → axi_s_monitor
                                                        ├── channel_ap → axi_basic_event_comparator
                                                        └── req_ap     → test-level request assertion

Reactive chain unit：
pin-level request source → s_if → axi_s_monitor.req_ap
                                  → s_sequencer request FIFO
                                  → reactive sequence
                                  → axi_rsp_item observer或axi_s_driver
```

pin-level peer只完成当前组件测试所需的确定性握手、响应或检查，不复用正式对端Driver/Monitor，也不实现DUT路由功能。

### 三类Checker的用途和边界

Stage 1审核过程使用过三种检查方式，但它们用于不同层次，不能相互替代。当前仓库保留`axi_basic_event_comparator`和`stage1_e2e_checker`；`pin_peer_checker`随Stage 1A一次性独立测试支架删除。

| Checker | 所属阶段/测试 | Expected来源 | Actual来源 | 主要检查 | 是否进入Stage 1B最终闭环 |
|---|---|---|---|---|---|
| `pin_peer_checker` | Stage 1A历史Driver unit | sequence item及测试预设握手计划 | interface引脚上的Driver实际输出 | Driver信号映射、VALID时序、stall稳定、READY和LAST派生 | 否，已删除 |
| `axi_basic_event_comparator` | Stage 1A Monitor unit和后续同类型event比较基础 | pin-level waveform source同步创建的expected event | Monitor `channel_ap`发布的actual event | Monitor是否漏采、重复采样、通道标记及4-state payload是否正确 | 否，组件仍保留在`dv/env` |
| `stage1_e2e_checker` | Stage 1B DUT闭环 | 请求方向来自上游Monitor；响应方向来自下游Monitor | 请求方向来自下游Monitor；响应方向来自上游Monitor | DUT转发、payload、ID扩展/恢复、响应透传、丢失和重复 | 是 |

三种检查在Stage 1A/1B审核时均已执行并通过：

- `pin_peer_checker`证明正式Driver能够把item正确转换为接口行为。
- `axi_basic_event_comparator`证明正式Monitor能够把接口握手正确转换为event。
- `stage1_e2e_checker`在前两者可信的基础上检查请求和响应是否正确穿过真实DUT。

Stage 1B通过不能在审核意义上替代前两种组件级检查。当前日常回归只保留真实DUT闭环，组件级结论沿用已冻结的Stage 1A审核记录；若后续修改Driver或Monitor，应重新建立相应unit支架，而不能只依赖端到端用例。

Slave Monitor `req_ap`的重建请求由Monitor unit中的test-level assertion直接检查。它是针对`axi_req_item`的测试断言，不是第四个可复用Checker组件，也不进入Stage 1B的端到端判定。

### Stage 1B单端口闭环连接

Stage 1B的活动路径固定为：

```text
Master sequence
      ↓
Master Agent 0
      ↓
4-bit m_if
      ↓
DUT M_AXI_*[0]
      ↓ 路由到S0并扩展ID
DUT S_AXI_*[0]
      ↓
8-bit s_if
      ↓
Slave Agent 0的Monitor和reactive response chain
      ↓ B/R响应
DUT返回路径
      ↓
Master Agent 0的Monitor
      ↓
stage1_e2e_checker
```

Master Agent和Slave Agent之间不存在直接事务连接；请求和响应必须经过真实DUT接口。唯一的响应生成因果连接位于Slave Agent内部，由Slave Monitor观察真实下游请求后触发reactive sequence。

### Master侧（M0上游）完整信号关系

M0上游接口使用4-bit ID的`axi_if`。从协议角色看，验证环境的Master Driver是AXI Master，DUT的`M_AXI_*[0]`是AXI Slave。

HDL bridge将`m_if.aw* / w* / b* / ar* / r*`逐字段一一映射到DUT的`M_AXI_AW* / W* / B* / AR* / R*[0]`；bridge只做连线和大小写命名转换，不改变payload、ID或握手语义。

| Channel | Master Driver/TB侧行为 | DUT M0侧行为 | Master Monitor行为 | 握手条件 |
|---|---|---|---|---|
| 公共 | Stage 1顶层产生`ACLK/ARESETn`；Driver读取`ARESETn`控制复位退出 | 接收同一`ACLK/ARESETn` | 采样`ARESETn`，reset期间不发布event | 不适用 |
| AW | 驱动`AWID/AWADDR/AWLEN/AWSIZE/AWBURST/AWVALID`；读取`AWREADY`只用于结束AW发送 | 驱动`AWREADY`并接收AW payload | 采样AW全部信号，握手时发布上游AW event | `AWVALID && AWREADY` |
| W | 驱动`WID/WDATA/WSTRB/WLAST/WVALID`；读取`WREADY`只用于结束W发送 | 驱动`WREADY`并接收W payload | 采样W全部信号，握手时发布上游W event | `WVALID && WREADY` |
| B | 驱动`BREADY`；读取`BID/BRESP/BVALID`只用于完成本地写上下文 | 驱动`BID/BRESP/BVALID` | 采样B全部信号，握手时发布上游B event | `BVALID && BREADY` |
| AR | 驱动`ARID/ARADDR/ARLEN/ARSIZE/ARBURST/ARVALID`；读取`ARREADY`只用于结束AR发送 | 驱动`ARREADY`并接收AR payload | 采样AR全部信号，握手时发布上游AR event | `ARVALID && ARREADY` |
| R | 驱动`RREADY`；读取`RID/RDATA/RRESP/RLAST/RVALID`只用于完成本地读上下文 | 驱动`RID/RDATA/RRESP/RLAST/RVALID` | 采样R全部信号，握手时发布上游R event | `RVALID && RREADY` |

Master Driver读取READY和B/R输入是协议驱动所需的握手控制，不生成覆盖率、不发布event，也不作为功能检查的actual。Master Monitor通过`mon_mp`只读采样全部五通道信号；`stage1_e2e_checker`的上游观察只能来自Master Monitor。

### Slave侧（S0下游）完整信号关系

S0下游接口使用8-bit扩展ID的`axi_if`。从协议角色看，DUT的`S_AXI_*[0]`是AXI Master，验证环境的Slave Driver是AXI Slave。

HDL bridge将`S_AXI_AW* / W* / B* / AR* / R*[0]`逐字段一一映射到`s_if.aw* / w* / b* / ar* / r*`；bridge不承担ID扩展、恢复或响应生成，这些行为必须由DUT或Slave Agent完成并由Monitor观察。

| Channel | DUT S0侧行为 | Slave Driver/TB侧行为 | Slave Monitor行为 | 握手条件 |
|---|---|---|---|---|
| 公共 | 接收Stage 1顶层产生的`ACLK/ARESETn` | 接收同一`ACLK/ARESETn`；Driver读取`ARESETn`控制复位退出 | 采样`ARESETn`，reset期间不发布event | 不适用 |
| AW | 驱动`AWID/AWADDR/AWLEN/AWSIZE/AWBURST/AWVALID` | 驱动`AWREADY`；不根据AW输入直接生成响应 | 采样AW全部信号，握手时发布下游AW event并参与写请求重建 | `AWVALID && AWREADY` |
| W | 驱动`WID/WDATA/WSTRB/WLAST/WVALID` | 驱动`WREADY`；不以AW先握手作为WREADY条件 | 采样W全部信号，握手时发布下游W event并参与写请求重建 | `WVALID && WREADY` |
| B | 驱动`BREADY`并接收B payload | 驱动`BID/BRESP/BVALID`；读取`BREADY`只用于结束B发送 | 采样B全部信号，握手时发布下游B event | `BVALID && BREADY` |
| AR | 驱动`ARID/ARADDR/ARLEN/ARSIZE/ARBURST/ARVALID` | 驱动`ARREADY`；不根据AR输入直接生成响应 | 采样AR全部信号，握手时发布下游AR event并重建读请求 | `ARVALID && ARREADY` |
| R | 驱动`RREADY`并接收R payload | 驱动`RID/RDATA/RRESP/RLAST/RVALID`；读取`RREADY`只用于结束R发送 | 采样R全部信号，握手时发布下游R event | `RVALID && RREADY` |

Slave Driver负责驱动`AWREADY/WREADY/ARREADY`和B/R响应。请求内容只能由Slave Monitor观察并通过`req_ap`发送给请求FIFO；reactive sequence依据该请求创建新的`axi_rsp_item`，再由Slave Driver驱动响应。这里必须使用`ARREADY`表示读地址通道READY；R通道的READY是`RREADY`，由DUT驱动、Slave Driver读取。

### `stage1_e2e_checker`检查内容和数据来源

端到端Checker只接受上下游Monitor发布的真实握手event。表中的expected/actual是比较角色，不等同于“激励/输出”：expected表示进入DUT前已观察到的基准，actual表示穿过DUT后观察到的结果。

| 检查项 | Expected来源 | Actual来源 | 比较和变换规则 |
|---|---|---|---|
| AW请求转发 | Master Monitor `channel_ap`的M0上游AW event | Slave Monitor `channel_ap`的S0下游AW event | `addr/len/size/burst_raw`一致；下游ID等于`{2'b01, 2'b01, upstream_id}` |
| W请求转发 | Master Monitor `channel_ap`的M0上游W event | Slave Monitor `channel_ap`的S0下游W event | `data/strb/last`一致；下游WID按同一规则扩展 |
| AR请求转发 | Master Monitor `channel_ap`的M0上游AR event | Slave Monitor `channel_ap`的S0下游AR event | `addr/len/size/burst_raw`一致；下游ID按同一规则扩展 |
| B响应返回 | Slave Monitor `channel_ap`的S0下游B event | Master Monitor `channel_ap`的M0上游B event | 下游BID等于已匹配写请求的扩展ID；`resp_raw`一致；上游BID恢复为该写请求的原始4-bit ID |
| R响应返回 | Slave Monitor `channel_ap`的S0下游R event | Master Monitor `channel_ap`的M0上游R event | 下游RID等于已匹配读请求的扩展ID；`data/resp_raw/last`一致；上游RID恢复为该读请求的原始4-bit ID |
| 完整性和因果关系 | 各方向进入Checker的expected队列、已匹配请求上下文和期望计数 | 各方向进入Checker的actual队列和实际计数 | 每个event只匹配一次；B/R不得早于对应完整请求；无漏传、重复、额外event；test结束时所有队列和上下文清空 |

Stage 1B为单端口、单笔、单拍环境，Checker可以按通道分别使用FIFO顺序匹配，但不得比较固定`sample_cycle`或要求上下游具有固定周期差。sequence item、Driver内部状态和reactive response计划都不能直接作为端到端actual；这样才能保持对DUT的黑盒判定。

### 当前M0到S0的ID宽度和路由编码

上游和下游ID宽度在`dv/common/axi_types_pkg.sv`中分别定义为：

```systemverilog
AXI_M_ID_WIDTH = 4;
AXI_S_ID_WIDTH = 8;
```

`M_AXI_AWID[0]`中的`[0]`是物理端口数组下标，不是DUT内部Master路由编码。当前RTL在`axi_interconnect.v`中固定使用：M0=`2'b01`、M1=`2'b10`、M2=`2'b11`。S0的路由编码同样为`2'b01`。M0请求转发到S0时，`axi_mtos_m3.v`按以下方式扩展AWID/ARID：

```text
downstream_id = {slave_route[1:0], master_route[1:0], original_id[3:0]}
```

因此当前定向用例中：

```text
M_AXI_*[0] original_id = 4'h5
S0 route                 = 2'b01
M0 route                 = 2'b01
S_AXI_*[0] expanded_id   = {2'b01, 2'b01, 4'h5} = 8'h55
```

返回B/R响应时，DUT用扩展ID中的Master路由位选择返回端口，并把低4位原始ID恢复到M0。当前`stage1_e2e_checker.expand_id()`固定实现同一`{2'b01, 2'b01, original_id}`规则，所以它只适用于本Stage的M0到S0闭环，不是三主三从通用ID模型。

### TLM通信连接说明

Stage 1使用两类TLM通信：Driver与Sequencer之间使用UVM sequence pull协议；Monitor到被动消费者之间使用非阻塞analysis广播。

| 使用范围 | 生产者/发起者 | TLM连接 | 消费者/目标 | 传递对象 | 用途 |
|---|---|---|---|---|---|
| Stage 1A/1B | Master sequence | `start_item/finish_item`经Master sequencer | Master Driver `seq_item_port` | 4-bit ID `axi_req_item` | 提供单拍读写请求 |
| Stage 1A/1B | Slave reactive/direct sequence | `start_item/finish_item`经Slave sequencer | Slave Driver `seq_item_port` | 8-bit ID `axi_rsp_item` | 提供单拍B/R响应计划 |
| Stage 1A Monitor unit | pin-level waveform source | `expected_export` | `axi_basic_event_comparator` | 参数匹配的`axi_channel_event` | 提供与引脚波形同步创建的expected event |
| Stage 1A Monitor unit | Master或Slave Monitor | `channel_ap`连接`actual_export` | `axi_basic_event_comparator` | 参数匹配的`axi_channel_event` | 提供Monitor实际发布的actual event |
| Stage 1B | Master Monitor | `channel_ap` | `stage1_e2e_checker.upstream_export` | 4-bit ID `axi_channel_event` | 发布M0上游五通道真实握手 |
| Stage 1B | Slave Monitor | `channel_ap` | `stage1_e2e_checker.downstream_export` | 8-bit ID `axi_channel_event` | 发布S0下游五通道真实握手 |
| Stage 1A/1B reactive链路 | Slave Monitor | `req_ap` | Slave sequencer请求FIFO的`analysis_export` | 8-bit ID `axi_req_item` | 发布已经重建的完整单拍请求 |
| Stage 1A/1B reactive链路 | Slave sequencer请求FIFO | FIFO `get/peek`接口 | Reactive Slave sequence | 8-bit ID `axi_req_item` | 解耦Monitor采样和响应生成 |

连接规则如下：

- `seq_item_port/seq_item_export`是点到点pull连接，Driver通过`get_next_item()`取得item，并按本工单规定调用一次`item_done()`。
- `analysis_port`调用`write()`时不得阻塞Monitor采样；一个Monitor analysis port可以连接Checker、Comparator以及后续其他多个被动消费者。
- Slave请求FIFO用于保存Monitor已经发布的完整请求，reactive sequence从FIFO读取请求后创建新的response item。
- `channel_ap`不连接Driver，也不能用来绕过DUT产生功能actual。
- Master和Slave Monitor发布后不再修改对象；需要修改或重新发布的消费者必须先clone/copy。
- `stage1_e2e_checker`只被动接收上下游event，不向Driver、Sequencer或interface形成反馈控制。

# 第二部分：Stage 1实现内容

## 3. S1-01：定义通道观察事件和Stage 1能力约束

### 3.1 实现目标

新增参数化`axi_channel_event`，表示某个物理AXI端口在一个clocking event上实际完成的一次AW、W、B、AR或R握手。

`axi_channel_event`不是第三种sequence transaction，也不作为Driver输入。它是Monitor根据接口真实`VALID && READY`创建的不可变观察快照。

### 3.2 公共类型

在公共类型package中增加通道和接口侧别枚举，命名统一为：

```text
axi_channel_e    AW/W/B/AR/R
axi_side_e       UPSTREAM/DOWNSTREAM
```

不得同时保留语义相同的`axi_channel_obs`和`axi_channel_event`两套观察类型。Stage 1统一采用`axi_channel_event`作为类名。

### 3.3 `axi_channel_event`参数和字段

参数至少包括：

```text
ADDR_WIDTH
DATA_WIDTH
ID_WIDTH
LEN_WIDTH
```

对象至少保存：

```text
channel
side
port_index
sample_cycle或等价采样时序元数据

id
addr
len
size
burst_raw
data
strb
resp_raw
last
```

接口payload字段必须使用4-state类型保存，以保留Monitor观察到的X/Z。`burst_raw`和`resp_raw`保存接口原始编码，不得先转换到当前以`bit`为base type的事务枚举而丢失未知态。

### 3.4 各通道有效字段

| Channel | 有效payload |
|---|---|
| AW | `id/addr/len/size/burst_raw` |
| W | `id/data/strb/last` |
| B | `id/resp_raw` |
| AR | `id/addr/len/size/burst_raw` |
| R | `id/data/resp_raw/last` |

无效字段应归一化为0，便于打印和调试，但比较函数只能比较当前channel定义的有效字段。

### 3.5 观察对象边界

`axi_channel_event`不得包含：

- sequence ID或transaction ID。
- `addr_delay/w_start_delay/wbeat_gap[]`。
- `rsp_delay/rbeat_gap[]`。
- Driver内部上下文、队列索引或完成标记。
- Ref model预测的目标端口。
- outstanding或仲裁状态。

Monitor只在真实握手时发布event，因此event对象不需要额外保存`is_handshake`字段；对象被发布本身就表示一次握手已经发生。

### 3.6 对象所有权

- Monitor每次握手创建一个新的event对象。
- 同周期多个通道握手时，每个通道分别创建独立对象。
- Monitor调用analysis port的`write()`后不得再次修改该对象。
- 任何订阅者如果需要修改或跨阶段重新发布对象，必须先clone/copy。
- sample cycle/time属于观察元数据，基础payload比较默认不比较该字段。

### 3.7 Stage 1事务能力限制

Stage 1合法请求必须满足：

```text
len           == 0
addr_delay    == 0
w_start_delay == 0
读请求的wdata/wstrb/wbeat_gap为空
写请求的wdata/wstrb/wbeat_gap长度为1
wbeat_gap[0]  == 0
```

Stage 1合法响应必须满足：

```text
写响应：len==0，rsp_delay==0，读数组为空
读响应：len==0，rsp_delay==0，rdata/rresp长度为1，rbeat_gap为空
```

Driver不得静默忽略超出Stage 1范围的字段。已取得的非法item必须报告明确错误、不得产生总线传输，并保证sequencer握手最终完成。

## 4. S1-02：实现Master Driver单笔单拍能力

### 4.1 类参数和配置

新增参数化`axi_m_driver`，参数与现有Master cfg和sequencer一致：

```text
ADDR_WIDTH
DATA_WIDTH
ID_WIDTH
LEN_WIDTH
```

Driver必须：

- 继承类型正确的`uvm_driver#(axi_req_item, axi_rsp_item)`。
- 使用相同参数specialization的`axi_m_agent_cfg`。
- 只通过cfg中的`m_drv_mp` virtual interface访问接口。
- 在build阶段检查cfg和`drv_vif`非空。
- 在Stage 1检查BREADY/RREADY模式均为`ALWAYS_READY`。
- 在Stage 1检查读写outstanding配置上限均为1。

不支持的cfg值必须在仿真开始阶段给出明确fatal或等价阻止运行的错误，不能表现为已经支持后续Stage能力。

### 4.2 长期任务和信号所有权

Master Driver至少建立以下独立职责：

```text
请求item接收和快照线程
AW worker
W worker
AR worker
BREADY/B接收worker
RREADY/R接收worker
reset和内部状态协调逻辑
```

正常运行和reset期间均必须保持单一信号所有权：

- AW worker唯一驱动AWVALID及AW payload。
- W worker唯一驱动WVALID及W payload。
- AR worker唯一驱动ARVALID及AR payload。
- B worker唯一驱动BREADY。
- R worker唯一驱动RREADY。
- reset协调逻辑可以清理队列和发布reset状态，但不得与通道worker同时驱动同一接口信号。

不得使用一个串行task强制完成AW→W→B或AR→R全过程。

### 4.3 请求快照和共享上下文

Master Driver取得一个请求后必须：

1. 立即clone/copy原始`axi_req_item`。
2. 检查clone类型和Stage 1字段合法性。
3. 为合法请求建立Driver私有上下文。
4. 写请求把同一个上下文句柄登记到AW和W路径。
5. 读请求把上下文登记到AR路径。
6. 所有需要的内部登记成功后调用一次`item_done()`。

写请求上下文至少保存：

- 独立request快照。
- AW路径完成状态。
- W路径完成状态。
- B响应完成或reset终止状态。

AW和W worker共享同一个写上下文，不能各自复制为两个无法长期关联的独立事务。

### 4.4 `item_done()`要求

- 每个`get_next_item()`只能对应一次`item_done()`。
- 写请求必须在AW和W两条路径均完成内部登记后调用`item_done()`。
- 读请求必须在AR路径完成内部登记后调用`item_done()`。
- `item_done()`不等待AW/W/AR握手。
- `item_done()`不等待B/R响应。
- AW/W/AR/B/R worker不得调用`item_done()`。
- 如果item不满足Stage 1能力限制，接收线程仍需结束sequencer握手，但不得把item登记到发送路径。
- reset发生在item已取得但尚未完成登记时，必须保证sequencer不会永久挂起。

### 4.5 AW发送行为

Stage 1的AW worker必须：

- 使用request的`id/addr/len/size/burst`驱动AW payload。
- 在上下文具备发送资格后的第一个可工作clocking event拉高AWVALID。
- 不等待AWREADY拉高后才拉高AWVALID。
- `AWVALID && !AWREADY`期间保持AWVALID和全部AW payload稳定。
- 只在AW握手后撤销AWVALID并把空闲payload清零。
- reset优先终止当前AW活动。

### 4.6 W发送行为

Stage 1的W worker必须：

- 与AW worker独立启动，不等待AW握手。
- 使用`req.id`派生WID。
- 使用`wdata[0]`和`wstrb[0]`驱动单拍数据。
- 单拍请求始终派生`WLAST=1`。
- 不等待WREADY拉高后才拉高WVALID。
- `WVALID && !WREADY`期间保持WVALID、WID、WDATA、WSTRB和WLAST稳定。
- 只在W握手后撤销WVALID并把空闲payload清零。
- reset优先终止当前W活动。

### 4.7 AR发送行为

Stage 1的AR worker必须：

- 使用request的`id/addr/len/size/burst`驱动AR payload。
- 在上下文具备发送资格后的第一个可工作clocking event拉高ARVALID。
- 不等待ARREADY拉高后才拉高ARVALID。
- `ARVALID && !ARREADY`期间保持ARVALID和全部AR payload稳定。
- 只在AR握手后撤销ARVALID并把空闲payload清零。
- 能够与AW和W路径并行运行。

### 4.8 B/R接收行为

- reset释放并经过一个完整空闲clocking event后，BREADY和RREADY持续为1。
- B和R接收路径必须独立运行。
- B握手用于释放Stage 1单笔写上下文。
- R握手且`RLAST=1`用于释放Stage 1单笔读上下文。
- 对没有本地未完成请求的B/R响应给出明确错误。
- Stage 1可以使用唯一未完成上下文检查返回ID，但该检查只服务于Driver内部状态安全，不替代Monitor和端到端Checker的功能判定。

### 4.9 Master sequence response边界

Stage 1 Master Driver不得调用`put_response()`，也不向Master sequence返回独立`axi_rsp_item`。

这是Stage 1尚未实现正式响应关联的阶段限制，不表示关闭`S0-OPEN-01`。在后续多outstanding和响应关联Stage实施前，仍需决定最终默认策略。

## 5. S1-03：实现Slave Driver单笔单拍能力

### 5.1 类参数和配置

新增参数化`axi_s_driver`，参数至少包括：

```text
ADDR_WIDTH
DATA_WIDTH
ID_WIDTH
LEN_WIDTH
```

`ADDR_WIDTH`虽然不参与B/R payload驱动，仍需保留以便Driver使用完全匹配的参数化Slave cfg类型；Slave Driver不得因此承担地址路由或请求重建职责。

Slave Driver必须：

- 继承`uvm_driver#(axi_rsp_item)`。
- 使用相同参数specialization的`axi_s_agent_cfg`。
- 只通过cfg中的`s_drv_mp` virtual interface访问接口。
- 检查cfg和`drv_vif`非空。
- 检查AWREADY/WREADY/ARREADY模式均为`ALWAYS_READY`。

### 5.2 长期任务和信号所有权

Slave Driver至少建立：

```text
响应item接收和快照线程
AWREADY worker
WREADY worker
ARREADY worker
B worker
R worker
reset和内部状态协调逻辑
```

信号所有权固定为：

- 三个READY worker分别唯一驱动AWREADY、WREADY和ARREADY。
- B worker唯一驱动BVALID、BID和BRESP。
- R worker唯一驱动RVALID、RID、RDATA、RRESP和RLAST。
- reset协调逻辑不得形成第二驱动源。

### 5.3 响应快照和`item_done()`

Slave Driver取得`axi_rsp_item`后必须：

1. clone/copy形成独立快照。
2. 检查Stage 1响应字段合法性。
3. 根据`dir`登记到B或R发送路径。
4. 登记成功后调用一次`item_done()`。

`item_done()`不等待BVALID/BREADY或RVALID/RREADY握手。只有响应item接收线程能够调用`item_done()`。

非法或reset中止的已取得item必须结束sequencer握手，不得静默发送或造成sequencer永久等待。

### 5.4 AW/W/AR READY行为

- reset期间AWREADY/WREADY/ARREADY均为0。
- reset释放后先保持一个完整clocking event空闲。
- 空闲边界结束后，三个READY信号分别持续为1。
- READY可以在VALID到达前拉高。
- WREADY不得以AW已经握手作为拉高条件。
- Stage 1不实现容量门控或随机READY。

### 5.5 B响应行为

- 只消费写方向、`len==0`且`rsp_delay==0`的响应快照。
- 使用`rsp.id`驱动8-bit BID。
- 使用`rsp.bresp`驱动BRESP。
- 在响应具备发送资格后的第一个可工作clocking event拉高BVALID。
- BVALID不得依赖BREADY。
- `BVALID && !BREADY`期间保持BID、BRESP和BVALID稳定。
- B握手后撤销BVALID并将空闲payload清零。

### 5.6 R响应行为

- 只消费读方向、`len==0`、`rsp_delay==0`、`rdata/rresp`长度为1且`rbeat_gap`为空的响应快照。
- 使用`rsp.id`驱动RID。
- 使用`rdata[0]`和`rresp[0]`驱动RDATA和RRESP。
- 单拍响应始终派生`RLAST=1`。
- 在响应具备发送资格后的第一个可工作clocking event拉高RVALID。
- RVALID不得依赖RREADY。
- `RVALID && !RREADY`期间保持全部R payload稳定。
- R握手后撤销RVALID并将空闲payload清零。

### 5.7 Slave Driver职责边界

- Slave Driver不根据AW/W/AR接口输入自动创建response。
- Slave Driver不读取Slave Monitor内部状态。
- Slave Driver不检查DUT地址路由或扩展ID是否正确。
- “只对真实请求产生响应”的因果关系由Slave Monitor和reactive Slave sequence建立。
- Driver独立测试可以由pin-level peer提供对应请求背景，但不得把该测试支架变成Driver内部请求模型。

## 6. S1-04：实现Master/Slave Monitor最小能力

### 6.1 共同要求

新增参数化`axi_m_monitor`和`axi_s_monitor`。两者必须：

- 使用相同参数specialization的agent cfg。
- 只通过cfg中的`mon_mp` virtual interface采样。
- 在build阶段检查cfg和`mon_vif`非空。
- 使用一个每周期采样循环检查全部五个通道。
- 允许同一个clocking event发布多个不同channel event。
- 只在`VALID && READY`时发布event。
- 不根据sequence意图或Driver内部状态补造观察结果。
- reset期间不发布event。
- reset发生时清除未完成的局部重建状态。

建议同周期事件按固定顺序发布：

```text
AW → W → B → AR → R
```

该顺序只用于日志和确定性测试，不表示AXI通道之间存在协议优先级。

### 6.2 Master Monitor输出

Master Monitor至少提供：

```text
uvm_analysis_port #(master侧axi_channel_event) channel_ap
```

每个event必须带有：

- `side=UPSTREAM`。
- 当前Master cfg的`port_index`。
- 4-bit原始接口ID。
- 当前握手通道的原始4-state payload。

Stage 1不要求Master Monitor重建完整request或response transaction。

### 6.3 Slave Monitor通道输出

Slave Monitor至少提供：

```text
uvm_analysis_port #(slave侧axi_channel_event) channel_ap
```

每个event必须带有：

- `side=DOWNSTREAM`。
- 当前Slave cfg的`port_index`。
- 8-bit扩展接口ID。
- 当前握手通道的原始4-state payload。

AW/W/B/AR/R五个通道均发布channel event。

### 6.4 Slave Monitor完整请求输出

为建立reactive Slave响应链路，Slave Monitor还必须提供：

```text
uvm_analysis_port #(8-bit ID axi_req_item) req_ap
```

`channel_ap`记录每次原始握手，`req_ap`发布由一个或多个真实请求握手重建的完整单拍请求。两者服务于不同消费者，不表示总线上发生两次传输。

在把4-state event转换成2-state `axi_req_item`前，Monitor必须确认该请求的有效payload不存在X/Z。如果存在未知态，仍发布原始channel event以保留证据，但不得生成会把X/Z静默转换为0的完整request，并应报告明确错误。

### 6.5 单拍读请求重建

一次AR握手已经包含单拍读请求的全部请求属性。Slave Monitor应在AR握手时：

1. 发布一个AR channel event。
2. 创建新的8-bit ID `axi_req_item`。
3. 填写`dir/id/addr/len/size/burst`。
4. 将写数据数组保持为空。
5. 将无法从接口观察的delay/gap字段归一化为0或空数组。
6. 通过`req_ap`发布完整读请求。

Stage 1只接受`ARLEN==0`。观察到`ARLEN!=0`时仍发布channel event，但不得伪装为Stage 1已经支持的完整请求。

### 6.6 单拍写请求重建

写请求需要同时获得AW和W握手信息。Slave Monitor必须：

- 保存一个待匹配AW观察快照。
- 保存一个待匹配W观察快照。
- 支持AW先握手、W先握手或二者同周期握手。
- 只有AW和带`WLAST=1`的单拍W均完成真实握手后才发布完整写请求。
- 使用AWID作为请求ID，并检查Stage 1唯一WID与AWID一致。
- 使用AW属性填写地址字段。
- 使用W payload建立长度为1的`wdata[]`和`wstrb[]`。
- 将`addr_delay/w_start_delay/wbeat_gap[0]`归一化为0。
- 发布后清除当前AW/W局部重建状态。

如果Stage 1唯一AW和W的ID不一致、AWLEN不为0或W握手未带WLAST，Monitor仍须保留已经发布的channel event，并给出无法按Stage 1规则完成请求重建的明确错误。

### 6.7 B/R观察边界

Slave Monitor对B和R握手只发布channel event。Stage 1不要求Slave Monitor增加完整`rsp_ap`或重建多beat响应。

## 7. S1-05：实现基础Sequence和Reactive Slave链路

### 7.1 Master单拍sequence

实现可复用的单拍写和单拍读sequence。sequence必须显式约束：

```text
len           == 0
addr_delay    == 0
w_start_delay == 0
wbeat_gap     符合Stage 1尺寸和值限制
```

Master sequence负责选择ID、地址、SIZE、BURST、写数据和WSTRB，不直接驱动接口，不等待Driver内部B/R状态，也不读取Monitor结果。

Stage 1 sequence不调用`get_response()`，与Master Driver不返回sequence response的阶段边界保持一致。

### 7.2 扩展Slave Sequencer

现有`axi_s_sequencer`需要增加请求观察入口。推荐：

- 增加`ADDR_WIDTH`参数，使下游请求类型能够保持完整参数化。
- 定义8-bit ID `axi_req_item`请求类型。
- 在sequencer中创建请求`uvm_tlm_analysis_fifo`或等价FIFO。
- 为Slave Monitor的`req_ap`暴露类型正确的analysis export。
- 保持sequencer原有response item类型为8-bit ID `axi_rsp_item`。

该参数变更必须同步更新Stage 0测试中的Slave sequencer specialization，并通过Stage 0回归。

### 7.3 Reactive Slave sequence

实现最小reactive Slave response sequence：

```text
Slave Monitor.req_ap
        ↓
Slave sequencer请求FIFO
        ↓
Reactive Slave sequence
        ↓ axi_rsp_item
Slave Driver
```

sequence必须：

- 只根据已经重建并发布的真实下游请求产生响应。
- 写请求产生一个`AXI_RESP_OKAY` B响应。
- 读请求产生一个单拍`AXI_RESP_OKAY` R响应。
- 原样复制8-bit请求ID和`len=0`。
- 将`rsp_delay`设为0。
- 将`rbeat_gap`保持为空。
- 允许测试指定确定性读数据。
- 不实现memory model、随机错误响应、乱序或交织。

Reactive sequence应由test控制预期处理的请求数量并能够正常结束，不应依赖永久`forever`循环持有objection导致仿真无法退出。

### 7.4 对象所有权

- Slave Monitor发布完整request后不得再次修改。
- 请求FIFO持有已发布对象句柄；如果reactive sequence需要修改请求，必须先clone。
- response必须是新创建的`axi_rsp_item`，不得把请求对象强制转换或改写为响应。
- response发送完成后的原始response item所有权仍遵守UVM sequence/Driver协议。

## 8. S1-06：实现Master/Slave Agent

### 8.1 Master Agent

新增参数化`axi_m_agent`：

- 从`uvm_config_db`取得类型正确的`axi_m_agent_cfg`。
- 总是创建Master Monitor。
- `is_active==UVM_ACTIVE`时创建Master sequencer和Master Driver。
- active模式下连接`driver.seq_item_port`与`sequencer.seq_item_export`。
- 把同一个单端口cfg精确传递给本Agent内的Driver和Monitor。
- passive模式不创建Driver或sequencer，也不驱动接口。

### 8.2 Slave Agent

新增参数化`axi_s_agent`：

- 从`uvm_config_db`取得类型正确的`axi_s_agent_cfg`。
- 总是创建Slave Monitor。
- `is_active==UVM_ACTIVE`时创建Slave sequencer和Slave Driver。
- active模式下连接response sequencer和Driver。
- active模式下连接Slave Monitor的`req_ap`与Slave sequencer请求FIFO的analysis export。
- 把同一个单端口cfg精确传递给本Agent内的Driver和Monitor。
- passive模式不创建Driver、sequencer或reactive内部连接。

### 8.3 Agent共同边界

- Agent只绑定一个物理interface实例。
- Agent不得保存或索引三端口interface数组。
- `port_index`只用于日志和观察对象元数据。
- Agent不实现路由、仲裁、Scoreboard或test场景。
- virtual interface路径必须精确，不能使用使多个Agent得到同一interface的宽泛通配符。

## 9. S1-07：实现三类Checker和端到端检查路径

### 9.1 Driver pin-level Checker

在Master Driver unit和Slave Driver unit测试支架中实现`pin_peer_checker`。它直接读取interface引脚，至少提供：

```text
sequence item/握手计划输入
实际引脚传输记录
握手和stall状态记录
match/mismatch计数
test结束时未完成检查
```

比较规则：

- sequence item和测试预设握手计划作为expected，Driver在interface上的实际输出作为actual。
- Master Driver侧检查AW/W/AR payload、VALID、BREADY/RREADY、WLAST及stall期间稳定性。
- Slave Driver侧检查AWREADY/WREADY/ARREADY、B/R payload、VALID、RLAST及stall期间稳定性。
- 允许pin-level peer驱动被测Driver的输入信号，但checker不得调用正式Monitor弥补引脚检查，也不得产生DUT转发expected。
- test结束时必须检查预期握手和实际握手计数一致，且没有未完成的发送或响应。

### 9.2 基础事件比较组件

实现`axi_basic_event_comparator`，至少提供：

```text
expected事件输入
actual事件输入
match计数
mismatch计数
未匹配对象检查
```

比较规则：

- 首先比较side、port和channel。
- 只比较当前channel定义的有效payload。
- 使用保留X/Z语义的4-state比较。
- 默认不比较sample cycle/time。
- 比较组件不得驱动总线或产生Slave响应。
- test结束时必须检查expected和actual均无残留。

### 9.3 Stage 1端到端Checker

Stage 1B实现并使用`stage1_e2e_checker`，通过`upstream_export`和`downstream_export`接收M0上游Monitor和S0下游Monitor的channel event，检查：

- 上游AW与下游AW的协议payload一致，ID按项目规则扩展。
- 上游W与下游W的数据、WSTRB和LAST一致，ID按项目规则扩展。
- 上游AR与下游AR的协议payload一致，ID按项目规则扩展。
- 下游B与上游B的RESP一致，上游ID恢复为原始4-bit ID。
- 下游R与上游R的数据、RESP和LAST一致，上游ID恢复为原始4-bit ID。
- 每个预期事件只匹配一次，无丢失、重复或额外事件。

Checker不得要求固定DUT流水延迟，只按本阶段的单笔单拍顺序匹配。

### 9.4 与最终Scoreboard的边界

`stage1_e2e_checker`是测试支架，不命名或宣称为最终系统级`axi_scoreboard`。它不实现：

- 三主三从跨端口队列。
- Default Slave路径。
- 任意地址路由预测。
- 多ID匹配和乱序。
- outstanding、交织和仲裁检查。

后续正式Scoreboard可以复用event类型和通道payload比较函数，但不得把Stage 1单FIFO假设扩展为全局比较规则。

## 10. S1-08：建立独立组件测试支架

### 10.1 总体原则

Stage 1A测试不例化AXI Interconnect DUT。测试顶层例化一个4-bit Master侧`axi_if`和一个8-bit Slave侧`axi_if`，由简单pin-level peer或确定性波形发生器完成正式对端组件的职责。

必须遵守：

- Master Driver测试不以正式Master Monitor作为唯一判断依据。
- Slave Driver测试不依赖正式Slave Monitor或reactive sequence才能产生响应item。
- Monitor测试不以正式Driver作为唯一激励源。
- 比较组件测试允许直接注入expected和actual对象。

### 10.2 Master Driver测试支架

pin-level peer负责：

- 驱动AWREADY、WREADY和ARREADY。
- 在请求握手后产生确定性B或R响应。
- 记录并直接检查Master Driver接口输出。

至少覆盖：

- 单拍写AW和W payload正确。
- AW和W可以独立握手。
- 分别stall AW和W时payload稳定。
- 单拍读AR payload正确。
- stall AR时payload稳定。
- BREADY和RREADY在正常阶段持续为1。
- WID来自请求ID，WLAST为1。
- sequence的`finish_item()`能够在总线READY保持低时返回，证明`item_done()`不等待握手。
- sequence在`finish_item()`返回后修改原始item不改变Driver已锁定payload。

### 10.3 Slave Driver测试支架

pin-level peer负责：

- 产生确定性AW/W/AR请求背景。
- 控制BREADY和RREADY。
- 直接检查Slave Driver的READY及B/R接口输出。

至少覆盖：

- reset释放后AWREADY/WREADY/ARREADY均为1。
- READY可以先于VALID拉高。
- WREADY不依赖AW握手。
- 单笔B响应ID和RESP正确。
- stall BREADY时BVALID和payload稳定。
- 单拍R响应ID、DATA、RESP和RLAST正确。
- stall RREADY时RVALID和payload稳定。
- response sequence的`finish_item()`不等待接口响应握手。

### 10.4 Monitor测试支架

确定性pin-level波形发生器负责产生五通道组合，至少验证：

- `VALID=1 && READY=0`不发布event。
- 一次真实握手只发布一个event。
- 连续VALID跨多个周期只按实际握手次数发布。
- 同周期多个通道握手时分别发布多个event。
- Master Monitor正确保留4-bit ID。
- Slave Monitor正确保留8-bit ID。
- event使用独立对象且后续事件不会覆盖先前对象。
- reset期间不发布event。
- Slave Monitor支持AW先于W、W先于AW和同周期AW/W，并只在请求完整时发布一次request。

### 10.5 Agent和Reactive链路测试

在不例化DUT的情况下直接验证：

- active Agent创建并连接预期子组件。
- passive Agent只创建Monitor。
- cfg和virtual interface没有串接。
- 向Slave Monitor提供一个单拍AR后，reactive sequence产生正确R response item。
- 向Slave Monitor提供一个完整单拍AW/W后，reactive sequence产生正确B response item。
- 只提供AW或只提供W时不产生提前B响应。

## 11. S1-09：建立DUT桥接和单端口最小闭环

### 11.1 Stage 1专用顶层

新增Stage 1端到端测试顶层，至少包含：

```text
ACLK和低有效ARESETn
一个4-bit ID Master侧axi_if
一个8-bit ID Slave侧axi_if
axi_interconnect DUT
DUT分立数组端口桥接信号
未启用端口idle tie-off
基础protocol assertions
```

顶层不使用旧`uvm_tb/tb/testbench.sv`或旧RTL testbench。

### 11.2 DUT bridge

活动端口固定为：

```text
Master Agent 0 ↔ Master axi_if ↔ DUT M_AXI_*[0]
Slave Agent 0  ↔ Slave axi_if  ↔ DUT S_AXI_*[0]
```

连接方向必须遵守：

| 连接侧 | Testbench到DUT | DUT到Testbench |
|---|---|---|
| M0上游 | AW/W/AR payload及VALID，BREADY/RREADY | AWREADY/WREADY/ARREADY，B/R payload及VALID |
| S0下游 | AWREADY/WREADY/ARREADY，B/R payload及VALID | AW/W/AR payload及VALID，BREADY/RREADY |

其余端口必须确定性置空：

- M1/M2的AW/W/AR VALID和payload为0，BREADY/RREADY为0。
- S1/S2的AWREADY/WREADY/ARREADY为0，B/R VALID和payload为0。
- 不得对DUT输出形成第二驱动源。

### 11.3 UVM组件组装

Stage 1测试层实例化：

```text
一个axi_m_agent，使用m_cfg[0]
一个axi_s_agent，使用s_cfg[0]
一个stage1_e2e_checker
```

暂不创建把Master和Slave永久绑定成一对的生产级`single_port_env`，因为完整crossbar环境中Master和Slave不是一对一拓扑。Stage 1的组合层明确属于测试支架；可复用Agent保持单端口边界，后续完整`axi_env`再按三主三从独立实例化。

### 11.4 最小写闭环

写闭环必须按以下真实因果关系运行：

```text
Master write sequence
        ↓ axi_req_item
Master Driver
        ↓ 上游AW/W握手
DUT
        ↓ 下游AW/W握手
Slave Monitor
        ↓ 完整单拍write request
Reactive Slave sequence
        ↓ axi_rsp_item
Slave Driver
        ↓ 下游B握手
DUT
        ↓ 上游B握手
Master Monitor和stage1_e2e_checker
```

不得由test根据Master sequence意图直接提前启动B响应。

### 11.5 最小读闭环

读闭环必须按以下真实因果关系运行：

```text
Master read sequence
        ↓ axi_req_item
Master Driver
        ↓ 上游AR握手
DUT
        ↓ 下游AR握手
Slave Monitor
        ↓ 完整单拍read request
Reactive Slave sequence
        ↓ axi_rsp_item
Slave Driver
        ↓ 下游R握手
DUT
        ↓ 上游R握手
Master Monitor和stage1_e2e_checker
```

读数据由Stage 1 reactive sequence使用确定性配置值产生，不要求写后读memory一致性。

### 11.6 Stage 1定向ID限制

项目预期的下游扩展ID格式为：

```text
{2-bit Slave编码, 2-bit Master编码, 4-bit原始ID}
```

M0访问S0时预期：

```text
expected_sid = {2'b01, 2'b01, original_id}
```

当前RTL写数据路由还依赖原始`WID[3:2]`选择目标Slave。为使Stage 1闭环专注于验证环境连通性，M0到S0的写smoke固定选择：

```text
original_id[3:2] == 2'b01
```

推荐定向值：

```text
original_id = 4'h5
expected_sid = 8'h55
```

该限制标记为`S1-LIMIT-01`，只适用于Stage 1定向smoke：

- 不得加入`axi_req_item`通用约束。
- 不得写入Master Driver作为合法性规则。
- 不得解释为AXI3对ID的限制。
- 后续完整ID和路由测试仍需检查并报告RTL对`WID[3:2]`的非协议依赖。

## 12. S1-10：实现基础Reset和协议检查

### 12.1 Driver reset输出

Master Driver在reset期间驱动：

```text
AWVALID=0
WVALID=0
ARVALID=0
BREADY=0
RREADY=0
全部主动payload=0
```

Slave Driver在reset期间驱动：

```text
AWREADY=0
WREADY=0
ARREADY=0
BVALID=0
RVALID=0
全部主动payload=0
```

### 12.2 reset状态处理

- Master/Slave Driver在获取新item前等待`ARESETn===1'b1`。
- Master Driver取得request后先clone；写快照在`item_done()`前同时放入AW/W mailbox，读快照在`item_done()`前放入AR mailbox。
- Slave Driver取得response后先clone，并在`item_done()`前放入B或R mailbox。
- 各通道发送task在reset中撤销自己驱动的VALID和payload；READY task使用明确的reset/normal分支驱动0或1。
- `watch_reset()`只清理共享busy/ID状态和mailbox，旧快照不在reset释放后重新入队。
- Master/Slave Monitor在reset期间不发布event；Slave Monitor同时清除未完成的AW/W重建状态。
- 当前`axi_basic_event_comparator`和`stage1_e2e_checker`没有reset端口或自动清空逻辑。当前保留用例只在启动reset之后发送事务，因此Checker不会跨reset保存业务状态；后续若加入运行中reset闭环，必须补充统一的Checker清理机制。

### 12.3 Stage 1 reset测试范围

当前保留的`axi_write_test`和`axi_read_test`覆盖仿真启动reset、reset期间无业务event以及reset释放后完成新单拍事务。空闲期间再次reset和VALID stall期间reset曾在Stage 1A一次性unit支架中审核，当前目录收敛后的日常闭环用例未保留这两类场景。

运行中reset的Checker统一清理、burst中途reset、多outstanding清理、交织候选清理和容量状态恢复留到后续Stage。

### 12.4 基础协议检查

当前代码保留以下运行时检查：

- Master Driver检查B/R响应是否存在待完成请求、返回ID是否一致，以及单拍R是否带RLAST。
- Slave Monitor检查AWID/WID一致、AWLEN/ARLEN为0，以及单拍W是否带WLAST。
- `stage1_e2e_checker`使用4-state比较检查五通道payload、M0/S0端口位置、ID扩展/恢复、B/R因果关系、重复/遗漏和结束时pending状态。
- `axi_base_test.finish_test()`汇总e2e mismatch、pending event和Slave request FIFO，并以UVM错误数判定用例结果。

当前接口中没有SVA集合，stall稳定性和握手X/Z也没有作为独立常驻assertion实现；Stage 1A的pin-level检查支架已经删除。响应依赖、完整burst LAST计数、4KB、ordering、outstanding和仲裁规则继续留给后续Stage。

### 12.5 已落地的代码组织风格

- `axi_if`只用modport声明方向，不使用带`input #1step`或`output #0`偏斜的clocking block。
- Driver和Monitor通过`vif.signal`直接访问接口，并用`@(posedge vif.ACLK)`同步；Driver使用非阻塞赋值驱动信号。
- `axi_channel_event`、Master/Slave Driver和Master/Slave Monitor在类内声明`extern`方法，在同一文件的`endclass`之后实现；内部task不加`local`。
- Driver不再包含`valid_stage1_request()`一类重复事务边界检查；请求字段能力由sequence、Monitor和Checker按职责检查。
- reset值和正常值采用清晰的`if/else`分支赋值，避免使用复位比较表达式直接生成控制信号。
- 详细约束以`dv/doc/code_style.md`为准。

## 13. S1-11：建立Package、文件组织和回归入口

### 13.1 当前项目代码结构

当前Stage 1相关源码和仿真入口如下：

```text
dv/
├── common/
│   └── axi_types_pkg.sv
├── doc/
│   ├── code_style.md
│   ├── stage.md
│   ├── stage0.md
│   └── stage1.md
├── env/
│   ├── axi_env_pkg.sv
│   ├── axi_channel_event.sv
│   ├── axi_basic_event_comparator.sv
│   ├── axi_env_cfg.sv
│   ├── axi_env.sv
│   ├── axi_req_item.sv
│   ├── axi_rsp_item.sv
│   ├── master/
│   │   ├── axi_m_agent_cfg.sv
│   │   ├── axi_m_sequencer.sv
│   │   ├── axi_m_driver.sv
│   │   ├── axi_m_monitor.sv
│   │   └── axi_m_agent.sv
│   └── slave/
│       ├── axi_s_agent_cfg.sv
│       ├── axi_s_sequencer.sv
│       ├── axi_s_driver.sv
│       ├── axi_s_monitor.sv
│       └── axi_s_agent.sv
├── seq/
│   ├── axi_seq_pkg.sv
│   ├── axi_m_single_write_seq.sv
│   ├── axi_m_single_read_seq.sv
│   └── axi_s_single_reactive_seq.sv
├── tc/
│   ├── support/
│   │   ├── stage1_e2e_checker.sv
│   │   └── axi_test_env.sv
│   ├── axi_test_pkg.sv
│   ├── axi_base_test.sv
│   ├── axi_write_test.sv
│   └── axi_read_test.sv
├── tb/
│   ├── axi_if.sv
│   └── tb.sv

rtl/
├── axi_interconnect.v
├── axi_crossbar.v
├── axi_mtos_m3.v
├── axi_stom_s3.v
├── axi_arbiter_mtos_m3.v
├── axi_arbiter_stom_s3.v
├── axi_default_slave.v
├── axi_fifo_sync.v
├── round_robin_m2s.v
├── round_robin_s2m.v
├── sid_buffer.v
└── reorder.v

sim/
├── Makefile
├── sim.f
└── work/
    ├── lib/              # Questa work编译库
    ├── log/              # compile.log和各test日志
    ├── wave/             # <test>.wlf
    ├── cov/              # UCDB和HTML覆盖率报告
    └── modelsim.ini      # 本地library mapping
```

各目录职责为：`dv/env`只放可复用验证组件，`dv/seq`放sequence，`dv/tc`放测试及测试专用env/checker，`dv/tb`只保留interface和唯一顶层，`rtl`放DUT源码，`sim`联合编译RTL与DV并保存运行产物。

仓库根目录还保留以下历史或参考内容，但它们不进入当前`sim/sim.f`：

- `doc/`：总体验证规范、框架规范、历史讨论摘要和更细测试计划。
- `design/`：历史AXI slave模型，接口契约与当前AXI3 Interconnect环境不同。
- `uvm_tb/`：旧验证环境和旧测试用例，仅作为历史参考。
- `rtl/axi_interconnect_tb.v`和`rtl/filelist.f`：RTL历史测试入口；当前统一顶层为`dv/tb/tb.sv`。

`axi_test_pkg.sv`是测试代码的统一编译、typedef和factory注册入口，不属于冗余文件。`axi_test_env`继承一主一从特化的`axi_env`并增加`stage1_e2e_checker`。Stage 1A审核使用过的pin-level peer、`pin_peer_checker`及独立unit test package在组件审核完成后删除；`stage1_e2e_checker`仍保持测试支架身份，不include进生产环境package。

### 13.2 `axi_env_pkg` include顺序

当前`axi_env_pkg.sv`的实际include顺序：

```text
1. axi_req_item.sv
2. axi_rsp_item.sv
3. axi_channel_event.sv
4. master/axi_m_agent_cfg.sv
5. slave/axi_s_agent_cfg.sv
6. axi_env_cfg.sv
7. master/axi_m_sequencer.sv
8. slave/axi_s_sequencer.sv
9. master/axi_m_driver.sv
10. slave/axi_s_driver.sv
11. master/axi_m_monitor.sv
12. slave/axi_s_monitor.sv
13. master/axi_m_agent.sv
14. slave/axi_s_agent.sv
15. axi_env.sv
16. axi_basic_event_comparator.sv
```

`axi_if.sv`由`sim.f`在package之前单独编译，不include到package中。

### 13.3 编译顺序

Stage 1总体编译顺序为：

```text
1. UVM package和宏
2. axi_types_pkg.sv
3. axi_if.sv
4. axi_env_pkg.sv
5. axi_seq_pkg.sv
6. axi_test_pkg.sv
7. RTL设计源码
8. tb.sv
```

不得直接使用包含旧testbench入口的历史RTL文件列表。Stage 1B文件列表只纳入`axi_interconnect`及其设计依赖模块和新的Stage 1顶层。

### 13.4 Makefile目标

`sim/Makefile`当前提供：

```text
make clean
make clean_all
make com
make sim test=axi_write_test SEED=1
make all test=axi_read_test dump=y SEED=1
make debug test=axi_write_test dump=y SEED=1
make wave test=axi_write_test
make all test=axi_read_test cov=y SEED=1
make cov_report test=axi_read_test
make regress test=axi_write_test reg_times=20
```

当前行为：

- `make all`依次执行`clean`、`com`和`sim`；`make com`只编译，`make sim`使用已有编译库仿真。
- 变量名为小写`test`，通过`+UVM_TESTNAME=$(test)`传给顶层`run_test()`；当前不使用旧的`TESTNAME`写法。
- `dump=y`记录`m_if`、`s_if`和`dut`层次，生成`work/wave/<test>.wlf`；`make wave`用Questa打开该WLF。
- `cov=y`启用Questa代码覆盖率，生成`work/cov/<test>.ucdb`；`make cov_report`生成HTML报告。这里是代码覆盖率，不是Stage 1未实现的UVM functional coverage。
- `rand=y`自动生成seed；否则`SEED`默认0。`regress`按`reg_times`重复当前选定的一个`test`，不会自动同时运行读写两个test。
- QuestaSim 10.6c会把名为`dump`的环境变量识别为内部层次转储开关，因此Makefile使用`unexport dump`，但用户侧`dump=y/n`用法不变。
- `clean`删除`work/lib`和`work/modelsim.ini`，保留日志、波形和覆盖率；`clean_all`删除整个`work`。
- 仿真后脚本同时检查`AXI_TC_PASS`、`UVM_ERROR : 0`和`UVM_FATAL : 0`，任一条件不满足则Make返回失败。
- `sim.f`按上一小节的编译顺序引用当前RTL和DV，不引用旧`uvm_tb`。

# 第三部分：Stage 1验收方案

## 14. 验收总体要求

Stage 1验收分为Stage 1A组件级验收和Stage 1B最小闭环验收。

- Stage 1A必须先证明Driver、Monitor、Agent、sequence和比较组件自身行为正确。
- Stage 1B只能使用已经通过Stage 1A验收的正式组件建立闭环。
- 端到端闭环通过不能替代组件级验收。
- Stage 1A审核阶段的`pin_peer_checker`和独立unit test只作为一次性验收支架；审核通过后的日常回归保留真实DUT闭环。
- `axi_basic_event_comparator`保留在`dv/env`，用于同类型event的基础比较；`stage1_e2e_checker`用于当前上下游ID宽度不同的DUT闭环。
- 所有测试使用新`dv`入口，不依赖旧`uvm_tb`。
- 所有通过测试必须无非预期UVM warning/error/fatal及SystemVerilog fatal。

## 15. A1-01：文档、职责和Stage边界审核

- 核对本工单覆盖`stage.md`中的全部Stage 1A和Stage 1B内容。
- 核对Driver只消费item并驱动接口，不产生Monitor actual。
- 核对Monitor只根据真实握手产生event或重建请求。
- 核对Slave reactive响应只能由真实下游请求触发。
- 核对event、完整request和response item的职责没有混淆。
- 核对Stage 1只支持单笔、单拍、ALWAYS_READY和零delay/gap。
- 核对没有提前实现burst、复杂READY、多outstanding、乱序、交织或正式Tracker。
- 核对`S0-OPEN-01`没有被Stage 1实现擅自关闭。
- 核对`S1-LIMIT-01`只存在于定向smoke，不污染通用transaction或Driver。

## 16. A1-02：Stage 0回归和Stage 1独立编译

- 从干净构建目录重新执行Stage 0 smoke并通过。
- 编译4-bit Master和8-bit Slave两组event、Driver、Monitor和Agent specialization。
- 编译增加`ADDR_WIDTH`后的Slave sequencer和reactive sequence。
- factory能够创建所有新增参数化UVM object/component。
- active/passive Agent均能完成build/connect。
- Stage 1 unit文件列表不包含DUT或旧`uvm_tb`。
- Stage 1 e2e文件列表只包含必要RTL设计文件和新测试顶层。
- 编译日志无非预期error和warning。

## 17. A1-03：Master Driver独立验收

至少执行以下确定性测试：

1. 单拍写请求AW和W均完成握手，payload正确。
2. AWREADY先低后高，AWVALID和payload在stall期间稳定。
3. WREADY先低后高，WVALID、WID、WDATA、WSTRB和WLAST稳定。
4. AWREADY和WREADY采用不同节奏，证明AW/W独立推进。
5. 单拍读请求完成AR握手，payload正确。
6. ARREADY stall期间ARVALID和payload稳定。
7. BREADY和RREADY在正常ALWAYS_READY阶段保持为1。
8. 请求ID正确派生为WID，单拍WLAST为1。
9. pin peer未拉高READY时sequence已经结束`finish_item()`。
10. sequence修改原始item后接口上的已锁定payload不变。
11. 每个item只发生一次`item_done()`。
12. reset能够终止当前单拍活动且不重放。
13. `pin_peer_checker`的预期握手全部匹配，match/mismatch和未完成计数符合预期。

## 18. A1-04：Slave Driver独立验收

至少执行：

1. reset释放和一个空闲clocking event后，AWREADY/WREADY/ARREADY均为1。
2. VALID为0时READY仍可保持为1。
3. WREADY不等待AW握手。
4. 单笔B响应的BID和BRESP正确。
5. BREADY stall期间BVALID和payload稳定。
6. 单拍R响应的RID、RDATA、RRESP和RLAST正确。
7. RREADY stall期间RVALID和payload稳定。
8. B和R路径可以独立运行。
9. response sequence的`finish_item()`不等待接口握手。
10. reset能够终止当前B/R活动且不重放。
11. `pin_peer_checker`的预期READY和B/R传输全部匹配，且无未完成检查。

## 19. A1-05：Master/Slave Monitor独立验收

- 对AW/W/B/AR/R分别制造一次握手并检查event内容。
- VALID没有与READY同时为1时不发布event。
- 同周期多个通道握手时每个通道各发布一个对象。
- event中的side、port、channel和4-state payload正确。
- Master Monitor保存4-bit ID，Slave Monitor保存8-bit ID。
- 每个event为独立对象，后续发布不修改先前对象。
- reset期间不发布event并清除部分请求重建状态。
- Slave Monitor在AR握手后发布一次完整读request。
- Slave Monitor在AW和W均完成后发布一次完整写request。
- 分别覆盖AW先于W、W先于AW和AW/W同周期。
- 只出现AW或只出现W时不得发布完整写request。
- 上述channel event均通过`axi_basic_event_comparator`以波形发生器同步创建的event为expected、Monitor `channel_ap`输出为actual进行判定。

## 20. A1-06：Agent、Sequence和Reactive链路验收

- active Master Agent包含sequencer、Driver和Monitor且连接正确。
- passive Master Agent只包含Monitor。
- active Slave Agent包含sequencer、Driver和Monitor且两条TLM连接正确。
- passive Slave Agent只包含Monitor。
- Master读写sequence只产生Stage 1合法item。
- Slave sequencer请求FIFO能够接收8-bit ID完整request。
- 单拍读request产生ID相同、数据确定、OKAY的R response item。
- 完整单拍写request产生ID相同、OKAY的B response item。
- 未完成写请求不产生提前B response item。
- reactive sequence能够按照test指定数量正常结束。

## 21. A1-07：基础比较组件验收

- AW/W/B/AR/R五种相同事件均能够匹配成功。
- 每个channel只比较定义的有效payload。
- sample cycle不同不造成payload误判。
- ID、地址、数据、STRB、RESP或LAST发生差异时能够检测mismatch。
- X/Z差异不能因2-state转换而被隐藏。
- 比较结束后expected和actual队列均为空。
- 直接对象测试不依赖正式Driver、Monitor或DUT。

## 22. A1-08：单端口写闭环验收

使用M0到S0、`len=0`、零delay/gap和`ALWAYS_READY`运行单拍写：

- 上游M0 AW和W均完成一次握手。
- 下游S0 AW和W均完成一次握手。
- Slave Monitor只在AW/W完整后发布一次写request。
- reactive sequence产生一次8-bit ID B response item。
- Slave Driver完成一次下游B握手。
- DUT完成一次上游B握手。
- `stage1_e2e_checker`确认AW/W payload、WSTRB、LAST、RESP和ID变换正确。
- 使用`original_id=4'h5`时，下游扩展ID为`8'h55`，返回上游BID为`4'h5`。
- 测试结束所有Stage 1匹配队列和局部请求状态清空。

## 23. A1-09：单端口读闭环验收

使用M0到S0、`len=0`、零delay/gap和`ALWAYS_READY`运行单拍读：

- 上游M0 AR完成一次握手。
- 下游S0 AR完成一次握手。
- Slave Monitor发布一次完整读request。
- reactive sequence产生一次8-bit ID、确定性数据和OKAY的R response item。
- Slave Driver完成一次下游R握手且RLAST为1。
- DUT完成一次上游R握手且RLAST为1。
- `stage1_e2e_checker`确认AR属性、RDATA、RRESP、LAST和ID变换正确。
- 使用`original_id=4'h5`时，下游扩展ID为`8'h55`，返回上游RID为`4'h5`。
- 测试结束所有Stage 1匹配队列和局部请求状态清空。

## 24. A1-10：Reset、协议检查和Stage完成检查

### 24.1 Reset验收

- 启动reset期间所有Testbench主动VALID/READY和payload为0。
- reset释放后存在至少一个完整clocking event空闲边界。
- 空闲reset后组件可以继续完成新事务。
- 单拍VALID stall期间reset会撤销VALID、清零payload并终止旧事务。
- reset前未完成事务不会在reset释放后自动重放。
- reset不会造成sequencer永久挂起。
- Stage 1A历史unit支架在测试结束时确认Monitor重建状态和pin-level检查状态无残留。

当前保留的读写闭环只重新执行前两项启动reset检查；运行中reset和Checker自动清理尚未形成常驻回归，具体边界见12.2和12.3。

### 24.2 基础协议检查验收

- 对Master Driver AW/W/AR和Slave Driver B/R分别制造stall，稳定性检查无误报或漏报。
- 对非法X/Z握手波形的测试支架能够报告错误。
- Monitor不会对未握手周期重复发布event。
- 单拍W/R的LAST检查通过。
- pin-level支架能够区分环境侧和DUT侧违规来源。

上述stall和X/Z检查属于Stage 1A历史unit审核内容；当前仓库没有保留对应支架，也没有常驻SVA集合。当前可重跑检查是Monitor握手发布、单拍LAST、Driver响应关联和端到端4-state比较。

### 24.3 Stage边界检查

变更集合中不得出现：

- burst循环发送或多beat重建实现。
- delay/gap运行状态机。
- RANDOM/SCRIPTED READY状态机。
- 大于1的outstanding调度。
- 不同ID乱序队列。
- W/R交织仲裁。
- 正式Tracker、Reference Model、Arbiter Checker或最终Scoreboard。
- functional coverage。
- 三主三从完整UVM环境组装。

## 25. 后续Stage再验证的内容

以下内容不作为Stage 1完成门槛：

- 1～16 beat burst发送和Monitor重建。
- delay/gap的精确运行时计数。
- 五通道确定性backpressure策略。
- 多outstanding、同ID保序和不同ID乱序。
- WID/RID交织。
- 完整READY随机及脚本策略。
- 容量门控和复杂reset清理。
- 三主三从并行、路由、仲裁和Default Slave。
- 正式Tracker、Reference Model和系统级Scoreboard。
- 完整assertion、functional coverage和随机压力回归。
- Master Driver是否向Master sequence返回独立response的最终策略。

## 26. Stage 1完成条件

Stage 1满足以下全部条件才可标记完成：

1. 本工单已经审核并冻结。
2. S1-01～S1-11全部实施完成。
3. Stage 0在目录收敛前的历史回归通过，结果已记录。
4. A1-01～A1-07组件级历史验收全部通过，当前保留组件与审核版本一致。
5. A1-08单拍写闭环通过。
6. A1-09单拍读闭环通过。
7. A1-10历史unit检查通过；当前保留闭环的启动reset、单拍协议和Stage边界检查通过。
8. 编译及仿真无非预期warning、error或fatal。
9. Stage 1A历史unit审核结束时`pin_peer_checker`和`axi_basic_event_comparator`无pending；当前闭环结束时`stage1_e2e_checker.pending_count()==0`且Slave request FIFO为空。
10. 新`dv`环境未引用旧`uvm_tb`代码。
11. 实施结果、工具版本、命令和已知限制已经记录。

## 27. 审核记录

| 审核项 | 状态 | 说明 |
|---|---|---|
| Stage 1A范围 | 已冻结 | Driver、Monitor、Agent、sequence和基础比较组件 |
| Stage 1B范围 | 已冻结 | M0到S0单端口单拍读写闭环 |
| Channel event模型 | 已冻结 | 统一采用`axi_channel_event`和4-state payload |
| Slave Monitor双输出 | 已冻结 | `channel_ap`发布握手，`req_ap`发布完整请求 |
| Driver线程和对象所有权 | 已冻结 | 保持Stage 0共享上下文及`item_done()`契约 |
| Reactive Slave链路 | 已冻结 | 只响应真实重建请求 |
| 基础Checker边界 | 已冻结 | 不作为最终系统级Scoreboard |
| `S1-LIMIT-01` | 已冻结 | 写smoke使用ID 4'h5，不污染通用约束 |
| Reset和协议检查 | 已冻结 | 只覆盖单笔单拍基础能力 |
| 验收方案 | 已冻结 | Stage 1A和Stage 1B必须分别通过 |

### 27.1 实施与验收记录

Stage 1A已经完成组件级验收，Stage 1B已经完成DUT单端口闭环验收。

| 记录项 | 实施结果 |
|---|---|
| 实施日期 | Stage 1A：2026-09-13；Stage 1B：2026-09-14；当前结构与运行复核：2026-09-15 |
| 工具版本 | QuestaSim 10.6c，UVM 1.1d |
| 当前编译命令 | 在`sim/`执行`make clean`后执行`make com`；Questa使用`sim.f`和本地`work/modelsim.ini` |
| 当前仿真命令 | `make sim test=axi_write_test dump=y SEED=1`；`make sim test=axi_read_test dump=y SEED=1` |
| 当前覆盖率命令 | `make all test=<test> cov=y SEED=1`，随后执行`make cov_report test=<test>` |
| Stage 0结果 | 历史审核：`stage0_smoke_test`通过，最终`UVM_ERROR=0`、`UVM_FATAL=0`；目录收敛后一次性入口未保留 |
| Stage 1A编译 | 历史审核：Errors 0，Warnings 0 |
| Stage 1A结果 | 历史审核：7个独立UVM test全部通过；其测试支架现已删除，当前不能直接重跑 |
| 当前Stage 1编译 | 2026-09-15使用QuestaSim 10.6c重新编译统一`tb`、RTL、env、sequence、checker和test package：Errors 0，Warnings 0 |
| 当前写闭环 | `axi_write_test`通过；AW/W/B各匹配1次，`AXI_TC_PASS`，`UVM_WARNING=0`、`UVM_ERROR=0`、`UVM_FATAL=0`，生成`work/wave/axi_write_test.wlf` |
| 当前读闭环 | `axi_read_test`通过；AR/R各匹配1次，`AXI_TC_PASS`，`UVM_WARNING=0`、`UVM_ERROR=0`、`UVM_FATAL=0`，生成`work/wave/axi_read_test.wlf` |
| 代码覆盖率入口 | 已审核可生成`work/cov/<test>.ucdb`和`work/cov/<test>_report/index.html`；不等同于functional coverage |
| DUT使用情况 | Stage 1A不例化DUT；Stage 1B例化真实`axi_interconnect`并只启用M0和S0 |
| 保留项 | `S0-OPEN-01`继续保留；`S1-LIMIT-01`仅在Stage 1B定向写smoke中使用 |
| 当前运行注意事项 | 如果Questa GUI/`vish`仍打开并占用`work/lib`，`make clean`会打印文件占用错误；关闭相关GUI后再执行干净编译。系统`MODELSIM`警告不影响当前命令，因为`vlog/vmap/vsim`均显式指定`-modelsimini work/modelsim.ini` |

Stage 1A审核时通过、目录收敛后已删除测试支架的独立测试为：

1. `stage1_m_driver_unit_test`。
2. `stage1_s_driver_unit_test`。
3. `stage1_m_monitor_unit_test`。
4. `stage1_s_monitor_unit_test`。
5. `stage1_event_comparator_unit_test`。
6. `stage1_agent_unit_test`。
7. `stage1_reactive_chain_unit_test`。

当前保留的Stage 1B闭环测试为：

1. `axi_write_test`。
2. `axi_read_test`。

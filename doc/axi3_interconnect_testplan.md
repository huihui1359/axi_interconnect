# 三主三从 AXI3 Interconnect UVM 验证 Testplan

editor：孙梦晖  
date：2026-08-26  
版本号：v1

| 项目 | 内容 |
|---|---|
| 关联SPEC | `axi3_interconnect_verification_spec.md` v2 |
| DUT | 三主三从 AXI3 Interconnect |
| 当前阶段 | 顶层黑盒UVM环境搭建与功能验证 |
| 后续阶段 | 对FIFO、Arbiter、Switch增加灰盒bind assertion |
| 不包含 | AXI2AHB、APB config、后端实现及其他附加模块 |

## 1. Testplan目的

本Testplan用于指导三主三从AXI3 Interconnect黑盒UVM验证环境的实现，并将SPEC要求映射到环境组件、checker、assertion、coverage和testcase。

当前阶段必须首先完成可独立运行和签核的黑盒环境。Reference model和checker只能根据外部接口的实际握手、项目地址映射和AXI3规则生成期望结果，不得读取DUT内部select、grant、FIFO指针或状态机作为expected。后续灰盒assertion只用于提高错误定位能力。

## 2. 已确认基线与非阻塞假设

### 2.1 DUT配置

| 项目 | Testplan基线 |
|---|---|
| 上游Master数量 | 3，编号M0～M2 |
| 下游Slave数量 | 3，编号S0～S2 |
| 地址宽度 | 32 bit |
| 数据宽度 | 32 bit |
| 上游ID宽度 | 4 bit |
| 当前下游扩展ID宽度 | 8 bit |
| `AWLEN/ARLEN` | 4 bit，表示`beats-1` |
| 最大burst | 16 beats |
| outstanding | 每个Master最多4读、4写，分别统计 |
| 复位 | 低有效 |
| 协议定位 | 赛题裁剪后的AXI3数据传输子集 |

### 2.2 地址映射

| 目标 | 地址范围 |
|---|---|
| S0 | `0x0000_0000～0x0000_0FFF` |
| S1 | `0x0000_2000～0x0000_2FFF` |
| S2 | `0x0000_4000～0x0000_4FFF` |
| Default Slave | 其余未映射地址 |

### 2.3 不阻塞环境搭建的处理约定

- 赛题未规定复位后的第一位round-robin winner。Checker允许第一次从有效候选中选择任意Master，并以实际首次winner初始化轮询历史；从下一次服务开始严格检查round-robin。
- 黑盒阶段不把内部单个FIFO的精确深度作为pass/fail条件，只检查端到端缓冲行为、背压、无丢失、无重复和顺序。精确指针、full/empty和occupancy留给灰盒阶段。
- 赛题未给出吞吐量数值门限。当前阶段测量并报告吞吐量和延迟，不设置硬性性能门限。
- 正常随机事务必须满足4KB规则；专门跨4KB负向测试期望DUT不向正常Slave转发并返回`DECERR`。
- 除跨4KB和未映射地址外，非法`AxBURST/AxSIZE/WRAP`组合主要由环境约束和协议检查报告，不对DUT返回结果作功能要求。
- 严格round-robin顺序在候选集合明确的定向场景中判定；随机流水场景重点检查合法winner、无丢失、无重复、公平性和最终完成。

## 3. 验证策略

### 3.1 黑盒检查边界

黑盒环境通过以下外部端口观察DUT：

- 上游侧：`M_AXI_*[0:2]`，DUT表现为三个AXI Slave端口。
- 下游侧：`S_AXI_*[0:2]`，DUT表现为三个AXI Master端口。

主要判定分为三类：

| 判定 | 回答的问题 | 主要组件 |
|---|---|---|
| AXI协议判定 | 每个接口传输是否合法 | interface assertions、monitor |
| Switch/数据判定 | 事务去向、内容、ID和返回路径是否正确 | xbar ref model、scoreboard |
| Arbiter判定 | 同一目标的候选请求中是否选择正确winner | arbiter checker |

### 3.2 数据流原则

- Driver只驱动，不检查、不采样覆盖率。
- Monitor只根据实际握手发布观察结果，不根据sequence意图补造事务。
- Ref model独立预测目标和事务关联，不复制RTL实现。
- Arbiter checker独立维护round-robin历史，不使用内部grant作为expected。
- Scoreboard负责最终内容比较和队列清空检查。
- Coverage只采样已实际发生的握手、竞争、乱序和交织事件。

## 4. UVM总体框架

```text
axi_base_test
└── axi_env
    ├── mst_agent[0:2]                  active
    │   ├── axi_m_sequencer
    │   ├── axi_m_driver
    │   └── axi_m_monitor
    ├── slv_agent[0:2]                  reactive active agent
    │   ├── axi_s_sequencer
    │   ├── axi_s_driver
    │   └── axi_s_monitor
    ├── axi_virtual_sequencer
    ├── axi_xbar_ref_model
    ├── axi_arbiter_checker
    ├── axi_scoreboard
    ├── axi_outstanding_order_tracker
    └── axi_funcov

tb_top
├── axi_interface
├── DUT axi_interconnect
├── clock/reset
└── axi_protocol_assertions
```

推荐的源代码组织：

```text
uvm_tb/
├── env/
│   ├── axi_types_pkg.sv
│   ├── axi_env_cfg.sv
│   ├── axi_master_agent_cfg.sv
│   ├── axi_slave_agent_cfg.sv
│   ├── axi_seq_item.sv
│   ├── axi_channel_event.sv
│   ├── axi_m_sequencer.sv
│   ├── axi_m_driver.sv
│   ├── axi_m_monitor.sv
│   ├── axi_m_agent.sv
│   ├── axi_s_sequencer.sv
│   ├── axi_s_driver.sv
│   ├── axi_s_monitor.sv
│   ├── axi_s_agent.sv
│   ├── axi_virtual_sequencer.sv
│   ├── axi_xbar_ref_model.sv
│   ├── axi_rr_model.sv
│   ├── axi_arbiter_checker.sv
│   ├── axi_outstanding_order_tracker.sv
│   ├── axi_scoreboard.sv
│   ├── axi_funcov.sv
│   └── axi_env.sv
├── tc/
│   ├── axi_base_seq.sv
│   ├── axi_virtual_sequences.sv
│   ├── axi_base_test.sv
│   └── axi_directed_random_tests.sv
└── tb/
    ├── axi_interface.sv
    ├── axi_protocol_assertions.sv
    └── tb_top.sv
```

文件名是建议组织方式，允许在实现时拆分package或sequence文件，但组件职责不得混淆。

## 5. 事务和观察事件建模

### 5.1 Sequence item

每个Master agent处理一个端口，因此新的sequence item不应再把三个Master的信号声明成`[0:2]`数组。建议一笔事务包含：

- 方向：read/write。
- `id`、`addr`、`len`、`size`、`burst`。
- 写数据动态数组`wdata[]/wstrb[]`。
- 读数据动态数组`rdata[]/rresp[]`。
- 写响应`bresp`。
- 可配置AW/W/AR间延迟和各beat间延迟。

`len`仍保存AXI编码值，数组beat数为`len+1`。

### 5.2 Channel event

Monitor除完整事务外，还应发布通道级事件，供arbiter和协议关联检查使用。事件至少包含：

- channel：AW/W/B/AR/R。
- port_side：upstream/downstream。
- port_index：Master或Slave编号。
- cycle/time。
- 当前beat payload。
- 是否为实际握手事件。
- Ref model填充的source Master、target Slave和事务序号。

完整事务用于scoreboard；通道事件用于仲裁、outstanding、交织和性能统计。

## 6. 组件职责

### 6.1 `axi_env_cfg`

- 保存三个Master agent和三个Slave agent配置。
- 保存地址映射、ID宽度、数据宽度、最大outstanding等公共参数。
- 保存各端口active/passive设置、背压配置和超时门限。
- 统一分发六个virtual interface。

### 6.2 `axi_m_sequencer`

- 接收单Master的读写sequence item。
- 不直接管理其他Master。
- 与virtual sequencer配合形成三Master并发场景。

### 6.3 `axi_m_driver`

- 并行管理AW、W、AR发送线程以及BREADY、RREADY控制线程。
- 严格遵守VALID不得依赖READY和stall期间payload稳定规则。
- 支持AW/W独立时序、1～16 beats、FIXED/INCR/WRAP、窄传输和WSTRB。
- 支持每Master最多4读加4写outstanding。
- 支持不同WID写数据交织。
- Driver不计算DUT路由、不比较DUT输出、不采样功能覆盖率。

### 6.4 `axi_m_monitor`

- 只在上游五通道实际握手时采样。
- 分别发布AW、W、B、AR、R channel event。
- 根据ID和LAST重建完整读写事务。
- 为每个观察对象附加Master编号和采样周期。
- 对未握手的driver意图不发布事务。

### 6.5 `axi_s_sequencer/axi_s_driver`

- 作为reactive responder接收DUT发往该Slave的AW/W/AR。
- 可独立随机控制`AWREADY/WREADY/ARREADY`。
- 可配置B/R延迟、错误响应、不同ID乱序和不同RID读数据交织。
- 必须原样返回DUT下游扩展ID。
- 为每个Slave维护独立响应调度队列和可选memory model。
- Slave responder的queue是响应调度数据结构，不是DUT FIFO参考实现。

### 6.6 `axi_s_monitor`

- 采集DUT转发到各Slave的AW/W/AR实际握手。
- 采集各Slave返回给DUT的B/R实际握手。
- 发布Slave编号、完整payload、扩展ID和采样周期。
- 其观察结果作为DUT反向B/R路由的expected输入来源，不直接采用slave driver意图值。

### 6.7 `axi_virtual_sequencer`

- 持有三个Master sequencer和三个Slave response sequencer句柄。
- 组织竞争、并行、背压、outstanding、乱序、交织和复位场景。
- 不保存scoreboard状态，不计算expected winner。

### 6.8 `axi_xbar_ref_model`

负责Switch和事务语义预测：

- 根据AW/AR地址独立计算S0/S1/S2/Default目标。
- 生成`route_info`，包含source Master、target Slave、channel、原始ID、预期扩展ID和事务句柄。
- 维护per-Master/per-ID的AW-W-B和AR-R上下文队列。
- 根据已接受AW建立`Master+WID → target Slave`，不得使用`WID[3:2]`直接选择Slave。
- 计算FIXED/INCR/WRAP每beat地址和4KB合法性。
- 预测下游ID扩展及返回上游时的原始ID恢复。
- 预测未映射地址和跨4KB事务的`DECERR`行为。
- 向arbiter checker发布路由分类信息，向scoreboard发布expected transaction。

Ref model不维护round-robin winner历史，不规定DUT的固定流水延迟。

### 6.9 `axi_rr_model`

- 是纯算法helper object，不是UVM driver。
- 保存某个资源的`last_winner`和可选`locked_winner`。
- 输入有效候选向量，按照M0→M1→M2循环并跳过无请求者，返回expected winner。
- 第一次竞争允许任一有效winner并据此初始化；后续严格轮询。
- 仅在有效服务握手完成后commit winner。

### 6.10 `axi_arbiter_checker`

负责顶层黑盒仲裁检查：

- 接收ref model的route info和上下游monitor事件。
- 维护每个Master尚未转发的AW/AR/W候选队列。
- 建立`AW/AR/W request_matrix[slave][master]`。
- 建立`B/R response_matrix[master][slave_or_default]`。
- 每个Slave、每个仲裁通道使用独立RR model预测winner。
- 根据下游扩展ID和事务payload识别实际forward winner。
- 根据上游B/R输出识别实际response winner。
- 在候选集合明确的服务事件上比较expected和actual winner。
- 检查winner必须属于候选集合、单资源单winner、轮询顺序、背压保持、公平性和无饥饿。
- 检查不同Slave可以在同周期并行完成服务。

该checker只检查“谁先走”，完整payload和数据正确性由scoreboard检查。

### 6.11 `axi_outstanding_order_tracker`

- 每个Master分别统计read/write outstanding 0～4。
- AW握手建立write outstanding，B握手释放。
- AR握手建立read outstanding，`RLAST`握手释放。
- 为每个Master、方向和ID维护顺序队列。
- 为scoreboard提供同ID保序、不同ID乱序合法性信息。
- 检查提前响应、未知ID响应、重复释放、超过上限和仿真结束未清空。

### 6.12 `axi_scoreboard`

负责端到端比较：

- 上游AW/AR与正确Slave侧AW/AR比较。
- 上游W beat与AW上下文确定的正确Slave侧W比较。
- 下游B/R实际输入与正确Master侧B/R输出比较。
- 检查地址、ID、LEN、SIZE、BURST、DATA、STRB、RESP和LAST。
- 检查无丢失、无重复、无错误广播和无Master/Slave串扰。
- 按Master、Slave、方向、ID和burst使用队列，而不是按全局到达顺序比较。
- 仿真结束检查所有expected/actual/outstanding队列清空。

### 6.13 `axi_funcov`

- 只从monitor、arbiter checker和outstanding tracker采样已发生事件。
- 覆盖路由、burst、长度、size、ID、backpressure、outstanding深度、竞争矩阵、winner、乱序、交织、错误响应和并行度。
- 不从driver调用`sample()`，不把sequence意图作为覆盖结果。

## 7. TLM连接计划

推荐使用analysis port连接多个被动消费者，必要时在消费者端使用`uvm_tlm_analysis_fifo`解耦：

```text
mst_monitor.ap
├──> xbar_ref_model.upstream_export
├──> arbiter_checker.upstream_export
├──> outstanding_tracker.upstream_export
├──> scoreboard.upstream_export
└──> funcov.upstream_export

slv_monitor.ap
├──> xbar_ref_model.downstream_export
├──> arbiter_checker.downstream_export
├──> scoreboard.downstream_export
└──> funcov.downstream_export

xbar_ref_model.expected_ap
└──> scoreboard.expected_export

xbar_ref_model.route_ap
└──> arbiter_checker.route_export

arbiter_checker.event_ap
└──> funcov.arb_export

outstanding_tracker.event_ap
└──> funcov.outstanding_export
```

每条analysis路径必须clone事务或明确所有权，避免同一对象句柄被后续修改。

## 8. Switch、请求矩阵与Arbiter的协作

### 8.1 前向请求

```text
上游AW/AR握手
      ↓
Ref model地址译码
      ↓
route_info：source Master + target Slave
      ↓
Arbiter checker按target Slave建立request matrix
      ↓
RR model预测该Slave的winner
      ↓
下游monitor观察实际winner
      ↓
Arbiter checker比较winner，Scoreboard比较payload
```

### 8.2 写数据

```text
AW握手建立Master+ID到Slave的上下文
      ↓
WID查找AW上下文
      ↓
建立W request matrix
      ↓
检查W winner、目标Slave、beat顺序和WLAST
```

### 8.3 返回响应

```text
Slave侧B/R握手进入DUT
      ↓
扩展ID确定目标Master和原始ID
      ↓
建立response matrix[master][slave]
      ↓
检查返回仲裁、ID恢复、顺序和数据
```

### 8.4 黑盒可见性控制

输入FIFO会使顶层输入握手时间与内部仲裁时间不同。严格round-robin定向测试应先阻塞下游，确保所有竞争请求都已在上游完成握手，再释放目标Slave READY；这样候选集合明确。随机流水场景不对有歧义的同周期新到请求强制固定winner，只检查实际winner来自pending集合、公平性和最终完成。

## 9. AXI接口断言计划

| Assertion组 | 检查内容 | 适用侧 |
|---|---|---|
| A-HS | `VALID&&!READY`时VALID及payload稳定 | 上游和下游五通道 |
| A-RST | Reset期间VALID、历史事务和复位恢复 | DUT输出通道 |
| A-WDEP | B响应不早于对应AW及WLAST完成 | 上游返回 |
| A-RDEP | R响应对应已接受AR | 上游返回 |
| A-LAST | `WLAST/RLAST`与LEN及beat数匹配 | 两侧 |
| A-4K | 正常AW/AR burst不跨4KB | 上游输入和下游输出 |
| A-SIZE | `AxSIZE`不大于32-bit数据宽度 | 合法刺激 |
| A-WRAP | WRAP长度及对齐合法 | 合法刺激 |
| A-RESP | RESP和ID在VALID期间稳定 | B/R通道 |

断言必须区分环境输入违规和DUT输出违规，避免把Master BFM错误误报为DUT defect。

## 10. 功能覆盖率计划

### 10.1 基础覆盖点

- Master：M0/M1/M2。
- Slave：S0/S1/S2/Default。
- 方向：read/write。
- ID：0～15。
- LEN：1、2～4、5～8、9～15、16 beats。
- SIZE：1/2/4 bytes。
- BURST：FIXED/INCR/WRAP。
- RESP：OKAY/SLVERR/DECERR。
- outstanding深度：0～4，读写分别采样。
- backpressure：无、短、长、随机。
- 并行Slave数：0/1/2/3。

### 10.2 关键交叉覆盖

- Master × Slave × direction。
- Master × Slave × burst × LEN。
- SIZE × burst ×地址对齐情况。
- request matrix pattern × target Slave × winner。
- last winner × eligible set × current winner。
- 竞争Master数量 × backpressure ×公平性结果。
- outstanding depth ×相同/不同ID × response order。
- WID数量 ×写数据交织深度。
- RID数量 ×读数据交织深度。
- 地址边界类型 × burst ×合法/非法 × response。
- 多Master同值ID ×目标Slave ×响应返回Master。

## 11. 详细测试点

### 11.1 Reset与握手

| ID | 测试点 | 激励/场景 | 主要检查 |
|---|---|---|---|
| TP-RST-01 | 空闲复位 | 无事务时拉低/释放复位 | 输出VALID清零、环境队列清空、恢复工作 |
| TP-RST-02 | 传输中复位 | AW/W/AR/R/B存在pending或stall时复位 | 不返回旧事务、无残留、复位后可重新传输 |
| TP-HS-01 | 五通道基本握手 | 单事务、无背压 | 每次握手只计一次，payload正确 |
| TP-HS-02 | VALID先到 | VALID提前且READY延迟 | VALID/payload稳定 |
| TP-HS-03 | READY先到 | READY提前、VALID延迟 | 无虚假握手 |
| TP-HS-04 | 长时间stall | 各通道分别READY=0多个周期 | payload稳定、解除后完成 |
| TP-HS-05 | 通道独立 | AW/W/AR/B/R分别独立延迟 | 无非法跨通道依赖和死锁 |

### 11.2 Switch与ID路由

| ID | 测试点 | 激励/场景 | 主要检查 |
|---|---|---|---|
| TP-ROUTE-01 | 9条Master-Slave路径 | 每个Master分别访问每个Slave | 所有3×3路径正确 |
| TP-ROUTE-02 | 地址首尾边界 | 每个窗口base和end地址 | 正确选择唯一Slave |
| TP-ROUTE-03 | 地址空洞 | `0x1000/0x3000/0x5000`附近 | 不到正常Slave，Default DECERR |
| TP-ROUTE-04 | AW/AR独立路由 | 同一Master读写访问不同Slave | AW/AR互不串扰 |
| TP-ROUTE-05 | W跟随AW | 遍历4-bit AWID/WID和三个Slave | W目标由AW上下文决定 |
| TP-ROUTE-06 | ID扩展恢复 | 遍历Master、Slave、ID | 下游扩展ID正确，上游恢复原始ID |
| TP-ROUTE-07 | 多Master同值ID | M0/M1/M2使用相同ID | 响应回到正确Master，无串扰 |
| TP-ROUTE-08 | 无错误广播 | 单请求随机地址 | 同一请求不能出现在多个正常Slave |

### 11.3 Round-robin仲裁与Crossbar并行

| ID | 测试点 | 激励/场景 | 主要检查 |
|---|---|---|---|
| TP-ARB-01 | 双Master AW竞争 | 任意两Master持续请求同一Slave | 首次任意，后续严格轮询 |
| TP-ARB-02 | 三Master AW竞争 | 三Master预装请求后释放READY | M0/M1/M2循环、无饥饿 |
| TP-ARB-03 | 双/三Master AR竞争 | 与AW对应的读地址场景 | AR独立轮询 |
| TP-ARB-04 | 跳过无请求者 | 竞争过程中某Master撤出/重新加入 | 只选择有效候选，轮询跳过空请求 |
| TP-ARB-05 | 仲裁背压保持 | winner产生后目标Slave READY=0 | winner和payload保持，握手后更新指针 |
| TP-ARB-06 | W竞争和交织 | 不同WID数据流指向同一Slave | 合法beat winner、无串流、无饥饿 |
| TP-ARB-07 | B/R返回竞争 | 多Slave同时响应同一Master | 返回winner合法、公平、ID和顺序正确 |
| TP-ARB-08 | 不同Slave并行 | 三Master分别访问S0/S1/S2 | 三行请求矩阵可同时产生winner |
| TP-ARB-09 | 部分并行加竞争 | M0/M1竞争S0，M2访问S1 | S0仲裁同时S1独立前进 |
| TP-ARB-10 | 长时公平性 | 持续竞争至少多个完整轮次 | 每个持续请求者均获得服务 |

### 11.4 FIFO外部行为与背压

| ID | 测试点 | 激励/场景 | 主要检查 |
|---|---|---|---|
| TP-FIFO-01 | AW/AR填充排空 | 阻塞下游地址READY后释放 | 已接受请求全部按规则输出 |
| TP-FIFO-02 | W填充排空 | 阻塞WREADY、多beat连续发送 | 数据、WSTRB、WID、WLAST无丢失重复 |
| TP-FIFO-03 | B/R返回缓冲 | Master BREADY/RREADY阻塞后释放 | 响应和R beat完整稳定 |
| TP-FIFO-04 | 随机入出队 | 五通道独立随机背压 | 队列最终清空、无死锁 |
| TP-FIFO-05 | 同周期推进 | 连续流量、上下一直READY | 不因push/pop并发产生重复或丢失 |
| TP-FIFO-06 | 通道隔离 | 单独长阻塞某通道 | 无关通道可继续推进 |
| TP-FIFO-07 | 满载恢复 | 长背压直到上游READY降低再释放 | 背压及时、已接受事务完整恢复 |

### 11.5 Burst、Size、WSTRB与数据完整性

| ID | 测试点 | 激励/场景 | 主要检查 |
|---|---|---|---|
| TP-BURST-01 | 单beat | LEN=0，读写所有路径 | 1 beat和LAST正确 |
| TP-BURST-02 | 长度扫描 | 1～16 beats | beat数、WLAST/RLAST、数据完整 |
| TP-BURST-03 | FIXED | 不同LEN/SIZE | 地址保持不变 |
| TP-BURST-04 | INCR | 不同LEN/SIZE/对齐 | 地址按`2^SIZE`递增 |
| TP-BURST-05 | WRAP | 2/4/8/16 beats | wrap base、回绕地址和LAST正确 |
| TP-BURST-06 | 窄传输 | SIZE=1/2 bytes | byte lane和WSTRB正确 |
| TP-BURST-07 | 32-bit传输 | SIZE=4 bytes | 全字数据和WSTRB正确 |
| TP-BURST-08 | 数据模式 | walking-1、地址相关、随机数据 | 端到端数据无篡改 |

### 11.6 Outstanding、Ordering和Out-of-order

| ID | 测试点 | 激励/场景 | 主要检查 |
|---|---|---|---|
| TP-OUT-01 | 读深度扫描 | 每Master read outstanding 1～4 | 计数、响应匹配、最终释放 |
| TP-OUT-02 | 写深度扫描 | 每Master write outstanding 1～4 | AW/W/B关联和计数 |
| TP-OUT-03 | 读写并存 | 同一Master 4读+4写 | 读写独立统计和并行完成 |
| TP-OUT-04 | 三Master满深度 | 三Master同时多笔读写 | 状态隔离、无串扰、无死锁 |
| TP-OUT-05 | 达到上限 | 保持4笔未完成并尝试后续请求 | 合法背压、已有事务继续完成 |
| TP-ORD-01 | 同ID读保序 | 同Master同RID多笔读 | 按AR接受顺序返回burst |
| TP-ORD-02 | 同ID写保序 | 同Master同BID多笔写 | B响应按事务顺序返回 |
| TP-ORD-03 | 不同ID读乱序 | Slave延迟不同RID | Checker接受合法乱序并正确匹配 |
| TP-ORD-04 | 不同ID写乱序 | Slave调整不同BID响应顺序 | 合法乱序、同ID仍保序 |
| TP-ORD-05 | 跨Master同ID | 三Master相同ID并发 | ID namespace隔离 |

### 11.7 Interleaving

| ID | 测试点 | 激励/场景 | 主要检查 |
|---|---|---|---|
| TP-INT-01 | 双WID写交织 | 同Master两个写burst交替beat | 每WID数据顺序、目标Slave和WLAST |
| TP-INT-02 | 2～4 WID写交织 | 多ID、多目标、随机背压 | 无beat串流、上下文独立 |
| TP-INT-03 | 双RID读交织 | Slave交替返回两个RID | RID、数据、RRESP、RLAST匹配 |
| TP-INT-04 | 2～4 RID读交织 | 多ID随机交织和RREADY背压 | 同RID保序，不同RID可交织 |

### 11.8 4KB、Default Slave与错误响应

| ID | 测试点 | 激励/场景 | 主要检查 |
|---|---|---|---|
| TP-4K-01 | 4KB内末端合法INCR | burst最后字节位于`...FFF` | 正常路由，无误报 |
| TP-4K-02 | 合法FIXED/WRAP边界 | 边界附近合法地址 | 完整burst位于一个4KB窗口 |
| TP-4K-03 | 写burst跨4KB | 专门非法AW及对应W | 不到正常Slave，排空W，B DECERR |
| TP-4K-04 | 读burst跨4KB | 专门非法AR | 不到正常Slave，LEN+1个DECERR R beat |
| TP-ERR-01 | 未映射写 | 地址空洞和范围外写 | Default处理，单次B DECERR，ID正确 |
| TP-ERR-02 | 未映射读 | 地址空洞和范围外读 | LEN+1个R DECERR，RID/RLAST正确 |
| TP-ERR-03 | 下游SLVERR透传 | Slave返回SLVERR | 正确Master收到相同响应 |
| TP-ERR-04 | 下游DECERR透传 | Slave主动返回DECERR | 响应和值正确透传 |

### 11.9 随机压力、死锁与性能观测

| ID | 测试点 | 激励/场景 | 主要检查 |
|---|---|---|---|
| TP-STRESS-01 | 三主三从混合随机 | 随机读写/burst/ID/地址/背压 | 无错误、无死锁、队列清空 |
| TP-STRESS-02 | 最大outstanding压力 | 长时间保持高请求率 | 最终完成、无状态泄漏 |
| TP-PERF-01 | 单路径吞吐 | 单Master单Slave无背压 | 记录首响应延迟、beat/cycle |
| TP-PERF-02 | 三路径聚合吞吐 | M0-S0、M1-S1、M2-S2并行 | 记录并行度和聚合吞吐 |
| TP-PERF-03 | 单Slave竞争带宽 | 三Master持续竞争同一Slave | 记录各Master服务数和公平性 |
| TP-PERF-04 | 背压敏感性 | 多档随机READY比例 | 记录吞吐和延迟变化 |

## 12. 建议Testcase列表

| Testcase | 主要内容 | 主要测试点 |
|---|---|---|
| `axi_smoke_test` | M0到S0单拍读写 | TP-HS-01、TP-BURST-01 |
| `axi_all_route_test` | 3×3路径、首尾地址、Default | TP-ROUTE-01～08、TP-ERR-01/02 |
| `axi_handshake_backpressure_test` | 五通道VALID/READY组合 | TP-HS-02～05 |
| `axi_burst_test` | FIXED/INCR/WRAP、LEN、SIZE、WSTRB | TP-BURST-01～08 |
| `axi_fifo_behavior_test` | 各通道填充、排空、随机背压 | TP-FIFO-01～07 |
| `axi_aw_arbitration_test` | 双/三Master AW竞争 | TP-ARB-01/02/04/05/10 |
| `axi_ar_arbitration_test` | 双/三Master AR竞争 | TP-ARB-03/04/05/10 |
| `axi_crossbar_parallel_test` | 不同Slave并行及局部竞争 | TP-ARB-08/09、TP-PERF-02 |
| `axi_response_arbitration_test` | 多Slave同时向同Master返回 | TP-ARB-07 |
| `axi_outstanding_test` | 每Master读写深度1～4 | TP-OUT-01～05 |
| `axi_order_ooo_test` | 同ID保序、不同ID乱序 | TP-ORD-01～05 |
| `axi_write_interleave_test` | 2～4 WID交织 | TP-INT-01/02、TP-ARB-06 |
| `axi_read_interleave_test` | 2～4 RID交织 | TP-INT-03/04 |
| `axi_4kb_boundary_test` | 合法边界和非法跨界 | TP-4K-01～04 |
| `axi_error_response_test` | SLVERR/DECERR透传 | TP-ERR-01～04 |
| `axi_reset_test` | 空闲和传输中复位 | TP-RST-01/02 |
| `axi_random_stress_test` | 三主三从约束随机回归 | TP-STRESS-01/02 |
| `axi_performance_test` | 吞吐、延迟、公平性测量 | TP-PERF-01～04 |

每个testcase应通过配置和sequence组合复用统一环境，不应派生多个功能重复但结构不同的env。

## 13. 回归分层

### 13.1 Smoke回归

- `axi_smoke_test`
- `axi_all_route_test`
- `axi_handshake_backpressure_test`

用于每次环境或RTL提交后的快速检查。

### 13.2 Feature回归

- burst、FIFO行为、仲裁、并行、outstanding、ordering、interleaving、4KB、error和reset测试。
- 定向覆盖每个SPEC requirement。

### 13.3 Random/Stress回归

- 多seed `axi_random_stress_test`。
- 随机Master/Slave延迟、burst、ID、地址、outstanding和backpressure。
- 测试结束必须等待所有合法事务排空并检查统一timeout。

### 13.4 Performance回归

- 独立运行，避免随机环境噪声影响统计。
- 输出吞吐量、首响应延迟、平均延迟和每Master服务计数。

## 14. 需求追踪矩阵

| SPEC要求 | Testplan覆盖 |
|---|---|
| VER-M01～M05 | 第3～8节、TP-FIFO、TP-ARB、TP-ROUTE |
| AXI3-P01～P04 | TP-HS、TP-RST、TP-ERR、A-HS/A-RST/A-RESP |
| AXI3-B01～B06 | TP-BURST、A-LAST/A-SIZE/A-WRAP |
| XBAR-R01～R03 | TP-ROUTE、TP-ERR、route scoreboard |
| XBAR-F01～F03 | TP-FIFO、end-to-end queue checks |
| XBAR-A01～A03 | TP-ARB、request/response matrix、RR checker |
| AXI3-O01～O02 | TP-OUT、outstanding tracker |
| AXI3-ORD01～ORD02 | TP-ORD、per-ID scoreboard |
| AXI3-INT01～INT02 | TP-INT、interleave coverage |
| AXI3-4K01～4K02 | TP-4K、A-4K、Default prediction |
| XBAR-E01～E02 | TP-ERR-01/02 |
| XBAR-PERF01～PERF03 | TP-ARB-08/09、TP-STRESS、TP-PERF |

## 15. 覆盖率和完成标准

### 15.1 Testplan完成标准

- 每个测试点至少映射到一个testcase、一个checker/assertion和一个coverage观测方式。
- 3×3 Master-Slave读写路径需求覆盖率为100%。
- 所有SPEC requirement均有执行结果，不允许未映射要求。
- 功能覆盖率目标暂定不低于95%，未覆盖bin必须分析并给出新增测试或合理waiver。
- 代码覆盖率作为RTL质量参考；不可达代码需要设计确认，不能为了提高数字降低功能检查。

### 15.2 单次测试通过标准

- 无未豁免UVM error/fatal。
- 无DUT侧protocol assertion failure。
- Scoreboard无mismatch，仿真结束所有expected/actual队列清空。
- Outstanding tracker读写计数归零。
- Arbiter checker无非法winner、顺序、公平性或保持错误。
- 测试未因统一timeout结束。

### 15.3 RTL缺陷与环境缺陷区分

- 合法stimulus下DUT输出违反SPEC，记录为RTL defect。
- Driver产生非法正常事务、monitor重复采样、ref model预测错误或checker误报，记录为environment defect。
- 当前RTL尚未支持高级机制导致测试失败时，不得删除测试或放宽SPEC；应保留可复现seed、输入事务、预期结果、实际结果和首次错误时间。

## 16. 环境实现里程碑

| 阶段 | 实现内容 | 完成标志 |
|---|---|---|
| M1 基础骨架 | config、transaction、3M/3S agent、virtual sequencer、tb_top | smoke读写能运行 |
| M2 Monitor与协议 | 两侧五通道monitor、基础assertion | 握手事务可稳定重建 |
| M3 Switch模型 | decode、route info、ID模型、基础scoreboard | 3×3路由和Default可检查 |
| M4 Arbiter模型 | pending队列、请求矩阵、RR checker | 定向双/三Master竞争可判定 |
| M5 数据与burst | W/R beat、burst算法、WSTRB、LAST | FIXED/INCR/WRAP通过或定位RTL错误 |
| M6 高级机制 | outstanding、ordering、乱序、交织、4KB | 高级feature测试可运行 |
| M7 覆盖率与回归 | funcov、testcase、seed管理、报告 | Feature和Random回归形成闭环 |
| M8 灰盒增强 | FIFO/Arbiter/Switch bind assertion | 内部错误定位能力完成 |

黑盒环境在M7完成后应能够独立对DUT进行功能签核；M8不得改变M1～M7的reference结果或scoreboard判定。


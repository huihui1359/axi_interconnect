# AXI3 Interconnect UVM验证环境Stage 3执行工单

> 状态：待实施
> 前置条件：dv/doc/stage2.md已经实施并通过回归，当前M0到S0单端口环境支持burst、delay/gap、五通道backpressure、完整Monitor重建、协议断言和Stage 2端到端检查
> ID定义：本阶段严格遵守dv/doc/ID_intro.md
> 代码风格：本阶段所有新增和修改代码必须遵守dv/doc/code_style.md
> 实施边界：本工单只修改dv、sim及验证入口，不修改rtl目录

## 1. 文档目的和阶段概述

### 1.1 Stage 2已经完成的内容

Stage 2已经在M0到S0闭环上完成：

- FIXED、INCR和合法WRAP burst。
- 1～16拍W和R传输。
- addr_delay、w_start_delay、wbeat_gap[]、rsp_delay和rbeat_gap[]。
- AW、W、AR、B和R五通道独立backpressure。
- AW/W独立推进和读写并行。
- Master/Slave Monitor对完整request和response的重建。
- 基于真实接口Monitor输出的Stage 2端到端Checker。
- 五通道stall稳定性、X/Z、LAST和beat数量协议断言。
- Stage 1和Stage 2正向回归以及独立断言自测。

Stage 2仍将每个方向限制为一笔未完成事务，并使用单一写上下文和单一读上下文关联B/R响应。

### 1.2 Stage 3需要新增的能力

Stage 3在Stage 2能力基础上增加：

- Master Driver读、写方向分别最多4笔outstanding。
- 基于真实AW、WLAST、AR、B和RLAST握手的按ID计数。
- 相同ID允许存在多笔outstanding。
- 相同ID的B/R响应严格按照请求接受顺序返回。
- 不同ID的B/R响应允许按预定义顺序乱序返回。
- Slave reactive侧保存尚未发送的B/R响应计划并进行ID选择。
- Master/Slave Monitor按ID维护多个并存请求和响应上下文。
- Stage 3端到端Checker按完整ID关联事务，不再依赖全局单一FIFO。
- 独立Outstanding Tracker根据Monitor发布的真实握手event维护按ID观察状态。
- 完整实现M0到S0场景中的4-bit Master ID和8-bit Slave ID操作。
- 增加Switch reference model的地址译码和ID编解码核心。
- 增加outstanding、同ID保序、不同ID乱序和ID映射相关协议检查。

### 1.3 Stage 3A和Stage 3B划分

Stage 3分为两个连续实施阶段：

1. **Stage 3A：组件能力扩展。** 完成按ID上下文、outstanding计数、Switch reference model、Monitor、断言、Checker、response计划池和编译入口修改。本阶段进行代码审核、编译和elaboration。
2. **Stage 3B：功能测试和闭环验收。** 建立outstanding、相同ID保序、不同ID乱序、ID映射、并行和stall测试，并运行Stage 1～3正向回归及Stage 3断言自测。

Stage 3A编译通过只表示组件可以进入测试，不表示outstanding、乱序和ID关联已经验证正确。

### 1.4 Stage 3冻结决策

本阶段冻结以下实现决策：

- 只启用M0和S0，不提前扩展三主三从完整环境。
- Master侧合法ID使用4'h4～4'h7。
- Slave侧对应扩展ID使用8'h54～8'h57。
- 读方向最大outstanding为4。
- 写方向最大outstanding为4。
- outstanding只统计已经在真实接口完成相应请求握手、但尚未完成最终响应的事务。
- AW、W和AR mailbox继续使用无界mailbox，不设置容量上限。
- mailbox中的待发送快照不计入AXI outstanding。
- 写outstanding上限由AW握手至B握手的事务数决定。
- w_outstanding_by_id用于记录已完成WLAST、尚未被B消费的写数据状态，不作为新AW的容量上限。
- 读outstanding上限由AR握手至RLAST握手的事务数决定。
- 不同ID允许B响应和完整R burst乱序返回。
- 相同ID必须按照请求接受顺序返回。
- 一个R burst开始发送后保持连续到RLAST，不在不同RID之间进行beat交织。
- 一个W burst开始发送后保持连续到WLAST，不在不同WID之间进行beat交织。
- AXI3 WID支持的写数据交织以及不同RID的读数据beat交织留到Stage 4。
- Switch reference model只实现地址译码和ID编解码，不实现完整多端口转发和仲裁。
- S0-OPEN-01继续保留，Master Driver不向Master sequence返回独立axi_rsp_item。
- UVM sequence_id/transaction_id不参与AXI ID映射。
- 本阶段不修改RTL，也不在工单中预判RTL实现结果。

### 1.5 Stage 3能力边界

本阶段不实现：

- 三个Master和三个Slave同时工作的完整环境。
- 跨Master或跨Slave仲裁验证。
- W/R beat级交织。
- 多端口Switch TLM转发网络。
- Default Slave完整验证。
- 最终系统级Reference Model和三主三从Scoreboard。
- mailbox、request FIFO和response计划池的容量门控。
- 运行中reset、outstanding期间reset和reset后事务恢复。
- Master sequence根据B/R结果产生后续依赖激励。
- 最终functional coverage collector和覆盖率闭环。

# 第一部分：Stage 3需要完成的任务

## 2. S3-01：Outstanding基本原理

### 2.1 Outstanding定义

Stage 3使用以下定义：

~~~text
写事务进入outstanding：AWVALID && AWREADY
写事务离开outstanding：BVALID && BREADY

写数据完成待响应：WVALID && WREADY && WLAST
写数据状态被消费：BVALID && BREADY

读事务进入outstanding：ARVALID && ARREADY
读事务离开outstanding：RVALID && RREADY && RLAST
~~~

Driver已clone但仍停留在mailbox中的事务不是AXI outstanding事务。

### 2.2 按ID计数数组

Master Driver必须保留以下固定命名：

~~~systemverilog
int unsigned aw_outstanding_by_id[ID_COUNT];
int unsigned w_outstanding_by_id[ID_COUNT];
int unsigned ar_outstanding_by_id[ID_COUNT];
~~~

其中：

~~~text
ID_COUNT = 1 << ID_WIDTH
~~~

在当前Master侧ID_WIDTH为4，因此数组具有16个索引，Stage 3正向测试只使用4'h4～4'h7。

计数规则固定为：

| 真实握手 | 状态更新 |
|---|---|
| AW握手 | aw_outstanding_by_id[AWID]增加1 |
| WLAST握手 | w_outstanding_by_id[WID]增加1 |
| B握手 | aw_outstanding_by_id[BID]和w_outstanding_by_id[BID]各减少1 |
| AR握手 | ar_outstanding_by_id[ARID]增加1 |
| 非RLAST的R握手 | 不释放读outstanding |
| RLAST握手 | ar_outstanding_by_id[RID]减少1 |

计数器只能在真实VALID、READY同时为1的时钟边界更新。

### 2.3 全局outstanding数量

写、读全局数量分别由按ID数组求和得到：

~~~text
write_outstanding = sum(aw_outstanding_by_id[id])
read_outstanding  = sum(ar_outstanding_by_id[id])
~~~

不增加write_slots_used或read_slots_used。

不要求额外维护与数组重复的全局可变计数；如果为日志或性能维护镜像总数，必须在同一个状态更新点更新，并通过一致性检查确认其等于数组求和。

### 2.4 上限控制

- drive_aw在准备发送一个新AW前检查write_outstanding。
- write_outstanding达到cfg.max_write_outstanding时，drive_aw不得为下一事务拉高AWVALID。
- B握手释放一个写outstanding后，drive_aw可以继续发送下一事务。
- drive_ar以相同方式使用read_outstanding和cfg.max_read_outstanding。
- 达到上限只阻止新的AW或AR进入接口，不停止accept_items接收和clone sequence item。
- 达到写上限不能停止已有W burst、BREADY、AR或RREADY。
- 达到读上限不能停止已有R接收、AW、W或BREADY。
- cfg.max_write_outstanding和cfg.max_read_outstanding的Stage 3合法范围为1～4。

### 2.5 mailbox和item_done

- aw_queue、w_queue和ar_queue继续使用无界mailbox。
- Master Driver取得item后立即clone。
- 写快照在item_done前放入AW和W路径。
- 读快照在item_done前放入AR路径。
- item_done不等待outstanding空位，不等待接口握手，也不等待B/R响应。
- sequence完成不表示总线事务完成。
- 测试必须等待Stage 3 Checker、outstanding数组和相关上下文全部完成。

### 2.6 同周期状态更新

同一时钟边界可能同时出现：

- AW握手和B握手。
- WLAST握手和B握手。
- AR握手和RLAST握手。
- AW、WLAST和B同时握手。

三个outstanding数组必须只有一个状态更新所有者。实现可以使用统一track_outstanding task，或使用单一同步状态管理方法。

同周期更新按净变化计算，不能依赖多个并行task对同一数组执行无序的自增和自减。

## 3. S3-02：各通道Outstanding职责

### 3.1 AW通道

- AW worker继续按aw_queue FIFO取出稳定快照。
- 在拉高新AWVALID前等待write_outstanding小于配置上限。
- 空位满足后执行该request的addr_delay。
- AWVALID拉高后不再因outstanding变化撤销或切换payload。
- AW握手后按AWID增加aw_outstanding_by_id。
- 每个AW握手建立一个写事务地址上下文。
- 同一ID的多个AW上下文按照握手顺序进入该ID的FIFO。
- 不同ID分别维护独立FIFO。

### 3.2 W通道

- W worker继续按w_queue顺序发送完整burst。
- Stage 3不允许不同WID的beat交织。
- W发送不等待AW握手，继续支持W先于AW。
- W通道不使用write_outstanding上限阻塞已有数据发送。
- 每个WLAST握手按WID增加w_outstanding_by_id。
- 完整W burst必须关联到与其共享request快照的写事务上下文。
- WLAST前的普通W beat不增加w_outstanding_by_id。

### 3.3 B通道

- BREADY继续由独立latency_gen产生backpressure。
- 每个B握手使用完整4-bit BID查找Master侧写事务上下文。
- BID必须对应至少一个未完成写事务。
- 当前Stage 3验证模型产生B响应前要求完整写request已经在Slave Monitor重建完成。
- B握手时，aw_outstanding_by_id[BID]和w_outstanding_by_id[BID]均不得为0。
- 合法B握手后两个计数器各减1。
- 相同BID必须消费该ID写上下文FIFO的队首。
- 不同BID可以按任意已配置顺序完成。

### 3.4 AR通道

- AR worker继续按ar_queue FIFO取出稳定快照。
- 在拉高新ARVALID前等待read_outstanding小于配置上限。
- 空位满足后执行addr_delay。
- AR握手后按ARID增加ar_outstanding_by_id。
- 每个AR握手将request快照放入对应ARID的读上下文FIFO。
- 同一ARID允许存在多笔未完成读事务。

### 3.5 R通道

- RREADY继续由独立latency_gen产生逐beat backpressure。
- 一个新R burst的第一拍使用RID选择对应读上下文FIFO。
- 必须选择该RID队列的队首事务。
- 选中后锁定当前读上下文，直到RLAST握手。
- Stage 3中RID不得在一个未完成R burst内变化。
- 每拍检查RID、RRESP和beat索引。
- 只有RLAST真实握手后，ar_outstanding_by_id[RID]减少1并弹出读上下文。
- 不同RID的完整R burst可以按任意已配置顺序返回。

## 4. S3-03：Out-of-order基本原理

### 4.1 Stage 3乱序定义

Stage 3的out-of-order定义为：

~~~text
不同AXI ID的B响应可以与请求接受顺序不同。
不同AXI ID的完整R burst可以与AR接受顺序不同。
~~~

Stage 3不把以下行为称为out-of-order：

- AW和W的先后关系。
- W beat在不同WID之间交织。
- R beat在不同RID之间交织。
- READY早于或晚于VALID。

### 4.2 相同ID顺序规则

对于同一ID：

- 第一个被接受的AW事务必须先于该ID的第二个AW事务完成B响应。
- 第一个被接受的AR事务必须先于该ID的第二个AR事务完成整个R burst。
- response计划列表即使多次包含相同ID，也只能依次弹出该ID pending FIFO的队首。
- 不允许通过内部issue序号选择同ID队列中的非队首事务。

### 4.3 不同ID乱序规则

对于不同ID：

- B返回顺序不要求与AW握手顺序一致。
- R burst返回顺序不要求与AR握手顺序一致。
- B和R使用独立调度器，允许并行工作。
- 一个方向发生stall不能强制另一个方向停止。
- 乱序策略只改变response计划进入Slave Driver的顺序，不改变单个response item内部的payload和时序字段。

### 4.4 预定义返回顺序

Stage 3 reactive response机制至少支持：

~~~text
b_return_order[$]
r_return_order[$]
~~~

两者保存Slave侧完整8-bit ID。

对于M0到S0，合法脚本ID为：

~~~text
8'h54, 8'h55, 8'h56, 8'h57
~~~

当脚本指定某ID时：

1. 等待该ID至少存在一个eligible response计划。
2. 从该ID pending FIFO弹出队首。
3. 写响应交给B发送路径。
4. 读响应以一个完整axi_rsp_item交给R发送路径。
5. 如果直到测试超时仍不存在目标ID，报告明确错误，不静默跳过。

### 4.5 默认和随机策略

- Stage 1/2 reactive sequence继续保留原有FIFO行为。
- Stage 3 scripted sequence使用预定义ID顺序。
- Stage 3可以增加不同ID随机选择smoke，但随机策略不能代替定向顺序测试。
- 随机选择只能在当前eligible的不同ID队首之间进行。
- 相同ID内部永远保持FIFO。

## 5. S3-04：ID和Switch reference model

### 5.1 Master侧4-bit ID

Master侧ID格式为：

~~~text
[3:2] 目标Slave编号
[1:0] 事务ID-tag
~~~

Stage 3 M0到S0合法ID：

| transaction tag | Master ID |
|---|---|
| 2'b00 | 4'h4 |
| 2'b01 | 4'h5 |
| 2'b10 | 4'h6 |
| 2'b11 | 4'h7 |

AWID、WID、ARID使用完整4-bit ID。BID和RID必须恢复相同的4-bit原始ID。

### 5.2 Slave侧8-bit ID

Slave侧ID格式为：

~~~text
[7:6] 实际目标Slave编号
[5:4] 请求来源Master编号
[3:0] 原始Master侧4-bit ID
~~~

M0到S0的合法映射为：

| Master ID | Slave ID |
|---|---|
| 4'h4 | 8'h54 |
| 4'h5 | 8'h55 |
| 4'h6 | 8'h56 |
| 4'h7 | 8'h57 |

### 5.3 地址映射

Switch reference model必须实现：

| 地址范围 | 路由 |
|---|---|
| 32'h0000_0000～32'h0000_0FFF | S0 |
| 32'h0000_2000～32'h0000_2FFF | S1 |
| 32'h0000_4000～32'h0000_4FFF | S2 |
| 其他 | Default |

整个burst只按AW/AR地址译码一次，不对每个数据beat重新译码。

### 5.4 Switch reference model接口

Stage 3提前实现以下无状态映射核心：

~~~text
decode_address(address) -> S0/S1/S2/DEFAULT
decode_w_target(wid) -> S0/S1/S2/INVALID
master_to_tag(port_index) -> 01/10/11/INVALID
slave_to_tag(route) -> 01/10/11/INVALID
build_master_id(slave, transaction_tag) -> 4-bit ID
encode_sid(master, slave, original_id) -> 8-bit SID
decode_master(sid) -> M0/M1/M2/INVALID
restore_id(sid) -> 4-bit original ID
~~~

该模型：

- 只计算路由和ID。
- 不驱动任何接口。
- 不选择arbiter winner。
- 不维护outstanding。
- 不实现TLM事务转发。
- 不替代Monitor和Checker。

### 5.5 五通道ID关系

Checker必须验证：

~~~text
S_AWID = {decode_address(AWADDR), source_master_tag, M_AWID}
S_WID  = {M_WID[3:2], source_master_tag, M_WID}
S_ARID = {decode_address(ARADDR), source_master_tag, M_ARID}

M_BID  = S_BID[3:0]
M_RID  = S_RID[3:0]
~~~

正常请求还必须满足：

~~~text
M_WID == 对应M_AWID
S_WID == 对应S_AWID
M_AWID[3:2] == decode_address(M_AWADDR)
M_ARID[3:2] == decode_address(M_ARADDR)
S_ID[7:6] == S_ID[3:2]
S_ID[5:4] == M0 tag
~~~

## 6. S3-05：数据流和职责边界

### 6.1 请求数据流

~~~text
Master Stage 3 sequence
        │ 4-bit axi_req_item
        ▼
Master sequencer
        ▼
Master Driver clone
        ├── aw_queue
        ├── w_queue
        └── ar_queue
        ▼
m_if → DUT → s_if
~~~

### 6.2 Slave响应计划流

~~~text
Slave Monitor完整request
        │ 8-bit axi_req_item
        ▼
Slave sequencer request_fifo
        ▼
Stage 3 reactive collector
        ├── pending_b_by_id[id][$]
        └── pending_r_by_id[id][$]
                 │
                 ▼
        B/R response scheduler
                 │ 8-bit axi_rsp_item
                 ▼
            Slave Driver
                 ▼
             s_if → DUT
~~~

### 6.3 Master响应观察流

~~~text
DUT → m_if
      ├── Master Driver：响应关联、outstanding释放、本地运行检查
      └── Master Monitor：发布B/R event和完整response
                              ▼
                     stage3_e2e_checker
~~~

Master Driver不调用put_response，Master sequence不调用get_response。

### 6.4 独立观察路径

~~~text
Master Monitor channel event ──┐
                              ├── upstream outstanding tracker
Slave Monitor channel event  ──┘

Master/Slave Monitor channel/request/response
                              └── stage3_e2e_checker
~~~

Tracker只使用Monitor观察到的真实握手，不读取Driver计数器、mailbox或response脚本。Driver内部计数与Tracker观察计数独立形成，并在关键边界和结束状态进行核对。

# 第二部分：测试点、时序约束和协议检查

## 7. S3-06：Outstanding功能测试点

### 7.1 写outstanding深度

定向覆盖：

- 最大值配置为1、2、3和4。
- 连续发出4笔AW并延迟全部B响应。
- write_outstanding依次达到1、2、3和4。
- 深度为4时，第5笔AW不得握手。
- 释放一个B后，第5笔AW可以继续。
- W通道、AR/R通道和BREADY在AW满时仍可推进。
- 四笔使用四个不同ID。
- 四笔全部使用相同ID。
- 两组ID重复，例如4、5、4、5。

### 7.2 写数据完成计数

- 每个WLAST握手只增加一次w_outstanding_by_id。
- 非最后W beat不增加计数。
- B握手前对应W计数必须存在。
- B握手后对应AW/W计数同时减少。
- BREADY stall期间计数不提前减少。
- AW先、W先和AW/W并行均能形成正确计数。

### 7.3 读outstanding深度

定向覆盖：

- 最大值配置为1、2、3和4。
- 连续发出4笔AR并延迟R响应。
- read_outstanding依次达到1、2、3和4。
- 深度为4时，第5笔AR不得握手。
- 一个RLAST握手后第5笔AR可以继续。
- 四笔使用四个不同ID。
- 四笔全部使用相同ID。
- 两组ID重复，例如4、6、4、6。

### 7.4 同周期更新

定向构造：

- AW握手与B握手同周期。
- WLAST握手与B握手同周期。
- AW、WLAST与B握手同周期。
- AR握手与RLAST握手同周期。
- B和RLAST同周期。

每种场景检查净计数、上下文队列和结束状态一致。

## 8. S3-07：Out-of-order功能测试点

### 8.1 B响应乱序

至少覆盖：

~~~text
AW接受顺序：54, 55, 56, 57
B返回顺序 ：57, 55, 54, 56
~~~

检查：

- 每个BID属于已完成写request。
- 上游BID恢复为4'h4～4'h7。
- 每个写事务只产生一个B。
- 不同ID乱序不会错误弹出其他ID上下文。

### 8.2 R响应乱序

至少覆盖：

~~~text
AR接受顺序：54, 55, 56, 57
R返回顺序 ：56, 54, 57, 55
~~~

每个读事务使用可区分的RDATA模式。检查：

- 第一拍RID选择正确读上下文。
- 整个burst保持相同RID。
- beat数量和原ARLEN一致。
- RLAST只出现在最后一拍。
- 一个burst结束后才选择下一个RID。

### 8.3 相同ID保序

写方向：

- 连续发出至少3笔相同ID写请求。
- 每笔使用可区分BRESP，或使用Checker内部issue序号验证队首消费。
- 返回计划多次指定相同ID。
- 实际完成顺序必须等于AW接受顺序。

读方向：

- 连续发出至少3笔相同ID读请求。
- 每笔使用不同RDATA base pattern。
- 实际完整R burst顺序必须等于AR接受顺序。

### 8.4 混合ID和重复ID

至少覆盖：

~~~text
请求ID：54, 55, 54, 56
响应ID：55, 54, 56, 54
~~~

不同ID可以越过，相同54的第二笔不能越过第一笔。

### 8.5 B/R并行

- 写、读各保持2～4笔outstanding。
- B和R在同周期或相邻周期握手。
- B返回顺序和R返回顺序分别配置。
- 写方向stall不能改变读返回计划。
- 读方向stall不能改变写返回计划。

### 8.6 backpressure叠加

- BVALID等待BREADY期间保持BID/BRESP。
- RVALID等待RREADY期间保持RID/RDATA/RRESP/RLAST。
- response已经选中后，stall期间不能改选其他ID。
- stall解除后只完成当前response或当前beat。
- 乱序选择发生在response尚未锁定之前。

## 9. S3-08：ID映射测试点

### 9.1 地址到Master ID

对S0地址窗口分别使用tag 00、01、10、11，得到：

~~~text
4'h4, 4'h5, 4'h6, 4'h7
~~~

检查AWID和ARID高两位均与地址目标一致。

### 9.2 4-bit到8-bit扩展

逐一检查：

~~~text
4'h4 -> 8'h54
4'h5 -> 8'h55
4'h6 -> 8'h56
4'h7 -> 8'h57
~~~

AW、W和AR三个通道分别检查，不允许只检查地址通道。

### 9.3 响应ID恢复

- S_BID 8'h54～8'h57恢复为M_BID 4'h4～4'h7。
- S_RID 8'h54～8'h57恢复为M_RID 4'h4～4'h7。
- BID和RID恢复与对应请求上下文一致。
- 不同ID乱序时仍按当前响应SID恢复，不能使用全局请求顺序猜测。

### 9.4 Switch reference model单元测试

单独验证：

- 三个正常地址窗口和边界地址。
- Default地址译码。
- 三个Master tag。
- 三个Slave tag。
- build_master_id。
- encode_sid。
- decode_master。
- restore_id。
- decode_w_target。

该单元测试只检查DV reference model，不访问DUT。

## 10. S3-09：协议断言和状态检查

### 10.1 断言部署

继续在m_if和s_if分别例化参数化axi_protocol_assertions，并扩展Stage 3观察状态。

Stage 3新增检查必须基于真实接口握手，不读取Driver mailbox、sequence计划或Checker内部队列。

### 10.2 Outstanding相关检查

至少检查：

- AW握手后对应ID计数增加。
- WLAST握手后对应ID数据完成计数增加。
- B握手不能消费不存在的W完成状态。
- AR握手后对应ID计数增加。
- R beat不能使用没有pending AR上下文的RID。
- RLAST不能消费不存在的读outstanding。
- 每方向outstanding不得超过配置的Stage 3上限。
- 计数不得下溢。
- reset释放后的初始计数为0。

AXI3通用BVALID因果断言继续沿用Stage 2已经冻结的规则；完整AW/W/B事务关联由Stage 3状态检查和Checker共同完成。

### 10.3 同ID顺序检查

- 相同ARID的读请求按握手顺序进入FIFO。
- 相同RID只能消费对应ARID FIFO队首。
- 相同AWID的写请求按握手顺序进入FIFO。
- 相同BID只能消费对应写上下文FIFO队首。
- 断言无法从接口payload唯一分辨的同ID写实例，由Monitor/Checker的内部issue顺序补充检查。

### 10.4 非交织检查

Stage 3项目级断言检查：

- 一个W burst开始后，直到WLAST握手前WID保持不变。
- 一个R burst开始后，直到RLAST握手前RID保持不变。
- WLAST/RLAST数量和LEN一致。
- 一个burst未完成时不能切换到其他ID。

这些检查是Stage 3能力边界，不表示AXI3协议永久禁止交织；Stage 4实现交织后必须更新或关闭对应项目级断言。

### 10.5 ID有效性检查

握手时检查：

- 所有ID位均不含X/Z。
- M0到S0正向测试的Master请求ID属于4'h4～4'h7。
- 下游SID属于8'h54～8'h57。
- AWID与WID按完整ID关联。
- ARID与RID按完整ID关联。
- SID的slave tag、master tag和original ID字段一致。

### 10.6 现有断言继续生效

Stage 2以下断言不得回退：

- 五通道VALID stall稳定性。
- VALID在握手前不得撤销。
- 握手payload不得包含X/Z。
- WLAST/RLAST提前、缺失和beat数量检查。
- reset期间Testbench主动驱动VALID/READY为0。

### 10.7 负向断言自测

新增独立负向场景：

- B响应使用没有pending写事务的BID。
- R响应使用没有pending读事务的RID。
- 相同ID第二笔响应提前返回。
- R burst中途改变RID。
- W burst中途改变WID。
- outstanding计数故意超过4。
- 下游SID master tag错误。
- 下游SID slave tag与original ID目标位不一致。

负向自测必须区分预期断言触发和测试失败，不进入正向回归。

## 11. S3-10：覆盖率基础观察点

Stage 3不建立最终functional coverage collector，但必须保证Monitor event、Checker状态和测试日志可以支持后续采样：

- read outstanding深度0～4。
- write outstanding深度0～4。
- Driver内部深度与Tracker接口观察深度的一致性。
- 每个ID独立outstanding深度。
- 使用ID数量1～4。
- 相同ID多笔和不同ID多笔。
- FIFO返回、完全逆序、部分逆序。
- B和R并行。
- AW/W先后关系与outstanding深度交叉。
- response乱序与BREADY/RREADY stall交叉。
- burst长度、burst类型与乱序交叉。
- ID tag 00、01、10、11。
- 同周期增加和释放。

日志中必须能够打印ID、方向、issue顺序、请求接受顺序、响应计划顺序和实际响应顺序。

## 12. S3-11：Reset和异常边界

### 12.1 本阶段Reset要求

- 正常回归只在启动reset释放后发送事务。
- reset期间三个outstanding数组清零。
- reset期间所有按ID上下文队列清空。
- reset期间Slave response计划池和脚本索引清空。
- Monitor清除所有AW/W/AR/B/R重建上下文。
- Stage 3 Checker在启动reset后从空状态开始。

### 12.2 本阶段不验证

- outstanding存在时进入reset。
- B/R乱序返回过程中reset。
- W/R burst中途reset。
- reset后重放部分请求。
- reset与response脚本恢复。

这些内容留到Stage 5复杂reset阶段。

# 第三部分：各组件需要完成的内容

## 13. S3-12：组件修改总览

| 文件/组件 | Stage 3需要完成 |
|---|---|
| axi_types_pkg.sv | 增加DV路由枚举或tag公共类型，保持AXI ID宽度定义 |
| axi_switch_ref_model.sv | 新增无状态地址译码和ID编解码模型 |
| axi_req_item.sv | 保持id为完整AXI ID，不增加UVM sequence ID字段 |
| axi_rsp_item.sv | 保持id为完整响应AXI ID |
| axi_m_agent_cfg.sv | 支持max_read_outstanding/max_write_outstanding为1～4 |
| axi_m_driver.sv | 三个按ID计数数组、多上下文、AW/AR限流、B/R按ID释放 |
| axi_s_driver.sv | 接收按计划排序的多笔B/R response，继续完整burst发送 |
| axi_m_monitor.sv | 多AW/W/AR/B/R上下文和按ID重建 |
| axi_s_monitor.sv | 多AW/W/AR/B/R上下文和按ID重建 |
| axi_protocol_assertions.sv | outstanding、ID关联、同ID顺序和Stage 3非交织检查 |
| axi_outstanding_tracker.sv | 根据Monitor channel event独立维护按端口、方向和ID的观察计数 |
| axi_s_sequencer.sv | request_fifo继续接收多笔完整request |
| Stage 3 Master sequence | 生成多ID、多请求、相同ID和不同ID场景 |
| Stage 3 reactive sequence | pending response计划池和B/R独立ID调度 |
| stage3_e2e_checker.sv | 按ID比较请求/响应、ID转换、顺序、因果和结束状态 |
| axi_env.sv/axi_env_cfg.sv | 例化、连接和选择Stage 3 Checker |
| axi_env_pkg.sv | include新增model、context和checker |
| axi_seq_pkg.sv | include Stage 3 sequence |
| axi_test_pkg.sv | include Stage 3 tests |
| sim/sim.f | 保持类型、interface、package、RTL、断言和tb编译顺序 |
| sim/Makefile | 增加Stage 3回归和Stage 3断言自测入口 |

## 14. S3-13：Switch reference model

### 14.1 定位

axi_switch_ref_model是DV参考模型，不是接口Driver，不访问virtual interface，不保存arbiter状态。

### 14.2 API要求

模型至少提供：

~~~systemverilog
decode_address(addr);
decode_w_target(id);
master_to_tag(port_index);
slave_to_tag(route);
build_master_id(route, transaction_tag);
encode_sid(master_index, route, original_id);
decode_master(sid);
restore_id(sid);
~~~

### 14.3 使用者

- Master Stage 3 sequence使用decode_address和build_master_id生成合法request。
- Stage 3 Checker独立计算预期路由和SID。
- 定向测试可以使用encode_sid生成Slave reactive返回脚本。
- Driver不得调用该模型修正sequence给出的ID。
- Monitor不得调用该模型改写真实观察值。

### 14.4 自检

reference model必须有独立对象级测试，使用固定输入输出表验证，避免生成激励和Checker共同使用错误映射而互相掩盖。

## 15. S3-14：Master Driver

### 15.1 状态替换

删除Stage 2单事务运行限制：

~~~text
write_busy
read_busy
write_id
read_id
单一read_len
单一read_beat_index
~~~

替换为：

~~~text
aw_outstanding_by_id[ID_COUNT]
w_outstanding_by_id[ID_COUNT]
ar_outstanding_by_id[ID_COUNT]

write_context_by_id[id][$]
read_context_by_id[id][$]
active_r_context
~~~

内部上下文必须保存稳定request快照或引用Driver拥有的稳定context对象。

### 15.2 accept_items

- reset释放后调用get_next_item。
- 立即clone request。
- 写request生成一个稳定写context，并将同一个context引用放入AW和W路径。
- 读request生成一个稳定读context并放入AR路径。
- 所有内部登记完成后调用一次item_done。
- 不等待outstanding空位。
- 不等待接口握手和响应。

### 15.3 AW发送

- aw_queue取出context。
- 等待write_outstanding小于上限。
- 执行addr_delay。
- 驱动完整AW payload。
- stall期间锁定。
- AW握手后登记该context的AW完成状态和按ID顺序。
- 计数由唯一状态更新者增加。

### 15.4 W发送

- w_queue取出与AW路径共享的context。
- 执行w_start_delay和逐beat wbeat_gap。
- 完整burst连续发送，不切换WID。
- WLAST握手后标记该context的W完成状态。
- 计数由唯一状态更新者增加。
- W路径不读取write_outstanding作为发送资格。

### 15.5 AR发送

- ar_queue取出context。
- 等待read_outstanding小于上限。
- 执行addr_delay。
- 驱动完整AR payload。
- AR握手后将context放入对应ARID FIFO。
- 计数由唯一状态更新者增加。

### 15.6 B接收

- BREADY继续独立随机化。
- B握手时使用BID选择write_context_by_id。
- 队列为空时报关联错误。
- 只允许消费队首。
- 检查该context的W完成状态。
- 检查BRESP合法。
- 合法完成后弹出队首并减少AW/W计数。
- 不调用item_done。
- 不创建返回Master sequence的response。

### 15.7 R接收

- RREADY继续逐beat独立随机化。
- 新burst第一拍使用RID选择read_context_by_id队首。
- 保存为active_r_context。
- 后续beat必须保持相同RID。
- 使用该context的len检查beat索引和RLAST。
- RLAST握手后弹出队首并减少AR计数。
- 不调用item_done。
- 不向Master sequence返回response。

### 15.8 状态更新所有权

outstanding数组只能由一个task或同步状态管理块写入。drive_aw、drive_w、drive_ar、receive_b和receive_r不得分别无协调地修改相同计数器。

### 15.9 Reset

watch_reset清除：

- 三个outstanding数组。
- 所有按IDcontext队列。
- active_r_context。
- AW/W/AR mailbox。

各通道task继续只负责自己驱动信号的reset值。

## 16. S3-15：Slave reactive sequence和Slave Driver

### 16.1 Collector

Stage 3 reactive sequence使用collector持续读取request_fifo：

- 完整写request转换为B response计划。
- 完整读request转换为完整R response计划。
- response计划保留完整8-bit request ID。
- 按方向和ID放入pending队列。
- 相同ID按request接受顺序排队。

### 16.2 B scheduler

- 独立消费b_return_order。
- 等待指定ID pending B队列非空。
- 只弹出指定ID队首。
- 填写rsp_delay和BRESP。
- 通过Slave sequencer发送给Slave Driver。
- 支持连续多个相同ID。

### 16.3 R scheduler

- 独立消费r_return_order。
- 等待指定ID pending R队列非空。
- 只弹出指定ID队首。
- 生成完整len+1拍RDATA/RRESP。
- 使用可区分的transaction base和beat index数据模式。
- 填写rsp_delay和rbeat_gap[]。
- 一个response item表示一个完整R burst。

### 16.4 Collector和scheduler并行

collector、B scheduler和R scheduler必须能够并行工作。scheduler等待尚未到达的脚本ID时不能阻止collector继续读取request_fifo。

Slave sequencer仍只有一条seq_item请求通道。B/R scheduler向sequencer提交response item时必须通过统一send_response方法、semaphore或等价机制串行完成start_item/finish_item，不能由两个线程同时操作同一个sequence握手。该短暂串行只约束UVM item提交；Slave Driver在item_done前把B/R快照分别放入独立队列，因此不会阻止B和R接口并行发送。

### 16.5 Slave Driver

Slave Driver继续：

- clone response item。
- 写response进入b_queue。
- 读response进入r_queue。
- item_done不等待接口握手。
- B和R使用独立发送task。
- R response完整连续发送到RLAST。

Stage 3的乱序选择在reactive scheduler完成；Slave Driver不重新排列已经收到的response item。

## 17. S3-16：Master/Slave Monitor

### 17.1 通用原则

- Monitor只观察真实接口握手。
- 每个握手发布一个新的channel event。
- Monitor不读取Driver、sequence或Switch model的计划状态。
- 保存对象时必须clone。

### 17.2 写request重建

两侧Monitor分别维护：

~~~text
aw_context_by_id[id][$]
completed_w_by_id[id][$]
active_w_burst
~~~

- 每个AW握手保存完整地址上下文。
- Stage 3不交织W，因此只需要一个active W burst。
- WLAST后形成一个完整W burst上下文。
- AW和完整W burst按完整ID及FIFO顺序配对。
- 支持AW先、W先和多个AW等待W。
- 每个完整写request只发布一次。

### 17.3 读request和R重建

- 每个AR握手立即发布一个完整读request。
- 同时按ARID保存读上下文FIFO。
- 新R burst第一拍RID选择对应读上下文队首。
- R burst期间锁定RID。
- RLAST后发布一个完整读response并弹出读上下文。

### 17.4 B重建

- 每个B握手发布一个写response。
- 使用BID关联对应写上下文队首。
- 不要求全局B顺序与AW顺序相同。

### 17.5 Reset

reset期间清除所有按IDFIFO、active burst和未完成配对，不发布event或完整item。

## 18. S3-17：协议断言

### 18.1 状态结构

axi_protocol_assertions必须从Stage 2单一AW/AR观察状态扩展为按ID状态：

~~~text
AW acceptance FIFO/state
completed W state
AR context FIFO/state
active W burst
active R burst
per-ID outstanding counters
~~~

### 18.2 职责边界

断言负责：

- 握手级协议状态。
- outstanding上下溢。
- ID X/Z。
- Stage 3非交织边界。
- LAST和beat数量。
- stall稳定性。

Checker负责：

- DUT上下游转发。
- 4-bit/8-bit ID变换。
- 完整request/response内容。
- 不同ID乱序匹配。
- 相同ID端到端顺序。

Driver负责：

- 运行所需的本地response关联和资源释放。

## 19. S3-18：Outstanding Tracker和stage3_e2e_checker

### 19.1 Outstanding Tracker

新增参数化axi_outstanding_tracker。每个被观察接口使用与该接口ID宽度一致的tracker实例。

Tracker输入只来自Monitor channel_ap，收到对象后clone再处理。它至少维护：

~~~text
aw_observed_by_id[id]
wlast_observed_by_id[id]
ar_observed_by_id[id]
当前写、读outstanding总数
观察到的最大写、读outstanding深度
每个ID的请求和完成数量
~~~

状态更新规则与真实接口握手一致：

- AW event增加AW观察计数。
- WLAST event增加W完成观察计数。
- B event按BID减少AW/W观察计数。
- AR event增加AR观察计数。
- RLAST event按RID减少AR观察计数。

Tracker负责接口观察状态、下溢、深度和结束非空检查，不生成DUT expected transaction，不读取Driver内部数组。

### 19.2 Checker定位

stage3_e2e_checker用于M0到S0的多outstanding和响应乱序端到端检查。它不替代Stage 1/2 Checker，不实现三主三从仲裁和路由Scoreboard。

### 19.3 输入端口

至少接收：

~~~text
upstream_channel_export
downstream_channel_export
upstream_req_export
downstream_req_export
upstream_rsp_export
downstream_rsp_export
~~~

所有analysis对象clone后入队。

### 19.4 Request比较

- 上游request按完整4-bit ID保存。
- 下游request按完整8-bit SID保存。
- 使用Switch reference model计算预期SID。
- 相同ID请求按FIFO比较。
- 不依赖B/R返回顺序决定request匹配。
- 写request比较AW属性、W数据、WSTRB和LAST。
- 读request比较AR属性。

### 19.5 Response比较

- 下游B/R response作为返回路径expected。
- 上游B/R response作为actual。
- 根据下游SID恢复4-bit ID。
- 以恢复后的ID选择上游响应队列。
- 不同ID可以以任意顺序比较。
- 相同ID只比较各自队列队首。
- R response比较len、每拍RDATA、RRESP和RLAST。
- B response比较BRESP。

### 19.6 因果和顺序

Checker必须确认：

- B关联一个完整下游写request。
- R关联一个已接受下游读request。
- 每个request只被一个response消费。
- 相同ID完成顺序与接受顺序一致。
- 不同ID发生逆序时不报全局FIFO错误。
- B和R上下文独立。

### 19.7 计数

Checker至少统计：

~~~text
AW/W/B/AR/R event数量
完整写request数量
完整读request数量
完整写response数量
完整读response数量
每个ID的请求和响应数量
观察到的最大读写outstanding深度
不同ID逆序发生次数
相同ID多笔发生次数
~~~

### 19.8 结束检查

测试结束时确认：

- 所有event队列为空。
- 所有完整request/response队列为空。
- 所有按IDexpected/actual队列为空。
- 没有未配对AW或完整W burst。
- 没有未完成R burst。
- 没有未匹配B/R。
- Master Driver三个outstanding数组全为0。
- upstream/downstream Outstanding Tracker所有观察计数全为0。
- Slave request_fifo为空。
- Slave response计划池为空。
- response脚本全部消费。
- 实际计数等于测试期望计数。

## 20. S3-19：Env、Cfg和Checker选择

### 20.1 Checker使能

Stage 3多事务测试不能让Stage 1/2 Checker继续按旧单事务假设判定。

环境必须支持明确选择当前Checker：

- Stage 1测试启用Stage 1 Checker。
- Stage 2测试启用Stage 2 Checker并关闭Stage 1 Checker。
- Stage 3测试启用Stage 3 Checker并关闭Stage 1/2 Checker。

可以使用统一checker mode或各Checker enabled字段，但不得依赖测试直接修改未公开内部队列。

### 20.2 Cfg

axi_m_agent_cfg中的：

~~~text
max_write_outstanding
max_read_outstanding
~~~

Stage 3默认设为4，允许测试配置1～4。

response返回脚本属于Stage 3 reactive sequence或Stage 3 scenario配置，不放入通用agent cfg。

### 20.3 S0-OPEN-01

继续保持：

- Master Driver不调用put_response。
- Master sequence不调用get_response。
- B/R完成由Driver内部状态和Monitor/Checker观察。
- sequence_id/transaction_id不用于AXI ID关联。

## 21. S3-20：文件和测试组织

### 21.1 建议新增文件

~~~text
dv/env/axi_switch_ref_model.sv
dv/env/axi_outstanding_tracker.sv
dv/env/checker/stage3_e2e_checker.sv

dv/seq/axi_stage3_scenario_seq.sv
dv/seq/axi_stage3_outstanding_write_seq.sv
dv/seq/axi_stage3_outstanding_read_seq.sv
dv/seq/axi_stage3_write_ooo_seq.sv
dv/seq/axi_stage3_read_ooo_seq.sv
dv/seq/axi_stage3_same_id_order_seq.sv
dv/seq/axi_stage3_mixed_rw_seq.sv
dv/seq/axi_s_stage3_reactive_seq.sv

dv/tc/axi_stage3_base_test.sv
dv/tc/axi_stage3_outstanding_write_test.sv
dv/tc/axi_stage3_outstanding_read_test.sv
dv/tc/axi_stage3_write_ooo_test.sv
dv/tc/axi_stage3_read_ooo_test.sv
dv/tc/axi_stage3_same_id_order_test.sv
dv/tc/axi_stage3_mixed_rw_test.sv
dv/tc/axi_stage3_id_mapping_test.sv
dv/tc/axi_stage3_outstanding_stall_test.sv

dv/tb/axi_stage3_protocol_assertions_selftest.sv
~~~

### 21.2 文件职责

- 可复用model、Driver、Monitor、断言和Checker放在dv/env。
- Master和Slave sequence放在dv/seq。
- 每个testcase单独放在dv/tc。
- test只负责配置、脚本、启动sequence和等待统一结果。
- tb只完成接口、DUT、断言和时钟reset连接。
- 不向dv目录写入仿真生成物。

# 第四部分：Stage 3验证和验收

## 22. A3-01：Stage 3A代码审核

审核：

- 只修改dv、sim和文档范围文件，rtl目录无修改。
- 三个数组名称严格为aw_outstanding_by_id、w_outstanding_by_id和ar_outstanding_by_id。
- mailbox保持无界。
- 不存在write_slots_used/read_slots_used。
- max outstanding范围为1～4。
- 三个计数数组只有一个状态更新所有者。
- Driver支持相同ID多笔上下文。
- Monitor支持多个AW/AR和按IDresponse重建。
- reactive侧B/R scheduler相互独立。
- Stage 3 Checker按ID匹配，不使用全局response FIFO强制顺序。
- Switch reference model不承担arbiter和Driver职责。
- Master Driver不调用put_response。
- 没有提前实现W/R交织和三主三从环境。

工具门槛：

~~~text
Questa编译0 error
elaboration 0 error
无新增非预期warning
~~~

## 23. A3-02：Outstanding验收

### 23.1 写方向

- 深度1～4分别通过。
- 四个不同ID达到深度4。
- 同一ID四笔达到深度4。
- 第5笔AW在满时不握手。
- B释放后只允许对应数量的新AW进入。
- AW/W计数按BID正确减少。
- 测试结束数组归零。

### 23.2 读方向

- 深度1～4分别通过。
- 四个不同ID达到深度4。
- 同一ID四笔达到深度4。
- 第5笔AR在满时不握手。
- RLAST释放后只允许对应数量的新AR进入。
- 非RLAST R beat不释放outstanding。
- 测试结束数组归零。

### 23.3 同周期

所有第7.4节同周期组合通过，无计数下溢、覆盖写入或上下文错配。

## 24. A3-03：Out-of-order验收

- 不同BID按预定义非FIFO顺序返回。
- 不同RID完整burst按预定义非FIFO顺序返回。
- 相同BID多笔保持AW接受顺序。
- 相同RID多笔保持AR接受顺序。
- 混合重复ID场景通过。
- R burst内不切换RID。
- W burst内不切换WID。
- B和R乱序调度可以并行。
- response stall期间选择保持稳定。

## 25. A3-04：ID验收

- S0四个Master ID全部覆盖。
- 4'h4～4'h7分别正确扩展为8'h54～8'h57。
- AW、W和AR三个请求通道映射全部正确。
- B和R响应ID全部恢复正确。
- Switch reference model单元测试通过。
- Checker在不同ID乱序时仍使用当前SID正确恢复和关联。

## 26. A3-05：Monitor和Checker验收

- 两侧Monitor支持至少4笔未完成request。
- Outstanding Tracker在两侧接口按完整ID正确增加、释放并最终清空。
- AW先、W先和多个AW等待W时重建正确。
- 多AR等待R时重建正确。
- 不同IDresponse乱序发布完整item。
- 相同ID完整item顺序正确。
- Stage 3 Checker每拍event、完整request和完整response全部匹配。
- 所有结束pending状态为0。
- Stage 1/2 Checker在Stage 3测试中不会按旧假设参与判定。

## 27. A3-06：协议断言验收

正向回归要求：

- 所有Stage 3协议断言零非预期失败。
- outstanding深度1～4均不误报。
- 合法不同ID乱序不误报。
- 合法相同ID顺序不误报。
- 合法AW/W独立推进不误报。

负向自测要求：

- 第10.7节每个错误场景命中对应断言或状态检查。
- 每种预期错误有唯一可识别标记。
- 未出现额外非预期断言。
- 最终打印AXI_STAGE3_ASSERT_SELFTEST_PASS。

## 28. A3-07：端到端测试清单

至少建立：

~~~text
axi_stage3_outstanding_write_test
axi_stage3_outstanding_read_test
axi_stage3_write_ooo_test
axi_stage3_read_ooo_test
axi_stage3_same_id_order_test
axi_stage3_mixed_rw_test
axi_stage3_id_mapping_test
axi_stage3_outstanding_stall_test
~~~

继续运行Stage 2七个正向测试和Stage 1两个单拍测试。

## 29. A3-08：统一通过条件

每个Stage 3正向DUT测试必须满足：

- 预期AW/W/B/AR/R握手数量全部匹配。
- 最大outstanding深度达到测试目标且不超过配置。
- Driver内部计数和Tracker真实接口观察计数达到一致的目标深度。
- 三个outstanding数组结束时全为0。
- 上游4-bit ID和下游8-bit SID映射全部正确。
- 不同ID预定义response顺序实际发生。
- 相同ID响应保持FIFO。
- W/R burst数据、STRB、RESP和LAST一致。
- 完整request/response内容一致。
- 没有重复、遗漏或额外event。
- 没有未完成上下文和active burst。
- Slave request_fifo为空。
- Slave response计划池和返回脚本为空。
- 协议断言零非预期失败。
- UVM_WARNING=0、UVM_ERROR=0、UVM_FATAL=0。
- 测试打印统一PASS标记并正常退出。

## 30. A3-09：运行入口和回归

沿用当前QuestaSim入口并增加：

~~~text
cd sim
make com
make sim test=<testname>
make stage3_regress
make positive_regress
make stage3_assertion_selftest
make assertion_selftest
~~~

要求：

- stage3_regress连续运行全部Stage 3正向测试。
- positive_regress连续运行Stage 1、Stage 2和Stage 3正向测试。
- Stage 3负向断言自测不混入positive_regress。
- 任一测试失败时回归命令返回非0。
- 日志存放在sim/work/log。
- 波形存放在sim/work/wave。
- 覆盖率数据库如果启用，存放在sim/work。

## 31. Stage 3完成条件

只有同时满足以下条件，Stage 3才能审核冻结：

1. Stage 3A所有组件代码完成并通过代码风格审核。
2. RTL目录未被Stage 3修改。
3. Questa编译和elaboration无错误。
4. 读、写outstanding深度1～4全部通过。
5. 三个指定outstanding数组按真实握手正确更新。
6. 满深度时AW/AR停止发出，释放后恢复。
7. 同周期增加和释放场景通过。
8. 相同ID多笔事务严格保序。
9. 不同ID的B响应乱序通过。
10. 不同ID的完整R burst乱序通过。
11. W/R保持Stage 3非交织边界。
12. M0到S0四组ID映射和恢复全部通过。
13. Switch reference model单元测试通过。
14. 两侧Monitor多上下文重建通过。
15. Outstanding Tracker的接口观察计数、最大深度和结束状态检查通过。
16. stage3_e2e_checker的event、item、顺序、因果和结束检查通过。
17. Stage 3正向协议断言零失败。
18. Stage 3负向断言自测全部命中预期。
19. Stage 1和Stage 2全部正向回归继续通过。
20. S0-OPEN-01继续保留。
21. 没有提前实现Stage 4交织、Stage 5复杂reset或Stage 6三主三从能力。

## 32. 审核记录

| 审核项 | 当前状态 | 说明 |
|---|---|---|
| Stage 3范围 | 待实施 | M0到S0，多outstanding和不同ID响应乱序 |
| RTL修改 | 禁止 | 本工单不修改rtl目录 |
| Outstanding深度 | 待实施 | 读写分别1～4 |
| Outstanding数组 | 待实施 | 使用三个冻结名称 |
| mailbox容量 | 已冻结 | 保持无界，不计入AXI outstanding |
| 相同ID顺序 | 待实施 | 每个ID独立FIFO |
| 不同ID乱序 | 待实施 | B和完整R burst预定义顺序 |
| W/R交织 | 不实施 | 留Stage 4 |
| ID范围 | 已冻结 | M侧4'h4～4'h7，S侧8'h54～8'h57 |
| Switch reference model | 待实施 | 只实现地址译码和ID编解码 |
| Master sequence response | 继续保留限制 | 不调用put_response/get_response |
| Reset范围 | 已冻结 | 只覆盖启动reset |
| Stage 3 Checker | 待实施 | 按ID匹配多上下文 |
| Outstanding Tracker | 待实施 | 只根据Monitor真实event维护独立观察计数 |
| 协议断言 | 待实施 | outstanding、顺序、ID和非交织 |
| 编译与仿真结果 | 未运行 | 实施完成后填写实际记录 |

### 32.1 实际运行记录

Stage 3尚未实施。本节在代码和测试实际运行后填写：

- 工具版本。
- 实际修改文件。
- 编译命令和结果。
- Stage 3正向测试列表和结果。
- Stage 1～3完整正向回归结果。
- Stage 3断言自测结果。
- 日志、波形和覆盖率路径。
- 遗留限制和最终冻结结论。

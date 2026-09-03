# AXI3 Interconnect UVM Driver设计SPEC

editor：Codex / 项目讨论结论整理  
date：2026-09-04  
版本号：v1-draft

## 迭代记录

| 版本 | 日期 | 迭代原因 | 迭代内容 |
|---|---|---|---|
| v1-draft | 2026-09-04 | 基于已经完成的请求/响应transaction，定义Master/Slave Driver的实现边界和并发模型 | 定义接口依赖、队列和线程划分、五通道驱动规则、outstanding、交织、响应返回、reset及待讨论项 |

## 1. 文档目的

本文档定义三主三从AXI3 Interconnect新`dv`验证环境中的Driver设计。设计基于：

- [axi3_interconnect_uvm_framework_spec.md](./axi3_interconnect_uvm_framework_spec.md) v1。
- [transaction_spec.md](./transaction_spec.md) v3。
- [axi3_interconnect_testplan.md](./axi3_interconnect_testplan.md)中的Driver能力要求。
- 当前RTL顶层`rtl/axi_interconnect.v`的五通道端口。

本文档优先于旧`uvm_tb`目录中的历史Driver实现。旧代码只可用于核对RTL端口名称，不沿用以下设计：

- 一个Driver同时操作三个Master或三个Slave端口。
- transaction直接保存VALID、READY和三组端口信号。
- Driver把激励意图直接发给scoreboard或coverage。
- 等一笔请求的响应全部返回后才允许sequencer发送下一笔请求。
- 使用固定周期延迟代替真实VALID/READY握手。

本文档当前是Driver实现前的设计草案。第13节列出的事项需要在编码前确认；其他章节作为推荐实现基线。

## 2. 设计范围与边界

新环境包含两类单端口Driver：

```text
axi_m_driver    模拟一个上游AXI Master
                消费axi_req_item
                驱动AW/W/AR，控制BREADY/RREADY

axi_s_driver    模拟一个下游reactive AXI Slave
                消费axi_rsp_item
                控制AWREADY/WREADY/ARREADY，驱动B/R
```

每个Driver实例只绑定一个物理AXI端口。三主三从环境实例化三个`axi_m_driver`和三个`axi_s_driver`，Driver内部不使用`[0:2]`端口数组，也不根据`port_index`选择接口。

Driver负责：

- 将transaction内容映射到正确通道。
- 按transaction中的delay/gap意图安排发送时机。
- 严格执行VALID/READY握手及stall稳定规则。
- 对其主动驱动的通道执行并发调度。
- 使用配置对象控制READY/backpressure、内部队列深度和超时诊断。
- 在提前完成sequencer握手时保存transaction独立快照。
- 在reset期间把主动输出恢复到规定的空闲值。

Driver不负责：

- 地址译码、Slave选择或DUT路由预测。
- 判断DUT仲裁、数据、响应或ID恢复是否正确。
- 向scoreboard发布“预计已经发生”的传输。
- 调用functional coverage的`sample()`。
- 重新随机化、静默修正、拆短或丢弃sequence给出的事务。
- 用Driver内部队列代替monitor、reference model或outstanding tracker。

接口真实发生的功能事件只能由monitor在`VALID && READY`时发布。Driver内部观察B/R握手仅用于流控、可选sequence响应返回和超时诊断，不作为scoreboard的actual输入。

## 3. 对interface的前置要求

Driver代码依赖新的单端口AXI interface。该interface尚未实现，应在Driver编码前完成。

### 3.1 参数与单端口形式

建议interface参数与transaction保持一致：

```systemverilog
interface axi_if #(
  int unsigned ADDR_WIDTH = 32,
  int unsigned DATA_WIDTH = 32,
  int unsigned ID_WIDTH   = 4,
  int unsigned LEN_WIDTH  = 4
) (
  input logic ACLK,
  input logic ARESETn
);
```

上游interface实例使用4-bit `ID_WIDTH`，下游interface实例使用8-bit扩展`ID_WIDTH`。顶层通过generate或逐端口连接，把三个单端口interface映射到RTL的`M_AXI_*[0:2]`和`S_AXI_*[0:2]`数组。

### 3.2 Driver clocking block

interface至少提供两个Driver视角的clocking block：

| clocking block | Driver输出 | Driver输入 |
|---|---|---|
| `m_drv_cb` | AW payload/VALID、W payload/VALID、BREADY、AR payload/VALID、RREADY | AWREADY、WREADY、B payload/VALID、ARREADY、R payload/VALID |
| `s_drv_cb` | AWREADY、WREADY、B payload/VALID、ARREADY、R payload/VALID | AW payload/VALID、W payload/VALID、BREADY、AR payload/VALID、RREADY |

推荐统一使用：

```systemverilog
default input #1step output #0;
```

所有Driver线程只通过对应clocking block采样和驱动，不能混用裸`@(posedge ACLK)`、直接层次赋值和clocking block访问。一个clocking event的处理顺序定义为：

1. 使用input skew采样刚刚到达的时钟边沿是否完成握手。
2. 更新内部状态、计数和队列。
3. 使用output skew设置下一传输周期的输出。

这样可避免Driver、DUT和monitor在同一时钟沿的竞争条件。

### 3.3 空闲值

默认空闲值规定为：

- 所有由Driver输出的VALID为0。
- reset期间所有由Driver输出的READY为0。
- 非reset空闲期READY由backpressure策略决定。
- 非有效周期的payload驱动为0，不能驱动`X`或`Z`。
- VALID为1且尚未握手时，payload不能被空闲值覆盖。

## 4. Driver类和类型关系

建议定义参数化别名，避免类声明中重复长类型：

```systemverilog
typedef axi_req_item #(ADDR_WIDTH, DATA_WIDTH, ID_WIDTH, LEN_WIDTH) req_t;
typedef axi_rsp_item #(DATA_WIDTH, ID_WIDTH, LEN_WIDTH)             rsp_t;
```

Master Driver建议支持独立REQ/RSP类型：

```systemverilog
class axi_m_driver #(参数...) extends uvm_driver #(req_t, rsp_t);
```

对应Master sequencer使用`uvm_sequencer #(req_t, rsp_t)`。即使首版关闭“响应返回sequence”，保留RSP参数也可以避免后续修改类继承关系。

Slave Driver只消费响应计划：

```systemverilog
class axi_s_driver #(参数...) extends uvm_driver #(rsp_t);
```

Driver从各自agent配置对象获得：

- 单端口virtual interface。
- active/passive模式由agent决定，Driver只在active agent中创建。
- READY/backpressure策略。
- 最大outstanding、内部队列深度和超时门限。
- W/R交织及response-to-sequence开关。

Driver不直接从全局`axi_env_cfg`读取其他端口的配置。

## 5. 通用对象所有权和sequencer握手

### 5.1 推荐的提前`item_done()`模型

为了形成多笔outstanding，Driver不能一直持有`get_next_item()`取得的对象直到总线响应完成。推荐流程为：

```text
sequencer提供item
       ↓
Driver确认内部入口队列有空间
       ↓
clone/copy为独立快照
       ↓
快照成功进入内部队列
       ↓
调用item_done()
       ↓
各通道线程异步处理快照
```

要求：

- 只能在clone成功且快照已经进入有界队列后调用`item_done()`。
- `item_done()`以后不得再读取或修改原始`req/rsp`句柄。
- Driver不得把原始句柄同时放入多个通道队列。
- 多个通道共享一笔事务时，队列中保存一个内部context句柄；context拥有唯一transaction快照和各通道完成状态。
- 队列已满时不从sequencer取新item，从源头形成背压，不能无限缓存。

为避免reset杀死一个已经`get_next_item()`但尚未`item_done()`的线程，推荐入口线程在时钟循环中使用非阻塞`try_next_item()`，并把“取得、clone、入队、item_done”做成不可被reset中断的短操作。若最终使用阻塞`get_next_item()`，必须额外证明reset时不会遗留未完成的sequencer握手。

### 5.2 内部context

内部context是Driver实现数据结构，不是新的sequence item。Master请求context至少包含：

- `req_t req`：独立快照。
- 接收顺序号和reset epoch。
- AW、W、AR的started/done状态。
- W当前beat索引和下一个可发送周期。
- 读/写issue credit占用状态。
- 原请求的UVM sequence/request标识，用于可选response返回。

Slave响应context至少包含：

- `rsp_t rsp`：独立快照。
- 接收顺序号和reset epoch。
- B或R当前发送状态。
- R当前beat索引和下一个可发送周期。

context不发布到scoreboard，不需要factory注册。

### 5.3 结构检查

Driver可以在入队前检查防止数组越界所必需的结构条件，例如：

- 写请求的`wdata/wstrb/wbeat_gap`长度是否等于`len+1`。
- 读请求的写数组是否为空。
- 读响应的`rdata/rresp`长度是否等于`len+1`，`rbeat_gap`长度是否等于`len`。
- 参数宽度是否与绑定interface一致。

检查失败时Driver报告`UVM_FATAL`或可配置的`UVM_ERROR`并停止该测试；不能自行resize、补数据、修改`len`或重新randomize。地址、WSTRB、4KB等协议合法性仍由transaction约束和assertion负责，Driver不重复实现协议检查函数。

## 6. Master Driver设计

### 6.1 总体线程与队列

一个`axi_m_driver`建议包含以下长期线程：

```text
request intake/admission
    ├── read_pending_q  ──> AR worker ──> read outstanding context
    └── write_pending_q ──┬─> AW worker ──> write outstanding context
                         └─> W scheduler/worker

BREADY policy worker  ───────────────┐
RREADY policy worker  ───────────────┤
B response collector  <──────────────┤ DUT
R response collector  <──────────────┘

reset supervisor / timeout watchdog
```

每个线程只能驱动自己负责的信号，禁止两个线程同时写同一个VALID、READY或payload。

多个通道可以在同一个时钟沿同时握手。所有worker应先形成该边沿的握手采样结果，再通过单一状态更新阶段或受保护的方法提交context、credit和per-ID队列变化，不能依赖SystemVerilog并行线程的执行先后。例如AR握手与首个R beat握手、最后W beat与B握手出现在同一边沿时，也必须得到确定结果。可使用中央cycle coordinator、mailbox或semaphore实现，但接口驱动仍由各通道worker独占。

### 6.2 请求分发和issue credit

请求按`dir`分流：

- `AXI_READ`进入读pending队列，仅由AR worker处理。
- `AXI_WRITE`进入写pending队列，同一个context同时供AW worker和W scheduler引用。

每个Master最多允许4笔读和4笔写outstanding。推荐Driver实现独立的read/write issue credit：

- read context获得credit后才进入AR发送域，credit在最后一个R beat握手时释放。
- write context获得credit后才同时进入AW/W发送域，credit在B握手时释放。
- 使用“进入发送域即占credit”的保守模型，使W可以合法地先于AW发送，同时不会无界发送尚无AW容量的写数据。
- pending队列可以缓存尚未获得credit的请求，但必须有配置上限。

Driver的credit用于限制激励规模和防止自身过量发包；monitor/outstanding tracker仍根据真实AW/AR/B/RLAST握手独立检查DUT的实际outstanding。

### 6.3 AW worker

对每个写context：

1. context获得write credit后启动`addr_delay`倒计时。
2. 倒计时只表示最小等待周期；前一笔AW stall、reset或调度冲突可以增加实际延迟。
3. 倒计时结束后驱动：

```text
AWID    = req.id
AWADDR  = req.addr
AWLEN   = req.len
AWSIZE  = req.size
AWBURST = req.burst
AWVALID = 1
```

4. AWVALID不得等待AWREADY才拉高。
5. `AWVALID && !AWREADY`期间所有AW输出保持不变。
6. 在`AWVALID && AWREADY`握手边沿记录AW完成；下一周期才能撤销VALID或切换下一笔payload。
7. AW通道按Driver接收顺序发送，不在Driver内因地址或ID重排。

AW完成不要求W已经开始或完成。

### 6.4 AR worker

AR worker与AW规则相同，使用`addr_delay`并驱动：

```text
ARID    = req.id
ARADDR  = req.addr
ARLEN   = req.len
ARSIZE  = req.size
ARBURST = req.burst
ARVALID = 1
```

ARVALID及payload在stall期间必须稳定。AR握手后，将context按ID登记到读响应匹配队列；同ID使用FIFO，不同ID分别维护。

### 6.5 W scheduler/worker

写数据由请求快照派生：

```text
WID    = req.id
WDATA  = req.wdata[beat_index]
WSTRB  = req.wstrb[beat_index]
WLAST  = (beat_index == req.len)
```

禁止重新计算或改写`WDATA/WSTRB`，禁止随机化WID/WLAST。

W发送规则：

- `w_start_delay`从write context获得credit时开始计数，与AW的`addr_delay`独立。
- 每个beat在自己的gap满足后才可成为eligible。
- 一旦某个beat拉高WVALID，在该beat完成握手前不能切换到另一个WID或改变payload。
- beat握手后更新该context的beat索引；最后一拍握手后标记W完成。
- W可以早于AW、晚于AW或与AW并行。
- W完成不释放write credit，write credit只在B握手后释放。

为支持AXI3写数据交织，目标W scheduler按beat调度，而不是整burst串行锁定：

- 每个已获得credit的write context保存独立beat索引和next-eligible-cycle。
- 每次W通道空闲时，在eligible context中选择一个beat。
- 推荐不同WID之间使用round-robin；相同WID保持请求/beat顺序，不允许后一个同ID burst越过前一个同ID burst。
- 选中一个beat后锁定该选择直到握手，READY低时不能重新仲裁。
- 首版可通过配置关闭交织并按整burst FIFO发送，但完整Driver必须支持按beat交织。

### 6.6 BREADY和RREADY

BREADY、RREADY不属于`axi_req_item`，由Master agent配置的backpressure策略独立控制。至少支持：

| 策略 | 行为 |
|---|---|
| `ALWAYS_READY` | reset结束后持续为1，用于smoke和基础功能测试 |
| `RANDOM_READY` | 按配置的高/低周期或概率产生背压 |
| `SCRIPTED_READY` | 由配置/策略对象提供确定性高低窗口，用于定向测试 |

READY策略要求：

- reset期间为0。
- 在时钟边沿更新，不对VALID形成零延迟组合依赖。
- BREADY和RREADY分别配置，互不阻塞。
- 策略只能控制本端口，不能读取其他Master/Slave状态决定READY。
- Driver不得为了“尽快完成事务”而越过已配置的backpressure策略。

### 6.7 B响应收集

在`BVALID && BREADY`时：

- 根据BID匹配该ID最早的write context。
- 检查该context的AW和全部W beat应已经握手；异常只作Driver诊断，正式协议判定由assertion/tracker完成。
- 记录`BRESP`，释放write credit并删除匹配context。
- 如果开启sequence响应返回，创建新的`rsp_t`，设置`dir=AXI_WRITE`、`id=BID`、`bresp=BRESP`，并用保存的原请求UVM标识执行`set_id_info()`。
- 不能修改原`axi_req_item`来填写响应。

### 6.8 R响应收集

在每个`RVALID && RREADY`边沿：

- 根据RID选择该ID最早的read context。
- 把当前RDATA/RRESP追加到Driver内部响应构造对象。
- 根据原请求`len`检查beat计数和RLAST位置，仅作诊断。
- 只有最后一个R beat握手后才释放read credit。
- 如果开启sequence响应返回，在完整burst结束时返回新的`rsp_t`，并通过`set_id_info()`关联原请求。

不同RID可交织到达，因此不能使用单一“当前读事务”变量；必须维护per-ID context及beat计数。同RID按最早请求匹配。

sequence响应返回线程必须与接口采样解耦，不能因sequence未调用`get_response()`而阻塞B/R握手收集和credit释放。

## 7. Slave Driver设计

### 7.1 reactive数据流

Slave侧推荐数据流为：

```text
Slave monitor观察AW/W/AR真实握手并重建请求
             ↓
reactive Slave sequence取得已接收请求
             ↓
复制dir/id/len并随机化axi_rsp_item
             ↓
axi_s_driver clone并缓存响应计划
             ↓
B/R worker在接口上驱动响应
```

Slave Driver不自行猜测请求、不读取Master sequence意图，也不内建地址译码。默认OKAY响应、错误注入或memory data均由reactive sequence/response model生成后写入`axi_rsp_item`。

### 7.2 总体线程与队列

一个`axi_s_driver`建议包含：

```text
response intake
    ├── write_rsp_q/per-ID queues ──> B scheduler/worker
    └── read_rsp_q/per-ID queues  ──> R scheduler/worker

AWREADY policy worker
WREADY policy worker
ARREADY policy worker
reset supervisor / timeout watchdog
```

AWREADY、WREADY、ARREADY和B/R发送相互独立。某个请求通道持续背压不能无条件阻塞其他请求或响应通道。

### 7.3 AWREADY/WREADY/ARREADY

三个请求READY分别配置，至少支持`ALWAYS_READY`、`RANDOM_READY`和`SCRIPTED_READY`。

要求：

- reset期间全部为0。
- READY可在VALID之前拉高。
- READY策略在时钟边沿更新，不形成对VALID的组合依赖。
- WREADY不依赖“已经看见对应AW”才允许拉高，以覆盖AXI3 W先于AW场景。
- 三个READY策略可使用不同随机种子和参数，形成独立通道背压。

Slave Driver无需根据AW/W/AR握手直接生成响应；请求重建和合法关联由Slave monitor及reactive sequence完成。

READY随机策略还需要服从响应系统的容量门限。单个下游Slave可能汇聚三个Master的请求，理论上可同时面对最多12笔读和12笔写outstanding。首版可以使用足够深的monitor/reactive sequence/Driver队列；压力测试阶段应由Slave agent中的response manager向READY policy提供`capacity_available`状态，在容量不足时施加背压。该容量保护只防止验证环境队列溢出，不决定响应payload或DUT expected。

### 7.4 B scheduler/worker

写响应item驱动：

```text
BID    = rsp.id
BRESP  = rsp.bresp
BVALID = 1
```

规则：

- `rsp_delay`从响应context成功入队或获得发送资格时开始计数，最终语义需按第13节确认。
- BVALID不得等待BREADY才拉高。
- `BVALID && !BREADY`期间BID/BRESP/BVALID保持稳定。
- 握手完成后下一周期才可撤销VALID或切换payload。
- 相同ID按响应item进入Driver的顺序发送。
- 不同ID可以依据delay和配置的调度策略乱序发送。
- Driver必须原样驱动下游8-bit扩展ID，不能截断或自行重新编码。

reactive sequence必须保证写响应只为已经完整接收AW和全部W beat的请求创建。Slave Driver可以做一致性诊断，但不应重复维护一套权威请求模型。

### 7.5 R scheduler/worker

每个读响应beat驱动：

```text
RID    = rsp.id
RDATA  = rsp.rdata[beat_index]
RRESP  = rsp.rresp[beat_index]
RLAST  = (beat_index == rsp.len)
RVALID = 1
```

规则：

- `rsp_delay`控制第一个R beat开始前的等待。
- `rbeat_gap[i]`控制第`i`拍握手后到第`i+1`拍首次拉高RVALID前的空闲周期。
- `RVALID && !RREADY`期间RID/RDATA/RRESP/RLAST保持稳定。
- 不同RID可按beat交织；相同RID保持事务和beat顺序。
- scheduler只能在上一beat完成握手后重新选择RID。
- 选中beat在stall期间不能被另一个RID抢占。
- Driver从`len`派生RLAST，不能随机化或信任外部单独提供的LAST。

### 7.6 Slave响应顺序契约

`axi_rsp_item`只有`dir/id/len`，不包含请求唯一序号。仅依靠该对象时：

- Driver能够保证同一ID按“响应item到达Driver的顺序”发送。
- Driver不能证明该顺序一定等于真实请求接受顺序。
- 因此reactive sequence/response manager必须按请求接受顺序提交同ID响应。
- 不同ID的选择和乱序由reactive sequence及Driver scheduler共同形成。

若后续需要Driver独立验证关联，可在内部TLM路径传递请求context或增加非随机关联元数据，但不得把DUT路由expected逻辑塞入Driver。

## 8. Delay和gap的统一语义

所有delay/gap均按完整时钟周期计数，并只控制VALID首次拉高前的空闲周期：

| 字段 | 建议起点 | 建议语义 |
|---|---|---|
| `req.addr_delay` | 请求获得对应read/write issue credit | AW或AR首次拉高VALID前等待N个可运行周期 |
| `req.w_start_delay` | write context获得issue credit | 第一拍W具备启动资格前等待N周期 |
| `req.wbeat_gap[i]` | W beat `i`成为当前待发beat时 | 第`i`拍W首次拉高VALID前再等待N周期 |
| `rsp.rsp_delay` | 响应context被Driver接纳 | B或第一拍R首次拉高VALID前等待N周期 |
| `rsp.rbeat_gap[i]` | 第`i`拍R完成握手 | 第`i+1`拍R首次拉高VALID前等待N个空闲周期 |

统一约定：

- `delay=0`允许在下一个可驱动周期立即拉高VALID，不表示在item进入Driver的同一个已采样边沿完成握手。
- stall周期不计入新的delay；VALID已经拉高后只等待READY。
- 通道被其他事务占用、credit不足或scheduler未选中会增加实际延迟，因此这些字段表示最小等待而不是绝对到达周期。
- reset有效周期不计入delay，reset后是否重新计数见第9节。

第一拍W同时存在`w_start_delay`和`wbeat_gap[0]`。本草案建议二者相加，使前者描述burst级起始偏移、后者描述统一的per-beat gap；该语义列为待确认项。

## 9. Reset设计

### 9.1 接口行为

`ARESETn`低有效。Driver必须支持空闲reset和存在未完成事务时reset：

- reset断言后尽快把所有主动VALID拉低。
- Master Driver把BREADY/RREADY拉低。
- Slave Driver把AWREADY/WREADY/ARREADY拉低。
- 主动驱动payload清零。
- reset期间不从sequencer接收新item，不启动delay计数，不产生B/R响应。
- reset释放后至少等待一个clocking event，再按配置恢复READY和接受新item。

### 9.2 内部状态

推荐把reset定义为新的transaction epoch：

- 清空Master pending、AW、W、AR、B/R匹配和可选sequence响应队列。
- 清空Slave待发B/R及交织调度队列。
- 释放所有Driver内部issue credit。
- 清除当前锁定的VALID beat及delay计数器。
- 对被中止的context输出汇总日志，不能在reset后重放已经部分握手的burst。

选择flush而不选择自动重放的原因是：部分AW/W/AR可能已经被DUT接受，reset后重放可能制造重复请求；同时协议基线要求DUT清除reset前的未完成状态。

入口线程必须保证reset不会留下“已取item但永远不调用`item_done()`”的sequencer死锁。monitor、tracker、scoreboard和reactive sequence也需要使用同一reset epoch清空状态，这属于环境级reset协调，不由Driver单独完成。

当前transaction没有`aborted_by_reset`状态，因此被提前`item_done()`的item无法通过原请求对象报告中止。是否增加独立Driver状态事件或sequence通知机制列为待讨论项。

## 10. 配置对象建议

建议公共READY策略枚举：

```text
AXI_READY_ALWAYS
AXI_READY_RANDOM
AXI_READY_SCRIPTED
```

Master Driver配置至少包含：

| 配置项 | 建议默认值 | 说明 |
|---|---:|---|
| `max_read_outstanding` | 4 | read issue credit上限 |
| `max_write_outstanding` | 4 | write issue credit上限 |
| `request_queue_depth` | 8或更大 | 已clone但尚未获得credit的入口容量 |
| `bready_policy` | ALWAYS | B通道接收背压 |
| `rready_policy` | ALWAYS | R通道接收背压 |
| `enable_w_interleave` | 1 | 是否允许不同WID按beat交织 |
| `enable_seq_response` | 0 | 是否把实际B/R构造成`axi_rsp_item`返回请求sequence |
| `channel_timeout_cycles` | 项目统一值 | VALID stall或请求长期未完成的诊断门限 |

Slave Driver配置至少包含：

| 配置项 | 建议默认值 | 说明 |
|---|---:|---|
| `response_queue_depth_per_dir` | 16或更大 | 每方向已clone待发送响应容量；单Slave最坏可汇聚三个Master的outstanding |
| `awready_policy` | ALWAYS | AW请求背压 |
| `wready_policy` | ALWAYS | W数据背压 |
| `arready_policy` | ALWAYS | AR请求背压 |
| `enable_r_interleave` | 1 | 是否允许不同RID按beat交织 |
| `b_schedule_policy` | FIFO/eligible-RR | 不同ID B选择策略 |
| `r_schedule_policy` | eligible-RR | 不同RID R beat选择策略 |
| `channel_timeout_cycles` | 项目统一值 | 响应stall诊断门限 |

RANDOM策略还需要高电平概率、连续高/低周期范围和独立随机种子。SCRIPTED策略可使用周期窗口队列或独立policy object；不建议把READY数组加入每笔请求/响应item。

## 11. 错误处理、日志和超时

### 11.1 报告级别

建议分类：

- `UVM_FATAL`：virtual interface缺失、参数宽度不匹配、动态数组尺寸导致无法安全驱动、内部队列或context状态损坏。
- `UVM_ERROR`：未知BID/RID响应、LAST位置错误、响应早于所需请求阶段、同一context重复完成。
- `UVM_WARNING`：reset中止若干已接纳item、配置被合理裁剪、可选响应队列未被sequence消费。
- `UVM_INFO`：item接纳、各通道握手和credit变化，默认使用中高verbosity，避免回归日志爆量。

协议错误的最终归属仍由assertion、tracker和scoreboard判断。Driver诊断不能通过修改接口行为来“恢复”DUT。

### 11.2 超时

Driver超时只负责定位，例如：

- AW/W/AR VALID连续等待READY过久。
- B/R响应超过配置周期未返回。
- Slave B/R VALID连续等待READY过久。

超时后默认报告错误但不强制拉低VALID、不跳过当前beat。是否由test全局watchdog终止仿真，由test配置决定。

### 11.3 不设置Driver analysis port

首版Driver不提供通向scoreboard或coverage的analysis port。若需要调试统计，可提供独立的Driver状态事件，但必须明确标记为“内部意图/状态”，不能与monitor的真实握手事件混用。

## 12. 建议的分阶段实现顺序

为便于定位问题，建议按以下阶段实现，但最终接口和context设计一次到位：

1. 实现单端口interface、clocking block和reset空闲驱动。
2. 实现Master intake、单拍AW/W/AR及ALWAYS BREADY/RREADY。
3. 扩展1～16 beat写burst、独立AW/W时序和动态数组检查。
4. 实现Master read/write issue credit和多outstanding。
5. 实现Master不同WID按beat交织及B/R内部匹配。
6. 实现Slave三个READY策略和单笔OKAY B/R响应。
7. 扩展Slave多响应调度、不同ID乱序和不同RID交织。
8. 加入随机/脚本backpressure、reset中止和超时诊断。
9. 按需要开启Master response-to-sequence路径。

阶段性关闭交织只能用于bring-up，不改变最终Driver需要覆盖AXI3交织的目标。

## 13. 编码前需要讨论并确认的细节

以下问题不会改变请求/响应分离的transaction基线，但会影响Driver实现方式。

### D1：`item_done()`时机

推荐：clone并成功进入有界内部队列后立即`item_done()`。

备选：等AW/AR或全部请求通道握手后再`item_done()`。该方案会限制sequencer并发，难以自然形成4笔outstanding，不推荐。

需要确认：是否接受推荐方案，以及入口队列默认深度。

### D2：Master sequence是否需要收到实际响应

推荐首版：`enable_seq_response=0`，monitor/tracker/scoreboard作为功能检查主路径；Driver仍收集B/R以释放credit。

需要sequence等待具体响应时，可开启`axi_rsp_item`返回，并用`set_id_info()`路由到原sequence。必须设置足够的response queue深度或专门dispatcher，不能让未消费response阻塞接口线程。

需要确认：基础sequence采用“发送后即完成”，还是需要`get_response()`语义。

### D3：第一拍W的delay组合

当前字段同时有`w_start_delay`和`wbeat_gap[0]`。

推荐：第一拍实际最小等待为二者之和；后续beat只使用对应`wbeat_gap[i]`。

备选：规定`wbeat_gap[0]`恒为0，第一拍只使用`w_start_delay`。若采用此方案，建议同步修改transaction约束和文档，消除冗余随机量。

### D4：delay起算点

推荐：请求delay从获得issue credit时起算，响应delay从Driver接纳响应item时起算。

备选：全部从item进入入口队列时起算。该方案在队列拥塞时会使delay在获得通道前已经耗尽，降低时序意图的可预测性。

### D5：是否由Master Driver强制4读+4写上限

推荐：使用issue credit主动节流，sequence仍可提前排队；真实协议计数由tracker独立检查。

备选：Driver完全信任sequence不超过上限。该方案容易因多个virtual sequence组合而意外过量发包。

### D6：首版是否立即实现W/R交织

推荐：内部context和scheduler从一开始支持per-beat状态，bring-up时可用配置关闭交织。这样无需从整burst阻塞式代码重构。

需要确认：首个可运行里程碑只验证非交织，还是同时完成交织调度。

### D7：不同ID的Slave响应调度策略

可选策略包括响应item到达顺序、最早eligible优先、不同ID round-robin和sequence显式排序。

推荐：sequence决定宏观响应顺序，Driver在所有已到达且delay满足的per-ID队首之间使用round-robin；同ID永远FIFO。

### D8：READY随机策略的表达方式

推荐：独立policy object，支持always、概率随机和脚本窗口，三个Slave请求READY及两个Master响应READY分别实例化。

简化方案：配置对象直接保存`ready_high_pct`和连续低周期范围。简化方案适合首版，但后续定向背压可能需要重构。

### D9：reset中止通知

推荐接口行为是flush而不重放。尚需确认如何通知已经提前`item_done()`的sequence：

- 只记录Driver reset统计，由test/virtual sequence统一停止并重启流量。
- 发布独立abort状态事件。
- 对开启response-to-sequence的请求返回专用abort响应；这会要求扩展当前响应模型。

在决定前，不建议向`axi_req_item`添加可变完成状态。

### D10：超时严重级别和终止责任

推荐Driver报告`UVM_ERROR`并保持当前协议输出，test全局watchdog决定是否结束仿真。

需要确认正常回归、负向测试和reset测试是否使用不同timeout/severity配置。

### D11：Slave请求接收与响应容量如何协调

推荐：每方向至少容纳12笔待响应事务并留有余量，默认队列深度取16；由Slave agent response manager提供容量状态，READY policy在随机结果之外叠加容量门控。

简化方案：首版使用足够深或不设上限的TLM FIFO，READY只按测试策略变化。该方案便于bring-up，但stress阶段必须增加水位控制和队列上限，避免验证环境自身无界增长。

## 14. Driver验收标准

### 14.1 Master Driver

1. 每个实例只驱动一个上游Master端口。
2. 请求item在提前`item_done()`前已被独立clone，原对象后续修改不影响接口。
3. AW、W、AR可以并行运行，AW/W先后关系由delay决定。
4. 所有VALID均不依赖READY才产生，所有stall payload保持稳定。
5. 1～16 beat写burst的WID、WDATA、WSTRB、WLAST与item一致。
6. 每Master能够形成最多4读和4写outstanding，读写credit互相独立。
7. 不同WID写数据能够交织，同WID保持顺序。
8. BREADY/RREADY可独立产生持续和随机背压。
9. B/R收集支持不同ID乱序和R beat交织，不使用全局FIFO匹配。
10. reset中断任意通道后接口回到空闲，reset前事务不被自动重放。

### 14.2 Slave Driver

1. 每个实例只驱动一个下游Slave端口，并使用8-bit扩展ID。
2. AWREADY/WREADY/ARREADY能够独立持续或随机背压。
3. WREADY不以先接收AW为前提。
4. B/R VALID不依赖READY，stall期间payload稳定。
5. BID/RID原样取自响应item，RLAST只由`len`和beat index派生。
6. 不同ID响应可乱序，不同RID读数据可按beat交织，同ID保持FIFO。
7. Driver不自行生成memory数据或响应码，不修改response item。
8. reset期间不输出有效响应，并清除reset前待发队列。

### 14.3 环境级检查

- Driver不向scoreboard/coverage发布功能actual。
- monitor可观察到的每次握手与Driver协议行为一致，但monitor结果不依赖Driver内部context。
- protocol assertions覆盖VALID稳定、LAST计数、响应依赖和reset行为。
- backpressure、outstanding、乱序和交织测试无Driver死锁或sequencer握手遗留。

## 15. 当前结论

基于现有`axi_req_item`和`axi_rsp_item`，无需新增驱动型sequence item即可实现完整Master/Slave Driver。推荐的核心结构是：

- 一个agent/Driver对应一个物理端口。
- transaction clone后进入有界内部context队列并提前`item_done()`。
- AW、W、AR、READY控制和B/R收集使用独立线程。
- W和R从一开始采用可配置的per-beat scheduler结构。
- Driver内部credit负责激励节流，monitor/tracker负责真实功能判定。
- reset flush所有Driver内部状态，不重放部分握手事务。

第13节决策确认后，可以继续编写单端口AXI interface、Driver配置对象和`axi_m_driver/axi_s_driver`代码。

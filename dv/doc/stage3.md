# AXI3 Interconnect UVM验证环境Stage 3执行工单

> 状态：待实施、待审核
> 前置条件：Stage 2已经冻结，当前M0到S0单端口环境支持1～16拍burst、delay/gap、五通道backpressure、AW/W独立推进、读写并行、完整Monitor重建、协议断言和Stage 2端到端检查  
> 代码风格：本阶段所有新增和修改代码必须遵守`dv/doc/code_style.md`  
> 工单格式：本文遵守`dv/doc/task_work_order_standard.md`

## 1. 文档目的和阶段概述

### 1.1 Stage 2已经冻结的能力

Stage 2已经完成并冻结以下基线能力：

- 验证拓扑保持为一个Master agent、一个Slave agent以及真实DUT的M0到S0闭环。
- Master Driver支持AW、W、AR独立发送，Slave Driver支持B、R独立发送。
- 支持FIXED、INCR和WRAP burst，W/R burst长度为1～16拍。
- 支持`addr_delay`、`w_start_delay`、`wbeat_gap[]`、`rsp_delay`和`rbeat_gap[]`。
- AWREADY、WREADY、ARREADY、BREADY和RREADY分别由独立`latency_gen`控制。
- 支持AW先于W、W先于AW、完整W burst先于AW以及读写并行。
- Master/Slave Monitor能够发布逐通道`axi_channel_event`并重建完整request/response。
- `stage2_e2e_checker`能够比较M0到S0的逐拍转发、完整burst、ID扩展和响应恢复。
- `axi_protocol_assertions`能够检查stall稳定性、握手payload、LAST、beat数量和基础因果关系。
- Stage 2保持每个方向最多一笔未完成事务，Master Driver仍使用单一`write_busy/read_busy`上下文。

Stage 3不得破坏上述功能。所有Stage 1和Stage 2正向用例必须继续作为Stage 3回归内容。

### 1.2 Stage 3要完成的能力

Stage 3在Stage 2能力基础上增加事务级多outstanding和响应乱序：

- Master Driver支持读方向和写方向分别最多4笔在途事务。
- 读写方向使用独立准入资源，一个方向达到上限不得阻塞另一个方向。
- Driver使用稳定快照和事务上下文保存异步状态，不依赖sequence原始对象。
- Master Driver按照BID/RID把响应关联到正确请求。
- 相同ID的请求按照接受顺序关联，相同ID响应不得乱序。
- 不同ID的B响应允许乱序返回。
- 不同ID的完整R burst允许乱序返回。
- Slave响应路径能够保存多个尚未发送的响应计划，并按定向脚本或随机策略选择不同ID。
- Master/Slave Monitor按照方向和ID维护多笔请求、响应和burst重建上下文。
- 建立独立outstanding tracker，对真实握手进行计数、上限检查、最大深度记录和结束检查。
- 建立`stage3_e2e_checker`，按照端口、方向、ID和同ID序号完成端到端匹配。
- 协议断言从单事务状态扩展为多ID状态，不再把第二笔AW/AR自动判为错误。

### 1.3 Stage 3A和Stage 3B划分

Stage 3分为两个连续验收阶段，但两阶段从一开始使用同一套最终架构：

1. **Stage 3A：多Outstanding和按ID上下文。** 完成credit准入、读写独立pending队列、按ID FIFO、Monitor多上下文、tracker、Checker和有序响应测试。Stage 3A的Slave响应仍按照请求接受顺序返回，用于先验证容量、释放和同ID顺序。
2. **Stage 3B：不同ID响应乱序。** 在Stage 3A的按ID架构上增加Slave响应调度、B/R不同ID乱序、乱序叠加backpressure、读写同时乱序和随机响应顺序测试。

Stage 3A不是全局FIFO临时实现。Driver、Monitor、Tracker和Checker在Stage 3A就必须使用按ID FIFO；Stage 3B只增加响应选择策略和对应验收，不重写Stage 3A的上下文模型。

### 1.4 Stage 3能力边界

本阶段保持以下边界：

- 继续只验证M0到S0，不扩展三主三从、跨端口仲裁或Default Slave。
- 读方向最多4笔，写方向最多4笔；读写可以同时达到4笔，即最多4+4个未完成事务。
- 支持相同ID多笔事务；同ID严格按照请求接受顺序完成。
- 不同ID允许响应乱序，但不允许同一R burst内部切换RID。
- 不支持不同WID写数据按beat交织，也不支持不同RID读数据按beat交织；beat级交织留到Stage 4。
- 同一W burst和同一R burst继续保持各自beat顺序。
- 继续支持Stage 2的全部burst、delay/gap和READY backpressure能力。
- 只验证启动reset，不验证存在outstanding、队列非空或响应乱序期间的运行时reset；复杂reset留到Stage 5。
- 不建立三主三从最终Reference Model或系统级Scoreboard；本阶段tracker和Checker只面向M0到S0。
- Stage 3继续保留`S0-OPEN-01`：Master Driver不向Master sequence返回独立`axi_rsp_item`。响应关联在Driver内部执行，正确性由Monitor、Tracker和Checker从真实接口独立确认。
- M0到S0写路径继续受`S1-LIMIT-01`约束。不同写ID定向测试只使用`4'h4`、`4'h5`、`4'h6`和`4'h7`，保证`WID[3:2]==2'b01`并路由到S0。
- 对应下游扩展ID固定为`8'h54`、`8'h55`、`8'h56`和`8'h57`。
- Stage 3正向Slave响应由真实Slave Monitor重建的完整请求产生，因此B响应在正向用例中晚于AW和完整W请求重建。AXI3中基于最后一个W beat的B因果断言语义继续保留，不在断言中错误增加AXI4式AW强依赖。

# 第一部分：Stage 3需要完成的任务

## 2. S3-01：冻结Outstanding定义和计数模型

### 2.1 两类计数不得混用

Stage 3同时存在两类计数：

| 计数 | 所有者 | 用途 | 增加/占用时机 | 减少/释放时机 |
|---|---|---|---|---|
| Driver准入槽位 | Master Driver | 限制最多4笔并控制新请求进入通道worker | 请求进入AW/W或AR发送路径之前 | 写事务完成B握手；读事务完成RLAST握手 |
| 接口实际outstanding | Passive Tracker | 根据真实接口证明DUT和环境行为 | AW或AR真实握手 | B或最后一个R beat真实握手 |

Driver准入槽位属于主动流控，不能作为Scoreboard的Expected来源。Tracker实际计数来自Monitor发布的真实`axi_channel_event`，不能读取Driver内部计数或mailbox状态。

### 2.2 写方向协议计数

在本阶段正向闭环中：

```text
AWVALID && AWREADY                    -> actual_write_outstanding + 1
BVALID && BREADY                      -> actual_write_outstanding - 1
```

要求：

- W握手和WLAST不增加实际写outstanding计数。
- B握手必须关联一个相同ID的未完成写上下文。
- 相同BID始终关联该ID最早未完成的写事务。
- 计数不得小于0或超过配置上限。
- Driver准入槽位在AW/W两个worker开始前预留，因此即使W先于AW也不会绕过容量限制。
- Driver只有在该写事务B握手完成后释放准入槽位。

### 2.3 读方向协议计数

```text
ARVALID && ARREADY                    -> actual_read_outstanding + 1
RVALID && RREADY && RLAST             -> actual_read_outstanding - 1
```

要求：

- 普通R beat不释放读outstanding。
- 第一拍R使用RID选择该ID最早未完成的读请求。
- Stage 3不允许R beat交织；选中一个读请求后，后续R beat保持相同RID直到RLAST。
- RLAST完成后才从该ID队列弹出请求并释放Driver读槽位。

### 2.4 同周期增加和释放

AW与B、AR与RLAST可以在同一时钟边界分别完成旧事务和新事务的握手。实现不得由两个长期线程无保护地对同一个整数执行`++`和`--`。

统一规则：

- Driver使用credit/semaphore进行容量控制，按ID队列保存关联关系。
- 需要保留可见计数时，所有更新必须通过单一状态管理路径或短临界区锁完成。
- Tracker在一个采样边界先解析旧响应完成，再登记同周期新请求，保证同ID的B/R响应关联到边界前已经存在的队首请求。
- 同周期一增一减时，最终全局计数不变，但两个事务的上下文状态都必须正确更新。
- credit在响应握手后归还；等待中的准入线程可以随后取得credit，但新VALID只能在后续驱动边界生效。

### 2.5 上限配置

`axi_m_agent_cfg`继续使用已有字段：

```text
max_write_outstanding
max_read_outstanding
```

本阶段规则：

- 合法范围为1～4。
- Stage 1/2测试保持默认值1。
- Stage 3测试在run phase开始前设置为4，或按定向容量用例设置为1、2、3、4。
- Driver build阶段拒绝0或大于4的配置。
- 不新增重复的Stage 3专用上限字段。

## 3. S3-02：Master Driver实现独立准入和按ID关联

### 3.1 长期线程结构

Master Driver目标线程结构：

```text
accept_items
admit_write
admit_read
drive_aw
drive_w
drive_ar
receive_b
receive_r
watch_reset
```

信号所有权继续保持Stage 2规则，新增准入线程和状态管理线程不得驱动接口信号。

### 3.2 request接收和pending队列

`accept_items()`只完成：

1. reset释放后调用`get_next_item()`。
2. clone得到Driver拥有的稳定快照。
3. 按`dir`放入`write_pending_queue`或`read_pending_queue`。
4. 调用且只调用一次`item_done()`。

`item_done()`仍表示Driver已经保存request，不表示取得outstanding槽位、接口握手或收到响应。

写方向达到上限时，`admit_write()`等待写credit，但`accept_items()`和`admit_read()`仍可继续推进。读方向达到上限时同理。

Stage 3引入pending准入层后，`dv/doc/code_style.md`第4节中“写快照在`item_done()`前同时进入AW/W队列”的Stage 1/2规则必须同步扩展：Stage 3以“快照在`item_done()`前进入唯一方向pending queue”完成所有权转移，取得credit后再由准入线程同时fan-out到AW/W worker。不得在代码实现和风格文档之间保留互相矛盾的对象所有权规则。

### 3.3 credit准入

Driver分别持有：

```text
write_credit = max_write_outstanding
read_credit  = max_read_outstanding
```

`admit_write()`行为：

1. 从`write_pending_queue`取得快照。
2. 等待并取得一个写credit。
3. 创建独立写上下文并分配单调递增的本地序号。
4. 将上下文加入`write_by_id[id]`队尾。
5. 把同一个只读上下文句柄分别放入AW和W worker mailbox。

`admit_read()`行为：

1. 从`read_pending_queue`取得快照。
2. 等待并取得一个读credit。
3. 创建独立读上下文并分配本地序号。
4. 将上下文加入`read_by_id[id]`队尾。
5. 把上下文放入AR worker mailbox。

上下文中的request快照在事务结束前不得修改。AW/W共享上下文只用于引用同一不可变request和更新明确的握手完成标志，不得分别再次clone成内容可能不一致的事务。

### 3.4 写响应关联

B握手时使用BID索引`write_by_id[BID]`：

- 队列为空表示孤立B响应，报告UVM error。
- 队首是唯一合法关联对象，不允许从同ID队列中间搜索。
- 检查B响应到达前完整W burst已经握手完成。
- 正向Stage 3场景中还应观察到AW已经握手。
- 记录BRESP并把队首弹出。
- 归还一个写credit。

不同BID可以以任意顺序访问各自队首，从而支持不同ID响应乱序。

### 3.5 读响应关联

Stage 3使用一个全局活动R burst上下文，因为本阶段不支持R beat交织：

- 第一个R beat握手时，根据RID取得`read_by_id[RID][0]`并锁定为活动上下文。
- 队列为空表示无请求R响应。
- 后续beat的RID必须与活动上下文ID一致。
- 逐拍检查beat索引和RLAST位置。
- RLAST握手时弹出该ID队首、清除活动上下文并归还一个读credit。
- RLAST之前不得选择另一个RID。

### 3.6 状态并发保护

以下共享状态必须通过单一owner或短临界区锁保护：

- `write_by_id[]`和`read_by_id[]`。
- 准入槽位的可见计数。
- 本地事务序号。
- 活动R上下文。

临界区内不得等待时钟、等待mailbox、等待sequence item或等待接口握手。credit等待在进入状态临界区之前完成。

## 4. S3-03：实现同ID有序和不同ID乱序

### 4.1 顺序规则

Stage 3固定以下顺序规则：

| 场景 | 是否允许 | 关联规则 |
|---|---|---|
| 相同ID的B响应乱序 | 不允许 | 相同BID总是弹出该ID队首 |
| 不同ID的B响应乱序 | 允许 | BID选择对应ID队首 |
| 相同ID的R burst乱序 | 不允许 | 相同RID总是关联该ID最早AR |
| 不同ID的完整R burst乱序 | 允许 | 每个burst开始时RID选择对应ID队首 |
| R beat交织 | 不允许 | 一个burst开始后锁定RID直到RLAST |
| W beat交织 | 不允许 | 一个W burst完整发送后才发送下一burst |

### 4.2 Slave请求保存

Slave reactive路径只能消费Slave Monitor通过`request_fifo`发布的真实完整request。收到请求后：

- 按方向拆分为write pending和read pending。
- 按扩展ID保存为每ID FIFO。
- 为每个请求建立响应计划，包含方向、ID、LEN、数据模式、RESP、delay/gap和本地接受序号。
- 不允许sequence凭空构造没有真实request的B/R响应。

### 4.3 定向响应脚本

Stage 3B sequence允许为B和R分别提供ID顺序脚本，例如：

```text
请求ID顺序：4, 5, 6, 7
B响应顺序：6, 4, 7, 5
R响应顺序：7, 5, 4, 6
```

选择规则：

- 脚本中的ID必须存在对应pending队列。
- 选择相同ID时只能弹出队首。
- 脚本必须覆盖本场景全部计划，不得遗漏或重复消费。
- B和R脚本彼此独立，可以并行推进。
- R选择一个计划后，Slave Driver必须发送完整burst至RLAST。
- 随机场景从当前非空ID集合中随机选择，不通过打乱同ID队列实现乱序。

### 4.4 Slave Driver边界

Slave Driver继续接受完整`axi_rsp_item`快照并分别放入`b_queue`或`r_queue`。乱序选择发生在reactive sequence/响应调度器，不发生在Driver内部：

- `b_queue`按照sequence提交顺序发送B。
- `r_queue`按照sequence提交顺序发送完整R burst。
- B和R worker继续独立并行。
- Driver不得自行改变相同ID顺序。
- Driver不得把一个R response item拆开后与另一个RID交织。

## 5. S3-04：保持Stage 2通道和时序能力

### 5.1 AW/W/AR发送

- 每个worker仍使用FIFO取得已经准入的上下文。
- AW和W引用同一写上下文，但继续独立计算和执行Stage 2时序。
- W worker一次发送完整burst；多个写事务之间不做beat交织。
- AR worker一次发送一个AR请求，可以在先前读响应返回前继续发送其他已准入AR。
- AW worker可以在先前B返回前继续发送其他已准入AW。
- 写credit耗尽时不得装载新的写事务到AW/W worker。
- 读credit耗尽时不得装载新的读事务到AR worker。

### 5.2 B/R READY

- BREADY和RREADY继续使用独立`latency_gen`。
- BREADY backpressure不得阻止AW/W worker发送仍有credit的其他写事务。
- RREADY backpressure不得阻止AR worker发送仍有credit的其他读事务。
- 一个方向的READY stall不得阻止另一个方向使用自己的credit和通道。

### 5.3 burst、delay和gap

Stage 3不改变Stage 2字段语义：

- `addr_delay`按每个AW或AR request独立执行。
- `w_start_delay`和`wbeat_gap[]`按每个写burst执行。
- `rsp_delay`和`rbeat_gap[]`按每个响应计划执行。
- VALID stall期间payload和当前上下文保持稳定。
- 不同事务可以具有不同delay/gap。
- response reorder只能改变完整响应事务的选择顺序，不能改变选中burst内部的gap内容和beat顺序。

### 5.4 读写并行

Stage 3必须支持：

- 写方向4笔在途的同时继续接受和发送读请求。
- 读方向4笔在途的同时继续接受和发送写请求。
- B和R同周期握手。
- AW、W、AR和B/R在允许的不同通道上并行握手。
- 一个方向释放credit后立即允许该方向pending队首继续准入。

# 第二部分：测试点、时序约束和协议检查

## 6. S3-05：冻结准入、计数和释放时序

### 6.1 Driver准入周期语义

- pending request只有取得credit后才能进入AW/W或AR worker mailbox。
- `max_*_outstanding==1`时行为应与Stage 2单事务限制等价。
- 第4个credit被占用后，第5笔同方向request可保存在pending queue，但不能使对应地址VALID进入发送状态。
- B或RLAST握手归还credit后，等待中的准入线程可以继续。
- 新准入事务的VALID最早在其worker后续可发送边界拉高，不允许在归还credit的同一采样边界凭空完成新握手。

### 6.2 Tracker采样顺序

Tracker只消费真实握手event。对于同一`sample_cycle`内多个通道事件：

1. 保存本周期所有输入event，不依赖analysis port调用先后推断协议先后。
2. 先处理B和RLAST对旧上下文的完成。
3. 再处理AW和AR对新上下文的登记。
4. W和普通R beat更新对应burst状态。
5. 计算周期结束后的全局计数和每ID计数。

同周期完成和新建不得造成错误弹出新请求或漏掉旧请求。

### 6.3 达到上限的检查

定向容量测试必须从接口实际握手确认：

- 已经观察到4个AW且尚无对应B，才算写深度达到4。
- 已经观察到4个AR且尚无对应RLAST，才算读深度达到4。
- 只把4个item交给Driver不代表达到4笔实际outstanding。
- 在保持4笔未完成期间观察固定窗口，确认没有第5个AW/AR握手。
- 释放一个响应后确认第5个AW/AR最终完成握手。

## 7. S3-06：多Outstanding功能测试点

### 7.1 深度测试

写和读分别覆盖：

```text
max_outstanding = 1, 2, 3, 4
```

每个深度检查：

- 发出的请求数达到配置上限。
- Tracker最大观察深度等于目标值。
- 当前深度从0逐步达到目标值。
- 响应完成后逐步回到0。
- Driver没有提前释放或重复释放credit。

### 7.2 第5笔阻塞和释放

分别建立写和读场景：

1. 连续发送5笔不同ID或包含重复ID的请求。
2. Slave暂缓第1～4笔响应。
3. 确认只有4个AW/AR完成握手。
4. 保持至少20个周期，确认第5笔没有地址握手。
5. 返回其中一笔B或完整R burst。
6. 确认第5笔随后完成地址握手。
7. 完成全部响应并确认上下文清空。

### 7.3 同ID多事务

同一个ID连续发送4笔，使用不同地址、数据、长度和响应内容：

- AW/AR可以在前一响应完成前连续接受。
- 相同ID的B/R必须按请求接受顺序关联。
- Checker使用同ID队列序号而不是只比较ID。
- B场景使用不同BRESP模式或对应上下文序号证明顺序。
- R场景使用不同数据基址和LEN证明顺序。

### 7.4 快照和对象所有权

定向测试复用或修改sequence侧临时对象后，必须确认已经进入Driver的4个请求仍保持各自原始内容：

- ID、地址、LEN、burst属性不变。
- 每个W beat数据和WSTRB不变。
- delay/gap数组不变。
- `item_done()`每个request只发生一次，且不等待响应。

## 8. S3-07：响应乱序测试点

### 8.1 不同ID B乱序

使用上游ID`4'h4`、`4'h5`、`4'h6`和`4'h7`发出4笔写事务，至少覆盖：

```text
请求顺序：4, 5, 6, 7
响应顺序：7, 6, 5, 4

请求顺序：4, 5, 6, 7
响应顺序：6, 4, 7, 5
```

检查：

- 下游BID使用对应扩展ID。
- 上游BID恢复为原始4-bit ID。
- 每个B只释放对应ID队首上下文。
- 全局返回顺序与请求顺序不同不会报错。
- 同ID队列内部顺序仍保持。

### 8.2 不同ID R burst乱序

使用4个不同ID和可区分的LEN、数据基址：

- AR按照4、5、6、7顺序接受。
- 完整R burst按照7、5、4、6等脚本返回。
- 每个burst内部RID保持不变。
- 每个burst内部beat索引、数据、RRESP和RLAST正确。
- 前一个burst完成RLAST后才允许选择下一个RID。

### 8.3 乱序叠加backpressure

- B乱序时对BREADY施加不同长度stall。
- R乱序时在第一拍、中间拍和最后一拍施加RREADY stall。
- VALID stall期间响应选择结果和payload保持稳定。
- 已经拉高BVALID/RVALID后不得因为另一个ID更优而切换当前响应。
- backpressure只改变握手时间，不改变预定的同ID顺序。

### 8.4 随机响应顺序

随机测试从当前非空ID集合选择下一响应，必须通过实际采样统计确认：

- 至少发生一次不同ID返回顺序反转。
- 至少达到一次写深度4和读深度4。
- 至少出现一次相同ID队列深度大于1。
- B和R均出现非零backpressure。
- 随机测试不能替代7.1～8.3中的定向测试。

## 9. S3-08：协议断言和状态一致性检查

### 9.1 断言部署

继续在`m_if`和`s_if`分别实例化`axi_protocol_assertions`：

- 上游使用4-bit ID。
- 下游使用8-bit扩展ID。
- stall稳定性、X/Z、LAST和beat数量检查继续保留。
- 单一`aw_seen/read_active`状态必须扩展或替换，不能把合法第二笔AW/AR判为outstanding错误。

### 9.2 多事务因果关系

断言至少检查：

- B响应ID存在对应的已完成W burst资格。
- R响应ID存在对应AR请求。
- 相同W burst内WID稳定，Stage 3不允许W beat交织。
- 活动R burst在RLAST前RID稳定，Stage 3不允许R beat交织。
- RLAST只出现在对应LEN的最后一拍。
- WLAST只出现在对应LEN的最后一拍。
- 没有上下文的B/R触发错误。

AXI3 B因果继续以最后一个W beat完成为必要资格，不增加“必须先完成AW握手”的AXI4式断言。正向reactive环境仍等待完整AW/W request后才生成B。

### 9.3 策略上限检查边界

`max_read_outstanding/max_write_outstanding`是验证环境配置策略，不是接口固定协议参数：

- Driver负责不超过配置上限地准入。
- Tracker根据真实握手检查实际深度不超过配置。
- Checker检查请求和响应关联。
- 协议断言不读取Driver内部cfg，也不重复实现动态credit策略。

### 9.4 负向自测

Stage 3断言自测至少覆盖：

- 合法第二笔AW/AR不会误报。
- 没有请求的B/R触发因果错误。
- R burst中途改变RID触发错误。
- W burst中途改变WID触发错误。
- 同一活动burst提前或缺失LAST触发错误。
- 多事务stall期间改变payload触发稳定性错误。
- 预期断言触发与真实自测失败分离。

## 10. S3-09：Reset和异常场景边界

### 10.1 本阶段Reset要求

- 启动reset期间所有主动VALID/READY保持Stage 2复位规则。
- reset释放后credit初始值等于配置上限。
- 所有pending queue、按ID队列、活动R上下文、Tracker计数和最大深度记录从空状态开始。
- 启动reset不得造成sequencer握手永久阻塞。

### 10.2 本阶段不验证的Reset

以下场景不属于Stage 3验收：

- 已占用credit时reset。
- AW与W只有一个完成时reset。
- B/R乱序返回过程中reset。
- 同ID队列非空时reset。
- 准入线程正在等待credit时reset。
- R burst中途reset。

这些场景留到Stage 5统一处理。Stage 3代码不得宣称已经支持复杂运行时reset，也不得用未经测试的自动重放逻辑处理旧事务。

# 第三部分：各组件需要完成的内容

## 11. S3-10：组件修改总览

| 组件 | Stage 2当前能力 | Stage 3目标 | 动作 |
|---|---|---|---|
| `axi_m_agent_cfg` | 上限字段存在但Driver强制为1 | 合法范围1～4 | 修改 |
| `axi_outstanding_context` | 不存在 | 保存稳定request、序号和通道完成状态 | 新增 |
| Master Driver | 单写、单读busy上下文 | pending、credit、按ID FIFO和4+4事务 | 修改 |
| Slave Driver | B/R独立FIFO，逐item发送 | 保持Driver FIFO；接受乱序调度结果 | 小幅修改或保留 |
| Master Monitor | 单AW/W和单AR/R上下文 | 按ID多上下文，W/R burst不交织 | 修改 |
| Slave Monitor | 单AW/W和单AR/R上下文 | 按ID多上下文，真实request持续发布 | 修改 |
| Slave reactive sequence | 收到请求后顺序响应 | 保存计划并按ID脚本/随机选择 | 新增Stage 3 sequence |
| `axi_outstanding_tracker` | 不存在 | 实际握手计数、上限和最大深度 | 新增 |
| `stage2_e2e_checker` | 单读、单写上下文 | 保持冻结供旧回归使用 | 保留 |
| `stage3_e2e_checker` | 不存在 | 按ID和序号比较多事务及乱序响应 | 新增 |
| `axi_protocol_assertions` | 单事务因果状态 | 多ID因果和非交织检查 | 修改 |
| `axi_env` | Stage 1/2 Checker连接 | 增加Tracker和Stage 3 Checker连接 | 修改 |
| Stage 3 sequence/test | 不存在 | 3A/3B定向和随机场景 | 新增 |
| Makefile/filelist/package | Stage 2入口 | 增加Stage 3编译和回归入口 | 修改 |

## 12. S3-11：Outstanding上下文和公共对象

### 12.1 `axi_outstanding_context`

新增参数化上下文对象，建议文件：

```text
dv/env/axi_outstanding_context.sv
```

上下文至少包含：

```text
request快照句柄
local_sequence_number
aw_complete
w_complete
ar_complete
b_complete
r_complete
response_beat_index
```

要求：

- 上下文只保存Driver、Monitor或Tracker自身拥有的clone，不共享跨组件可变对象。
- `local_sequence_number`用于区分相同ID的多笔事务。
- 不把Driver内部credit或semaphore句柄放入transaction。
- 不向`axi_req_item`或`axi_rsp_item`增加只服务Driver调度的内部状态。
- Monitor和Tracker可以使用同一上下文类型，但必须分别创建自己的实例，不能读取Driver上下文。

### 12.2 request和response item

Stage 3原则上不增加协议字段：

- `axi_req_item`已有ID、方向、burst和全部请求payload。
- `axi_rsp_item`已有ID、LEN、响应payload和时序字段。
- response reorder顺序由Stage 3 sequence的计划队列保存，不增加`response_rank`一类总线无关字段。
- 如需要测试专用计划对象，应放在`dv/seq`并保持其不进入Monitor或Checker的actual路径。

### 12.3 ID和索引

- 上游Master按`ID_WIDTH`建立固定大小的每ID队列，索引范围为`0`到`(1<<ID_WIDTH)-1`。
- 下游Slave按8-bit扩展ID建立上下文；当前定向范围只使用`8'h54`～`8'h57`。
- Checker通过`{2'b01, 2'b01, original_id}`完成M0到S0 ID扩展。
- 不使用ID值0作为内部“空”标记；上下文有效性使用队列大小或显式valid字段。

## 13. S3-12：Master Driver

### 13.1 状态替换

删除或停止使用Stage 2单事务状态：

```text
write_busy
read_busy
单一write_id
单一read_id/read_len/read_beat_index
```

替换为：

```text
write_pending_queue
read_pending_queue
write_credit/read_credit
write_by_id[]/read_by_id[]
active_r_context
事务序号
共享状态锁或单一状态owner
```

### 13.2 AW/W fan-out

- 只在写事务取得credit后把同一上下文放入AW和W mailbox。
- AW worker只更新`aw_complete`。
- W worker发送完整burst后更新`w_complete`。
- AW和W谁先完成不影响上下文身份。
- B接收路径只能释放一次上下文和一次credit。

### 13.3 AR和R

- 每个取得读credit的上下文进入AR mailbox。
- AR握手完成后标记`ar_complete`。
- R接收路径按RID取得队首并锁定活动burst。
- RLAST后弹出、归还credit并清除活动上下文。

### 13.4 错误报告

Driver只报告运行必需错误：

- cfg上限非法。
- B/R找不到对应上下文。
- 相同R burst中RID变化。
- RLAST位置与请求LEN不符。
- credit或上下文发生重复释放。

普通payload端到端差异、DUT转发差异和响应顺序合法性由Monitor、Tracker和Checker检查，不在Driver重复实现。

## 14. S3-13：Slave响应保存和调度

### 14.1 Stage 3 reactive sequence

新增Stage 3 reactive/scenario sequence，负责：

- 从`s_sequencer.request_fifo`取得真实完整request。
- clone并按方向、扩展ID保存。
- 根据定向ID脚本或随机非空ID选择请求队首。
- 生成完整`axi_rsp_item`。
- 保持同IDFIFO顺序。
- 分别向Slave Driver提交B或R response item。

### 14.2 B/R并行

响应调度至少包含独立的write response和read response路径：

- write pending不阻塞read response生成。
- read pending不阻塞write response生成。
- 两条路径可以在同一测试中同时工作。
- 两条路径对Slave sequencer的使用不得造成永久仲裁饥饿。

### 14.3 响应计划结束检查

每个Stage 3测试结束时确认：

- 所有收集到的write request都有且只有一个B计划被消费。
- 所有read request都有且只有一个完整R计划被消费。
- 每IDpending队列为空。
- 定向顺序脚本为空。
- 没有为不存在的ID创建响应。

## 15. S3-14：Master/Slave Monitor

### 15.1 共同原则

- 每次真实握手继续发布新的`axi_channel_event`。
- analysis端保存对象时必须clone。
- 同周期多通道事件先采样，再按照确定性状态更新规则处理。
- 不依赖Driver内部准入顺序或sequence计划作为actual。

### 15.2 写request重建

每个Monitor维护：

```text
aw_by_id[id][$]
completed_w_by_id[id][$]
write_wait_b_by_id[id][$]
一个全局活动W burst重建器
```

规则：

- AW握手创建地址上下文并加入对应ID队列。
- Stage 3不允许W交织，因此从第一个W beat到WLAST只维护一个活动W burst。
- 完整W burst按照WID加入对应ID队列。
- 当同ID的AW和完整W都存在时，各弹出队首并重建完整write request。
- 完整request通过`req_ap`发布，同时clone到等待B的该ID队列。
- 多个AW可以在前一B返回前完成。
- W先于AW时先保存完整W burst，等待相同ID的AW。

### 15.3 读request和response重建

- 每个AR握手立即发布完整read request，并把上下文加入`read_wait_r_by_id[id]`。
- 第一拍R根据RID取得对应ID队首并锁定活动R burst。
- 后续beat必须保持RID。
- RLAST时发布完整read response并弹出该ID队首。
- 另一个ID的AR可以在当前R burst完成前已经存在。

### 15.4 B response重建

- B握手根据BID取得`write_wait_b_by_id[BID]`队首。
- 队列为空报告孤立B。
- 发布完整write response后弹出队首。
- 同IDB顺序由队首规则保证，不同ID不要求全局顺序。

### 15.5 同周期处理顺序

Monitor在同一采样周期中不得因为源码`if`语句顺序把旧响应关联到同周期新请求。推荐：

1. 先创建本周期所有channel event并发布。
2. 用周期开始前上下文处理B和R。
3. 处理AW、W和AR的新请求状态。
4. 执行本周期能够完成的AW/W配对。

Checker不得依赖同周期analysis回调的先后顺序判断协议因果。

## 16. S3-15：Sequence、Sequencer、Agent和Cfg

### 16.1 Master请求sequence

Stage 3 sequence需要产生：

- 4个不同ID请求，写ID使用4～7。
- 相同ID连续1～4笔请求。
- 不同LEN、地址、数据基址和delay/gap以区分上下文。
- 连续5笔请求用于容量阻塞测试。
- 读写各4笔并行请求。

sequence不等待Master Driver返回独立response。场景结束由Tracker和Checker的实际匹配计数判定。

### 16.2 Stage 3场景协调

新增`axi_stage3_scenario_sequence`作为公共场景基类，持有Master和Slave sequencer句柄并提供：

```text
send_write/send_read
collect_write_request/collect_read_request
send_next_b_by_id/send_next_r_by_id
serve_b_order/serve_r_order
等待指定实际匹配计数
```

具体场景sequence只配置请求集合、响应ID顺序、数据模式和时序，不复制公共发送实现。

### 16.3 Cfg

- 复用`max_read_outstanding/max_write_outstanding`。
- 不向cfg加入每ID固定数组或测试脚本。
- 响应顺序脚本属于具体sequence对象。
- Stage 3 base test负责在run phase开始前设置Driver上限和READY generator。
- Stage 1/2 base test继续使用上限1。

### 16.4 Agent和Sequencer

- Master sequencer类型不变。
- Slave sequencer继续保留`request_fifo`。
- Agent active/passive职责不变。
- 不增加把Master和Slave永久绑定为一对的新Agent类型。

## 17. S3-16：Outstanding Tracker和Stage 3 Checker

### 17.1 `axi_outstanding_tracker`

Tracker是被动UVM组件，输入为单接口Monitor的`channel_ap`。建议为上游和下游各实例化一个参数化tracker。

Tracker记录：

- 当前写/读实际outstanding总数。
- 每ID写/读outstanding数量。
- 历史最大写/读深度。
- AW、B、AR、R和RLAST计数。
- 每ID接受序号和完成序号。
- 未完成上下文和活动R burst。

Tracker检查：

- 实际深度不超过配置上限。
- 计数不下溢。
- B/R存在对应请求。
- 同ID完成顺序正确。
- Stage 3不发生R beat交织。
- 测试结束所有当前计数和上下文为0。

### 17.2 `stage3_e2e_checker`输入

输入保持六类TLM流：

```text
upstream channel event
downstream channel event
upstream complete request
downstream complete request
upstream complete response
downstream complete response
```

Checker收到对象后clone保存。Stage 3测试禁用Stage 1/2 Checker的单上下文检查，但Stage 1/2测试继续使用各自Checker。

### 17.3 request比较

- AW、W和AR正向转发仍比较上下游真实event。
- write/read完整request按照方向、原始ID、扩展ID和同ID接受序号关联。
- 比较地址、LEN、SIZE、BURST以及完整W数据和WSTRB。
- 不比较delay/gap字段。
- 不使用全局request FIFO强制不同ID同序；如果DUT保持请求顺序可以统计，但响应匹配不能依赖该假设。

### 17.4 response比较

B响应：

- 下游B response按扩展BID进入每IDexpected队列。
- 上游B response按恢复后的BID进入每IDactual队列。
- 比较同ID队首的RESP和ID转换。
- 不同ID队列可以以任意全局顺序完成。

R响应：

- 下游完整R burst按扩展RID进入每IDexpected队列。
- 上游完整R burst按恢复RID进入每IDactual队列。
- 比较LEN、全部RDATA、RRESP和RLAST结果。
- 相同ID按队首比较，不同ID不要求全局FIFO。

### 17.5 Checker不负责的内容

- Driver credit何时取得和归还。
- READY generator产生的精确随机值。
- delay/gap精确周期数。
- VALID stall稳定性和X/Z；这些由断言负责。
- 三主三从路由、跨端口仲裁和Default Slave。
- beat级W/R交织。
- 运行时reset清理。

### 17.6 结束检查

测试结束必须确认：

- 上下游所有channel event比较队列为空。
- 上下游每ID完整request/response队列为空。
- 所有Tracker当前读写计数为0。
- Driver所有credit已经归还。
- Driver pending queue和按ID上下文为空。
- Slave response plan和每IDpending队列为空。
- Slave sequencer `request_fifo`为空。
- 没有活动W/R burst。
- 实际匹配计数等于测试期望事务数。

## 18. S3-17：TLM和文件组织

### 18.1 Stage 3连接关系

```text
Master request sequence
        │ axi_req_item
        ▼
Master sequencer → Master Driver
                       │ clone + pending
                 ┌─────┴─────┐
                 ▼           ▼
             write admit   read admit
              │ credit       │ credit
          ┌───┴───┐          ▼
          ▼       ▼          AR worker
       AW worker W worker
          │       │           │
          └───────┴──── DUT ──┘
                           │
                           ▼
                    Slave Monitor
                           │ complete request
                           ▼
                 Slave request_fifo
                           │
                           ▼
              Stage 3 response scheduler
                    │ B plan   │ R plan
                    ▼          ▼
                 Slave Driver B/R workers

Master Monitor channel/req/rsp ─┬─ stage3_e2e_checker
Slave Monitor  channel/req/rsp ─┘

Master Monitor channel ─ upstream outstanding tracker
Slave Monitor  channel ─ downstream outstanding tracker
```

### 18.2 文件组织

新增文件建议：

```text
dv/env/axi_outstanding_context.sv
dv/env/axi_outstanding_tracker.sv
dv/env/checker/stage3_e2e_checker.sv

dv/seq/axi_stage3_scenario_seq.sv
dv/seq/axi_stage3_outstanding_write_seq.sv
dv/seq/axi_stage3_outstanding_read_seq.sv
dv/seq/axi_stage3_capacity_limit_seq.sv
dv/seq/axi_stage3_same_id_order_seq.sv
dv/seq/axi_stage3_write_reorder_seq.sv
dv/seq/axi_stage3_read_reorder_seq.sv
dv/seq/axi_stage3_read_write_parallel_seq.sv
dv/seq/axi_stage3_random_reorder_smoke_seq.sv

dv/tc/axi_stage3_base_test.sv
dv/tc/axi_stage3_outstanding_write_test.sv
dv/tc/axi_stage3_outstanding_read_test.sv
dv/tc/axi_stage3_capacity_limit_test.sv
dv/tc/axi_stage3_same_id_order_test.sv
dv/tc/axi_stage3_write_reorder_test.sv
dv/tc/axi_stage3_read_reorder_test.sv
dv/tc/axi_stage3_read_write_parallel_test.sv
dv/tc/axi_stage3_random_reorder_smoke_test.sv

dv/tb/axi_stage3_protocol_assertions_selftest.sv
```

### 18.3 需要修改的现有文件

```text
dv/env/master/axi_m_agent_cfg.sv
dv/env/master/axi_m_driver.sv
dv/env/master/axi_m_monitor.sv
dv/env/slave/axi_s_monitor.sv
dv/env/axi_protocol_assertions.sv
dv/env/axi_env.sv
dv/env/axi_env_pkg.sv
dv/seq/axi_seq_pkg.sv
dv/tc/axi_base_test.sv
dv/tc/axi_test_pkg.sv
dv/tb/tb.sv
dv/doc/code_style.md
sim/sim.f
sim/Makefile
```

Slave Driver如现有B/R item FIFO能够正确保持sequence提交顺序且支持B/R并行，可不修改其核心发送逻辑。

### 18.4 实施后的目录增量

```text
dv/
├── env/
│   ├── checker/
│   │   ├── stage1_e2e_checker.sv
│   │   ├── stage2_e2e_checker.sv
│   │   └── stage3_e2e_checker.sv
│   ├── axi_outstanding_context.sv
│   ├── axi_outstanding_tracker.sv
│   └── ... existing components
├── seq/
│   ├── axi_stage3_scenario_seq.sv
│   ├── axi_stage3_outstanding_write_seq.sv
│   ├── axi_stage3_outstanding_read_seq.sv
│   ├── axi_stage3_capacity_limit_seq.sv
│   ├── axi_stage3_same_id_order_seq.sv
│   ├── axi_stage3_write_reorder_seq.sv
│   ├── axi_stage3_read_reorder_seq.sv
│   ├── axi_stage3_read_write_parallel_seq.sv
│   └── axi_stage3_random_reorder_smoke_seq.sv
├── tc/
│   ├── axi_stage3_base_test.sv
│   └── axi_stage3_*_test.sv
└── tb/
    ├── axi_stage3_protocol_assertions_selftest.sv
    └── ... existing tb files
```

### 18.5 编译顺序

- `axi_req_item`之后include `axi_outstanding_context`。
- Driver/Monitor之前include context类型。
- Tracker在`axi_channel_event`之后include。
- `stage3_e2e_checker`在Monitor类型和公共对象之后include。
- `axi_env`在全部Agent、Tracker和Checker之后include。
- Stage 3公共scenario sequence先于具体Stage 3 sequence。
- Stage 3 base test先于具体Stage 3 testcase。
- `sim.f`继续只编译package入口，不重复单独编译被package include的类文件。

# 第四部分：Stage 3验证和验收

## 19. A3-01：Stage 3A代码审核

Stage 3A进入功能测试前必须满足：

- Driver不再使用单一`write_busy/read_busy`限制事务。
- request clone、pending、credit和`item_done()`契约明确。
- `dv/doc/code_style.md`已经同步Stage 3 pending准入和AW/W fan-out契约。
- 读写准入线程互不阻塞。
- 每ID队列从一开始用于Driver、Monitor、Tracker和Checker。
- cfg上限1～4检查完成。
- Monitor能够保存多个AW、AR和等待响应上下文。
- Tracker和`stage3_e2e_checker`加入正确TLM连接。
- 协议断言不再拒绝合法第二笔AW/AR。
- Stage 2 Checker保持可用于旧回归。
- 没有提前实现W/R beat交织、三主三从或复杂reset。

工具门槛：

```text
QuestaSim 10.6c编译0 error
elaboration 0 error
无新增非预期warning
```

## 20. A3-02：Stage 3A Outstanding深度测试

分别对读写执行深度1、2、3、4：

- 请求握手数达到目标深度。
- 最大实际深度等于目标深度。
- 所有响应完成后回到0。
- 每ID和全局计数一致。
- 没有孤立响应、重复释放或遗留credit。
- 深度1继续兼容Stage 2行为。

## 21. A3-03：Stage 3A容量阻塞和释放测试

- 配置上限4并发送5笔写请求，确认第5个AW在credit释放前不能握手。
- 返回一个B后，第5个AW能够继续。
- 配置上限4并发送5笔读请求，确认第5个AR在RLAST前不能握手。
- 返回一个完整R burst后，第5个AR能够继续。
- 写满期间读请求继续工作。
- 读满期间写请求继续工作。
- 同周期响应释放和其他地址握手时计数正确。

## 22. A3-04：Stage 3A同ID顺序测试

- 相同ID连续4笔写，B按请求顺序关联。
- 相同ID连续4笔读，完整R burst按请求顺序关联。
- 使用可区分地址、LEN、数据和响应结果证明不是仅比较ID。
- 同ID队列深度达到4后正确回到0。
- 不允许通过搜索同ID队列中间元素掩盖顺序错误。

Stage 3A全部通过后，才能进入不同ID乱序测试。

## 23. A3-05：Stage 3B不同ID乱序测试

- 4个不同写ID按逆序返回B。
- 4个不同写ID按非简单交错脚本返回B。
- 4个不同读ID按逆序返回完整R burst。
- 4个不同读ID按非简单交错脚本返回完整R burst。
- 上下游ID扩展和恢复正确。
- 不同ID全局返回顺序变化不产生误报。
- 相同ID队列仍严格FIFO。
- R burst内部不发生RID切换。

## 24. A3-06：Stage 3B并行和Backpressure测试

- 写4笔和读4笔同时在途。
- B和R独立选择乱序响应并并行工作。
- BREADY stall期间其他有credit的请求继续推进。
- RREADY stall期间其他地址通道继续推进。
- 已拉高VALID的B/R响应在stall期间不切换ID或payload。
- B和RLAST同周期释放各自credit时计数正确。
- 乱序、delay/gap和READY backpressure组合后全部上下文正确清空。

## 25. A3-07：Stage 3协议断言验收

正向Stage 1、Stage 2和Stage 3回归要求所有常驻协议断言零非预期失败。

独立Stage 3断言自测至少确认：

- 第二笔至第四笔合法AW/AR不会触发单outstanding误报。
- 无上下文B/R能够触发因果断言。
- WID/RID在活动burst中切换能够触发非交织断言。
- 多事务环境中的stall payload变化能够触发稳定性断言。
- WLAST/RLAST提前、缺失和beat过量继续能够触发。
- 自测打印统一`AXI_STAGE3_ASSERT_SELFTEST_PASS`标记。
- 预期触发全部命中且`unexpected_count==0`。

## 26. A3-08：Stage 3端到端测试清单

Stage 3建议建立以下独立testcase：

```text
axi_stage3_outstanding_write_test
axi_stage3_outstanding_read_test
axi_stage3_capacity_limit_test
axi_stage3_same_id_order_test
axi_stage3_write_reorder_test
axi_stage3_read_reorder_test
axi_stage3_read_write_parallel_test
axi_stage3_random_reorder_smoke_test
```

继续回归：

```text
axi_stage1_single_write_test
axi_stage1_single_read_test
axi_stage2_burst_write_test
axi_stage2_burst_read_test
axi_stage2_aw_w_order_test
axi_stage2_delay_gap_test
axi_stage2_channel_stall_test
axi_stage2_read_write_parallel_test
axi_stage2_ready_random_smoke_test
```

每个testcase单独一个文件，只配置本场景的上限、READY策略、场景sequence、期望事务数和覆盖条件。

## 27. A3-09：端到端检查结果

每个Stage 3正向测试必须满足：

- 预期AW/W/B/AR/R握手和完整transaction计数全部匹配。
- Tracker观察到的最大深度达到测试目标且不超过配置上限。
- 上游4-bit ID正确扩展为下游8-bit ID。
- 下游响应ID正确恢复为上游4-bit ID。
- 相同ID按接受顺序完成。
- 不同ID按照测试脚本完成预期乱序。
- 所有W/R beat数据、STRB、RESP和LAST一致。
- 没有额外、重复或遗漏event/transaction。
- Driver credit全部归还，pending和每ID上下文为空。
- Monitor、Tracker和Checker没有未完成上下文。
- Slave request FIFO、响应计划和每IDpending队列为空。
- 常驻协议断言零非预期失败。
- `UVM_WARNING=0`、`UVM_ERROR=0`、`UVM_FATAL=0`。
- 测试打印统一`AXI_TC_PASS`并正常退出。

## 28. A3-10：运行入口和回归要求

沿用当前`sim`目录和QuestaSim入口，增加：

```text
cd sim
make com
make sim test=<testname>
make stage3a_regress
make stage3b_regress
make stage3_regress
make positive_regress
make assertion_selftest
make stage3_assertion_selftest
```

目标定义：

- `stage3a_regress`运行Outstanding深度、容量和同ID顺序测试。
- `stage3b_regress`运行写乱序、读乱序、读写并行和随机乱序测试。
- `stage3_regress`连续运行全部Stage 3正向测试。
- `positive_regress`连续运行Stage 1、Stage 2和Stage 3全部正向测试。
- `stage3_assertion_selftest`只运行Stage 3负向断言支架，不混入正向回归。

Makefile对每个正向测试日志必须检查：

```text
AXI_TC_PASS存在
UVM_WARNING : 0
UVM_ERROR   : 0
UVM_FATAL   : 0
```

断言自测日志必须检查专用PASS标记和`unexpected_count==0`。仿真生成物继续放在：

```text
sim/work/log
sim/work/wave
sim/work/cov
```

不得向`dv`目录写入日志、波形、work library或覆盖率数据库。

## 29. Stage 3完成条件

只有同时满足以下条件，Stage 3才能审核冻结：

1. Stage 3A/3B所有组件代码完成并符合`dv/doc/code_style.md`。
2. Questa编译和elaboration为0 error、0非预期warning。
3. Driver读写独立credit和pending准入正确工作。
4. 写和读实际outstanding深度分别覆盖1～4。
5. 第5笔同方向请求在容量满时被阻塞，并在响应释放后继续。
6. 写满不阻塞读，读满不阻塞写。
7. 相同ID连续多事务严格按照接受顺序完成。
8. 不同ID B响应乱序测试通过。
9. 不同ID完整R burst乱序测试通过。
10. Stage 3范围内没有W/R beat交织。
11. Monitor能够重建所有多事务request/response。
12. Tracker的总数、每ID数、最大深度和结束状态全部正确。
13. `stage3_e2e_checker`的逐拍、完整事务、ID转换和乱序匹配全部通过。
14. 乱序叠加delay/gap和BREADY/RREADY backpressure测试通过。
15. 读写各4笔并行和B/R并行测试通过。
16. 正向回归协议断言零失败，Stage 3负向断言自测通过。
17. Stage 1和Stage 2全部正向回归继续通过。
18. 所有测试结束Driver、Monitor、Tracker、Checker、Slave FIFO和响应计划无pending。
19. 所有正向测试`UVM_WARNING=0`、`UVM_ERROR=0`、`UVM_FATAL=0`。
20. 没有提前实现Stage 4 beat交织、Stage 5复杂reset或Stage 6三主三从能力。

## 30. 审核记录

本节只记录实际实施和运行结果。当前工单尚未实施，不得预填“已通过”。

| 审核项 | 当前状态 | 说明 |
|---|---|---|
| Stage 2基线 | 已冻结 | Stage 3必须持续回归Stage 1/2现有用例 |
| Stage 3范围 | 待实施 | M0到S0，读写分别最多4笔outstanding |
| Stage 3A | 待实施 | credit、按ID上下文、有序响应和容量测试 |
| Stage 3B | 待实施 | 不同ID B/R乱序及组合测试 |
| Master response返回 | 已决策 | 继续保留`S0-OPEN-01`，不向Master sequence返回独立response |
| 写ID范围 | 已决策 | M0到S0定向写使用ID 4～7，对应SID 0x54～0x57 |
| Beat交织 | 后续Stage | W/R beat交织留到Stage 4 |
| 复杂reset | 后续Stage | outstanding期间reset留到Stage 5 |
| 三主三从 | 后续Stage | 完整端口扩展留到Stage 6 |
| 代码与编译 | 未运行 | 实施后填写工具版本和编译结果 |
| Stage 3A回归 | 未运行 | 实施后填写测试列表、结果和日志 |
| Stage 3B回归 | 未运行 | 实施后填写测试列表、结果和日志 |
| 断言自测 | 未运行 | 实施后填写预期命中和unexpected统计 |
| 最终状态 | 未冻结 | 只有第29节全部满足后才能冻结 |

### 30.1 实际运行记录模板

实施后按实际结果填写：

```text
工具版本：
代码版本/提交：
编译命令和结果：
Stage 3A测试列表和结果：
Stage 3B测试列表和结果：
Stage 1/2回归结果：
断言自测结果：
日志路径：
波形路径：
覆盖率路径：
遗留问题：
最终审核结论：
```

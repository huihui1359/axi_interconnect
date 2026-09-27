# AXI3 Interconnect UVM验证环境Stage 6执行工单

> 状态：待实施
>
> 前置条件：`dv/doc/stage3.md`已经实施并通过冻结审核，当前M0到S0环境支持burst、delay/gap、五通道backpressure、读写分别最多4笔outstanding、相同ID保序、不同ID响应乱序、4-bit/8-bit ID映射、完整Monitor重建、Outstanding Tracker、Stage 3 Checker和协议断言。
>
> ID定义：本阶段严格遵守`dv/doc/ID_intro.md`；Default Slave是未映射地址对应的内部路由，不定义Default Master ID。
>
> 代码风格：本阶段所有新增和修改代码必须遵守`dv/doc/code_style.md`。
>
> 工单格式：本工单遵守`dv/doc/task_work_order_standard.md`。
>
> 实施边界：本工单默认只修改`dv`、`sim`和验证文档。发现RTL缺陷时先保留独立失败测试、日志、波形和debug记录，未经审核不得修改`rtl`。

## 1. 文档目的和阶段概述

### 1.1 Stage 3基线

Stage 3已经在M0到S0闭环中完成：

- FIXED、INCR和合法WRAP burst，长度1～16拍。
- AW/W独立推进，支持AW先、W先和读写并行。
- 五通道独立delay、gap和backpressure。
- Master Driver读、写方向分别最多4笔outstanding。
- 基于真实AW、WLAST、B、AR和RLAST握手的按ID状态维护。
- 相同ID多笔事务严格保序，不同ID的B和完整R burst允许乱序。
- Master/Slave Monitor按ID重建完整request和response。
- M0到S0的4-bit Master ID和8-bit Slave SID映射及恢复。
- 无状态Switch映射模型、Outstanding Tracker和Stage 3端到端Checker。
- 正向协议断言、负向断言自测和Stage 1～3正向回归。

当前环境的数据结构已经对agent数量参数化，但TB只例化一套`m_if/s_if`，其余DUT端口保持inactive；环境Checker、Tracker和测试场景仍只连接或启动`m_agents[0]`和`s_agents[0]`。

### 1.2 Stage 6总体目标

Stage 6在保留Stage 3通道能力的前提下，将验证环境扩展为完整三主三从系统级环境：

- 实例化M0、M1、M2三个Master agent。
- 实例化S0、S1、S2三个Slave agent。
- 为六个agent分发独立virtual interface和cfg。
- 建立Virtual Sequencer和Stage 6 Virtual Sequence体系。
- 支持任意Master访问任意正常Slave的9条路由。
- 支持多个Master和多个Slave同时工作。
- 实现TLM连接的系统级Reference Model。
- 实现三主三从System Scoreboard。
- 实现按端口独立的Outstanding Tracker阵列。
- 实现逐通道转发Checker。
- 使用bind实现内部轮询仲裁精确检查。
- 验证ID扩展、恢复、来源Master、目标Slave和物理端口一致性。
- 验证内部Default Slave的DECERR路径。
- 建立Stage 6系统级functional coverage和分层回归。

### 1.3 Stage 6A和Stage 6B划分

Stage 6分为两个连续实施阶段：

1. **Stage 6A：环境和检查组件扩展。** 完成三主三从TB、Env、Cfg、Virtual Sequencer、系统Reference Model、System Scoreboard、Channel Checker、Tracker阵列、Coverage Collector、bind仲裁Checker、package/filelist和编译入口。Stage 6A必须通过代码审核、编译和elaboration。
2. **Stage 6B：系统场景和冻结验收。** 完成路由矩阵、ID矩阵、多端口并行、同Slave竞争、响应竞争、跨Master相同ID、多端口outstanding、Default Slave、随机smoke和负向自测，并运行Stage 1～3兼容回归。

Stage 6A编译通过只表示三主三从结构可以进入测试，不表示路由、仲裁、ID、Default路径或跨端口Scoreboard已经验证正确。

### 1.4 Stage 6冻结决策

本阶段冻结以下决策：

- 环境固定实例化3个Master agent和3个Slave agent。
- Stage 1～3旧测试继续只启动M0和S0，其余端口保持空闲。
- Stage 6新测试统一使用Virtual Sequence和Virtual Sequencer。
- 所有transaction传输使用标准`uvm_analysis_port`和`uvm_tlm_analysis_fifo`连接。
- 不新增自定义`uvm_analysis_imp_decl`作为Stage 6主要通信方式。
- req/rsp对象的来源端口由TLM FIFO数组下标表示，不把端口号编码进AXI ID。
- 系统Reference Model接收DUT输入方向的完整事务，输出expected事务。
- System Scoreboard接收Reference Model的expected事务和DUT输出方向Monitor的actual事务。
- Channel Checker只比较真实握手event的端到端转发，不代替System Scoreboard。
- Outstanding Tracker只根据Monitor event维护接口观察状态，不读取Driver、Reference Model或Scoreboard。
- 轮询仲裁由RTL实施；DV使用独立预测状态和bind Checker检查，不在Driver、sequence或System Scoreboard中替DUT选择winner。
- 轮询指针只在对应winner成功握手后更新；stall期间winner和指针保持稳定。
- Default Slave由未映射AWADDR/ARADDR选择，是合法DECERR路径，不定义Default Master。
- 下游响应SID的source-master tag `[5:4]`只允许`01/10/11`；`00`是非法Master tag。
- 非法Master tag不得被路由到任意Master，不得在正向测试中生成。
- Stage 6继续保留Stage 3的最大每Master、每方向4笔outstanding。
- Stage 6不提前实现Stage 4的W/R beat级交织。
- Stage 6不提前实现Stage 5的完整READY模式、容量门控和运行中复杂reset。
- 默认只允许启动reset；reset释放后再发送事务。
- Stage 6默认不修改RTL。任何RTL例外必须单独审核并记录。

### 1.5 Stage 6能力边界

本阶段实现：

- 三主三从外部物理端口全部启用。
- 9条正常Master到Slave路径。
- 内部Default Slave路径。
- 多Master、多Slave同时读写。
- 每个Master独立outstanding和相同ID顺序。
- 跨Master相同4-bit ID并存。
- 目标Slave竞争和返回Master竞争。
- 地址路由、SID扩展和ID恢复。
- 系统级request/response匹配。
- 通道级event转发匹配。
- 内部轮询仲裁检查。
- Stage 6范围的functional coverage。

本阶段不实现：

- 不同WID之间的W beat交织重建和验证。
- 不同RID之间的R beat交织重建和验证。
- 多拍W/R竞争下的逐beat轮询闭环。
- 完整`ALWAYS_READY/RANDOM_READY/SCRIPTED_READY`模式体系。
- Slave请求/响应缓存的容量门控。
- outstanding期间reset、burst中途reset和reset恢复。
- 后续Stage 4/5能力的最终交叉覆盖率闭环。

# 第一部分：Stage 6需要完成的任务

## 2. S6-01：三主三从TB拓扑

### 2.1 Interface阵列

TB必须例化：

~~~systemverilog
axi_if #(ADDR_WIDTH, DATA_WIDTH, M_ID_WIDTH, LEN_WIDTH) m_if[3](...);
axi_if #(ADDR_WIDTH, DATA_WIDTH, S_ID_WIDTH, LEN_WIDTH) s_if[3](...);
~~~

要求：

- `m_if[0]`、`m_if[1]`、`m_if[2]`分别连接DUT M0、M1、M2。
- `s_if[0]`、`s_if[1]`、`s_if[2]`分别连接DUT S0、S1、S2。
- 不再使用单一`m_if`和`s_if`代表整个系统。
- 不再把索引1、2的DUT端口固定为inactive常量。
- 所有DUT端口只能由对应interface/agent驱动一次。
- 六个interface共享同一个时钟和启动reset。
- TB不得直接产生功能事务；功能激励只能来自Driver。

### 2.2 六个协议断言实例

每个Master interface和每个Slave interface分别例化参数正确的`axi_protocol_assertions`：

~~~text
m_assertions[0..2]：ID_WIDTH=4，TB_IS_MASTER=1
s_assertions[0..2]：ID_WIDTH=8，TB_IS_MASTER=0
~~~

每个断言实例必须带端口索引，错误日志能够明确打印M0/M1/M2或S0/S1/S2。

### 2.3 配置分发

TB必须为六个agent填写：

~~~text
env_cfg.m_cfg[i].port_index = i
env_cfg.m_cfg[i].drv_vif    = m_if[i]
env_cfg.m_cfg[i].mon_vif    = m_if[i]

env_cfg.s_cfg[i].port_index = i
env_cfg.s_cfg[i].drv_vif    = s_if[i]
env_cfg.s_cfg[i].mon_vif    = s_if[i]
~~~

Stage 6正向测试中六个agent均为`UVM_ACTIVE`。未启动sequence的Master Driver保持请求VALID为0；未收到请求的Slave Driver不得凭空产生B/R。

## 3. S6-02：路由、端口和ID定义

### 3.1 正常地址路由

地址映射固定为：

| 地址范围 | 路由 | Slave端口 |
|---|---|---|
| `32'h0000_0000～32'h0000_0FFF` | `AXI_ROUTE_S0` | `s_if[0]` |
| `32'h0000_2000～32'h0000_2FFF` | `AXI_ROUTE_S1` | `s_if[1]` |
| `32'h0000_4000～32'h0000_4FFF` | `AXI_ROUTE_S2` | `s_if[2]` |
| 其他 | `AXI_ROUTE_DEFAULT` | DUT内部Default Slave |

整个burst只按AW/AR地址译码一次。

### 3.2 Master请求ID

正常S0、S1、S2请求继续遵守`ID_intro.md`：

~~~text
M_ID[3:2] = 目标Slave tag
M_ID[1:0] = transaction tag
~~~

| 目标 | 合法Master ID |
|---|---|
| S0 | `4'h4～4'h7` |
| S1 | `4'h8～4'hB` |
| S2 | `4'hC～4'hF` |

AWID、WID和ARID使用完整4-bit ID；同一写事务必须满足AWID等于WID。

### 3.3 Slave SID

正常外部Slave SID格式：

~~~text
[7:6] 实际目标Slave tag
[5:4] 来源Master tag
[3:0] 原始Master ID
~~~

合法source-master tag：

| Master | SID `[5:4]` |
|---|---|
| M0 | `2'b01` |
| M1 | `2'b10` |
| M2 | `2'b11` |

`2'b00`不表示Default Master，而是非法source-master tag。

### 3.4 系统级关联键

上游事务不能只按4-bit ID关联，固定使用：

~~~text
master_key = {master_port, master_id}
~~~

下游正常事务固定使用：

~~~text
slave_key = {slave_port, full_sid}
~~~

M0、M1和M2可以同时使用相同的4-bit ID，三者上下文必须完全独立。

### 3.5 Default Slave

Default Slave规则固定为：

- Default由未映射AWADDR/ARADDR选择。
- Default是DUT内部第四条物理路由，不实例化第四个Slave agent。
- Master侧不存在Default BID/RID编码。
- Default请求仍携带原始4-bit事务ID，AWID和WID仍必须相等；该ID用于事务关联和返回恢复，不用于表示Default路由。
- Default选择只由AWADDR/ARADDR未命中正常地址窗口决定，Reference Model不得把`ID[3:2]`解释成Default编码。
- Default B/R返回原请求的4-bit ID。
- Default写响应必须为`BRESP=DECERR`。
- Default读响应每拍必须为`RRESP=DECERR`。
- Default读数据按照当前项目RTL期望为全1。
- Default R beat数量为`ARLEN+1`，RLAST只在最后一拍。
- Reference Model用请求上下文记录`route=DEFAULT`，不能根据返回Master ID反推Default。
- Default写路径必须作为早期bring-up定向测试；如果失败，按RTL缺陷流程处理，不通过发明Default ID规避。

### 3.6 非法Slave响应

以下响应属于非法输入：

- `SID[5:4]==2'b00`，没有目标Master。
- SID目标Slave字段与实际外部Slave端口不一致。
- SID合法但没有对应pending request。
- SID指向错误Master。
- 同一Master/ID响应越过同ID队首。

对于`SID[5:4]==00`：

- 正向Slave sequence禁止生成。
- 断言在`BVALID/RVALID`出现时立即报告，不等待握手。
- DUT不得把响应路由到任意Master。
- 预期Slave侧READY保持低，不形成合法握手。
- Reference Model报告错误且不产生expected Master response。
- 负向自测在命中预期错误后主动结束注入，不等待正常事务完成。

## 4. S6-03：标准TLM通信约束

### 4.1 允许的端口类型

Stage 6事务通信只使用：

~~~text
uvm_analysis_port
uvm_tlm_analysis_fifo
uvm_tlm_analysis_fifo.analysis_export
~~~

Monitor继续提供：

~~~text
channel_ap
req_ap
rsp_ap
~~~

生产者使用`uvm_analysis_port::write()`广播；需要排队或异步处理的消费者使用独立`uvm_tlm_analysis_fifo`。

### 4.2 禁止事项

- 不为Stage 6新增大量自定义`uvm_analysis_imp_decl`名称。
- 不使用组件之间直接调用私有`write_*()`方法传输transaction。
- 不让Reference Model直接调用Scoreboard内部比较函数。
- 不让Scoreboard读取Monitor、Driver或sequence内部队列。
- 不让多个消费者共享同一个analysis FIFO；每个消费者使用自己的FIFO。
- 不把端口号塞入AXI ID字段。
- 不允许消费者修改Monitor已经发布的对象。

### 4.3 对象所有权

- Monitor每次发布新对象，发布后不得修改。
- Reference Model从FIFO取出对象后先clone，再生成expected对象。
- Scoreboard从FIFO取出对象后先clone，再存入按键队列。
- Channel Checker和Coverage Collector需要长期保存对象时也必须clone。
- analysis port允许连接多个analysis export，实现Tracker、Checker和Coverage并行订阅。

## 5. S6-04：Virtual Sequencer和Virtual Sequence

### 5.1 Virtual Sequencer

新增`axi_virtual_sequencer`，只保存六个真实sequencer句柄：

~~~systemverilog
axi_m_sequencer m_seqr[3];
axi_s_sequencer s_seqr[3];
~~~

Virtual Sequencer：

- 不连接Driver。
- 不持有virtual interface。
- 不接收AXI transaction。
- 不决定仲裁winner。
- 不读取Checker状态。

`axi_env.connect_phase()`通过普通句柄赋值连接：

~~~text
vseqr.m_seqr[i] = m_agents[i].sequencer
vseqr.s_seqr[i] = s_agents[i].sequencer
~~~

### 5.2 Stage 6 Virtual Sequence

Stage 6新增基类`axi_stage6_base_vseq`，通过`p_sequencer`访问六个sequencer。

Virtual Sequence负责：

- 创建每个场景需要的Master子sequence。
- 创建每个活动Slave需要的reactive sequence。
- 配置各端口请求、ID、地址、返回顺序和delay/gap。
- 使用`fork/join`组织多端口并行。
- 先启动需要的Slave reactive sequence，再启动Master激励。
- 使用有限请求计数和明确退出条件结束所有子sequence。

Virtual Sequence不负责：

- 直接驱动接口。
- 预测或强制仲裁winner。
- 修改Scoreboard expected队列。
- 通过固定延迟假定事务完成。

### 5.3 Test职责

Stage 6 test只负责：

- 配置环境和Checker模式。
- 配置本场景的预期事务数和覆盖目标。
- 创建并启动一个Stage 6 Virtual Sequence。
- 等待统一drain条件。
- 调用统一结束检查并打印PASS标记。

Stage 6新测试不得在每个test中重复直接访问六个agent层次并自行编写大段`fork/join`调度。

## 6. S6-05：多端口请求和响应能力

### 6.1 Master侧

三个Master Driver均复用Stage 3能力：

- 每Master读、写分别最多4笔outstanding。
- 三个Master的上限和状态相互独立。
- 每个Master可以访问S0、S1、S2和Default地址。
- 每个Master可以同时读写。
- 同一Master相同ID严格保序。
- 不同Master使用相同4-bit ID时互不影响。

达到某个Master写/读上限时，只阻塞该Master对应方向的新AW/AR，不得停止其他Master或其他方向。

### 6.2 Slave侧

三个Slave agent分别运行独立reactive sequence：

~~~text
s_reactive_seq[0]只消费S0 request_fifo
s_reactive_seq[1]只消费S1 request_fifo
s_reactive_seq[2]只消费S2 request_fifo
~~~

每个Slave reactive sequence分别维护：

~~~text
pending_b_by_sid[256]
pending_r_by_sid[256]
b_return_order[$]
r_return_order[$]
~~~

三个Slave可以并行响应。跨Slave响应竞争由Virtual Sequence配置各reactive sequence的脚本，不增加全局Slave Driver。

### 6.3 非交织边界

Stage 6仍使用Stage 3非交织能力：

- 一个Master W burst开始后保持连续到WLAST。
- 一个Slave R burst开始后保持连续到RLAST。
- Stage 6多Master同Slave的W仲裁定向测试使用单拍写。
- Stage 6多Slave同Master的R仲裁定向测试使用单拍读。
- 多拍burst并行测试避免在同一W/R仲裁资源上形成beat交织。

## 7. S6-06：轮询仲裁规则

### 7.1 Master到Slave仲裁

每个正常Slave及Default路径分别存在AW、W、AR仲裁候选。Stage 6主要检查正常S0～S2路径，Default仲裁结合Default定向测试检查。

三路Master仲裁初始优先级：

~~~text
M0 -> M1 -> M2
~~~

当前winner成功握手后，下次从winner的下一端口开始循环查找eligible request。

### 7.2 Slave到Master仲裁

每个Master的B/R返回方向候选包括：

~~~text
S0, S1, S2, Default
~~~

初始优先级：

~~~text
S0 -> S1 -> S2 -> Default
~~~

### 7.3 成功握手和指针更新

地址及B通道的完成条件：

~~~text
AW：grant && AWVALID && AWREADY
AR：grant && ARVALID && ARREADY
B ：grant && BVALID  && BREADY
~~~

Stage 6的W/R仲裁精确测试使用单拍事务，因此完成条件为对应单拍握手。多拍burst的WLAST/RLAST级轮转留到Stage 4重新冻结。

### 7.4 stall锁定

winner已经选择但尚未握手时：

- grant保持稳定。
- payload对应来源保持稳定。
- 新加入的更高优先级request不得抢占。
- 轮询指针不得前移。
- reset除外。

### 7.5 公平性

在请求持续有效、目标READY持续允许完成且没有reset的前提下：

- 三路Master仲裁的持续请求最多等待其他两个成功grant。
- 四路返回仲裁的持续请求最多等待其他三个成功grant。
- 公平性按成功握手计数，不按空闲周期计数。

## 8. S6-07：Default和非法响应处理

### 8.1 Default正常路径

Default请求是合法功能场景：

- 由未映射地址触发。
- 不产生外部S0/S1/S2 expected request。
- System Reference Model直接产生expected Master DECERR response。
- System Scoreboard检查原Master、原始ID、RESP、beat数量和RLAST。
- Channel Checker确认该请求没有错误出现在任一正常Slave端口。

### 8.2 Invalid Master Tag

`SID[5:4]==00`是非法Slave输入：

- 协议断言在VALID出现时报告。
- Reference Model报告并丢弃自身clone，不产生expected。
- 任一Master出现对应actual response时，System Scoreboard报告unexpected response。
- Tracker不得用该响应释放合法pending状态。
- 负向自测确认没有Master收到该响应。

### 8.3 Unsolicited Response

source-master tag合法但没有pending request时：

- Outstanding Tracker或因果Checker报告下溢。
- System Scoreboard报告无expected response。
- 不得消费其他Master、其他ID或同ID后续事务。

## 9. S6-08：Reset和运行边界

### 9.1 本阶段Reset要求

- 六个interface共享启动reset。
- reset期间所有TB主动驱动的VALID/READY为0。
- 六个Driver清空Stage 3内部上下文和mailbox。
- 六个Monitor清空按ID上下文和active burst。
- 三个Slave reactive sequence清空pending池和脚本索引。
- System Reference Model、Scoreboard、Channel Checker和Tracker清空所有状态。
- bind仲裁Checker清空预测指针和stall锁。
- reset释放后才启动Virtual Sequence。

### 9.2 本阶段不验证

- 多端口事务运行中reset。
- 仲裁winner锁定期间reset。
- outstanding非空时reset。
- W/R burst中途reset。
- reset后重放或恢复部分事务。

# 第二部分：测试点、时序约束和协议检查

## 10. S6-09：三主三从功能测试点

### 10.1 9路路由矩阵

读、写分别覆盖：

~~~text
M0 -> S0, S1, S2
M1 -> S0, S1, S2
M2 -> S0, S1, S2
~~~

每条路径检查：

- 实际Slave端口正确。
- 地址和burst属性不变。
- AW、W、AR完整SID正确。
- B/R返回原Master。
- BID/RID恢复原始4-bit ID。
- 数据、STRB、RESP和LAST正确。

### 10.2 ID矩阵

每个`Master × Slave`组合覆盖4个transaction tag。正常SID范围必须符合`ID_intro.md`中的36组映射关系。

至少检查：

- 三个Master同时使用相同4-bit ID访问同一个Slave。
- 三个Master使用不同4-bit ID访问同一个Slave。
- 一个Master使用不同ID访问三个Slave。
- 同一Master、同一ID多笔outstanding保序。

### 10.3 多Slave并行

至少覆盖：

- M0、M1、M2分别访问S0、S1、S2。
- 每个Master同时读写。
- 三个Slave同时返回B。
- 三个Slave同时或相邻周期返回单拍R。
- 一个Slave stall不阻止其他Slave推进。
- 一个Master达到outstanding上限不阻止其他Master推进。

### 10.4 多端口Outstanding

至少覆盖：

- 每个Master分别达到写深度4。
- 每个Master分别达到读深度4。
- 三个Master同时存在outstanding。
- 跨Master相同4-bit ID并存。
- 各Master释放独立，不发生跨端口计数。
- 测试结束六个Tracker全部归零。

不要求某个Slave一次接受12笔事务；实际接受深度由DUT backpressure和内部容量决定。验收重点是不得丢失、重复、错配或跨Master释放。

## 11. S6-10：仲裁测试点

### 11.1 AW竞争

三个Master使用单拍写请求同时访问同一Slave：

- 初始winner符合M0优先。
- 后续成功握手按M1、M2轮转。
- 某Master撤销候选后跳过该端口。
- winner stall期间保持稳定。
- 解除stall后只完成锁定winner。

分别对S0、S1、S2覆盖。

### 11.2 AR竞争

三个Master使用单拍读请求同时访问同一Slave，检查与AW相同的轮询、跳过、锁定和公平性规则。

### 11.3 B返回竞争

S0、S1、S2产生指向同一Master的合法B响应：

- 初始和后续winner符合四路返回仲裁规则。
- 未参与的Default候选被跳过。
- BREADY stall期间winner稳定。
- 每个B只到达SID指定的Master。

### 11.4 R返回竞争

S0、S1、S2使用单拍R响应指向同一Master，检查轮询、锁定、恢复ID和数据完整性。多拍R竞争不属于本阶段。

### 11.5 bind观察

仲裁测试必须同时满足：

- 外部System Scoreboard功能匹配。
- 内部bind Checker的request/grant预测匹配。
- 无onehot、grant非法、stall切换或指针提前更新错误。

## 12. S6-11：Default和非法场景测试点

### 12.1 Default正向测试

M0、M1、M2分别执行：

- 未映射地址单拍写。
- 未映射地址单拍读。
- 至少一个多拍读。
- 检查DECERR、原ID恢复、数据模式和LAST。
- 确认S0/S1/S2均未观察到对应request。

Default写失败时必须保留独立debug记录，不允许把测试静默移除。

### 12.2 Invalid Master Tag负向测试

三个Slave端口分别注入：

- `BID[5:4]==00`。
- `RID[5:4]==00`。

检查：

- 对应断言命中唯一标记。
- 指定观察周期内没有Master出现该B/R。
- 非法response没有释放任何Tracker状态。
- 测试主动终止注入并打印负向自测PASS标记。

### 12.3 其他SID负向测试

- S0返回S1/S2 target tag。
- S1返回S0/S2 target tag。
- S2返回S0/S1 target tag。
- source-master tag合法但没有pending request。
- SID指向错误Master。
- 同ID第二笔响应提前返回。

所有负向测试与正向回归隔离。

## 13. S6-12：协议断言和Checker补充

### 13.1 六接口通用断言

Stage 1～3已有断言必须在六个接口继续生效：

- VALID在握手前不得撤销。
- stall期间VALID和payload稳定。
- 握手payload不含X/Z。
- WLAST/RLAST位置和beat数量正确。
- reset期间TB主动驱动VALID/READY为0。
- outstanding计数不得上溢或下溢。
- Stage 6非交织边界内WID/RID保持稳定。

### 13.2 Master请求ID断言

正常S0～S2请求握手时检查：

~~~text
AWID[3:2] == decode_address(AWADDR)
ARID[3:2] == decode_address(ARADDR)
WID == 对应写事务AWID
~~~

Default地址作为例外由Default上下文检查，不把它误判为正常Slave ID错误。

### 13.3 Slave SID断言

外部S0～S2接口握手或响应VALID时检查：

- SID不含X/Z。
- SID `[7:6]`与实际Slave端口一致。
- SID `[5:4]`属于`01/10/11`。
- SID `[3:2]`与正常目标Slave一致。
- AWID和WID按完整SID关联。
- B/R SID存在对应pending请求。

非法source-master tag必须在VALID出现时检查，因为READY可能永久为0。

### 13.4 仲裁bind断言

新增bind模块至少检查：

- `grant`满足`$onehot0`。
- `grant`是eligible request的子集。
- 无request时grant为0。
- winner stall期间grant稳定。
- 成功握手前预测指针不更新。
- 成功握手后下一winner符合轮询次序。
- 持续eligible且READY允许时满足有界公平性。
- reset后预测指针回到初始状态。

Master到Slave的AW/W/AR和Slave到Master的B/R分别使用适配宽度的Checker。

### 13.5 正向和负向要求

- 所有Stage 6正向测试零非预期断言失败。
- Stage 6断言自测必须逐项命中指定错误。
- 每个预期错误有唯一可识别report ID。
- 负向测试不得通过屏蔽全部UVM_ERROR实现PASS。

## 14. S6-13：Functional Coverage

新增Stage 6 Coverage Collector，事务级采样来源只能是Monitor event/req/rsp。轮询仲裁覆盖由bind Checker在内部request/grant观察点独立采样，不通过非标准TLM回传内部RTL状态。

至少覆盖：

- source Master M0/M1/M2。
- target S0/S1/S2/Default。
- `Master × Slave × direction`。
- transaction tag `00/01/10/11`。
- burst类型和长度。
- 每Master读写outstanding深度0～4。
- 活动Master数量1～3。
- 活动Slave数量1～3。
- 相同4-bit ID跨Master并存。
- 同ID多笔和不同ID乱序。
- AW/AR竞争候选数量1～3。
- B/R竞争候选数量1～4。
- winner端口和轮询跳过。
- 仲裁stall。
- Default读写和DECERR。
- 路由与backpressure交叉。

Stage 6定向回归必须命中所有Stage 6计划功能bin。Stage 4交织和Stage 5复杂reset/READY相关bin不在本阶段完成条件中。

# 第三部分：新增组件职责、实现和TLM连接

## 15. S6-14：组件架构总览

Stage 6新增或扩展的检查路径：

~~~text
Master Monitor req_ap
        │
        ▼
System Reference Model
        │ expected Slave request
        ▼
System Scoreboard ◄──────── Slave Monitor req_ap(actual)

Slave Monitor rsp_ap
        │
        ▼
System Reference Model
        │ expected Master response
        ▼
System Scoreboard ◄──────── Master Monitor rsp_ap(actual)

Master/Slave Monitor channel_ap
        ├── Channel Forwarding Checker
        ├── per-port Outstanding Tracker
        └── Stage 6 Coverage Collector

RTL internal req/grant/ready/valid
        └── bind Round-Robin Checker
~~~

各组件职责必须相互独立，不允许通过读取其他组件私有状态形成隐式耦合。

## 16. S6-15：Switch映射核心

### 16.1 定位

现有`axi_switch_ref_model`作为无状态映射核心保留或按职责重命名为mapping core。它是`uvm_object`，不具有TLM端口。

### 16.2 输入输出API

至少提供：

~~~text
decode_address(address) -> S0/S1/S2/DEFAULT
decode_w_target(master_id) -> S0/S1/S2/INVALID
master_to_tag(master_port) -> 01/10/11/INVALID
tag_to_master(tag) -> 0/1/2/INVALID
slave_to_tag(route) -> 01/10/11/INVALID
tag_to_slave(tag) -> S0/S1/S2/INVALID
build_master_id(route, transaction_tag) -> 4-bit ID
encode_sid(master_port, route, original_id) -> 8-bit SID
decode_master(sid) -> 0/1/2/INVALID
decode_slave(sid) -> S0/S1/S2/INVALID
restore_id(sid) -> 4-bit ID
sid_is_legal(slave_port, sid) -> bit
request_id_matches_route(address, master_id) -> bit
~~~

`decode_slave()`只用于正常外部S0～S2 SID。Default由地址上下文和内部物理路径表示，不能通过Master返回ID反推。

### 16.3 职责限制

映射核心：

- 不连接Monitor。
- 不保存transaction队列。
- 不维护outstanding。
- 不选择仲裁winner。
- 不产生TLM expected流。
- 必须通过独立固定表格单元测试。

## 17. S6-16：System Reference Model

### 17.1 定位

新增`axi_system_ref_model`，它是有TLM输入输出的`uvm_component`，内部持有Switch映射核心。

它接收DUT输入方向事务：

~~~text
Master request
Slave response
~~~

并产生DUT输出方向expected事务：

~~~text
expected Slave request
expected Master response
~~~

### 17.2 TLM端口

固定使用：

~~~systemverilog
uvm_tlm_analysis_fifo #(m_req_t) m_req_fifo[3];
uvm_tlm_analysis_fifo #(s_rsp_t) s_rsp_fifo[3];

uvm_analysis_port #(s_req_t) s_req_ap[3];
uvm_analysis_port #(m_rsp_t) m_rsp_ap[3];
~~~

数组下标代表来源或目标端口。

### 17.3 Master request处理

每个Master端口独立处理线程：

1. 从`m_req_fifo[master_port]`取得完整request。
2. clone请求。
3. 根据地址计算route。
4. 正常route时计算expected SID。
5. 将4-bit ID替换为expected 8-bit SID。
6. 通过对应`s_req_ap[slave_port]`发布expected request。
7. Default route时不向任何`s_req_ap`发布，直接建立Default expected response。

### 17.4 Slave response处理

每个Slave端口独立处理线程：

1. 从`s_rsp_fifo[slave_port]`取得完整response。
2. clone响应。
3. 检查SID source-master tag、target-slave tag和实际端口。
4. 使用SID `[5:4]`计算目标Master端口。
5. 使用SID `[3:0]`恢复4-bit ID。
6. 通过对应`m_rsp_ap[master_port]`发布expected response。

非法SID只报告错误，不发布expected。

### 17.5 Default expected response

Default写request产生：

~~~text
dir   = WRITE
id    = original Master ID
bresp = DECERR
~~~

Default读request产生：

~~~text
dir       = READ
id        = original Master ID
len       = request len
rdata[]   = all ones
rresp[]   = DECERR
rlast     = only final beat
~~~

Reference Model不预测具体返回周期。

### 17.6 非职责

System Reference Model不：

- 读取DUT输出方向actual事务计算expected。
- 比较expected和actual。
- 维护接口outstanding统计。
- 预测仲裁winner。
- 直接驱动Slave Driver。
- 修改Monitor对象。

## 18. S6-17：System Scoreboard

### 18.1 定位

新增`axi_system_scoreboard`，负责完整request/response的系统级端到端比较、顺序、因果、计数和结束检查。

### 18.2 TLM输入

固定使用：

~~~systemverilog
uvm_tlm_analysis_fifo #(s_req_t) exp_s_req_fifo[3];
uvm_tlm_analysis_fifo #(s_req_t) act_s_req_fifo[3];
uvm_tlm_analysis_fifo #(m_rsp_t) exp_m_rsp_fifo[3];
uvm_tlm_analysis_fifo #(m_rsp_t) act_m_rsp_fifo[3];
~~~

expected来源只能是System Reference Model；actual来源只能是DUT输出侧Monitor。

### 18.3 Request比较

正常请求按`{slave_port, SID}`入队：

- expected来自Reference Model。
- actual来自对应Slave Monitor。
- 同一键按FIFO比较。
- 不同SID和不同Slave可以任意交错。
- 比较地址、ID、len、size、burst、WDATA、WSTRB和LAST。
- 实际物理Slave端口必须与expected数组索引一致。

### 18.4 Response比较

响应按`{master_port, restored_id}`入队：

- expected来自Reference Model。
- actual来自对应Master Monitor。
- 同一键按FIFO比较。
- 不同Master和不同ID允许任意顺序完成。
- 比较BRESP、RDATA、RRESP、RLAST和beat数量。

### 18.5 因果和顺序

Scoreboard必须确认：

- 每个正常下游B对应一个已完成写request。
- 每个正常下游R对应一个已接受读request。
- 每个request只被一个response消费。
- 同一`{master_port,id}`按接受顺序完成。
- 跨Master相同4-bit ID不会合并队列。
- Default expected response只消费对应Default请求。
- actual response没有expected时报告unexpected。

### 18.6 结束检查

测试结束时：

- 所有expected/actual FIFO为空。
- 所有按键比较队列为空。
- 所有pending request/response上下文为空。
- expected和actual总数及按端口、按方向计数一致。
- 没有重复、遗漏或额外transaction。

### 18.7 非职责

Scoreboard不：

- 比较每个channel event。
- 维护Driver outstanding。
- 读取Driver或sequence队列。
- 预测仲裁winner或完成周期。
- 强制不同键使用全局FIFO顺序。

## 19. S6-18：Channel Forwarding Checker

### 19.1 定位

新增`axi_channel_forwarding_checker`，只比较Monitor发布的真实AW/W/B/AR/R握手event在Crossbar两侧的转发关系。

### 19.2 TLM输入

使用标准FIFO阵列：

~~~text
m_event_fifo[3]
s_event_fifo[3]
~~~

Master/Slave Monitor的`channel_ap`分别连接对应FIFO的`analysis_export`。

### 19.3 比较规则

- AW/AR：根据Master端口、地址和4-bit ID计算目标Slave及SID。
- W：根据Master端口和WID计算目标Slave及SID。
- B/R：根据下游SID计算目标Master和恢复ID。
- 同一转发键按FIFO比较。
- 不同键允许因仲裁和流水任意交错。
- 不比较上下游`sample_cycle`相等。
- 比较物理端口、ID、单拍payload、RESP和LAST。

### 19.4 Default处理

- Default request不期待S0/S1/S2下游event。
- Checker记录Default路由并确认没有正常Slave错误接收。
- Default完整response内容由System Scoreboard检查。

### 19.5 event/item一致性

Channel Checker只维护event计数，System Scoreboard只维护完整item计数。Stage 6统一结束检查通过两者公开的只读统计接口进行核对，不让两个组件互相读取私有队列。结束时至少核对：

~~~text
AW event数 == 完整写request数
W event数  == 所有写request的Σ(len+1)
B event数  == 完整写response数
AR event数 == 完整读request数
R event数  == 所有读response的Σ(len+1)
RLAST event数 == 完整读response数
~~~

## 20. S6-19：Outstanding Tracker阵列

### 20.1 实例组织

环境必须例化：

~~~text
m_trackers[3]：ID_WIDTH=4
s_trackers[3]：ID_WIDTH=8
~~~

每个Tracker只连接一个物理接口的Monitor `channel_ap`。

### 20.2 TLM输入

Stage 6建议将Tracker输入统一为：

~~~systemverilog
uvm_tlm_analysis_fifo #(event_t) channel_fifo;
~~~

Tracker在`run_phase()`中从FIFO取得event并处理。若保留现有接收实现，也必须保证对外连接仍是标准analysis连接、每个Tracker只有单一接口来源且对象保存前clone。

### 20.3 状态内容

每个Tracker至少维护：

~~~text
aw_observed_by_id[]
wlast_observed_by_id[]
ar_observed_by_id[]
write/read request count by ID
write/read completion count by ID
current write/read outstanding
max write/read outstanding
underflow/error count
~~~

### 20.4 状态规则

~~~text
AW handshake    -> AW计数增加
WLAST handshake -> W完成计数增加
B handshake     -> AW/W计数按ID减少
AR handshake    -> AR计数增加
普通R beat      -> 不释放
RLAST handshake -> AR计数按ID减少
~~~

### 20.5 系统汇总

系统总数由各Tracker只读求和得到，不增加另一套重复可变状态：

~~~text
system_upstream_write = Σm_trackers[i].write_outstanding()
system_upstream_read  = Σm_trackers[i].read_outstanding()
~~~

由于DUT内部FIFO和Default路径，上下游瞬时总数不要求每周期相等；结束状态必须全部为0。

### 20.6 非职责

Tracker不：

- 比较payload。
- 计算路由和SID。
- 生成expected transaction。
- 读取Scoreboard或Reference Model状态。
- 处理未握手的非法SID VALID；该场景由断言负责。

## 21. S6-20：Round-Robin Checker

### 21.1 定位

新增独立的轮询预测和断言模块，通过`bind`挂接到：

~~~text
axi_arbiter_mtos_m3
axi_arbiter_stom_s3
~~~

bind不改变RTL功能端口，不驱动任何信号。

### 21.2 观察输入

Master到Slave Checker观察：

~~~text
AWSELECT/AWVALID/AWREADY/AWGRANT
WSELECT/WVALID/WREADY/WLAST/WGRANT
ARSELECT/ARVALID/ARREADY/ARGRANT
~~~

Slave到Master Checker观察：

~~~text
BSELECT/BVALID/BREADY/BGRANT
RSELECT/RVALID/RREADY/RLAST/RGRANT
~~~

### 21.3 预测状态

每个仲裁方向独立维护：

~~~text
last_successful_winner
locked_winner
lock_valid
wait/grant counters
~~~

预测器按本工单第7节规则更新，不读取RTL内部`last_winner`作为expected。

### 21.4 错误报告

至少提供唯一report ID：

~~~text
AXI_ARB_GRANT_NOT_ONEHOT
AXI_ARB_GRANT_WITHOUT_REQUEST
AXI_ARB_STALL_GRANT_CHANGED
AXI_ARB_POINTER_EARLY_UPDATE
AXI_ARB_WRONG_NEXT_WINNER
AXI_ARB_FAIRNESS_TIMEOUT
~~~

## 22. S6-21：Coverage Collector

新增`axi_stage6_coverage_collector`：

- 使用标准analysis FIFO订阅六个Monitor的event/req/rsp。
- 不读取Driver、sequence或Scoreboard私有状态。
- 不影响测试流控。
- 按端口、路由、ID、方向、深度和事务并行组合采样。
- 提供每个计划bin的命中摘要。
- `cov=0`时允许关闭数据库保存，但功能bin计数器仍可用于定向测试自检。

内部轮询request/grant/winner覆盖由bind Checker自己的covergroup采样，Coverage Collector不通过层次引用读取RTL内部信号。

## 23. S6-22：Env、Cfg和Checker选择

### 23.1 Checker模式

扩展`axi_checker_mode_e`增加：

~~~text
AXI_CHECKER_STAGE6
~~~

Stage 6测试启用：

~~~text
System Reference Model
System Scoreboard
Channel Forwarding Checker
六个Outstanding Tracker
Stage 6 Coverage Collector
bind仲裁Checker
六接口协议断言
~~~

Stage 1/2/3 Checker在Stage 6测试中关闭，不能按单端口假设参与判定。

### 23.2 旧测试兼容

- Stage 1测试仍启用Stage 1 Checker，只连接M0/S0。
- Stage 2测试仍启用Stage 2 Checker，只连接M0/S0。
- Stage 3测试仍启用Stage 3 Checker，只连接M0/S0。
- 其他端口虽已实例化，但没有激励且不得产生额外event。

### 23.3 Env连接

Env在build阶段创建六个agent和Stage 6组件，在connect阶段完成标准TLM连接和Virtual Sequencer句柄赋值。Test不得自行重接TLM端口。

## 24. S6-23：完整TLM连接表

### 24.1 Request expected路径

~~~text
m_agents[i].monitor.req_ap
  -> system_ref_model.m_req_fifo[i].analysis_export

system_ref_model.s_req_ap[j]
  -> system_scoreboard.exp_s_req_fifo[j].analysis_export
~~~

### 24.2 Request actual路径

~~~text
s_agents[j].monitor.req_ap
  -> system_scoreboard.act_s_req_fifo[j].analysis_export

s_agents[j].monitor.req_ap
  -> s_agents[j].sequencer.request_fifo.analysis_export
~~~

### 24.3 Response expected路径

~~~text
s_agents[j].monitor.rsp_ap
  -> system_ref_model.s_rsp_fifo[j].analysis_export

system_ref_model.m_rsp_ap[i]
  -> system_scoreboard.exp_m_rsp_fifo[i].analysis_export
~~~

### 24.4 Response actual路径

~~~text
m_agents[i].monitor.rsp_ap
  -> system_scoreboard.act_m_rsp_fifo[i].analysis_export
~~~

### 24.5 Event路径

~~~text
m_agents[i].monitor.channel_ap
  -> m_trackers[i].channel_fifo.analysis_export
  -> channel_checker.m_event_fifo[i].analysis_export
  -> coverage_collector.m_event_fifo[i].analysis_export

s_agents[j].monitor.channel_ap
  -> s_trackers[j].channel_fifo.analysis_export
  -> channel_checker.s_event_fifo[j].analysis_export
  -> coverage_collector.s_event_fifo[j].analysis_export
~~~

每个箭头表示独立connect；analysis port广播到多个消费者，每个消费者使用自己的FIFO。

### 24.6 Coverage transaction路径

~~~text
m_agents[i].monitor.req_ap
  -> coverage_collector.m_req_fifo[i].analysis_export

m_agents[i].monitor.rsp_ap
  -> coverage_collector.m_rsp_fifo[i].analysis_export

s_agents[j].monitor.req_ap
  -> coverage_collector.s_req_fifo[j].analysis_export

s_agents[j].monitor.rsp_ap
  -> coverage_collector.s_rsp_fifo[j].analysis_export
~~~

Coverage Collector的每个输入FIFO独立于Reference Model、Scoreboard、Tracker和Channel Checker使用的FIFO。

### 24.7 禁止连接

- Master request不得直接进入System Scoreboard作为expected。
- Slave response不得直接进入System Scoreboard作为expected。
- Slave actual request不得输入Reference Model计算同一个request的expected SID。
- Master actual response不得输入Reference Model计算同一个response的expected ID。
- Tracker、Coverage和Channel Checker不得共用同一个FIFO实例。

## 25. S6-24：文件和package组织

### 25.1 建议新增文件

~~~text
dv/env/axi_system_ref_model.sv
dv/env/checker/axi_system_scoreboard.sv
dv/env/checker/axi_channel_forwarding_checker.sv
dv/env/axi_stage6_coverage_collector.sv
dv/env/axi_virtual_sequencer.sv
dv/env/axi_stage6_arbiter_assertions.sv

dv/seq/axi_stage6_base_vseq.sv
dv/seq/axi_stage6_route_matrix_vseq.sv
dv/seq/axi_stage6_id_matrix_vseq.sv
dv/seq/axi_stage6_multi_slave_parallel_vseq.sv
dv/seq/axi_stage6_multi_master_write_arb_vseq.sv
dv/seq/axi_stage6_multi_master_read_arb_vseq.sv
dv/seq/axi_stage6_response_arb_vseq.sv
dv/seq/axi_stage6_cross_master_same_id_vseq.sv
dv/seq/axi_stage6_multiport_outstanding_vseq.sv
dv/seq/axi_stage6_default_slave_vseq.sv
dv/seq/axi_stage6_random_smoke_vseq.sv
dv/seq/axi_s_stage6_reactive_seq.sv

dv/tc/axi_stage6_base_test.sv
dv/tc/axi_stage6_route_matrix_test.sv
dv/tc/axi_stage6_id_matrix_test.sv
dv/tc/axi_stage6_multi_slave_parallel_test.sv
dv/tc/axi_stage6_multi_master_write_arb_test.sv
dv/tc/axi_stage6_multi_master_read_arb_test.sv
dv/tc/axi_stage6_response_arb_test.sv
dv/tc/axi_stage6_cross_master_same_id_test.sv
dv/tc/axi_stage6_multiport_outstanding_test.sv
dv/tc/axi_stage6_default_slave_test.sv
dv/tc/axi_stage6_random_smoke_test.sv

dv/tb/axi_stage6_protocol_assertions_selftest.sv
dv/tb/axi_stage6_arbiter_assertions_selftest.sv
dv/tb/axi_stage6_ref_model_selftest.sv
~~~

### 25.2 建议修改文件

~~~text
dv/common/axi_types_pkg.sv
dv/common/common_typedef.svh
dv/env/axi_switch_ref_model.sv
dv/env/axi_outstanding_tracker.sv
dv/env/axi_env_cfg.sv
dv/env/axi_env.sv
dv/env/axi_env_pkg.sv
dv/seq/axi_seq_pkg.sv
dv/tc/axi_base_test.sv
dv/tc/axi_test_pkg.sv
dv/tb/tb.sv
sim/sim.f
sim/Makefile
dv/doc/ID_intro.md
~~~

### 25.3 编译顺序

固定顺序：

~~~text
types package
interface
env package（item、agent、mapping core、ref model、checker、tracker、coverage、env）
sequence package
test package
RTL
protocol/assertion及bind模块
selftest模块
tb
~~~

module/bind文件不得include进UVM package。

# 第四部分：Stage 6验证和验收

## 26. A6-01：Stage 6A代码审核

审核：

- TB实际例化并连接3个Master interface和3个Slave interface。
- 不存在索引1、2端口的inactive常量绑死。
- 六个agent获得正确cfg、port index和vif。
- Stage 6新测试使用Virtual Sequence/Virtual Sequencer。
- req/rsp端口来源由FIFO数组下标区分。
- TLM只使用本工单批准的标准analysis连接。
- Mapping Core、System Reference Model、System Scoreboard、Channel Checker、Tracker和Arbitration Checker职责不重叠。
- System Reference Model只从DUT输入侧生成expected。
- System Scoreboard不读取Driver/sequence私有状态。
- 每个物理接口有独立Tracker。
- bind Checker不驱动RTL信号。
- Default和Invalid Master Tag定义没有混淆。
- 没有提前实现Stage 4/5能力。
- 未经批准没有修改RTL。

工具门槛：

~~~text
Questa compile：0 error
Stage 6 elaboration：0 error
无新增非预期warning
~~~

## 27. A6-02：Reference Model验收

独立自测必须覆盖：

- 三个正常地址窗口和边界。
- Default地址。
- M0/M1/M2 tag编解码。
- S0/S1/S2 tag编解码。
- 36组`Master × Slave × transaction tag` SID映射。
- SID恢复Master端口和4-bit ID。
- 实际Slave端口与SID target tag一致性。
- invalid master tag `00`。
- invalid slave tag。
- Default expected B/R内容。

自测使用固定输入输出表，不通过与sequence共用随机算法互相验证。

## 28. A6-03：System Scoreboard和Channel Checker验收

### 28.1 System Scoreboard

- 9条正常请求路由全部匹配。
- 三个Master相同4-bit ID不会串队列。
- 不同Master/ID/Slave乱序不会误报全局FIFO错误。
- 同一`{master_port,id}`严格保序。
- 正常B/R响应返回正确Master。
- Default response直接匹配原Master请求。
- 重复、遗漏、额外和错误端口transaction均能报告。
- 测试结束expected/actual和pending队列全空。

### 28.2 Channel Checker

- AW/W/AR逐通道payload和SID正确。
- B/R逐beat恢复ID、数据、RESP和LAST正确。
- 仲裁造成的跨键重排不误报。
- 同键保持FIFO。
- Default请求不会错误期待外部Slave event。
- event与完整item计数一致。

## 29. A6-04：Outstanding Tracker验收

- `m_trackers[0..2]`分别按4-bit ID增加和释放。
- `s_trackers[0..2]`分别按完整8-bit SID增加和释放。
- 跨Master相同ID不串计数。
- 一个端口释放不改变其他端口状态。
- 非RLAST R beat不释放读outstanding。
- B同时释放AW/W完成状态。
- 每Master深度不超过配置4。
- 测试结束六个Tracker全部为0。
- underflow和非法完成能够报告唯一错误。

## 30. A6-05：仲裁验收

- AW、AR、B和单拍W/R grant均满足onehot0。
- grant只选择eligible request。
- 初始优先级符合冻结规则。
- 每次成功握手后轮询到下一eligible端口。
- stall期间winner不切换。
- 请求撤销或缺席时正确跳过。
- 三路和四路持续竞争满足有界公平性。
- 外部功能结果与内部bind检查同时通过。
- bind Checker负向自测全部命中预期。

## 31. A6-06：Default和非法SID验收

### 31.1 Default

- 三个Master的Default读写全部返回原Master。
- BID/RID恢复原始4-bit ID。
- BRESP/RRESP均为DECERR。
- RDATA和beat数量符合期望。
- S0/S1/S2没有观察到Default请求。
- Default路径没有未完成上下文。

### 31.2 Invalid Master Tag

- `SID[5:4]==00`在VALID时命中断言。
- 没有Master收到该response。
- Reference Model不产生expected response。
- Tracker不释放任何合法状态。
- 负向测试能够主动退出并打印唯一PASS标记。

### 31.3 其他非法响应

- Wrong Slave Tag命中对应检查。
- Unsolicited B/R命中因果检查。
- 错误Master路由命中System Scoreboard或Channel Checker。
- 不出现额外非预期断言。

## 32. A6-07：端到端正向测试清单

至少建立：

~~~text
axi_stage6_route_matrix_test
axi_stage6_id_matrix_test
axi_stage6_multi_slave_parallel_test
axi_stage6_multi_master_write_arb_test
axi_stage6_multi_master_read_arb_test
axi_stage6_response_arb_test
axi_stage6_cross_master_same_id_test
axi_stage6_multiport_outstanding_test
axi_stage6_default_slave_test
axi_stage6_random_smoke_test
~~~

继续运行Stage 1的2个、Stage 2的7个和Stage 3的8个正向测试。Stage 6正向测试最少10个，因此完整正向回归当前最低目标为27个测试全部通过。

## 33. A6-08：负向和独立自测

至少建立独立入口：

~~~text
axi_stage6_ref_model_selftest
axi_stage6_protocol_assertions_selftest
axi_stage6_arbiter_assertions_selftest
~~~

负向内容至少包含：

- invalid master tag。
- wrong slave tag。
- unsolicited B/R。
- wrong Master response routing。
- grant非onehot。
- grant选择无request端口。
- stall期间grant切换。
- 指针在握手前更新。
- 握手后选择错误winner。
- 公平性超时。

负向自测不进入`positive_regress`。

## 34. A6-09：统一结束和通过条件

每个Stage 6正向测试结束前必须确认：

- Virtual Sequence及所有有限子sequence已结束。
- 三个Slave `request_fifo`为空。
- 三个reactive sequence pending池和返回脚本为空。
- System Reference Model输入FIFO为空。
- System Scoreboard expected/actual FIFO和按键队列为空。
- Channel Checker所有event队列为空。
- 六个Outstanding Tracker全部为0。
- 三个Master Driver无pending context和mailbox快照。
- 六个Monitor无active burst和未配对上下文。
- 仲裁Checker无锁定winner和pending错误。
- event、request和response计数一致。
- 测试期望事务数全部达到。
- Stage 6计划功能bin达到本测试目标。
- 协议断言零非预期失败。
- `UVM_WARNING=0`、`UVM_ERROR=0`、`UVM_FATAL=0`。
- 打印统一`AXI_TC_PASS`标记并正常退出。

统一timeout错误必须打印各端口、各ID/SID、各FIFO、active burst、reactive脚本和outstanding摘要。

## 35. A6-10：运行入口和回归

Makefile至少增加：

~~~text
cd sim
make com
make stage6_elab
make sim test=<stage6_test>
make stage6_regress
make positive_regress
make stage6_ref_model_selftest
make stage6_assertion_selftest
make stage6_arbiter_selftest
make assertion_selftest
~~~

要求：

- `stage6_regress`连续运行全部Stage 6正向测试。
- `positive_regress`连续运行Stage 1、Stage 2、Stage 3和Stage 6正向测试。
- 任何测试失败时命令返回非0。
- 正向回归不包含负向自测。
- 日志位于`sim/work/log`。
- 波形位于`sim/work/wave`。
- coverage数据库位于`sim/work/cov`。
- 波形脚本必须覆盖六个interface和必要的内部仲裁层次。

## 36. Stage 6完成条件

只有同时满足以下条件，Stage 6才能审核冻结：

1. 三个Master和三个Slave interface、agent、cfg全部实例化并连接正确。
2. Stage 1～3旧测试在3×3环境中继续通过。
3. Stage 6新测试统一使用Virtual Sequence/Virtual Sequencer。
4. 标准TLM连接符合第4节和第24节，不存在绕过连接的私有调用。
5. System Reference Model的输入、输出和Mapping Core职责正确。
6. System Scoreboard按端口和完整ID匹配，不依赖全局FIFO。
7. Channel Checker完成五通道event转发检查。
8. 六个Outstanding Tracker独立计数并最终清空。
9. 9条正常路由的读写全部通过。
10. 36组Master/Slave/tag ID映射及恢复全部通过。
11. 跨Master相同4-bit ID并存和完成正确。
12. 多Master、多Slave并行和多端口outstanding通过。
13. AW、AR、B和Stage 6单拍W/R轮询仲裁通过。
14. bind仲裁Checker的onehot、eligible、stall、pointer和公平性检查通过。
15. Default Slave三Master读写和DECERR检查通过。
16. Invalid Master Tag及其他非法SID负向自测命中预期。
17. 六接口协议断言正向零非预期失败。
18. Stage 6 Reference Model独立固定表格自测通过。
19. Stage 6计划functional coverage bin全部命中。
20. Stage 6最少10个正向测试全部通过。
21. 完整正向回归当前最低27/27通过。
22. 编译和elaboration为0 error且无新增非预期warning。
23. 所有统一结束状态检查通过。
24. 未经审核没有修改RTL。
25. 没有提前实现Stage 4交织或Stage 5复杂READY/reset能力。

## 37. Stage 4和Stage 5后续补充约束

### 37.1 Stage 4接入约束

Stage 4实现W/R beat交织时：

- 不改变Stage 6六agent、Virtual Sequencer和标准TLM拓扑。
- 扩展Monitor按WID/RID重建多个active burst。
- 扩展Channel Checker按ID和beat索引匹配。
- 扩展System Scoreboard支持交织后的完整事务重建结果。
- 更新W/R仲裁Checker，把轮询粒度明确为beat或burst，并按最终规格处理WLAST/RLAST。
- 删除或关闭Stage 6项目级非交织断言。
- 增加多拍同Slave写竞争和多Slave同Master读返回竞争。

### 37.2 Stage 5接入约束

Stage 5实现完整READY、容量和复杂reset时：

- 不改变Stage 6 Reference Model和Scoreboard的expected/actual方向。
- READY模式和容量门控只进入agent cfg及Driver，不进入Reference Model。
- 运行中reset必须统一清理Virtual Sequence子线程、Driver、Monitor、reactive sequence、Reference Model、Scoreboard、Checker、Tracker和Coverage临时状态。
- reset前部分握手事务不得自动重放。
- 新增复杂reset和容量相关断言、负向自测及coverage交叉。

## 38. 审核记录

| 审核项 | 当前状态 | 说明 |
|---|---|---|
| Stage 6范围 | 待实施 | 三主三从系统级环境，保留Stage 3通道能力 |
| Stage 4/5边界 | 已冻结 | 不实施beat交织、完整READY/容量和复杂reset |
| TLM连接 | 已冻结 | 使用`uvm_analysis_port`和`uvm_tlm_analysis_fifo` |
| Reference Model职责 | 已冻结 | DUT输入事务到expected输出事务，内部调用无状态映射核心 |
| System Scoreboard职责 | 已冻结 | 完整req/rsp端到端比较、顺序、因果和结束检查 |
| Channel Checker职责 | 已冻结 | 五通道真实握手event转发比较 |
| Tracker职责 | 已冻结 | 六接口按真实握手独立维护outstanding |
| 仲裁检查 | 已冻结 | 成功握手更新指针，使用bind精确观察内部req/grant |
| Virtual Sequence | 已冻结 | Stage 6新测试统一使用Virtual Sequence/Virtual Sequencer |
| Default Slave | 已冻结 | 未映射地址合法DECERR路径，不存在Default Master ID |
| Invalid Master Tag | 已冻结 | SID `[5:4]==00`非法，不路由到任何Master |
| RTL修改 | 未批准 | 默认仅修改`dv`、`sim`和文档 |
| 编译与仿真 | 待运行 | 实施后填写工具版本、命令和结果 |
| 正向回归 | 待运行 | 当前最低目标27/27 |
| 负向自测 | 待运行 | Reference Model、协议断言和仲裁断言独立入口 |
| Functional Coverage | 待实施 | 只闭环Stage 6计划bin |

### 38.1 实施后记录要求

实施完成后补充：

- 审核日期和工具版本。
- 实际新增、修改和排除文件。
- 编译和elaboration命令及结果。
- Stage 6正向测试逐项结果。
- Stage 1～3兼容回归结果。
- Reference Model、协议断言和仲裁断言自测结果。
- functional coverage摘要。
- 日志、波形和coverage路径。
- 发现的RTL问题、授权修复和独立debug记录。
- 最终冻结提交或标签。

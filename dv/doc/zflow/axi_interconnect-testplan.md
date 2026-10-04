# AXI Interconnect 验证计划

## 1. Overview

验证对象为 `axi_interconnect`：默认配置下 3 个 `M_AXI_*` 发起端、3 个 `S_AXI_*` 目标端、单 `AXI_CLK` 时钟域的 AXI3 风格交叉开关。

来源文档：

- `axi_interconnect-architecture-extracted.md`
- `axi_interconnect-microarchitecture-extracted.md`
- `axi_interconnect-top-microarchitecture.md`
- `axi_crossbar-routing-microarchitecture.md`
- `axi_ordering-buffering-microarchitecture.md`
- `axi-default-and-primitives-microarchitecture.md`

范围包括 AW/W/B/AR/R 握手、3×3 地址路由、8 位 SID 编解码、M→S 与 S→M 仲裁、30 个深度 4 FIFO、AR/AW 两个 4 项 SID 表、默认从设备、复位、反压、并发、前向进展和已知风险。缓存一致性、CDC、QoS、CSR、宽度转换和低功耗控制不在 DUT 功能范围内。

检查基准为独立事务级参考模型：地址窗口决定目标；SID 模型按 `{target_code, master_code, original_ID}` 生成；每个端口/通道使用独立有序队列保存期望 payload；仲裁检查器只约束合法候选、grant one-hot、反压稳定和无饥饿，不镜像 RTL FSM。所有 constrained-random 测试必须使用 scoreboard 逐事务比较，并启用 ready/valid、payload-stability、one-hot 和 outstanding-ID assertions。

架构没有定义数学误差、精度界限、穷举要求或独立 Verification Predicate，因此不包含 §5a。

## 2. Feature-to-Test Mapping

| # | Feature | Sub-Feature | Test Type | Test Case | Stimulus | Pass Criteria | Covergroup |
|---|---|---|---|---|---|---|---|
| F01 | 3×3 topology | 每个 M 到每个 S 的 AW/AR/W/B/R 路径 | Directed + CR | `tp_route_matrix_directed`, `tp_route_matrix_random` | 逐一及随机选择 3×3 source/target，读写均覆盖 | 9 个 M→S 组合均到唯一目标；9 个 S→M 返回组合均回 SID.MID 指定 M；scoreboard 0 mismatch | `cg_route_matrix` |
| F02 | Address decode | S0/S1/S2 三个 4 KiB 窗口 | Directed + CR | `tp_address_boundaries`, `tp_address_random` | 每窗口首/末地址及窗口内随机地址 | `0x0000_0000..0x0000_0fff` 仅到 S0，`0x2000..0x2fff` 仅到 S1，`0x4000..0x4fff` 仅到 S2 | `cg_address_decode` |
| F03 | Default route | 未命中 AW/AR | Directed + CR | `tp_default_holes`, `tp_default_random` | gaps、窗口相邻地址及 20% 未命中随机地址 | 未命中请求不出现在 S0/S1/S2；读返回 `RRESP=2'b11`，写返回 `BRESP=2'b11` | `cg_default_route` |
| F04 | SID encode/decode | 目标码、MID、原 ID | Directed + CR | `tp_sid_exhaustive`, `tp_sid_random` | 3 targets×3 masters×16 original IDs | 下游 SID逐位等于 `{01/10/11,01/10/11,ID[3:0]}`；返回 `M_AXI_BID/RID==ID[3:0]` | `cg_sid_map` |
| F05 | W routing contract | `WID[3:2]` 目标编码 | Directed + CR | `tp_wid_target_map`, `tp_wid_random` | 合法目标码及故意错误目标码 | 合法 W 只到编码目标；未登记/目标码错误的 W 在 32 个观测周期内无 `S_AXI_WVALID&&S_AXI_WREADY` | `cg_wid_route` |
| F06 | Read flow | AR登记、R资格、RLAST | Directed + CR | `tp_read_end_to_end`, `tp_read_outstanding_random` | LEN 0..15、ID 0..15、目标/主随机 | 每个已接受 AR 恰返回 `ARLEN+1` beat；payload/RESP/LAST逐 beat 与目标驱动一致；未知 SID R 不被接受 | `cg_read_flow` |
| F07 | Write flow | AW登记、W资格、B返回 | Directed + CR | `tp_write_end_to_end`, `tp_write_outstanding_random` | LEN 0..15、ID、WSTRB、数据和 B response 随机 | 每个 AW 的 `AWLEN+1` 个 W beat按目标码送达，最后 beat `WLAST=1`；B 回到 MID 指定 M 且 BID 为原 ID | `cg_write_flow` |
| F08 | Concurrent targets | 三个目标并行 | Directed + CR | `tp_three_target_parallel`, `tp_concurrency_random` | M0/M1/M2 同拍访问不同目标，混合读写 | 三个目标均可在同一周期观察各自通道握手；三条事务均只出现一次且数据 0 mismatch | `cg_concurrency` |
| F09 | M→S arbitration | S0/S1/S2/default 的 AW/W/AR 三路轮询 | Directed + CR | `tp_mtos_round_robin`, `tp_mtos_arb_random` | 3 M 同时持续请求同一目标，插入随机 ready stalls | ready持续为 1 时每 3 个 eligible handshake内 M0/M1/M2 各获胜至少 1 次；grant one-hot-or-zero | `cg_mtos_arb` |
| F10 | S→M arbitration | 每个 M 的 B/R 四路轮询 | Directed + CR | `tp_stom_round_robin`, `tp_stom_arb_random` | S0/S1/S2/default 同时向同一 MID 返回 | ready持续为 1 时每 4 个 eligible handshake内四个来源各获胜至少 1 次；输出 payload来自唯一 grant | `cg_stom_arb` |
| F11 | Grant lock | RUN/WAIT 反压保持 | Directed + CR | `tp_grant_stall_lock`, `tp_grant_lock_random` | 获 grant 后 ready拉低 1,2,5,16 周期，期间加入新请求 | WAIT 期间 grant及全部 payload逐周期 `$stable`；原请求握手前来源不切换 | `cg_grant_lock` |
| F12 | FIFO buffering | 30 个 `axi_fifo_sync`、深度 4 | Directed + CR | `tp_fifo_boundaries`, `tp_fifo_random_pressure` | 各通道 fill 0/1/3/4、pop/push组合 | 第 4 项后 `wr_rdy=0`；FIFO序列逐位保持；空时 `rd_vld=0`；30 个实例组全部覆盖 | `cg_fifo` |
| F13 | FIFO edge semantics | 空/满同拍 read+write | Directed + CR | `tp_fifo_empty_full_exchange`, `tp_fifo_edge_random` | empty与full边界同时拉高 wr_vld/rd_rdy | 空态同拍只接受 push且下一周期 `rd_vld=1`；满态同拍只 pop、不接受 push，下一周期 occupancy=3 | `cg_fifo_edges` |
| F14 | SID tables | AR/AW 各 4 项容量与压紧 | Directed + CR | `tp_sid_table_depth`, `tp_sid_table_random` | 登记 4 个不同 SID、乱序候选、逐项 LAST | 占用数仅 0..4；第 5 个地址被反压；删除 slot 0..3 后剩余项保持相对次序并左移 | `cg_sid_table` |
| F15 | Eligibility filter | 任意槽成员命中、非严格队首 | Directed + CR | `tp_sid_membership`, `tp_sid_membership_random` | 对 slot0..3 逐个提供 W/R，另提供未登记 SID | 任一槽命中者在注册资格后可握手；未命中者 32 周期内不得握手；不要求 slot0 先完成 | `cg_sid_eligibility` |
| F16 | SID push/clear priority | 固定优先级 0>1>2 | Directed + CR | `tp_sid_priority`, `tp_sid_priority_random` | 2/3 路同拍 push或clear | 同拍只有最低编号候选获 `*_rdy`；其余请求保持后在后续周期各处理一次，无重复/丢失 | `cg_sid_priority` |
| F17 | SID clear handshake risk | `VALID&LAST` 与真实 ready | Directed + CR | `tp_sid_clear_backpressure`, `tp_sid_clear_random` | 末 beat有效时令最终输出 FIFO满 1..16 周期 | 设计要求：SID在 `VALID&&READY&&LAST` 前保持；当前 RTL若提前清项，assertion必须报出且测试归类为已知缺陷，不得静默通过 | `cg_sid_clear` |
| F18 | Default read FSM | `STR_IDLE/RUN/WAIT/END` | Directed + CR | `tp_default_read_fsm`, `tp_default_read_random` | 未命中 AR，LEN=0,1,15，RREADY随机 stall | 每笔产生恰好 LEN+1 个 `RRESP=11`、`RDATA='1` beat；仅末 beat RLAST=1；四状态和全部合法弧命中 | `cg_default_read_fsm` |
| F19 | Default write FSM | `STW_IDLE/RUN/WAIT/RSP` | Directed + CR | `tp_default_write_fsm`, `tp_default_write_random` | 未命中 AW/W，LEN=0,1,15，BREADY随机 stall | 接收 LEN+1 beat 后恰产生 1 个 `BRESP=11`；BID等于保存 AWID；四状态和全部合法弧命中 | `cg_default_write_fsm` |
| F20 | Reset | 异步与同步低有效状态 | Directed + CR | `tp_reset_idle_and_active`, `tp_reset_random_phase` | 空闲及各通道活动时拉低 `AXI_RSTn` 1..5 周期，随机相位释放 | 复位后所有 FIFO `rd_vld=0`、`order_grant=0`、SID槽为0、仲裁状态回 RUN、default FSM回 IDLE；无复位前 payload泄漏 | `cg_reset` |
| F21 | Backpressure | 各通道 0/1/2..5/6+ 周期 stall | Directed + CR | `tp_channel_backpressure`, `tp_backpressure_random` | 对 S_AW/W/ARREADY、M_B/RREADY分别 stall 0,1,2,5,6,16 周期 | stall期间 VALID payload稳定；释放后每个已接受事务恰输出一次；scoreboard 0 drop/duplicate | `cg_backpressure` |
| F22 | AXI3-style bursts | LEN 0..15、逐 beat重仲裁 | Directed + CR | `tp_burst_lengths`, `tp_burst_interleave_random` | 单/多 ID burst，LEN边界，跨来源 beat交织 | 每事务 beat数=LEN+1且 LAST仅最后一拍；不同 ID交织不串 ID/data；同 ID顺序按驱动接受序比较 | `cg_burst` |
| F23 | Forward progress | 无 timeout/flush | Directed + CR | `tp_progress_after_release`, `tp_progress_random` | 有限 backpressure后永久 ready，合法 SID、valid保持 | ready释放后 32 周期内所有已入 FIFO事务至少发生下一次握手；超时报告具体通道/ID；该 32 周期是 TB 观测界限，非架构延迟保证 | `cg_progress` |
| F24 | Default diagnostics | WLAST缺失、AWID/WID mismatch | Directed + CR | `tp_default_write_diagnostics`, `tp_default_error_random` | 10% 默认写注入早/晚 WLAST或ID mismatch | 仿真日志出现对应 `Error expecting WLAST` 或 `AWID:WID mismatch`；硬件仍以 `BRESP=11` 收尾 | `cg_default_diag` |
| F25 | Parameter contract | 默认位宽和固定3×3 | Directed + static | `tp_default_parameter_elab`, `tp_unsupported_parameter_audit` | 默认 elaboration；另对非默认 WIDTH/NUM做编译负测 | 默认配置编译且端口宽度为 32/32/4/8；非默认配置不得被宣称支持，所有截断/宽度错误被测试报告列出 | `cg_parameter` |
| F26 | Address overlap risk | 非互斥窗口 | Directed + static | `tp_overlap_negative` | 单元级将两个 `ADDR_BASE*` 配成同一4 KiB窗口 | 同一 AW/AR 若出现两个真实目标 handshake，window-disjoint assertion失败；该配置必须判为非法，不作为功能通过 | `cg_overlap_negative` |
| F27 | No flush/kill/CSR/CDC/power/ECC | 不存在的功能 | Static + reset directed | `tp_scope_static_audit` | 端口/层次静态检查，复位中止在途事务 | 无 flush/kill/CSR/第二时钟/power-control/ECC/parity端口；复位后在途事务不得继续输出。随机化无额外价值，因这些接口不存在 | `cg_scope` |
| F28 | Observability | 外部握手与内部关键状态 | Directed + CR | `tp_monitor_consistency`, all CR tests | 比较 monitor计数、scoreboard和内部 bind checker | 每个外部 handshake恰生成1个 monitor item；结束时 expected/actual队列均为0；所有 checker 计数一致 | `cg_observability` |
| F29 | Single-clock architecture | `AXI_CLK/ACLK/clk` 单域 | Static + directed | `tp_single_clock_audit` | 静态检查所有时序块和实例时钟连接；用AXI_CLK驱动功能流量 | 所有状态只由AXI_CLK域更新；设计端口中不存在第二功能时钟；100笔读写在该时钟下0 mismatch | `cg_clock_scope` |

## 3. Constrained-Random Test Strategy

所有类均使用独立 reference model、逐事务 scoreboard 和 protocol assertions。除表中特别说明外，最少事务数为 10,000。

| Test Class | Randomised Dimensions | Constraints | Checking Strategy | Min Transaction Count |
|---|---|---|---|---:|
| `tp_route_matrix_random` | M/S选择、读写、地址、ID、LEN | 三个合法窗口各25%，未命中25%；ID 0..15 | 窗口函数预测目标；SID函数预测下游ID；端到端scoreboard | 10,000 |
| `tp_address_random` | AW/AR地址、边界距离、M端口 | S0/S1/S2/default各25%；距窗口边界0/1字节权重40% | 独立高位比较函数预测唯一目标；`p_decode_onehot` | 10,000 |
| `tp_default_random` | 未命中AW/AR、LEN、ID、读写比例 | 只生成三个4 KiB窗口之外地址；read/write各50% | default读写事务模型检查DECERR、beat数和ID | 10,000 |
| `tp_sid_random` | target code、MID、original ID、返回来源 | 3×3合法组合均匀；ID 0..15均匀 | 纯拼接函数计算SID，返回函数取低4位 | 10,000 |
| `tp_wid_random` | WID目标码、MID、ID、membership | 合法目标码95%，错误/未登记5% | AW登记模型预测W eligible与唯一目标 | 10,000 |
| `tp_read_outstanding_random` | 3 M、3 S、ARID、ARLEN、R返回顺序、gap、RREADY | outstanding 0..4；LEN 0/1/15权重各15%；只返回已发AR SID，另以5%注入非法SID | 每M按ID维护期望R队列；非法SID期望无握手 | 10,000 |
| `tp_write_outstanding_random` | AWID/WID、目标、LEN、WSTRB、data、AW/W相对时序、B顺序 | WID[3:2]与目标一致占95%，错误占5%；最多4 outstanding | AW模型登记SID，逐beat预测W目标，B按MID返回 | 10,000 |
| `tp_mtos_arb_random` | 请求组合、目标、ready stall长度 | 单请求/双请求/三请求分别20/30/50%；stall 0..16 | grant候选合法性、one-hot、stable-under-stall、3-way服务窗口 | 10,000 |
| `tp_stom_arb_random` | S0/S1/S2/default响应组合、MID、ready | 四路全开30%；stall 0..16；合法SID为主 | 4-way候选模型、返回payload scoreboard、服务窗口检查 | 10,000 |
| `tp_grant_lock_random` | 五通道grant来源、stall长度、新请求到达 | stall 1..16；WAIT期间原VALID保持 | 保存握手前grant/payload快照并逐周期比较 | 10,000 grants |
| `tp_fifo_random_pressure` | 五通道valid/ready、burst/gap、占用水平 | 重点命中occupancy 0/1/3/4；full/empty各20%时间 | 每个逻辑FIFO用独立SV queue预测push/pop及数据 | 30,000 channel handshakes |
| `tp_fifo_edge_random` | empty/mid/full下push/pop组合 | full和empty各30%；simultaneous操作50% | 独立queue按RTL接受条件预测occupancy和payload | 10,000 operations |
| `tp_sid_table_random` | push/clear来源、SID、重复ID、表占用 | occupancy 0..4；重复SID 10%；三路同拍20%；clear反压20% | 集合/压紧模型；检查槽位、ready、order_grant延迟1拍 | 10,000 SID operations |
| `tp_sid_membership_random` | AR/AW表、slot hit/miss、候选来源 | slot0..3和miss各20%；VALID随机gap | 前一拍四槽集合预测每个order_grant bit | 10,000 checks |
| `tp_sid_priority_random` | push/clear mask、来源、occupancy | request mask 1..7；push与clear各50% | 固定最低bit优先模型检查ready和单次更新 | 10,000 conflicts |
| `tp_sid_clear_random` | AR/AW末beat、最终FIFO ready、stall | LAST时ready=0概率50%，stall 1..16 | handshake-based shadow table；`p_sid_clear_on_handshake`暴露差异 | 10,000 terminal beats |
| `tp_default_read_random` | 未命中地址、ARID、LEN、RREADY stall | LEN 0..15；0/1/15重点；stall 0..16 | 期望 LEN+1 个全1数据、DECERR及末拍LAST | 10,000 |
| `tp_default_write_random` | 未命中地址、ID、LEN、W gap、BREADY | 合法流90%，诊断错误10%；LEN 0..15 | 默认写FSM事务模型和日志检查器 | 10,000 |
| `tp_reset_random_phase` | reset时刻、低电平长度、活动通道、occupancy | 1..5周期；覆盖FIFO空/半满/满、FSM WAIT/RSP/END | epoch-based scoreboard：复位前期望全部丢弃，复位后重新计数 | 2,000 resets |
| `tp_backpressure_random` | 五通道、stall位置/长度、FIFO占用 | stall 0/1/2..5/6..15/16+均匀 | 通道stable assertions和端到端queue scoreboard | 10,000 transactions |
| `tp_burst_interleave_random` | R/W、LEN、ID、交织来源、beat gap | 2或3事务交织60%；LEN 0/1/15重点 | per-SID beat queue检查data、count、LAST | 10,000 bursts |
| `tp_progress_random` | 被阻塞资源、阻塞时长、释放顺序 | 只生成有限stall 0..32；请求保持VALID | 释放后32周期TB watchdog及未完成事务列表 | 10,000 transactions |
| `tp_concurrency_random` | 6个外部端点活动、五通道组合、stall | 每周期至少2个接口活动概率70%，全接口活动20% | 多端口reference switch model；逐端点队列比较 | 20,000 |
| `tp_default_error_random` | 早/晚/缺失LAST、ID mismatch | 错误注入10%；其余事务合法 | 期望日志模式+DECERR；正常事务不受影响 | 10,000 |

### 3.1 Randomisation exclusions

- F25 非默认参数：这些值在 elaboration 时固定，且来源文档明确其不受支持；运行时 constrained-random 无法改变参数，故用默认配置功能测试加非默认配置编译/宽度审计替代。
- F26 地址窗口重叠：同样是 elaboration 参数负测；随机化重叠基址不会增加“译码必须one-hot”这一确定性判据的覆盖价值，采用覆盖AW和AR的最小重叠配置。
- F27 不存在的接口/功能：没有可驱动的 flush/CSR/CDC/power/ECC 端口；用静态端口/层次审计和随机相位reset测试覆盖唯一相关行为。
- F29 单时钟架构：只有 `AXI_CLK` 一个功能时钟，运行时不存在可随机选择的时钟域；用静态clock-connectivity审计和随机流量功能测试替代跨域随机化。

## 4. Interface Verification

### 4.1 Ready/valid 通用检查

对 `M_AXI_AW/W/ARVALID`、`S_AXI_B/RVALID` 的输入方向以及 DUT 输出方向分别覆盖三种合法相位：VALID先到、READY先到、同拍到达。每种相位必须在 AW/W/B/AR/R、端口0/1/2各至少命中1次。

| Test | Interface / Stimulus | Pass Criteria |
|---|---|---|
| `tp_valid_before_ready` | VALID先保持，READY延迟1、2、5、6、16周期 | 每个被阻塞通道的ID/address/data/control逐周期稳定；仅 `VALID&&READY` 周期计1次握手 |
| `tp_ready_before_valid` | READY先为1，VALID随后单拍或连续到达 | 每个VALID在同拍或首个合法周期被接收；无VALID时monitor计数保持0 |
| `tp_simultaneous_handshake` | VALID和READY同拍拉高 | 该周期计1次且仅1次事务；下一事务payload不与前一事务拼接 |
| `tp_valid_hold_rule` | 反压期间保持VALID与payload | assertions `p_aw_stable/p_w_stable/p_b_stable/p_ar_stable/p_r_stable` 全部通过 |
| `tp_valid_early_drop_negative` | VALID在READY前撤销 | 协议assertion在撤销周期报错；scoreboard不得把未握手payload计为事务 |
| `tp_spurious_response_negative` | 未登记SID送入S_AXI_R/B | R不得握手；B因RTL不受SID表门控，若MID匹配会被观察到并由`p_b_has_request`报错 |

### 4.2 AW/AR 接口

- 分别对 `M_AXI_AW*` 和 `M_AXI_AR*` 覆盖全部3个 M端口、3个合法窗口、default窗口、LEN 0..15。
- 下游 `S_AXI_AW*`/`S_AXI_AR*` payload必须逐位等于上游字段，唯一允许变化是 ID 从4位扩展到8位。
- SID表满4项后，第5个地址的 `M_AXI_AWREADY` 或 `M_AXI_ARREADY` 最终拉低；释放1项后，第5项可完成且只完成1次。

### 4.3 W 接口

- W可早于、同拍或晚于对应AW进入入口FIFO；只有 AW SID登记并经 `reorder` 注册资格后才允许目标侧握手。
- 对每个目标码 `WID[3:2]=01/10/11` 和每个MID覆盖至少16个原ID值。
- W反压期间 `WID/WDATA/WSTRB/WLAST` 必须稳定；一个burst中 `WLAST`只在第 `AWLEN+1` beat为1。

### 4.4 B/R 接口

- B/R按扩展 SID `[WIDTH_ID+1:WIDTH_ID]` 路由至 M0/M1/M2，外部 ID等于SID低4位。
- B/R来源同时竞争时验证四路仲裁；R还需验证 `r_order_grant` 注册延迟和任意槽成员资格。
- `M_AXI_BREADY/M_AXI_RREADY` 分别施加0、1、2、5、6、16周期stall，所有DUT输出payload保持稳定。

### 4.5 复位接口

- 异步状态：在非时钟边沿拉低 `AXI_RSTn`，`axi_fifo_sync`、仲裁器和default FSM应在下一个采样观察点呈复位值。
- 同步状态：`sid_buffer`和`reorder`只要求在拉低复位后的首个 `AXI_CLK` 上升沿清零。
- 释放仅在上升沿附近随机测试；因为规格没有复位同步器，亚稳性不作为RTL仿真可判定项，但必须覆盖相位偏移。

## 5. Datapath Verification

| Sub-Feature | Directed Stimulus | Expected Result |
|---|---|---|
| AW/AR地址窗口 | `0x0000_0000,0x0000_0fff,0x0000_1000,0x0000_1fff,0x0000_2000,0x0000_2fff,0x0000_3000,0x0000_3fff,0x0000_4000,0x0000_4fff,0x0000_5000,0xffff_ffff` | 三个闭区间分别唯一命中S0/S1/S2；其余命中default |
| AW/AR SID编码 | 对9个M×S组合和ID `0,1,7,15` | SID分别等于 `{target_code,master_code,ID}`；共36个向量全部逐位匹配 |
| W SID编码 | WID目标码 `01/10/11`，MID `01/10/11`，ID 0..15 | 内部候选SID等于 `{WID[3:2],MID,WID[3:0]}`；只允许命中AW表的候选通行 |
| B返回截取 | SID低位取 `0,1,7,15` | `M_AXI_BID`逐位等于SID `[3:0]`，BRESP不改变 |
| R返回截取 | SID低位取 `0,1,7,15`，随机RDATA/RRESP/RLAST | `M_AXI_RID==SID[3:0]`，RDATA/RRESP/RLAST逐位不改变 |
| AW/AR属性透明传递 | LEN 0..15，SIZE 0..7，BURST 0..3 | 目标侧ADDR/LEN/SIZE/BURST与输入逐位相同，不做对齐或合法性修正 |
| W数据透明传递 | WDATA `0,all1,0xaaaa5555,random`，WSTRB `0,1,5,f` | 目标侧DATA/STRB/LAST逐位相同 |
| Default read payload | LEN 0,1,15 | 分别输出1、2、16个 `RDATA=32'hffff_ffff,RRESP=2'b11` beat，最后一个RLAST=1 |
| Default write payload | LEN 0,1,15 | 接受1、2、16个W beat后各输出恰1个 `BRESP=2'b11`，BID等于AWID |
| SID membership | 表项位于slot0/1/2/3 | 对应候选在下一拍 `order_grant[N]=1`；不存在时为0 |

独立reference model不得复用RTL的 `AWSELECT_OUT/ARSELECT_OUT/order_grant` 作为预测输入；它只读取外部已握手事务和配置常量。

## 6. Control Logic & FSM Verification

### 6.1 `axi_arbiter_mtos_m3`

对 `stateAR/stateAW/stateW` 分别执行：

| Initial State | Condition | Expected Next State / Output |
|---|---|---|
| RUN | 无request | 保持RUN，grant=0 |
| RUN | request且READY=1 | 保持RUN，发生1次握手 |
| RUN | request且READY=0 | 下一拍WAIT，`*grant_reg`保存当前one-hot grant |
| WAIT | VALID=1且READY=0 | 保持WAIT，grant与payload稳定 |
| WAIT | `grant&VALID&READY` | 下一拍RUN；AW/W保存grant清0，AR下一次RUN重新选择 |

每个状态和合法弧覆盖100%。当READY释放并保持1时，WAIT不得超过2个额外观测周期；若request撤销违反valid保持规则，由接口assertion报错，不作为合法FSM弧。

### 6.2 `axi_arbiter_stom_s3`

对 `stateR/stateB` 重复RUN/WAIT矩阵。R每beat握手后回RUN，不等待RLAST；必须覆盖 `RLAST=0` 和 `RLAST=1` 两种返回RUN路径。READY持续为0时允许无限WAIT；READY恢复后2周期内必须观察到握手或VALID已合法撤销。

### 6.3 `axi_default_slave` 写 FSM

必须覆盖：

- `STW_IDLE→STW_RUN→STW_WAIT→STW_RSP→STW_IDLE`。
- `STW_RSP→STW_RUN`：B握手时已有下一笔AWVALID。
- `STW_WAIT` 自环：长度未完成且WLAST=0。
- 在BREADY=0时 `STW_RSP` 保持，BID/BRESP/BVALID稳定。

合法写事务在环境READY/VALID前提满足后，任何非终态不得无原因停留超过 `AWLEN+20` 个测试平台观察周期；四个状态均须命中。

### 6.4 `axi_default_slave` 读 FSM

必须覆盖：

- `STR_IDLE→STR_RUN→STR_WAIT→STR_END→STR_IDLE`。
- `STR_END→STR_RUN`：完成时下一笔ARVALID已存在。
- `STR_WAIT` 自环及LEN=0直接末beat情形。
- RREADY=0时保持RVALID/RID/RLAST。

每笔读握手数必须等于 `ARLEN+1`；四个状态及全部合法弧覆盖100%。

### 6.5 `sid_buffer` / `reorder` 状态行为

虽无显式枚举FSM，按占用状态0/1/2/3/4建立状态覆盖。要求所有相邻弧 `0↔1↔2↔3↔4` 命中；禁止占用小于0或大于4；`order_grant`在输入采样后一拍反映成员关系。

### 6.6 非法状态检查

bind assertions约束 `stateAR/stateAW/stateW/stateR/stateB` 仅为RUN/WAIT，default读写状态仅为各自四个localparam。由于部分case无default，任何X/非法编码立即失败，不尝试把恢复行为当作通过条件。

## 7. Arbitration & Scheduling

| Arbiter | Directed Cases | Fairness / Pass Criteria |
|---|---|---|
| 3-way AW | M0、M1、M2单独；三路同拍；两路所有组合 | 单请求者必获grant；三路持续且READY=1时任意3个握手窗口三者各1次 |
| 3-way AR | 同AW | 同AW；ARSELECT必须来自同一目标地址命中 |
| 3-way W | 同AW，且SID已登记 | 任意3个eligible W握手窗口三者各1次；未登记者不计eligible |
| 4-way B | S0/S1/S2/default单独及全开 | READY=1时任意4个eligible B握手窗口四来源各1次 |
| 4-way R | S0/S1/S2/default单独及全开 | READY=1时任意4个eligible R握手窗口四来源各1次；真实S需r_order_grant |

额外检查：

- `round_robin_m2s.last_winner` 和 `round_robin_s2m.last_winner` 在有request但无握手时仍会更新；外层WAIT必须保证最终外部grant不因此切换。
- asymmetric pattern：端口0 100%负载、端口1/2以10%负载到达；低负载请求从变为eligible起最多3个M→S握手机会内获服务。四路返回对应界限为4个握手机会。
- 架构没有全局最坏周期延迟保证；上述界限仅在目标READY恒为1、请求持续、无FIFO/SID资源阻塞时适用。

## 8. Buffered Structure Verification

### 8.1 30 个 `axi_fifo_sync`

下列序列对十个实例组的每个索引 `[0:2]` 执行，覆盖全部30个FIFO：

| Sequence | Initial Occupancy | Operations | Pass Criteria |
|---|---:|---|---|
| empty-pop | 0 | `rd_rdy=1` 4周期 | `rd_vld=0`，head/count不下溢 |
| single | 0 | push A，随后pop | A只输出1次；empty→1→0 |
| fill-drain | 0 | push A/B/C/D，再pop四次 | occupancy到4时`wr_rdy=0`；输出A/B/C/D |
| overflow-attempt | 4 | `wr_vld=1`携带E 3周期 | E不写入，原四项不变 |
| simultaneous-mid | 2 | 每拍push与pop，共16拍 | occupancy保持2；输出严格等于先前队列顺序 |
| simultaneous-empty | 0 | 同拍push A和`rd_rdy=1` | 当拍无pop；下一拍`rd_vld=1,rd_dout=A` |
| simultaneous-full | 4 | 同拍push E和pop | 只pop A，E不接受；下一拍occupancy=3 |
| reset-nonempty | 1..4 | 拉低`AXI_RSTn` | 下一观察周期`rd_vld=0,wr_rdy=1`；旧数据不再输出 |

### 8.2 AR/AW SID 表

| Sequence | Pass Criteria |
|---|---|
| push 4 unique SID | slots 0..3依次等于输入SID，第4项后full语义生效 |
| fifth push | 所有`sN_push_rdy=0`，四槽不变 |
| clear slot0/1/2/3 | 仅一个匹配项删除，后续项左移，剩余相对顺序不变 |
| duplicate SID twice | 每次clear只删除最低索引一个；第二副本仍可被membership命中 |
| 3-way push conflict | 来源0获选，来源1/2 ready=0；后续保持请求时分别入表 |
| 3-way clear conflict | 来源0获选，其余本拍不清；三项最终各清一次 |
| SID zero negative | `8'h00`不得被合法流量生成；若注入，checker报非法SID |
| full then clear | clear后occupancy=3，下一合法地址可push恢复到4 |

### 8.3 Default FSM counters

`countW/awlen_reg/countR/arlen_reg` 对LEN 0、1、14、15覆盖。读/写结束时counter回0；LEN=15不得溢出5位寄存器；每个burst的响应数量严格按§5。

## 9. Error Injection

| Error Class | Injection | Expected Response / Pass Criteria |
|---|---|---|
| Unmapped AW | 地址不在三个窗口 | 仅default接受；完成W后1个`BRESP=11` |
| Unmapped AR | 地址不在三个窗口 | 仅default接受；LEN+1个`RRESP=11,RDATA='1` |
| WID target mismatch | AW到S0但WID[3:2]编码S1 | 32周期内S0/S1/S2均不得接受该W；`p_w_matches_aw`报协议错误 |
| Unknown R SID | 未登记SID从真实S返回 | `S_AXI_RREADY`不得完成该beat；32周期内无M_AXI_R handshake |
| Spurious B | 无对应AW的合法MID BID | 当前RTL会按MID路由；`p_b_has_request`必须报错，记录为无硬件保护 |
| Early WLAST | beat数小于AWLEN+1 | default路径打印`Error expecting WLAST`或提前BRESP；正常目标由burst checker报错 |
| Missing WLAST | 达声明长度仍WLAST=0 | default日志必须含`Error expecting WLAST`，仍输出DECERR；正常目标checker报错 |
| AWID/WID mismatch | default写使用不同ID | 日志必须含`AWID:WID mismatch`；BRESP仍为11 |
| VALID early drop | 反压时撤销VALID/改变payload | 对应stable assertion在首次变化周期失败；未握手事务不进scoreboard |
| SID clear without READY | 末beatVALID、最终FIFO满 | `p_sid_clear_on_handshake`失败即暴露已知RTL缺陷；测试不得误判通过 |
| Overlapping windows | 单元配置两个相同base | `p_decode_onehot`失败；配置判非法 |
| Unsupported parameters | 改NUM或非默认ID/SID宽度 | 编译/宽度审计报告所有硬编码不匹配；不得发布为受支持配置 |
| Illegal FSM encoding | force状态为未定义值，仿真专用 | `p_legal_state`同拍或下一拍失败；无恢复要求 |

## 10. Concurrency & Timing Edge Cases

| Case | Stimulus | Pass Criteria |
|---|---|---|
| Different targets same cycle | M0→S0、M1→S1、M2→S2 同拍AW或AR | 三个目标均握手，且SID.MID分别为01/10/11 |
| Same target same cycle | M0/M1/M2 同拍访问S0 | 每拍最多一个S0握手；READY=1持续时3个请求均在3次握手内完成 |
| Read/write parallel | 同一M和同一S同时AW/W与AR/R | 五通道独立计数；读写数据均0 mismatch，无互相阻塞超过资源条件 |
| Back-to-back zero gap | 同端口连续16笔AW/AR，VALID不降 | 每次`VALID&&READY`计一笔；下游顺序与输入握手顺序一致 |
| One-cycle gap | 每笔事务间空1周期 | monitor不得生成空周期事务；实际笔数等于注入笔数 |
| AW/W ordering | W早AW 0..8周期、同拍、W晚0..8周期 | W只有在对应SID登记后目标侧握手；每个AW匹配LEN+1个W beat |
| Multiple outstanding | 同一M发4笔不同ID到不同S | 四项均可登记；第5笔被反压；乱序返回按SID送回同一M |
| Same ID outstanding | 同一M使用相同ID连续2笔 | 记录RTL实际集合语义；若响应无法唯一对应，scoreboard按接受顺序检查并将歧义报告为TOVERIFY风险 |
| R beat interleave | 两个S向同一M交替返回不同ID | 每beat ID/data关联不变；各事务各自LAST位置正确 |
| W beat interleave | 两个M交替向同一S发送不同SID | 每beat目标和SID匹配已登记AW；每个burst beat数独立正确 |
| Push vs clear same cycle | SID表同时有push候选和clear候选 | clear优先导致push ready=0；保持的push在后续周期只登记一次 |
| Reset vs handshake | handshake边沿前后拉低reset | reset epoch前事务被丢弃；reset释放后的首笔事务从空状态开始 |

## 11. Corner Cases

| Area | Values / Scenario | Pass Criteria |
|---|---|---|
| Address boundaries | 每窗口first/last、前一地址、后一地址 | 12个边界向量按§5唯一路由 |
| ID boundaries | original ID 0/15，SID各字段最小/最大合法码 | 返回ID严格为低4位；合法SID非0 |
| Burst length | LEN 0/1/14/15 | beat数1/2/15/16，LAST只在最后一拍 |
| Transfer size | SIZE 0/1/2/7 | 字段透明传递；设计不自行报错或修改 |
| Burst type | BURST 0/1/2/3 | 字段透明传递；保留值3不被硬件拦截 |
| WSTRB | 0、单bit、交替、all-one | 4位逐位透明传递 |
| Data patterns | all-zero、all-one、walking-one、`0xaaaa5555` | W/R数据逐位一致 |
| FIFO occupancy | 0/1/3/4 | ready/valid和边界转换符合§8.1 |
| SID occupancy | 0/1/3/4 | push/clear和第5项反压符合§8.2 |
| Default concurrency | 同时一笔default read和一笔default write | 两个独立FSM同时推进；各自产生正确DECERR响应 |
| READY stall | 0/1/2/5/6/16周期 | payload稳定，释放后无drop/duplicate |
| Reset length | 1/2/5周期低电平 | 异步和同步复位状态均在规定观察点清零 |
| Duplicate SID | 同SID占两个槽 | 单次clear只移除一个最低槽；剩余副本仍命中 |

参数corner仅验证默认配置，因为来源文档明确指出非默认 `NUM_MASTER/NUM_SLAVE/WIDTH_ID/WIDTH_SID` 并非受支持的可缩放契约；随机参数化不增加合法功能覆盖价值，改以§9编译负测覆盖。

## 12. Stress Tests

| Test Name | Category | Scenario | Pressure Point | Duration | Pass Criteria | Failure Indicators |
|---|---|---|---|---:|---|---|
| `stress_all_fifos_saturation` | Buffer saturation | 五通道轮流令30个FIFO达到occupancy=4，保持后排空 | 30×`axi_fifo_sync` | 10,000 cycles | 每组至少一次full；排空后全部expected queue=0，0 overflow/drop/reorder | occupancy>4、payload mismatch、永久VALID |
| `stress_fifo_streaming` | Buffer saturation | mid occupancy持续并行push/pop | FIFO pointers/count | 10,000 cycles | 每逻辑FIFO至少1,000次并行push/pop；scoreboard 0 mismatch | count漂移、重复/丢失 |
| `stress_mtos_all_active` | Arbitration fairness | M0/M1/M2持续访问同一S，AW/W/AR分别执行 | 12个M→S通道仲裁器 | 10,000 cycles/channel | 每个requestor获胜次数>0；READY恒1区间内任意3次握手覆盖三者 | 任一端口饥饿、非one-hot grant |
| `stress_stom_all_active` | Arbitration fairness | S0/S1/S2/default持续向同一M返回B/R | 6个S→M仲裁器 | 10,000 cycles/channel | READY恒1区间内任意4次eligible握手覆盖四来源 | 来源饥饿、payload选错 |
| `stress_sid_full_read` | Resource exhaustion | 反复填满4项AR表，延迟RLAST后释放 | `ar_sid_buffer` | 10,000 cycles | full期间第5个AR不握手；每次释放后32周期内重新接受1项 | occupancy越界、错误SID通行、死锁 |
| `stress_sid_full_write` | Resource exhaustion | 反复填满4项AW表，延迟WLAST后释放 | `aw_sid_buffer` | 10,000 cycles | full/释放行为同读侧；所有W只匹配已登记SID | 未登记W握手、表项泄漏 |
| `stress_backpressure_wave` | Back-pressure propagation | 每64周期轮流阻塞各S READY和各M READY 16周期 | FIFO链、grant WAIT | 10,000 cycles | 上游最终反压；释放后expected/actual队列在256周期内收敛且0 mismatch | payload变化、grant切换、永久堵塞 |
| `stress_default_read_fsm` | FSM stability | 连续1,000笔未命中读，LEN随机0..15 | `STR_*`, countR | 1,000 transactions | 每笔LEN+1个DECERR beat；四状态均覆盖，无非法状态 | beat数/LAST错误、stuck state |
| `stress_default_write_fsm` | FSM stability | 连续1,000笔未命中写，BREADY随机 | `STW_*`, countW | 1,000 transactions | 每笔1个DECERR B；四状态均覆盖，无非法状态 | 多/少响应、stuck state |
| `stress_arbiter_wait_states` | FSM stability | 每次获grant后随机stall 1..32周期 | 五类RUN/WAIT FSM | 1,000 transactions/FSM | WAIT期间grant稳定；ready恢复后2周期内握手 | grant/payload改变、未退出WAIT |
| `stress_full_concurrency` | Multi-interface concurrency | 3M和3S五通道全速、随机目标/ID/LEN | crossbar全路径 | 5,000 cycles | 9条route组合和5通道均命中；0 scoreboard mismatch；无端口永久饥饿 | drop/duplicate/misroute/deadlock |
| `stress_error_under_load` | Error injection under load | 90%合法流量，10%未命中/错误SID/LAST/ID错误 | default与checker | 2,000 cycles | 每个错误由指定DECERR、日志或assertion捕获；合法事务0 mismatch | 静默错误、合法事务受污染 |
| `stress_sid_clear_backpressure` | Known-risk exposure | 出口FIFO满时持续末beatVALID | SID clear路径 | 2,000 cycles | `p_sid_clear_on_handshake`必须捕获当前RTL提前clear；修复后应0失败且SID保持到握手 | 缺陷未被checker发现 |
| `stress_reset_under_load` | Reset/FSM/FIFO | 每100..300周期随机复位1..5周期 | 全部状态结构 | 5,000 cycles | 每次复位后FIFO/SID/grant/FSM复位值全部满足，跨epoch输出0笔 | 旧事务泄漏、X传播 |

不适用项：设计没有pipeline flush/kill输入，故不生成“pipeline flush under load”功能测试；其替代项为 `stress_reset_under_load`，验证唯一全局丢弃机制。

## 13. Performance Validation

架构只给出结构推断，没有签核级频率或固定延迟合同。下列测试负责测量并验证可从RTL明确得到的吞吐上限；测量值单独报告，不把未知目标伪造成通过门槛。

| Test | Preconditions | Measurement | Pass Criteria |
|---|---|---|---|
| `perf_single_target_channel` | FIFO预热、无争用、READY恒1、连续VALID | S0的AW/W/AR和M0的B/R分别统计1000周期握手数 | 稳态任一独立通道不得超过1 beat/cycle；观测平均吞吐和气泡率写入报告 |
| `perf_three_target_parallel` | 三M分别持续访问三个S | 1000周期总握手 | 可观察到同一周期3个不同目标并行握手；报告aggregate beats/cycle |
| `perf_fifo_full_exchange` | FIFO先填满，再同拍持续push/pop | 128周期accepted push/pop | 首个full交换周期push不被接受且occupancy降为3，明确记录1个结构气泡 |
| `perf_route_latency` | 空系统，READY恒1，单笔AW/AR/W/R/B | 从输入握手到对应输出握手逐通道测量 | 每类采集100笔min/avg/max；不得丢失；因规格无固定值，不设周期签核门槛 |
| `perf_arbiter_fairness` | 所有请求持续，READY恒1 | 10,000个eligible握手的各端口计数 | 3路每端口获胜占比在33.3%±1%；4路每来源占比在25%±1% |
| `perf_sid_capacity` | 不返回末beat，连续地址请求 | 成功接受地址数 | AR和AW各最多接受4个SID表登记项；第5项不完成目标侧登记 |

目标时钟频率、端到端最大延迟和保证带宽是规格缺口，不能由RTL仿真签核；需原设计者补充后再增加数值门槛。

## 14. Coverage Goals

### 14.1 Code Coverage Targets

| Metric | Target | Notes |
|---|---:|---|
| Line coverage | ≥95% | 仿真专用、非法参数和不可达防御代码可逐条说明 |
| Branch coverage | ≥95% | 未命中的case/default必须给出不可达证明或补测试 |
| Condition coverage | ≥90% | 地址比较、full/empty、grant、LAST各布尔项独立取真/假 |
| FSM state/transition coverage | 100% legal | 五类RUN/WAIT和default 8个命名状态的全部合法弧 |

### 14.2 Functional Coverage Targets

| Metric | Target | Notes |
|---|---:|---|
| Coverpoints | 100% | §14.3所有非illegal bins命中 |
| Crosses | ≥90% | 宽数据值不做全笛卡尔积；未命中cross需说明 |
| Assertions | 100% exercised | 每条checker至少一次vacuity检查；负测assertion必须观测到预期失败 |

Random suite完成条件：§3每类达到最少事务数，所有非illegal coverpoint为100%，cross coverage≥90%，且连续4小时或额外100,000笔事务无新增覆盖后才可分析剩余洞；这只是覆盖收敛判据，不替代0 scoreboard mismatch。

### 14.3 Functional Coverage Model

| Covergroup | Coverpoint | Bins | Target | Notes |
|---|---|---|---:|---|
| `cg_route_matrix` | master×target×direction | 3×3×{read,write} | 100% | 覆盖18组合 |
| `cg_address_decode` | address region | S0-first/mid/last, S1, S2, gaps, below/above | 100% | 与AW/AR交叉 |
| `cg_default_route` | channel×LEN | AW/AR × 0/1/2..14/15 | 100% | 与DECERR交叉 |
| `cg_sid_map` | target_code×MID×ID | 3×3×{0,1..14,15} | 100% | ID完整16值另设coverpoint |
| `cg_wid_route` | WID target×eligibility | 01/10/11/illegal × hit/miss | 100% | illegal为负测bin |
| `cg_read_flow` | master×target×LEN×response order | 3×3×4 LEN classes×in/out order | ≥90% cross | LEN classes 0,1,2..14,15 |
| `cg_write_flow` | master×target×LEN×WSTRB | 3×3×4×{0,single,partial,all} | ≥90% cross | 数据pattern单独cover |
| `cg_concurrency` | active M count×active S count×RW | 1/2/3 × 1/2/3 × R/W/both | 100% | 全接口active必须命中 |
| `cg_mtos_arb` | channel×request mask×winner | AW/W/AR × 1..7 × M0/M1/M2 | 100% legal | winner必须在mask内 |
| `cg_stom_arb` | channel×request mask×winner | B/R × 1..15 × S0/S1/S2/SD | 100% legal | R真实源需eligible |
| `cg_grant_lock` | channel×stall length | 5通道 × 0/1/2..5/6..15/16+ | 100% | WAIT进入/退出交叉 |
| `cg_fifo` | instance_group×index×occupancy | 10组×3×0/1/2/3/4 | 100% | 代表全部30实例 |
| `cg_fifo_edges` | occupancy×operation | empty/mid/full × push/pop/both | 100% | 满同拍both特殊bin |
| `cg_sid_table` | table×occupancy×operation | AR/AW × 0..4 × push/clear/conflict | 100% | slot cleared 0..3另设bin |
| `cg_sid_eligibility` | table×slot_hit | AR/AW × slot0/1/2/3/miss | 100% | registered delay 1拍 |
| `cg_sid_priority` | operation×request mask×winner | push/clear × 1..7 × 0/1/2 | 100% legal | winner固定最低bit |
| `cg_sid_clear` | table×final_ready×LAST | AR/AW × 0/1 × 0/1 | 100% | ready=0,LAST=1暴露缺陷 |
| `cg_default_read_fsm` | state×transition×LEN class | 4 states、全部合法弧、4 LEN类 | 100% | RREADY stall交叉 |
| `cg_default_write_fsm` | state×transition×LEN class | 4 states、全部合法弧、4 LEN类 | 100% | BREADY stall交叉 |
| `cg_reset` | phase×occupancy×state class | async phase bins × empty/mid/full × idle/wait/response | 100% | 同步模块首edge清零 |
| `cg_backpressure` | channel×stall length×occupancy | 5×5 stall classes×empty/mid/full | ≥90% cross | stall classes同grant lock |
| `cg_burst` | channel×LEN×interleave | R/W × 0/1/2..14/15 × none/two/three | 100% | LAST位置cover |
| `cg_progress` | blocked_resource×release_latency | FIFO/SID/arbiter/default × 0..32 | 100% | >32为illegal timeout |
| `cg_default_diag` | error kind×LEN | missing/early LAST/ID mismatch × 4 LEN类 | 100% | 日志命中计分 |
| `cg_parameter` | configuration | default-supported/nondefault-negative | 100% | 非默认不做功能signoff |
| `cg_overlap_negative` | overlap channel | AW/AR | 100% | 预期assertion failure |
| `cg_scope` | absent feature audit | CSR/CDC/flush/kill/power/ECC/parity | 100% | 静态cover item |
| `cg_observability` | channel×monitor path | 5通道×input/output | 100% | monitor与scoreboard计数一致 |
| `cg_clock_scope` | clocked structure | FIFO/arbiter/default/SID/reorder | 100% | 全部只连接AXI_CLK域 |

### 14.4 Assertion Set

至少实现并覆盖以下命名checker：

- `p_*_stable`：五通道在 `VALID&&!READY` 时payload和VALID稳定。
- `p_decode_onehot`：每个AW/AR最多命中S0/S1/S2/default之一。
- `p_grant_onehot0`：所有M→S/S→M grant one-hot-or-zero。
- `p_w_matches_aw`、`p_r_has_request`、`p_b_has_request`：数据/响应具有对应已接受请求。
- `p_fifo_occupancy_range`：每个FIFO occupancy为0..4，不overflow/underflow。
- `p_sid_occupancy_range`：AR/AW SID occupancy为0..4，合法SID非0。
- `p_order_grant_membership`：`order_grant[N]` 等于前一拍候选SID在四槽中的成员关系。
- `p_sid_clear_on_handshake`：SID只能在完整 `VALID&&READY&&LAST` 后释放；预期当前RTL的反压末beat用例会触发。
- `p_legal_state`：所有命名FSM状态只取文档列出的localparam。
- `p_default_response_count`：default read为ARLEN+1个R，default write为每AW一个B。

任何正向测试 assertion failure、scoreboard mismatch、未知X进入外部有效payload、expected/actual队列非空均为失败；负向测试只允许其测试项明确指定的assertion失败，并必须证明其他checker未被连带污染。

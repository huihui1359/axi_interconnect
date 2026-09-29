# AXI3 Interconnect 验证测试计划

## 1. 测试点梳理思路

本测试计划以当前实际参与编译和仿真的 `rtl/`、`dv/`、`sim/sim.f` 与 `sim/Makefile` 为基线，不把未被当前 filelist 使用的旧 `uvm_tb/` 用例作为“已实现”证据。测试点按以下思路展开：

1. 从 RTL 顶层接口与子模块职责出发，拆分复位、五通道传输、FIFO、地址译码、ID 扩展/还原、outstanding/reorder、默认 Slave 和双向仲裁等功能。
2. 从 AXI3 数据传输规则出发，补充 burst、长度、大小、WSTRB、VALID/READY、LAST、响应、同 ID 保序、不同 ID 乱序、写/读交织和 4 KB 边界等协议场景。
3. 从三主三从互连特性出发，建立 Master × Slave × 读写方向的路由矩阵，并覆盖同一 Slave 竞争、同一 Master 响应竞争、不同 Slave 并行及跨端口同 ID 场景。
4. 从验证环境能力出发，对照 sequence、test、scoreboard、channel checker、outstanding tracker、assertion、functional coverage 和回归入口，判断测试点是否真正落地。
5. “已实现”不仅要求存在激励，还要求存在自动检查；状态同时参考 `sim/work/log` 中截至 2026-09-28 的最近一次仿真结果。

状态标记：

- ✅：已有定向/随机激励和自动检查，且最近日志有通过证据。
- ⚠️：测试与检查已经实现，但当前最近一次仿真失败，或只实现了该测试点的一部分。
- ⬜：当前没有对应测试，或激励/检查不足以证明该测试点。

## 2. 设计与验证基线

| 项目 | 当前基线 |
|---|---|
| 互连规模 | 3 个上游 Master、3 个下游 Slave，另含内部 Default Slave |
| 数据/地址宽度 | 32-bit data、32-bit address、4-bit WSTRB |
| ID | 上游 4-bit ID，下游扩展为 8-bit SID；SID 编码包含目标 Slave、来源 Master 和原 ID |
| Burst | AXI3 FIXED/INCR/WRAP，`AxLEN[3:0]`，最大 16 beats |
| 地址映射 | S0=`0x0000_0000~0x0000_0FFF`；S1=`0x0000_2000~0x0000_2FFF`；S2=`0x0000_4000~0x0000_4FFF`；其余到 Default Slave |
| 缓冲 | AW/W/B/AR/R 两侧均有同步 FIFO，RTL 中实例深度为 4；读写 SID buffer 深度为 4 |
| 检查体系 | 分阶段端到端 checker、Stage6 系统参考模型/scoreboard、逐通道 forwarding checker、outstanding tracker、协议断言、内部 round-robin bind checker |
| 当前回归 | `positive_regress` 接入 27 个测试；最近日志中 25 个通过，2 个失败；6 个 checker/assertion/reference-model 自测通过 |

当前两个已知失败为：

- `axi_stage6_multi_master_write_arb_test`：round-robin `last_winner` 在真正握手前更新，触发 `AXI_STAGE6_ARB_AW_POINTER_CHANGED_WITHOUT_HANDSHAKE`。
- `axi_stage6_default_slave_test`：期望 3 个响应但仅收到 2 个，测试超时。

## 3. 详细测试点

### 3.1 复位与基本连通性

| ID | 测试点与建议激励 | 预期结果/检查内容 | 状态与现有证据 |
|---|---|---|---|
| RST-01 | 上电保持低有效复位至少 2 拍后释放 | Master/Slave 两侧由 DUT 驱动的 VALID/READY 输出在复位期归零；释放后可正常传输 | ✅ 每个现有测试均执行上电复位；`axi_protocol_assertions` 含两侧 reset-output 检查 |
| RST-02 | DUT 空闲时再次拉低并释放复位 | 内部 FIFO、SID buffer、仲裁状态和 outstanding 状态清空，复位后第一笔事务正确 | ⬜ assertion 自测会复位 assertion 状态，但没有针对完整 DUT 的二次复位用例 |
| RST-03 | AW/W/AR/R/B 被阻塞或 FIFO 非空时插入复位 | 所有未完成事务被丢弃且环境同步清理，复位后无陈旧响应、死锁或 X | ⬜ 未实现运行中复位场景 |
| BASIC-01 | M0→S0 单拍全字写，固定 ID/地址/数据/全 WSTRB | AW/W 正确转发，BID 恢复，BRESP/数据一致，无 pending | ✅ `axi_stage1_single_write_test` 通过 |
| BASIC-02 | M0→S0 单拍全字读 | AR 正确转发，RID/RDATA/RRESP/RLAST 正确返回 | ✅ `axi_stage1_single_read_test` 通过 |
| BASIC-03 | 空闲若干周期后发起事务、事务结束后再次空闲 | 不产生伪握手、伪响应或残留 pending | ✅ 各测试结尾检查 checker/driver/monitor/tracker 清空 |

### 3.2 地址译码、路由与 Default Slave

| ID | 测试点与建议激励 | 预期结果/检查内容 | 状态与现有证据 |
|---|---|---|---|
| ROUTE-01 | 3 Master × 3 Slave × 读/写，共 18 个组合 | 每笔请求只到目标物理 Slave，响应只回原 Master，非目标端口无泄漏 | ✅ `axi_stage6_route_matrix_test` 通过，系统 reference model、scoreboard、channel checker 自动比对 |
| ROUTE-02 | 同一 Master 同时访问 S0/S1/S2 | 三个 Slave 可并行接收，响应正确汇聚至原 Master | ✅ 读场景 `axi_stage6_multi_slave_parallel_test` 通过 |
| ROUTE-03 | 同一 Master 同时向 S0/S1/S2 写 | AW/W 分别路由，B 响应正确汇聚，互不阻塞 | ⬜ 现有多 Slave 并行用例只有读 |
| ROUTE-04 | 分别访问每个区域首地址和末地址：`0000/0FFF`、`2000/2FFF`、`4000/4FFF` | 边界地址仍落入正确 Slave | ⬜ 现有 Stage6 路由仅使用各区域内部地址 `0x0100/0x2100/0x4100` |
| ROUTE-05 | 访问区域相邻空洞和典型非法地址，如 `0x1000`、`0x1FFF`、`0x3000`、`0x3FFF`、`0x5000`、高地址 | 不访问 S0/S1/S2，由 Default Slave 处理 | ⚠️ 仅使用 `0x8000` 的 Default 测试已实现，但当前用例失败；空洞/高地址集合未覆盖 |
| ROUTE-06 | 3 Master × Default × 读/写完整矩阵 | 每个 Master 均收到原 ID 对应的 DECERR；写响应 1 个，读响应 beat 数/RLAST 正确 | ⚠️ `axi_stage6_default_slave_test` 只有 2 读+1 写且当前 3 响应仅完成 2 个 |
| ROUTE-07 | 合法映射与 Default 请求并发，并制造响应竞争 | Default 不影响正常 Slave 路由；B/R 仲裁仍正确 | ⬜ 未实现正常 Slave 与 Default 并发竞争 |
| ROUTE-08 | 合法 burst 的最后一个 byte 恰好位于 4 KB 边界前 | 整个 burst 路由到起始地址对应 Slave，不跨界、不拆包 | ⬜ transaction 有“不跨 4 KB”约束，但无定向边界值测试 |
| ROUTE-09 | 负向构造跨 4 KB 的 INCR burst | 协议 checker 报错；该非法输入不作为 DUT 功能正确性判定依据 | ⬜ 当前 assertion 没有 4 KB crossing 检查/自测 |

### 3.3 五通道转发、数据属性与响应

| ID | 测试点与建议激励 | 预期结果/检查内容 | 状态与现有证据 |
|---|---|---|---|
| CH-01 | AW 的 ID、ADDR、LEN、SIZE、BURST 转发 | 除规定的 ID 扩展外，其余 payload 逐字段不变 | ✅ Stage1/2/3 checker 与 Stage6 channel checker 均逐字段比较 |
| CH-02 | W 的 ID、DATA、WSTRB、LAST 转发 | SID 扩展正确，数据/字节使能/尾拍不变 | ✅ 已有 burst 数据逐 beat 比对，但只使用全 WSTRB |
| CH-03 | B 的 ID、RESP 反向转发 | SID 恢复为原 4-bit BID，BRESP 不变且返回原 Master | ✅ OKAY 响应路径在现有写测试中通过 |
| CH-04 | AR 的 ID、ADDR、LEN、SIZE、BURST 转发 | 除规定的 ID 扩展外，其余 payload 逐字段不变 | ✅ 已有端到端及逐通道检查 |
| CH-05 | R 的 ID、DATA、RESP、LAST 反向转发 | SID 恢复，所有 beat 数据/响应/尾拍正确且返回原 Master | ✅ 已有单拍、多拍、乱序读测试通过 |
| CH-06 | `AWSIZE/ARSIZE=0,1,2` 的 byte/halfword/word 传输 | SIZE 和地址原样通过，beat/WSTRB 合法，数据不被修改 | ⬜ 现有定向测试固定 `SIZE=2` |
| CH-07 | 对不同 SIZE 构造对齐和 AXI 允许的非对齐起始地址 | 路由与 payload 转发正确，无错拍 | ⬜ 未实现窄传输和非对齐用例 |
| CH-08 | 覆盖单 bit、低/高半字、交替等合法部分 `WSTRB` | 每拍 WSTRB 和 WDATA 原样到达目标 Slave | ⬜ 现有场景固定 `WSTRB='1` |
| CH-09 | 下游返回 `SLVERR` 的写与读（含中间某个 R beat 为 SLVERR） | 错误响应原样返回正确 Master，不改变 ID、beat 数和 RLAST | ⬜ reactive sequence 支持配置响应码，但现有用例只使用 OKAY；Default 使用 DECERR |
| CH-10 | 非法/未映射单拍读写返回 DECERR | BRESP/RRESP=`DECERR`，ID/beat 数正确 | ⚠️ checker 已实现 DECERR 检查，但 `axi_stage6_default_slave_test` 当前失败 |
| CH-11 | AW 与 AR 同时有效，读写并行 | 读写路径独立推进，响应均正确 | ✅ `axi_stage2_read_write_parallel_test` 通过；`axi_stage3_mixed_rw_test` 覆盖并发 outstanding |

### 3.4 Burst、LAST 与通道时序

| ID | 测试点与建议激励 | 预期结果/检查内容 | 状态与现有证据 |
|---|---|---|---|
| BURST-01 | FIXED 写 burst，长度 1~16 beats | LEN、数据、WSTRB、WLAST、B 响应正确 | ✅ `axi_stage2_burst_write_test` 覆盖 1~16 |
| BURST-02 | INCR 写 burst，长度 1~16 beats | 同上 | ✅ `axi_stage2_burst_write_test` 覆盖 1~16 |
| BURST-03 | WRAP 写 burst，合法长度 2/4/8/16 | WRAP 属性和完整数据转发正确 | ✅ `axi_stage2_burst_write_test` 覆盖合法长度 |
| BURST-04 | FIXED 读 burst，长度 1~16 beats | 返回 LEN+1 个 beat，最后一拍 RLAST | ✅ `axi_stage2_burst_read_test` 覆盖 1~16 |
| BURST-05 | INCR 读 burst，长度 1~16 beats | 同上 | ✅ `axi_stage2_burst_read_test` 覆盖 1~16 |
| BURST-06 | WRAP 读 burst，合法长度 2/4/8/16 | WRAP 属性和完整响应转发正确 | ✅ `axi_stage2_burst_read_test` 覆盖合法长度 |
| BURST-07 | 在 M0/M1/M2 与 S0/S1/S2 路由矩阵上重复多拍 burst | 仲裁、SID、FIFO 和路由在多 beat 条件下均正确 | ⬜ Stage2 多拍只覆盖 M0→S0；Stage6 路由矩阵均为单拍 |
| BURST-08 | W 在 AW 之前完整到达、AW 先到、AW/W 同拍 | 三种合法独立通道顺序均不丢失、不串单 | ✅ `axi_stage2_aw_w_order_test` 三种场景通过 |
| BURST-09 | W beat 之间插入固定 gap；R beat 之间插入固定 gap | gap 被允许，端到端数据与 beat 数保持正确 | ✅ `axi_stage2_delay_gap_test` 显式检查 W gap `{1,3,2}`、R gap `{3,1,2}` |
| BURST-10 | WLAST/RLAST 在期望尾拍出现 | 不早、不晚，响应仅在完整事务后产生 | ✅ burst 回归通过，协议 assertion 持续检查 |
| BURST-11 | 负向：WLAST/RLAST 提前、缺失、超拍 | assertion 分别报告 EARLY/MISSING/COUNT_EXCESS | ✅ `axi_protocol_assertions_selftest` 已注入并通过 |
| BURST-12 | 负向：非法 WRAP 长度/不对齐、保留 BURST=`2'b11`、超出总线宽度 SIZE | 协议 checker 明确报错 | ⬜ transaction 约束会阻止部分非法激励，但 assertion 尚无对应规则与自测 |

### 3.5 READY 背压、稳定性与 FIFO

| ID | 测试点与建议激励 | 预期结果/检查内容 | 状态与现有证据 |
|---|---|---|---|
| FLOW-01 | 分别让 AW/W/B/AR/R 出现长时间 READY=0 | 五通道均实际观察到 stall，最终无丢失/重复/死锁 | ✅ `axi_stage2_channel_stall_test` 对五通道做显式 stall 观测并通过 |
| FLOW-02 | 五通道 READY 随机延迟 0~100 cycle，配合随机 W/R beat gap | 事务最终完成，payload 稳定，scoreboard 无误 | ✅ `axi_stage2_ready_random_smoke_test` 通过 |
| FLOW-03 | `VALID=1 && READY=0` 时保持 AW/W/B/AR/R 的 VALID 与 payload | 直到握手前均稳定 | ✅ `axi_protocol_assertions` 对五通道启用稳定性检查；stall 回归通过 |
| FLOW-04 | FIFO 空时读、满时写 | 空时不输出有效数据，满时反压上游，不 underflow/overflow | ⬜ RTL 有 full/empty 逻辑，但无独立或端到端边界定向测试 |
| FLOW-05 | 每个通道 FIFO 连续写满 4 项、保持满、释放 1 项再继续写 | READY 在满时拉低，释放后恢复；顺序和数据保持 | ⚠️ outstanding 测试会达到深度 4，但未对 AW/W/B/AR/R 两侧所有 FIFO 做逐个容量检查 |
| FLOW-06 | FIFO 同拍 push/pop、读写指针多次回绕 | 计数不跳变，数据不丢失/重复，full/empty 正确 | ⬜ 未实现 FIFO wrap-around/同拍边界专项测试 |
| FLOW-07 | 多端口同时背压：3 Master/3 Slave 上分别随机 AW/W/AR/B/R READY | 各端口相互独立，无全局阻塞或错误串扰 | ⬜ Stage6 只在个别仲裁测试设置固定延迟，尚无系统级多端口随机背压回归 |

### 3.6 Outstanding、乱序、保序与交织

| ID | 测试点与建议激励 | 预期结果/检查内容 | 状态与现有证据 |
|---|---|---|---|
| ORD-01 | 写 outstanding 深度依次为 1/2/3/4，并额外提交第 depth+1 笔 | 峰值准确达到配置深度，超额请求被节流，全部响应后归零 | ✅ `axi_stage3_outstanding_write_test` 通过并交叉检查 driver/checker/上下游 tracker 峰值 |
| ORD-02 | 读 outstanding 深度依次为 1/2/3/4，并额外提交第 depth+1 笔 | 同上 | ✅ `axi_stage3_outstanding_read_test` 通过 |
| ORD-03 | 4 笔不同 ID 写事务按不同于请求的顺序返回 B | 不同 ID 允许乱序；BID/数据上下文匹配正确 | ✅ `axi_stage3_write_ooo_test` 通过并要求观察到 reorder |
| ORD-04 | 4 笔不同 ID 读事务按不同于请求的顺序返回 R burst | 不同 ID 允许乱序；每个 burst 内 RID/beat/RLAST 正确 | ✅ `axi_stage3_read_ooo_test` 通过并要求观察到 reorder |
| ORD-05 | 相同完整 ID 的多笔写/读同时 outstanding | 同 ID 响应保持请求顺序，不把同一 ID 的上下文串错 | ✅ `axi_stage3_same_id_order_test` 及 outstanding same-ID 子场景通过 |
| ORD-06 | 读写各 4 笔并行 outstanding，混合相同/不同 ID | 读写独立，允许不同 ID 乱序，同 ID 仍保序 | ✅ `axi_stage3_mixed_rw_test` 通过 |
| ORD-07 | outstanding + AW/W/AR/B/R 随机 backpressure + beat gap | 达到深度 4且完成乱序，最终所有状态清空 | ✅ `axi_stage3_outstanding_stall_test` 通过 |
| ORD-08 | 3 个 Master 使用相同本地 4-bit ID 访问同一 Slave | 扩展 SID 区分来源 Master，响应不串端口 | ✅ `axi_stage6_cross_master_same_id_test` 通过 |
| ORD-09 | 3 Master 各发 4 笔、跨 3 Slave 的读 outstanding | 12 笔请求正确路由和返回，无跨端口串扰 | ✅ `axi_stage6_multiport_outstanding_test` 通过 |
| ORD-10 | 3 Master 各发多笔、跨 3 Slave 的写 outstanding | AW/W/B 在多端口高压力下正确，深度限制有效 | ⬜ Stage6 multiport outstanding 当前仅覆盖读 |
| ORD-11 | AXI3 W 数据交织：同一 Master 的不同 WID 在 beat 间交替 | WID 对应的 AW 上下文正确，分别在各自尾拍 WLAST | ⬜ Master driver 当前按一个完整 W burst 连续发送，不能产生 beat 级 W interleaving |
| ORD-12 | R 数据交织：同一 Master 的不同 RID 在 beat 间交替 | 每个 RID 独立计数与 RLAST，数据归属正确 | ⬜ Slave driver 当前按完整 R burst 发送，未生成 beat 级 R interleaving |
| ORD-13 | SID buffer 满 4 项，同时发生清除与新事务进入 | 可接受能力与顺序正确，不错误反压、不漏记 SID | ⬜ 未实现 SID buffer 满边界/同拍 push-clear 专项测试 |

### 3.7 ID 编码、恢复和异常 ID

| ID | 测试点与建议激励 | 预期结果/检查内容 | 状态与现有证据 |
|---|---|---|---|
| ID-01 | 对 S0/S1/S2 的合法请求检查 4-bit MID→8-bit SID | `SID={slave_tag, master_tag, original_id}`，物理 Slave tag 与地址一致 | ✅ Stage3/6 reference model、protocol assertion、route matrix 已检查 |
| ID-02 | 返回 B/R 时检查 8-bit SID→原 Master 和原 4-bit ID | 根据 SID master tag 路由，向上游只恢复低 4-bit 原 ID | ✅ route matrix、cross-master same-ID、system scoreboard 已通过 |
| ID-03 | 4 个 transaction tag 在同一路由上分别进行读/写 | 所有 tag 都能独立匹配和返回 | ✅ `axi_stage6_id_matrix_test` 覆盖 M0→S0 的 4 个 tag 并通过 |
| ID-04 | 在所有 Master × Slave 上覆盖全部 4 个 transaction tag | ID 编码矩阵无遗漏 | ⬜ route matrix 每条路径只使用单个 tag，ID matrix 只覆盖 M0→S0 |
| ID-05 | WID 高位目标编码与 AWADDR 目标一致 | W 数据只进入对应 AW 所在 Slave | ✅ 正向测试遵守并由 protocol assertion 检查 route/tag 一致性 |
| ID-06 | 负向：AWADDR 与 AWID/WID 的 slave tag 不一致 | assertion 报 route/tag mismatch，不能静默送往错误 Slave | ✅ `axi_stage6_protocol_assertions_selftest` 已验证非法 master/slave tag 与 route mismatch 检查 |
| ID-07 | 负向：没有 outstanding 上下文的 BID/RID，或 burst 中途改变 WID/RID | assertion 报 causality/no-pending/ID-stable 错误 | ✅ `axi_stage3_protocol_assertions_selftest` 已注入并通过 |
| ID-08 | 向完整 DUT 注入不存在于 SID buffer 的下游 BID/RID | DUT 不把响应错误转发给任何 Master，checker 给出明确错误且系统不永久死锁 | ⬜ 仅有 assertion 单元自测，没有完整 DUT 负向注入用例 |

### 3.8 仲裁、并发与公平性

| ID | 测试点与建议激励 | 预期结果/检查内容 | 状态与现有证据 |
|---|---|---|---|
| ARB-01 | M0/M1/M2 同时向同一 Slave 发读请求 | AR grant one-hot，三笔均获服务并正确返回 | ✅ `axi_stage6_multi_master_read_arb_test` 通过 |
| ARB-02 | M0/M1/M2 同时向同一 Slave 发写请求并阻塞 AW/W | AW/W grant 稳定，三笔均获服务并正确返回 | ⚠️ `axi_stage6_multi_master_write_arb_test` 已实现但失败，确认 round-robin 指针提前更新 RTL bug |
| ARB-03 | S0/S1/S2 同时向同一 Master 返回 R | R grant one-hot，响应不串单，背压时 winner 保持 | ✅ `axi_stage6_response_arb_test` 通过 |
| ARB-04 | S0/S1/S2 同时向同一 Master 返回 B | B grant one-hot，BID/BRESP 正确 | ⬜ 当前 response arbitration 用例只有读响应 |
| ARB-05 | 单请求者分别覆盖 AW/W/AR/B/R | 唯一 requester 立即获得 grant，无无谓气泡 | ⚠️ 被大量功能测试间接覆盖，但没有对五类内部 grant 的专项检查 |
| ARB-06 | 两路/三路持续请求至少多个轮次 | 服务次序严格 round-robin，任一持续 requester 在有界周期内获服务，无饥饿 | ⬜ 当前用例每个竞争者仅一笔，不能证明持续公平性/最大等待界限 |
| ARB-07 | grant 后 READY=0 多拍，期间加入/撤销其他请求 | 实际 grant 和 payload 来源保持；指针仅在握手后更新 | ⚠️ bind checker 已实现且自测通过，但当前 RTL 在 AW 场景违反该规则 |
| ARB-08 | Default 与 S0/S1/S2 响应同时竞争同一 Master | 四输入 B/R 仲裁顺序、one-hot 和反压稳定正确 | ⬜ 未实现包含 Default 的四路响应竞争 |
| ARB-09 | AW、W、AR 仲裁同时活跃；B、R 仲裁也同时活跃 | 五个独立仲裁器互不干扰，无组合串扰/死锁 | ⬜ random smoke 有轻量并发，但无明确同步竞争与仲裁结果检查 |

### 3.9 协议断言与负向测试

| ID | 测试点与建议激励 | 预期结果/检查内容 | 状态与现有证据 |
|---|---|---|---|
| PROTO-01 | 五通道仅以 `VALID && READY` 计数一次传输 | checker/monitor 不重复、不漏计 | ✅ 所有 monitor/checker 按握手采样，正向回归通过 |
| PROTO-02 | B 在完成对应 WLAST 之前出现 | 报 `B_CAUSALITY` | ✅ assertion 自测通过 |
| PROTO-03 | R 没有对应 AR，或 B 没有对应已完成写 | 报 causality/no-pending | ✅ Stage3 assertion 自测通过 |
| PROTO-04 | outstanding 数超过 4 | 报 outstanding overflow | ✅ Stage3 assertion 自测通过；正向用例验证第 5 笔被节流 |
| PROTO-05 | 相同 ID 的后发写响应先返回 | 报 same-ID order 违规 | ✅ Stage3 assertion 自测通过 |
| PROTO-06 | 控制或有效 payload 含 X/Z | assertion 报错 | ⚠️ RTL 两侧均已绑定 X 检查，但自测只定向验证 AW payload X，未逐通道验证 |
| PROTO-07 | AW/W/B/AR/R stall 期间改变 payload | 分别触发各通道稳定性 assertion | ⚠️ 五通道 assertion 均已实现，单元自测只主动破坏 AW；其余由正向 stall 场景间接验证不报错 |
| PROTO-08 | 非法 ID tag、物理 Slave tag 与端口不符、地址路由与 tag 不符 | assertion 给出明确分类错误 | ✅ Stage6 assertion 自测通过 |
| PROTO-09 | round-robin grant 非 one-hot、无 request 获 grant、顺序错误、stall 切换、指针更新时机错误 | bind checker 报对应仲裁错误 | ✅ checker 与 `axi_stage6_arbiter_assertions_selftest` 已实现；同时已发现真实 RTL bug |

### 3.10 随机、覆盖率与回归闭环

| ID | 测试点与建议激励 | 预期结果/检查内容 | 状态与现有证据 |
|---|---|---|---|
| COV-01 | Master × Slave/Default × Read/Write 功能覆盖 | 3×4×2 路由交叉全部命中 | ⚠️ `axi_system_coverage` 已实现该 cross；正常 3×3×2 已命中，但 Default 只有 3 个组合被激励且用例当前失败 |
| COV-02 | burst type × length × direction × port 路由覆盖 | FIXED/INCR/WRAP、1~16、读写及各路由均可量化关闭 | ⬜ 当前 functional coverage 没有 burst/length coverpoint |
| COV-03 | SIZE × alignment × WSTRB 覆盖 | 窄传输、对齐/非对齐和合法 byte lane 组合可量化 | ⬜ 未实现对应 covergroup |
| COV-04 | ID × outstanding depth × same/different ID × reorder 覆盖 | 深度 1~4、同 ID 重叠、不同 ID 乱序全部命中 | ⬜ checker 有计数器，但没有完整 functional coverage cross |
| COV-05 | channel × stall length、FIFO occupancy/full/empty、同时 push/pop 覆盖 | 每通道关键流控状态均命中 | ⬜ 未实现 occupancy/backpressure functional coverage |
| COV-06 | arbitration requester pattern × winner × stall × round index 覆盖 | 单路/双路/三路/四路竞争和轮询顺序可量化 | ⬜ 仅有 assertion，无仲裁 functional coverage |
| COV-07 | OKAY/SLVERR/DECERR × B/R × port 覆盖 | 支持的响应类型和路径全部命中 | ⬜ 未实现响应 coverpoint，SLVERR 尚无测试 |
| COV-08 | RTL code coverage 采集与报告 | statement/branch/condition/toggle/FSM 数据可生成并设置关闭目标 | ⚠️ Makefile 已支持 `cov=y` 和 `cov_report`，当前仓库未见本轮 UCDB/覆盖率关闭结果 |
| RAND-01 | 3 Master × 3 Slave 的轻量随机单拍读写 | 随机 ID/数据/方向下 reference model/scoreboard 无误 | ✅ `axi_stage6_random_smoke_test` 通过，但每个 Master×Slave 仅一笔 |
| RAND-02 | 长时间约束随机：burst、SIZE、WSTRB、路由、outstanding、乱序响应、五通道随机背压 | 无死锁、无 pending、断言/scoreboard 全清，覆盖率持续增长 | ⬜ 当前没有系统级长随机压力测试 |
| REG-01 | Stage1/2/3/6 正向回归 | 全部测试出现 `AXI_TC_PASS`，UVM_ERROR/FATAL 均为 0 | ⚠️ 27 个已接入，最近 25 PASS；写仲裁和 Default Slave 两项失败 |
| REG-02 | assertion/reference-model 自测回归 | 故障注入能被 checker 捕获，自测输出专用 PASS marker | ✅ 6 个自测目标最近均通过 |

## 4. 建议的优先级

1. **P0：先修复当前红项**：round-robin 指针更新时机和 Default Slave 丢响应问题，恢复 `positive_regress` 全绿。
2. **P0：补关键功能空洞**：地址首尾边界、Default 完整矩阵、跨端口多拍 burst、部分 WSTRB、窄传输/非对齐、SLVERR 传播。
3. **P1：补高压力顺序场景**：多端口写 outstanding、W/R beat 交织、SID buffer/FIFO 满边界、持续 round-robin 公平性、四路响应竞争。
4. **P1：补鲁棒性场景**：运行中复位、多端口随机背压、非法 4 KB crossing 与非法 burst 属性的 assertion 负向测试。
5. **P2：覆盖率闭环**：增加 burst/length/size/ID/outstanding/arbitration/response/FIFO covergroup，执行带 code coverage 的多 seed 回归并给出关闭报告。

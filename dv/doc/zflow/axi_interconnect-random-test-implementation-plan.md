# AXI Interconnect 随机测试用例分阶段实施计划

**Author**: ?, Codex, ?
**Created**: 2026-10-21 23:11
**Current Version**: v1.0

**Version Changelog**:
- **v1.0** (2026-10-21 23:11): 建立 constrained-random 测试的分阶段实施路线，定义基础类复用方式、基础设施前置条件、24 个随机测试的阶段归属、准入/退出标准及回归策略。

---

## 1. 目的与适用范围

本文用于指导 [axi_interconnect-testplan.md](./axi_interconnect-testplan.md) 中 constrained-random 测试用例的设计、实现、评审和回归接入。本文不替代 testplan；testplan 定义需要验证的功能、随机维度、最小事务数和 pass criteria，本文定义这些要求应以什么顺序落地，以及每类测试应复用哪一层验证基础设施。

实施目标如下：

- 最大化复用现有 UVM agent、sequencer、reactive sequence、reference model、scoreboard、checker 和 assertion。
- 通过 `axi_cr_cfg`、`axi_cr_base_vseq` 和 `axi_cr_base_test` 集中处理公共配置、连接、并行调度、随机反压、完成判定和 watchdog。
- 具体测试类原则上只描述场景差异，不重复 env 例化、sequencer 连接和通用结束检查。
- 不以“测试类可编译”作为完成标准；只有满足 testplan 的全部刺激维度、自动检查、最小规模和 coverage 要求后，测试才能标记为 Implemented。
- 对负向流量、已知 RTL 缺陷和预期 assertion 分别建立明确的判定机制，禁止通过屏蔽全局错误获得假通过。

## 2. 已确认的协议和测试约定

### 2.1 ID 与路由语义

- 上游读请求的 4 位 original ID 是不透明字段，合法取值为完整 `0..15`；AR 路由由地址窗口决定，`ARID[3:2]` 不参与目标选择。
- 下游读 SID 应按 `{target_code, master_code, original_id}` 编码，返回上游时恢复低 4 位 original ID。
- 写数据路由由 `WID[3:2]` 决定。正向写流量必须保证该字段与 AW 地址选择的目标一致。
- 地址合法但 `WID[3:2]` 错误的事务不等同于 default route。DUT 不会自动为该错误返回 DECERR；负向测试应检查规定观察窗口内没有错误目标的 W handshake，而不能等待正常 B response。
- 未命中地址窗口的 AW/AR 属于 default route，按 testplan 单独检查 DECERR、beat 数、返回 ID 和 default FSM 行为。

### 2.2 当前 CR 基础框架的安全默认值

当前基础框架默认配置为：

- 仅生成 S0/S1/S2 三个合法地址窗口的正向事务。
- 读 ID 在 `0..15` 中随机；写 ID 的高两位与目标 Slave 编码一致。
- 单 beat，读写 outstanding 均为 1。
- 每个 Master 关闭 request prefetch，避免下一笔 W 在其 AW 上下文建立前误命中旧 SID。
- 对 Master 侧 BREADY/RREADY 和 Slave 侧 AWREADY/WREADY/ARREADY 施加随机有限延迟。
- default route、非法 WID 和 expected-error 流量默认禁止。

这些限制是基础设施成熟度约束，不是最终 testplan 范围。派生测试只有在对应前置能力完成后才能解除限制。

## 3. 基础类职责与复用规则

### 3.1 `axi_cr_cfg`

`axi_cr_cfg` 是随机场景的唯一公共配置入口，负责：

- 总事务数以及 Master、目标、读写方向的权重。
- LEN、burst、SIZE、请求延迟、W beat gap、READY 延迟和响应延迟。
- 最大读写 outstanding、request prefetch 和无进展 watchdog。
- default、非法 WID 等场景开关。
- plusarg 覆盖、配置合法性检查和配置打印。

具体测试应重写 `axi_cr_base_test::configure_cr_cfg()`，不要在 `run_phase()` 中零散修改同一组参数。

```systemverilog
class tp_example_random extends axi_cr_base_test;
  `uvm_component_utils(tp_example_random)

  function new(string name = "tp_example_random",
               uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual function void configure_cr_cfg();
    cr_cfg.transaction_count = 10_000;
    cr_cfg.read_weight       = 1;
    cr_cfg.write_weight      = 1;
    cr_cfg.route_weight[0]   = 1;
    cr_cfg.route_weight[1]   = 1;
    cr_cfg.route_weight[2]   = 1;
  endfunction
endclass
```

### 3.2 `axi_cr_op` 与 `axi_m_cr_seq`

- `axi_cr_op` 生成一笔完整事务意图，包括源 Master、目标、方向和随机化后的 request item。
- 通用正向约束放在 `axi_cr_op`；只属于单个场景的约束应由派生 operation 或场景级 plan builder 实现。
- `axi_m_cr_seq` 只负责将已经规划好的 request 投递到指定 Master sequencer，不负责选择目标或修改场景分布。

### 3.3 `axi_cr_base_vseq`

`axi_cr_base_vseq` 负责：

- 在发送前建立全局事务计划，使每个 Slave responder 的期望请求数可预测。
- 按配置权重选择 Master、目标和读写方向。
- 并行启动三个 Master producer，并将 sequence 驱动到对应的 `m_seqr[]`。
- 复用 `axi_s_stage6_reactive_seq` 在 `s_seqr[]` 上产生响应。
- 将全局完成判定交给 base test 的 scoreboard/watchdog，避免 responder 因缺失请求永久阻塞 vseq。

当测试需要脚本化同拍竞争、指定乱序响应、非法 SID/WID 或 reset 注入时，应派生专用 vseq，而不是把大量测试特例加入通用 `body()`。

### 3.4 `axi_cr_base_test`

`axi_cr_base_test` 统一负责：

- 创建、校验和打印 `axi_cr_cfg`。
- 将 outstanding/prefetch 配置传递给 Master agent。
- 配置五类 READY 的随机有限延迟。
- 创建 `axi_cr_base_vseq` 并传递配置。
- 根据 scoreboard 匹配数判断完成，并在无进展时报告 expected、matched 和 pending 状态。
- 复用 `axi_stage6_base_test` 的最终 mismatch、pending、tracker 和 agent drain 检查。

只有端到端、正常完成且可由通用 scoreboard 预测的场景才直接继承该类。内部结构测试、reset 中止测试和预期错误测试应使用专项 base test 或扩展完成协议。

## 4. 分阶段实施路线

### Phase 0：公共基础设施闭环

目标是在增加正式随机测试类之前，保证基础框架对 testplan 的合法流量不会产生误报或死锁。

必须完成：

1. 修正 Stage 6 读通道 ID assertion：上游 4 位 ARID/RID 允许 `0..15`；下游 8 位 SID 只检查新增 target/master tag 和 original ID 保留关系。
2. 修正 Master driver 的 AW/W 上下文同步，使 prefetch 和多 outstanding 下，W 不能错误消费旧 SID，也不能越过尚未建立的对应 AW 上下文。
3. 将 Master/Slave monitor 的活动 burst 状态从单一全局状态升级为满足 AXI3 ID interleave 的 per-ID/per-context 跟踪。
4. 建立统一 seed、最终配置、事务计数和失败上下文日志；失败必须能够用 seed 重现。
5. 定义 expected-error API，区分“预期协议拒绝”“预期 assertion”“普通 UVM_ERROR”和“已知缺陷 expected-fail”。
6. 明确 default read/write 的 RTL 当前行为，并使 reference model、scoreboard 和 responder 对 DECERR 的预测一致。
7. 为 reset 测试提供可由 vseq 控制的 reset API，并使 scoreboard/reference model 支持 epoch 清理。

退出条件：

- 100～1,000 笔合法单 beat 读写混合 smoke 在多个 seed 下 0 mismatch、0 unexpected error、0 pending。
- 读 original ID `0..15` 至少各命中一次且 assertion 无误报。
- 开启 prefetch 后的受控多 outstanding smoke 不发生 AW/W 上下文错配。
- 所有失败日志包含 test、seed、有效 cfg、未完成 channel/ID 和 pending 摘要。

### Phase 1：合法端到端随机流量

本阶段优先验证基础类复用和黑盒端到端数据通路，不包含 default、非法 ID、reset 和白盒内部状态。

候选正式测试：

- `tp_sid_random`
- `tp_backpressure_random`
- `tp_progress_random`
- `tp_concurrency_random`

注意：只有覆盖 testplan 中规定的全部维度后才使用正式 `tp_*` 名称。在基础设施尚未支持全部要求时，只运行 `axi_cr_base_test` 或显式命名为 smoke 的临时场景，不得将部分实现宣称为对应 testplan 测试完成。

退出条件：

- 每项达到 testplan 的最小事务数。
- scoreboard、channel checker、outstanding tracker 和 protocol assertion 全部清空且无 unexpected error。
- `master × route × direction × original_id` 等本阶段相关 coverage 达到预定目标。
- 有限 backpressure 释放后满足 progress watchdog，不出现 drop、duplicate 或永久阻塞。

### Phase 2：地址边界与 default 路径

本阶段在 default transaction model 和 DECERR checking 完成后实施：

- `tp_route_matrix_random`
- `tp_address_random`
- `tp_default_random`
- `tp_default_read_random`
- `tp_default_write_random`

关键要求：

- `tp_route_matrix_random` 和 `tp_address_random` 必须包含 testplan 规定的 default 比例，不能只覆盖三个合法窗口。
- 地址生成器必须显式覆盖三个窗口的首地址、末地址、边界内外 ±1 字节以及随机 hole。
- default 请求不得泄漏至 S0/S1/S2。
- default read 检查每个 beat 的全 1 数据、DECERR、RLAST 和返回 ID。
- default write 检查 W beat 数、WLAST、单个 DECERR B response 和 BID。
- default FSM 的状态和合法状态弧应由 coverage/assertion 检查，不依赖波形人工确认。

### Phase 3：outstanding、burst interleave 与 WID 负向流量

本阶段依赖 Phase 0 的 driver/monitor 上下文升级：

- `tp_read_outstanding_random`
- `tp_write_outstanding_random`
- `tp_wid_random`
- `tp_burst_interleave_random`

关键要求：

- 支持每个 Master 最多 4 个 outstanding，并记录实际达到的最大深度。
- read original ID 继续覆盖完整 `0..15`；不得为迁就旧 assertion 而限制高两位。
- 写正向流量保持 `WID[3:2]` 与目标一致；错误或未登记 WID 使用独立的 no-handshake 观察器。
- checker 按 SID/ID 维护 beat queue，检查 data、WSTRB、RESP、beat count 和 LAST。
- 响应乱序必须由显式 responder 策略生成和记录，而不是依赖仿真调度偶然形成。
- 同 ID 保序与不同 ID 允许乱序分别统计 coverage。

### Phase 4：仲裁和内部缓冲结构专项随机测试

本阶段不能只依靠普通端到端随机事务，需要脚本化竞争源、白盒 bind checker 或独立结构模型：

- `tp_mtos_arb_random`
- `tp_stom_arb_random`
- `tp_grant_lock_random`
- `tp_fifo_random_pressure`
- `tp_fifo_edge_random`
- `tp_sid_table_random`
- `tp_sid_membership_random`
- `tp_sid_priority_random`
- `tp_sid_clear_random`

实施原则：

- 仲裁测试显式构造单、双、三/四路持续 eligible 请求，按 testplan 检查 one-hot、锁存稳定性和服务窗口。
- FIFO 使用独立 SV queue 预测 push/pop、occupancy 和 payload；覆盖 30 个逻辑 FIFO 组以及 empty/full 同拍操作。
- SID table 使用独立集合/有序队列模型检查容量、membership、压紧、重复 ID 和固定优先级。
- 内部层次信号只用于白盒 assertion/coverage，端到端数据正确性仍由独立模型判定。
- `tp_sid_clear_random` 必须把末 beat 阻塞在最终 FIFO 前，当前 RTL 若提前清除 SID，应归类为已知缺陷或 expected-fail，不得静默通过。

### Phase 5：reset 与诊断负向测试

本阶段实现：

- `tp_reset_random_phase`
- `tp_default_error_random`

关键要求：

- reset 可在 idle、请求已接受、FIFO 非空、burst 中途、default FSM WAIT/RSP/END 等状态随机进入。
- scoreboard 和 reference model 使用 epoch；reset 前未完成 expectation 被明确丢弃，reset 后重新计数。
- 检查 reset 后 FIFO、SID table、arbiter 和 default FSM 状态，无 reset 前 payload 泄漏。
- default diagnostic 注入包含早/晚/缺失 WLAST 和 AWID/WID mismatch。
- 预期诊断使用结构化事件或受控 report catcher 计数；不能只通过字符串人工搜索日志。

## 5. 24 个随机测试的阶段和基类映射

| Test | Phase | 推荐实现形态 | 主要前置依赖 |
|---|---:|---|---|
| `tp_route_matrix_random` | 2 | `axi_cr_base_test` 派生 + default 扩展 | default model、地址分布、SID coverage |
| `tp_address_random` | 2 | `axi_cr_base_test` 派生 + boundary op | 边界地址生成、default checking |
| `tp_default_random` | 2 | default CR 专项 vseq/test | default read/write transaction model |
| `tp_sid_random` | 1 | 直接派生 `axi_cr_base_test` | 读 ID assertion 修正、SID coverage |
| `tp_wid_random` | 3 | 正向 CR + 负向 WID observer | AW/W 同步、no-handshake checker |
| `tp_read_outstanding_random` | 3 | outstanding 专项 vseq | per-ID monitor、乱序 responder |
| `tp_write_outstanding_random` | 3 | outstanding 专项 vseq | AW/W 上下文、per-ID monitor |
| `tp_mtos_arb_random` | 4 | 脚本化 contender vseq | arbiter bind checker、服务窗口模型 |
| `tp_stom_arb_random` | 4 | 脚本化 responder vseq | 四路响应源、default source |
| `tp_grant_lock_random` | 4 | channel/arbiter 专项测试 | grant/payload snapshot checker |
| `tp_fifo_random_pressure` | 4 | 白盒结构模型 + E2E traffic | occupancy 可观察性、30 组覆盖 |
| `tp_fifo_edge_random` | 4 | FIFO 单元/绑定专项测试 | push/pop 独立 queue model |
| `tp_sid_table_random` | 4 | SID 专项模型 | slot/occupancy 可观察性 |
| `tp_sid_membership_random` | 4 | SID 专项模型 | hit/miss 候选注入 |
| `tp_sid_priority_random` | 4 | SID 专项模型 | 多路同拍 push/clear 控制 |
| `tp_sid_clear_random` | 4 | SID backpressure 专项测试 | handshake-based shadow table |
| `tp_default_read_random` | 2 | default read 专项 vseq | DECERR beat model、FSM coverage |
| `tp_default_write_random` | 2 | default write 专项 vseq | DECERR write model、FSM coverage |
| `tp_reset_random_phase` | 5 | reset-aware base test/vseq | reset API、epoch scoreboard |
| `tp_backpressure_random` | 1 | `axi_cr_base_test` 派生 | stall bucket coverage |
| `tp_burst_interleave_random` | 3 | burst/interleave 专项 vseq | per-ID beat tracking |
| `tp_progress_random` | 1 | `axi_cr_base_test` 派生 + channel watchdog | 有限 stall 控制、ID/channel 诊断 |
| `tp_concurrency_random` | 1 | 多端口 CR vseq | 并发活动度控制和 coverage |
| `tp_default_error_random` | 5 | expected-error 专项测试 | report catcher、诊断事件模型 |

## 6. 单个测试的标准实施流程

每个随机测试按以下顺序实现：

1. 从 testplan 提取 Test、Feature ID、随机维度、约束比例、最小事务数、pass criteria 和 covergroup。
2. 判断能否直接复用 `axi_cr_base_test`；若需要 reset、非法输入、白盒状态或脚本化响应，则先定义最小专项扩展。
3. 在 cfg 中表达场景差异；仅在 cfg 无法表达事务相关约束时派生 operation/vseq。
4. 在编码前定义 reference/checker 如何判定每一条 pass criterion，禁止仅依赖仿真结束和无 fatal。
5. 增加场景专属 functional coverage，并建立 Feature ID 到 coverage bin 的映射。
6. 先运行 10～100 笔 deterministic seed smoke，确认 stimulus 和 checker。
7. 运行 100～1,000 笔多 seed stability regression，处理所有 unexpected error 和 pending。
8. 运行 testplan 规定的最小规模，保存 seed、cfg、coverage 和结果。
9. 评审 stimulus fidelity、checking completeness 和 coverage 后，才把状态改为 Implemented。

每个测试类头部建议保留以下元数据注释：

```systemverilog
// Covers: Fxx, Fyy
// Testplan: tp_example_random
// Minimum campaign: 10_000 transactions
// Expected result: PASS | EXPECTED_FAIL(<bug-id>)
```

## 7. 通用完成判据

除 testplan 的场景专属判据外，所有正常功能随机测试必须同时满足：

- 计划事务数、DUT 接受事务数和完成响应数关系符合场景定义。
- reference model、scoreboard 和 channel checker mismatch 为 0。
- 所有 expected/actual queue、monitor/driver context、sequencer FIFO 和 outstanding tracker 在结束时清空。
- protocol assertion 无 unexpected failure。
- watchdog 未超时；如超时，报告具体 channel、Master/Slave、ID 和 pending context。
- 所有随机 stall 都是有限的，除非测试明确验证永久阻塞或 no-handshake。
- 测试日志记录 simulator seed、有效 cfg、事务统计、coverage 摘要和 expected-error 统计。
- 达到 testplan 规定的最小事务/操作/handshake/reset 数量。

负向测试还必须满足：

- 每个注入错误都有唯一 expectation，实际观察次数与期望一致。
- 未被列入 expectation 的 UVM_ERROR/UVM_FATAL/assertion 仍导致失败。
- no-handshake 判据具有明确观察窗口，并在结束时证明目标通道没有错误握手。
- 已知缺陷使用 bug ID 和 expected-fail 状态管理；RTL 修复后必须转为普通 passing regression。

## 8. 回归分层与运行规模

建议建立以下回归层级：

| 层级 | 目的 | 推荐规模 |
|---|---|---|
| Compile/selftest | 编译和 checker/model 自测 | 每次提交 |
| CR smoke | 快速验证 test 可启动、可结束、可复现 | 每 test 10～100 笔，固定 seed |
| CR stability | 捕获调度和随机组合问题 | 每 test 100～1,000 笔，多 seed |
| Feature regression | 满足单项 testplan 最小规模 | 通常 10,000；按 testplan 特例执行 |
| Nightly stress | 长时间、高并发和 coverage 收敛 | 多 seed，规模高于最低要求 |

`+AXI_CR_NUM_TXN` 只用于缩短 smoke/stability。正式 feature regression 不得通过较小 plusarg 绕过 testplan 的最小事务数。

## 9. 待确认决策与推荐默认值

以下决策应在对应阶段开始前确认：

| 决策 | 推荐默认值 | 影响阶段 |
|---|---|---:|
| 是否允许同步修改 driver、monitor、assertion、scoreboard 等公共基础设施 | 允许；测试正确性优先于只新增 testcase 文件 | 0～5 |
| 正式回归是否默认执行 testplan 最小规模 | 是；smoke 通过 plusarg 缩短 | 1～5 |
| 负向 assertion/日志的判定方式 | 结构化 expected-error 计数，禁止全局降级 | 3、5 |
| 当前 RTL 已知缺陷的处理 | 以 bug ID 标记 expected-fail，不计为普通通过 | 4、5 |
| coverage collector 的归属 | 统一放在 env/coverage 层，test 只配置和检查目标 | 1～5 |
| Questa/VCS 的 canonical regression | 选择一个主入口，并对两个 filelist 做能力一致性检查 | 0 |

若没有新的项目约束，后续实现按本表推荐默认值执行。

## 10. 推荐的下一步

1. 完成 Phase 0 中读 ID assertion 修正，并增加完整 `0..15` 的 assertion selftest。
2. 修正 Master driver 的 AW/W 上下文同步，分别验证 prefetch 关闭和开启场景。
3. 为 CR 基础框架运行 100～1,000 笔多 seed 合法混合流量回归。
4. 首先实现 `tp_sid_random`，用它验证 3 targets × 3 masters × 16 original IDs 和返回 ID 恢复。
5. 随后实现 `tp_backpressure_random`、`tp_progress_random` 和 `tp_concurrency_random`。
6. 完成 default transaction model 后进入 Phase 2；完成 per-ID burst tracking 后进入 Phase 3。


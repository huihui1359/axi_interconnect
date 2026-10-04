# AXI Interconnect 现有验证与 Testplan 对照审查

**Author**: Wang Jianghao, Codex, GPT-5.6-Solar
**Created**: 2026-10-04 20:10
**Current Version**: v1.0

**Version Changelog**:
- **v1.0** (2026-10-04 20:10): 初版现有验证与 testplan 对照审查，评估测试实现完整性、结果检查、刺激正确性、方法学和 feature traceability。

---

## 1. 审查范围与结论

本审查依据 `axi_interconnect-testplan.md`、RTL 反向提取的架构/微架构文档，以及当前 `dv/`、`sim/`、`sim_vcs/` 下的 UVM 测试、序列、driver、monitor、checker、reference model、coverage、assertion 和构建清单完成。审查方法为静态代码对照；本次未运行仿真，因此“已有测试通过”不是本报告的结论。

验证方法学为 UVM。主环境共有 27 个具体 DUT 测试：Stage 1 两个、Stage 2 七个、Stage 3 八个、Stage 6 十个；另有六个 checker/reference-model 自测顶层。Stage 1–3 主要只检查 M0↔S0，Stage 6 才启用全 3×3 reference model、scoreboard、channel checker、六个 outstanding tracker 和 bound arbiter checker。

总体判定：**现有验证能支撑基本路由、单/多 beat 数据流、M0↔S0 outstanding/乱序场景，以及若干全端口并发和仲裁 smoke；不能满足当前 testplan 的完整签核要求。** 29 个 feature 中 19 个存在可映射实现、10 个 Missing；在 19 个已实现项中，仅 F01、F22 的结果检查可评为 Complete，其余 17 个均为 Partial。现有实现没有 Stubbed test，但计划中的大量 `tp_*` 测试类本身尚不存在。

| 指标 | 结果 |
|---|---:|
| Testplan feature | 29 |
| Implemented / Stubbed / Missing | 19 / 0 / 10 |
| 已实现项的结果检查 Complete / Partial / Absent | 2 / 17 / 0 |
| 现有具体 UVM DUT tests | 27 |
| 计划的 constrained-random classes | 24 |
| 已按计划名称和最小事务数实现的 CR classes | 0 |
| 功能覆盖模型 | 1 个 covergroup，24 个 `master×route×direction` bins |

## 2. Feature-to-Test Traceability Matrix

状态含义：Implemented 表示存在能够激励该 feature 的可运行测试，不表示达到全部计划维度；Missing 表示没有针对性测试。Checking 评价结果判定是否覆盖 testplan 的全部 pass criteria。

| ID | 现有映射 | 状态 | Checking | 覆盖判断与主要缺口 |
|---|---|---|---|---|
| F01 3×3 topology | `axi_stage6_route_matrix_test` | Implemented | Complete | 3 M×3 S、读写均走 system scoreboard/channel checker；缺少计划的 10k random campaign，但定向结果判定完整。 |
| F02 Address decode | Stage 2 burst tests；Stage 6 route/random smoke | Implemented | Partial | 只使用窗口内地址/中心点；未覆盖三个窗口首末地址及相邻 hole。 |
| F03 Default route | `axi_stage6_default_slave_test` | Implemented | Partial | 三笔 single-beat default 访问检查 DECERR；无 hole 边界、随机地址、LEN 1/15。 |
| F04 SID encode/decode | route matrix、`axi_stage6_id_matrix_test`、Stage 3 ID mapping | Implemented | Partial | route matrix 未穷举 16 个原 ID；ID matrix 仅 M0→S0 的 tag 0..3，未达到 3×3×16。 |
| F05 W routing contract | Stage 2/3 write tests、Stage 6 route matrix | Implemented | Partial | 合法 WID 路由有检查；故意错误目标码、未登记 WID 及 32-cycle no-handshake 判据缺失。 |
| F06 Read flow | burst read、outstanding/read OOO、Stage 6 read scenarios | Implemented | Partial | beat、payload、RESP、LAST 和合法 outstanding 有检查；非法/未知 SID 注入缺失，全端口多 beat 随机不足。 |
| F07 Write flow | burst write、AW/W order、outstanding/write OOO、Stage 6 writes | Implemented | Partial | 合法流、WSTRB/data/B 返回有检查；全端口 LEN/ID/WSTRB 随机与非法路径缺失。 |
| F08 Concurrent targets | `axi_stage6_multi_slave_parallel_test`、route matrix | Implemented | Partial | multi-slave 测试实际由 M0 同时发三个 read，不是计划的 M0/M1/M2 同拍、混合读写。 |
| F09 M→S arbitration | Stage 6 multi-master read/write arbitration tests；bound checker | Implemented | Partial | 三源同时争用和 one-hot/RR 逻辑有检查；每源仅一笔，未验证持续竞争下每 3 次服务窗口与三目标/default 全矩阵。 |
| F10 S→M arbitration | `axi_stage6_response_arb_test`；bound checker | Implemented | Partial | 只覆盖三真实 slave 的 R 返回；未覆盖 B、default 第四路和持续四路公平性。 |
| F11 Grant lock | Stage 2 channel stall；Stage 6 arbiter tests；bound checker | Implemented | Partial | assertion 检查 stall 时 grant 稳定；未覆盖五通道、规定 stall 长度及 WAIT 中新请求组合。 |
| F12 FIFO buffering | — | Missing | N/A | 没有 30 个 FIFO 组、occupancy 0/1/3/4、full/empty 和序列保持的定向或随机检查。 |
| F13 FIFO edge semantics | — | Missing | N/A | 没有 empty/full 同拍 push+pop 及 occupancy 后状态检查。 |
| F14 SID tables | Stage 3 outstanding depth tests、stall test | Implemented | Partial | 外部行为覆盖到 outstanding=4；没有第 5 项反压、slot0..3 删除、压紧/相对顺序和内部占用检查。 |
| F15 Eligibility filter | Stage 3 OOO/same-ID/outstanding tests | Implemented | Partial | 能证明若干非严格全局完成顺序；没有逐 slot hit 和 miss/未登记 SID 的 no-handshake 测试。 |
| F16 SID push/clear priority | — | Missing | N/A | 没有 2/3 路同拍 push/clear、最低 bit 优先和无丢失/重复检查。 |
| F17 SID clear handshake risk | — | Missing | N/A | 没有末 beat 被最终 FIFO 反压的专门场景，也没有 `p_sid_clear_on_handshake`；已知 RTL 风险会静默逃逸。 |
| F18 Default read FSM | `axi_stage6_default_slave_test` | Implemented | Partial | 只有 single-beat read；无 LEN=1/15、RREADY stall、状态/弧覆盖。 |
| F19 Default write FSM | `axi_stage6_default_slave_test` | Implemented | Partial | 只有 single-beat write；无 LEN=1/15、BREADY stall、状态/弧覆盖。 |
| F20 Reset | — | Missing | N/A | harness 仅仿真开始施加两拍 reset；没有 idle/active/random-phase reset 或 epoch scoreboard。 |
| F21 Backpressure | Stage 2 delay/stall/random-ready；Stage 3 stall；Stage 6 delay knobs | Implemented | Partial | 五通道都有一定 stall/稳定性检查；未系统覆盖 0/1/2/5/6/16、全部端口及 FIFO 占用交叉。 |
| F22 AXI3-style bursts | Stage 2 burst read/write；Stage 3 ordering tests | Implemented | Complete | 定向覆盖 LEN 0..15、FIXED/INCR 及合法 WRAP 长度；checker/assertion检查 beat count/LAST/data，同/异 ID ordering 有独立测试。随机交织规模仍不足。 |
| F23 Forward progress | Stage 2/3/6 test-local timeout；top global timeout | Implemented | Partial | 有 5k/100k-cycle 或全局 watchdog；没有 release 后 32-cycle、按 channel/ID 报告的 progress checker。 |
| F24 Default diagnostics | — | Missing | N/A | 没有早/晚/缺失 WLAST、AWID/WID mismatch 注入及日志匹配。 |
| F25 Parameter contract | — | Missing | N/A | 主 top 仅默认参数 elaboration；没有明确的默认位宽审计或非默认参数编译负测。 |
| F26 Address overlap risk | — | Missing | N/A | 没有重叠窗口配置、双目标 handshake 检查或 disjoint assertion。 |
| F27 Scope/static audit | — | Missing | N/A | 现有文档识别了 absent features，但没有可回归的静态测试或 reset abort 判据。 |
| F28 Observability | 各 stage finish checks、scoreboards、trackers | Implemented | Partial | Stage 3/6 会检查 mismatch/pending/drain；未证明“每个 pin handshake 恰产生一个 monitor item”，也无 checker 计数一致性覆盖。 |
| F29 Single-clock architecture | — | Missing | N/A | 功能测试都使用单 `clk`，但没有时序块/连接静态审计和明确的 100 笔判据。 |

### 缺失项清单

Missing：F12、F13、F16、F17、F20、F24、F25、F26、F27、F29。

Stubbed：无。现有 27 个 DUT test 均有实际 stimulus 和检查，不满足计划的部分被归为 Partial，而不是 Stubbed。

## 3. 现有测试结果检查审计

下表逐个列出当前具体 DUT test。`C`=Complete（对该测试自身声称的 stimulus 有自动结果检查），`P`=Partial，`A`=Absent。这里的 C 不代表完整覆盖对应 testplan feature。

| Test | 主要 plan 映射 | Checking | 判定依据 |
|---|---|---|---|
| `axi_stage1_single_write_test` | F07 | C | 等待 AW/W/B match，随后 `finish_test` 检查 mismatch/pending。 |
| `axi_stage1_single_read_test` | F06 | C | 等待 AR/R match，检查 payload 与队列清空。 |
| `axi_stage2_burst_write_test` | F07/F22 | C | 36 笔 burst；逐 channel/item、beat、WSTRB、B 比较及 expected counts。 |
| `axi_stage2_burst_read_test` | F06/F22 | C | 36 笔 burst；逐 beat data/RESP/LAST 和 expected counts。 |
| `axi_stage2_aw_w_order_test` | F07 | C | AW-first、W-first、concurrent 三种顺序，且显式检查相对 cycle。 |
| `axi_stage2_delay_gap_test` | F21 | C | 检查配置的 W/R gap 与端到端内容。 |
| `axi_stage2_channel_stall_test` | F11/F21 | P | 确认五通道发生过 stall 并靠 checker 判数据；未验证计划的全部时长、端口和 lock 服务窗口。 |
| `axi_stage2_read_write_parallel_test` | F08 | P | 检查读写均完成及内容；只在 M0↔S0，非三目标场景。 |
| `axi_stage2_ready_random_smoke_test` | F21 | P | 8 write+8 read，随机 delay 0..100；规模与覆盖点不足。 |
| `axi_stage3_outstanding_write_test` | F14/F22 | C | 深度 1..4 和 same-ID depth 4，检查 max depth、counts、pending。 |
| `axi_stage3_outstanding_read_test` | F14/F22 | C | 同上，针对 read。 |
| `axi_stage3_write_ooo_test` | F15/F22 | C | 四个不同 ID、脚本化返回顺序，检查 reorder 发生及逐项内容。 |
| `axi_stage3_read_ooo_test` | F15/F22 | C | 同上，针对 read。 |
| `axi_stage3_same_id_order_test` | F15/F22 | C | 三 write+三 read same-ID overlap，检查 same-ID overlap、counts 和内容。 |
| `axi_stage3_mixed_rw_test` | F06/F07/F22 | C | 4 write+4 read，双向 checker/trackers/drain 检查。 |
| `axi_stage3_id_mapping_test` | F04 | P | 只覆盖 M0/S0 tags 0..3，检查该小范围的 SID 转换。 |
| `axi_stage3_outstanding_stall_test` | F14/F21/F22 | C | 4+4 outstanding、random gap/stall，检查深度、reorder、内容和 drain。 |
| `axi_stage6_route_matrix_test` | F01/F02/F04/F06/F07 | C | 全 3×3 single-beat read/write；system model、scoreboard、channel checker 自动比较。 |
| `axi_stage6_id_matrix_test` | F04 | P | 只有 M0/S0 tag 0..3，未做计划中的 144 组合。 |
| `axi_stage6_multi_slave_parallel_test` | F08 | P | 三个并发 read 均来自 M0；不满足三 master 和混合方向判据。 |
| `axi_stage6_multi_master_write_arb_test` | F09/F11 | P | 三 M→S0 各一笔，未形成持续三轮服务窗口。 |
| `axi_stage6_multi_master_read_arb_test` | F09/F11 | P | 三 M→S1 各一笔，缺少持续公平性和目标矩阵。 |
| `axi_stage6_response_arb_test` | F10/F11 | P | S0/S1/S2→M0 read response；缺 B/default 四路。 |
| `axi_stage6_cross_master_same_id_test` | F04/F15 | C | 三 master 同原 ID 到 S1，检查 MID 隔离和返回。 |
| `axi_stage6_multiport_outstanding_test` | F06/F14 | P | 每 M 四笔 read，覆盖全端口深度；没有内部 slot/第 5 项/压紧检查。 |
| `axi_stage6_default_slave_test` | F03/F18/F19 | P | 三笔 default single-beat 自动比较；FSM 长 burst、stall 和状态覆盖缺失。 |
| `axi_stage6_random_smoke_test` | F01/F06/F07/F21 | P | 仅 9 笔、单 beat、合法 route，远低于 testplan 的 10k 和随机维度。 |

六个 `dv/tb/*selftest.sv` 验证 checker/reference model 自身，属于环境单元测试，不直接计入 F01–F29 的 DUT feature 覆盖；它们也不会从主 `tb` 自动运行，必须另选 top。

## 4. Stimulus Fidelity 与 Constrained-Random 审查

### 4.1 与计划参数的偏差

- 计划 §3 定义 24 个 constrained-random class，通常要求至少 10,000 transactions；仓库中没有任何同名 `tp_*` class。
- `axi_stage6_random_smoke_vseq` 仅对 3×3 组合各发一笔，共 9 笔，并只随机读/写和 2-bit tag；不随机 LEN、burst、stall、default、非法 SID/WID、reset 或 outstanding 返回顺序。
- `axi_stage2_ready_random_smoke_seq` 只有 8 write+8 read，且局限 M0↔S0。
- Stage 6 基础序列只生成 single-beat；因此全 3×3 checker 的存在不能转化为全端口 burst/outstanding 覆盖。
- 地址 route matrix 使用窗口内部代表地址，没有覆盖 `0x0000/0x0fff`、`0x2000/0x2fff`、`0x4000/0x4fff` 及相邻 holes。
- 没有 negative stimulus：错误 WID、未知 SID、spurious B/R、VALID early-drop、地址重叠和非默认参数均未被驱动。

### 4.2 并发、顺序和反压真实性

Stage 3 在 M0↔S0 上对 outstanding depth、different-ID reorder 和 same-ID overlap 的 stimulus 质量较好；Stage 6 可同时启动多个 master/slave sequence。主要偏差是 arbitration 每个 contender 通常只有一笔事务，不能证明长期 round-robin/fairness；`multi_slave_parallel` 也只是单 master 到三个目标的 read。反压测试能制造固定或随机 delay，但没有把计划指定的 stall bucket、FIFO occupancy、grant winner 和前向进展做交叉。

## 5. Testbench Methodology 与隔离性审查

### 5.1 方法学强项

- Stage 6 reference model 独立计算 address route、SID encode/decode 和 default response；scoreboard 按 port/direction/ID 队列比较 request/response。
- channel checker 在五个 channel 粒度比较转发 payload；outstanding trackers 和 protocol assertions 提供因果、beat count、LAST、ID、stable-under-stall 检查。
- Stage 3/6 base test 在结束时检查 mismatch、pending model/checker queues、tracker 状态、monitor/driver queues，减少“激励发出但未完成”的假通过。
- 测试经 factory 选择，配置集中在 env cfg；多端口场景使用 virtual sequencer，结构符合 UVM 复用方式。

### 5.2 方法学缺口

- 功能覆盖只有 `master×route×direction`，没有 testplan 中 29 个 covergroup 对应的 address boundary、LEN/burst、SID、outstanding、stall、FIFO、FSM、reset、arbiter、diagnostic bins。
- bound arbiter checker 的 enable 依赖 `UVM_TESTNAME=axi_stage6` 前缀，而不是 `checker_mode`；Stage 6 测试若改名可能静默失去内部仲裁检查。
- Stage 1 test 以无局部 timeout 的 `wait` 等待 match；虽然 top 有全局 timeout，但数值为 100,000,000 time units，失败定位慢且不报告具体 channel/ID。
- 没有 memory model；当前数据正确性来自 reactive response sequence 的脚本数据，不能验证地址可寻址存储语义（该点不是 interconnect 本身的必需功能，但限制系统级场景）。
- 计划名称与实现名称完全不同，测试代码没有 F-ID/requirement-ID 元数据；回归结果无法自动回链到 F01–F29。

### 5.3 Test isolation

每次 UVM run 只选择一个 test，env 在 build 时重建，未发现跨 test 的持久 static scoreboard 状态。随机调用使用 simulator seed，可重复，但测试日志没有统一记录 env cfg/latency knobs/有效 seed 的独立 metadata artifact。六个 selftest 是替代顶层，主回归若未显式选择不会执行。

## 6. Findings

### Blocking

**B1 — F17 已知 SID 提前清除风险完全未验证。** 微架构明确指出 SID 在候选 `VALID&LAST` 时清除而不是在最终 `VALID&&READY&&LAST` 时清除；testplan 要求该场景必须暴露为已知缺陷。现有测试没有把最终 FIFO 填满后阻塞末 beat，也没有 `p_sid_clear_on_handshake` 或 shadow SID table。结果是可能导致后续同 ID/容量状态错误的高风险路径可在全部现有回归中静默逃逸。建议首先实现 `tp_sid_clear_backpressure` 与 assertion，并将预期行为按当前 RTL 缺陷归类为 expected-fail，修复 RTL 后转为 passing regression。

### Major

**M1 — 10/29 feature 没有任何对应测试。** F12、F13、F16、F17、F20、F24、F25、F26、F27、F29 为 Missing，集中在 FIFO 边界、SID 多路冲突、active reset、诊断/参数/静态契约。建议按 B1→reset→FIFO/SID→static/diagnostic 的风险顺序补齐。

**M2 — constrained-random 策略基本未落地。** 计划要求 24 个 CR class 和通常 10k transactions；现有“random smoke”最多 16 或 9 笔，且随机维度很少。建议先实现一个统一多端口 random virtual sequence，随后用 scenario knobs 派生 route/SID/outstanding/backpressure/reset campaigns，并在 regression manifest 中记录最小计数。

**M3 — 功能覆盖模型无法衡量 testplan closure。** 当前只有 24 个 `master×route×direction` bins，缺少 testplan 其余覆盖模型；即使所有测试运行通过，也无法说明 boundary、burst、SID table、stall、FSM、reset 或 fairness 是否命中。建议按 F-ID 建 covergroup/cover property，并生成 feature→test→coverage 的 closure 表。

**M4 — reset 验证只有上电初始 reset。** `tb.sv` 只在时间 0 拉低 reset 两拍；没有活动事务/FIFO 非空/FSM WAIT 中 reset、异步相位或复位前 expectation 丢弃检查。混合同步/异步 reset 是架构已识别风险。建议增加可由 sequence 控制的 reset agent/API 和 epoch-aware scoreboard。

**M5 — arbitration 测试不足以证明公平性。** M→S 测试三源各一笔，S→M 仅三真实 slave 的 read；不能满足 3-way/4-way eligible-handshake 服务窗口。bound checker验证当前 grant/pointer关系，但不是持续无饥饿证明。建议每个 contender 保持至少 8–16 笔请求，覆盖 AW/W/AR/B/R、三个真实目标和 default 来源，并收集 winner transition/service-distance coverage。

**M6 — 地址/SID 组合远未达到计划边界和穷举要求。** route matrix 使用窗口代表点；ID matrix 只覆盖 M0/S0 的四个 tag。建议增加三个窗口首/末/相邻 hole directed cases，并穷举 3 target×3 master×16 original-ID，直接比较 8-bit SID 与返回低 4-bit ID。

**M7 — default slave 仅有 single-beat smoke。** 当前没有 LEN=1/15、RREADY/BREADY stall、FSM state/arc coverage，也没有 WLAST/AWID-WID diagnostic injection。建议把 default read/write 分成 transaction model、FSM arc coverage 和 negative diagnostics 三组测试。

**M8 — 内部容量/边界语义没有可观察检查。** 外部 outstanding depth=4 测试不能证明 30 个 FIFO 的 full/empty exchange、SID slot 压紧或同拍 push/clear priority。建议以 bind checker 或 hierarchy probe 暴露 occupancy/slot/grant，仅将内部状态用于白盒断言，数据正确性仍由独立队列模型判断。

### Minor / Warning

**W1 — Stage 6 arbiter checker 的启用条件脆弱。** checker 用 test-name prefix 判断是否 enable；改名或 wrapper test 可能不启用。建议从 config_db/plusarg 明确控制，并在 test start 打印 enabled instance count。

**W2 — Stage 1 failure timeout 定位较差。** 两个 Stage 1 test 使用裸 `wait`；只能依赖很大的全局 UVM timeout。建议统一使用带 cycle bound 的 wait helper，并报告等待的 channel/count。

**W3 — traceability 命名缺失。** 现有类名表达开发阶段而非 testplan feature，代码和回归清单均无 F-ID。建议在 test class 注释/metadata 中加入 `covers={Fxx}`，不要为了对齐文档批量重命名稳定类名。

**W4 — VCS 与主 Questa 清单能力不一致。** 现有环境分析指出 VCS focused build 只覆盖早期 Stage 1 路径；若作为正式回归入口，会遗漏 Stage 6 checker/测试能力。建议选择一个 canonical manifest，并为两套 simulator 做 filelist parity check。

### Notes

**N1 — 现有测试没有发现空壳。** 每个具体 DUT test 都启动 sequence 并有自动检查；不足之处是 stimulus/criteria 不完整，而非只有占位代码。

**N2 — Stage 2 burst directed coverage质量较高。** read/write sequence 覆盖 1..16 beats、FIXED/INCR，以及合法 WRAP 2/4/8/16，且 checker/assertion 同时核对 beat count 与 LAST；可作为 F22 后续随机测试的 golden baseline。

**N3 — Stage 6 检查基础可复用。** system reference model、scoreboard、channel checker 和 per-port trackers 已具备补充大规模 random tests 的基础，无需重建整套环境。

**N4 — 本报告不把 selftest 计作 DUT feature coverage。** 它们对环境可信度有价值，应单列为 checker qualification regression。

## 7. 21 项审查清单结论

1. **Feature mapping：部分通过。** 29 项均已审计；19 Implemented、10 Missing。
2. **Test existence：部分通过。** 27 个现有 DUT test 均存在；计划 `tp_*` 类不存在。
3. **Stub detection：通过。** 未发现少于五行或无 stimulus/check 的具体 DUT test。
4. **Result checking：部分通过。** 已实现 feature 中 2 Complete、17 Partial。
5. **Expected/actual independence：通过但有限。** Stage 6 路由/SID模型独立于 RTL层次；内部 FIFO/SID/FSM 尚无独立模型。
6. **Scoreboard completeness：部分通过。** Stage 6 全端口完整；Stage 1–3 仅 M0↔S0。
7. **End-of-test drain：通过。** Stage 3/6 检查 pending queues/trackers/agents；Stage 1/2 也检查主 checker pending。
8. **Assertions：部分通过。** stable、causality、beat/LAST、ID 和 RR pointer 已有；计划特定 SID clear/decode disjoint/progress 缺失。
9. **Functional coverage：不通过。** 只有单一 route cross，不能支持 closure。
10. **Address stimulus：部分通过。** 合法窗口内部地址有覆盖，boundary/hole/overlap 缺失。
11. **ID/SID stimulus：部分通过。** 合法映射有小范围覆盖，穷举和 illegal SID/WID 缺失。
12. **Burst stimulus：通过（定向）。** LEN 全范围和三种 burst 类型已有；大规模全端口随机不足。
13. **Outstanding/ordering：部分通过。** M0/S0 depth 与 OOO 较强；全端口及内部 slot semantics 不足。
14. **Backpressure：部分通过。** 五通道有 stall 场景和 stable assertion；规定 buckets/crosses 不全。
15. **Concurrency/arbitration：部分通过。** 有并发 smoke；持续公平性和四路返回不全。
16. **Reset：不通过。** 仅初始 reset，无测试内 reset。
17. **Negative/error tests：不通过。** default legal path 有，协议/参数/overlap/diagnostic negative cases 缺失。
18. **Timeout/forward progress：部分通过。** Stage 2/3/6 和 top 有 timeout；缺 32-cycle per-channel watchdog，Stage 1 仅裸 wait。
19. **Reproducibility/isolation：部分通过。** simulator seed 可重复、run 间环境隔离；缺统一 run metadata。
20. **Naming/traceability：不通过。** 测试名与 F-ID/计划名无机器可读关联。
21. **Build/regression reachability：部分通过。** 主 `sim/sim.f` 包含完整环境；alternate selftest 和 VCS focused flow 需显式选择/对齐。

## 8. 建议实施顺序与签核门槛

### P0：先消除高风险静默逃逸

1. 实现 F17 SID clear backpressure test、shadow table 和 assertion，先作为 known-fail 锁定当前问题。
2. 实现 F20 active/random-phase reset 与 epoch scoreboard。
3. 为 F12/F13/F14/F16 建立 FIFO/SID 白盒 assertion 与独立 queue/set model。

### P1：补齐主数据面和仲裁 closure

1. 地址边界/hole、3×3×16 SID 穷举、错误 WID/未知 SID。
2. 持续 M→S/S→M 竞争，覆盖五通道、default 第四来源和服务距离。
3. default LEN 0/1/15、stall、FSM arcs 与 diagnostics。
4. 统一多端口 constrained-random sequence，逐步达到 testplan 的最小 transaction counts。

### P2：建立可量化签核

1. 按 F01–F29 增加 coverage model 和 requirement metadata。
2. 补 F25/F26/F27/F29 static/elaboration audits。
3. 对齐 Questa/VCS manifests，把六个 environment selftests 纳入独立 qualification regression。

建议签核门槛：B1 关闭；29/29 feature 至少 Implemented；所有 pass criteria 的 checking 为 Complete；testplan covergroups/cover properties 达到约定目标且无 waiver 外空洞；所有 checker queues/drivers/monitors 在 test end 清空；固定种子 smoke 与多种子 CR regression 均无 UVM_ERROR/FATAL。

## 证据索引

- Testplan feature 表：`dv/doc/zflow/axi_interconnect-testplan.md:24-54`；CR 最小计数：`:56-85`。
- 全端口 Stage 6 stimulus：`dv/seq/axi_stage6_vseqs.sv:4-153`；single-beat helper：`dv/seq/axi_stage6_base_vseq.sv:16-80`。
- Stage 2 burst 1..16：`dv/seq/axi_stage2_burst_write_seq.sv:20-39`、`axi_stage2_burst_read_seq.sv:20-36`。
- Stage 6 completion/drain checks：`dv/tc/axi_stage6_base_test.sv:72-114`；Stage 3 checks：`dv/tc/axi_stage3_base_test.sv:88-149`。
- System scoreboard mismatch/pending：`dv/env/checker/axi_system_scoreboard.sv:44-46,190-292`；channel checker：`dv/env/checker/axi_channel_forwarding_checker.sv:42,330-396`。
- 当前功能覆盖：`dv/env/axi_system_coverage.sv:23-31`。
- bound RR checker及 test-name enable：`dv/env/axi_stage6_arbiter_assertions.sv:51-92`。
- 初始 reset 与全局 timeout：`dv/tb/tb.sv:21-26,334`。
- SID clear 风险来源：`rtl/doc/axi_interconnect-microarchitecture-extracted.md` §15、`rtl/doc/axi_interconnect-architecture-extracted.md` §§2.4–2.5、14。

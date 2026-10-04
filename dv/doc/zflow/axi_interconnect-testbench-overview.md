# AXI 互连 UVM 验证环境概览

## 1. 目的与来源基线

本文档描述 `dv/` 下实际实现的验证环境，是实现概览，不代表尚未实现的 testplan 目标。

| 项目 | 值 |
|---|---|
| DUT | `axi_interconnect`，固定 3 个 initiator × 3 个 target |
| 主顶层 | `dv/tb/tb.sv` (`tb`) |
| 主文件列表 | `sim/sim.f` |
| UVM 环境 | `axi_env` |
| 协议 | 带 WID 以及自定义 4 位 MID/8 位 SID 映射的 AXI3 风格子集 |
| 时钟/复位 | 名义 100 MHz TB 时钟（半周期 `#5ns`）；低有效复位在两个上升沿和一个下降沿后释放 |
| 已实现源范围 | `dv/` 下 89 个 SV/SVH 文件 |
| DUT 规格参考 | `rtl/doc/axi_interconnect-architecture-extracted.md`；`rtl/doc/axi_interconnect-microarchitecture-extracted.md` 及组件文档 |
| 验证环境图 | `dv/doc/zsp_aiflow/axi_interconnect-tb-environment-map.md` |

面向 DUT 的接口实现 AW/W/B/AR/R ready-valid 通道，地址/数据宽度为 32 位，上游 ID 为 4 位，下游 ID 为 8 位，AXI3 长度字段为 4 位。验证环境驱动并观测全部三个上游端口和三个下游端口。

## 2. 架构

```text
                         +---------------- UVM test ----------------+
                         |                                           |
  m-sequences/vseq ------+--> m_agent[0..2].sequencer               |
                         |             |                             |
                         |             v                             |
                         |       m_agent[0..2].driver                 |
                         +-------------|-----------------------------+
                                       v
                m_if[0..2]  <---->  axi_interconnect  <---->  s_if[0..2]
                    |                   (DUT)                    |
         pin assertions/monitor                         pin assertions/monitor
                    |                                              |
                    +--------- monitor TLM streams ----------------+
                                      |
              +-----------------------+-------------------------+
              |                       |                         |
       Stage 1/2/3 checker      阶段 6 model/SB         outstanding trackers
          (M0↔S0 only)          + channel checker          (per interface)
                                      |
                              functional 覆盖率
                                      |
                         s_agent[0..2].sequencer
                                      |
                           reactive slave sequences
                                      |
                             s_agent[*].driver
```

验证环境包含两个互补的观测平面：

1. 引脚平面： six `axi_protocol_assertions` instances observe all external DUT interfaces, and 18 bound checkers observe internal request/response arbiters.
2. 事务平面： six UVM monitors reconstruct channel events, complete requests, and complete responses for end-to-end checking and 覆盖率.

## 3. 顶层测试线束与 DUT 映射

`tb.sv` 创建两个接口数组：

- `m_if[0..2]`: TB acts as AXI master; DUT acts as slave on `M_AXI_*[0..2]`.
- `s_if[0..2]`: DUT acts as AXI master; TB acts as slave on `S_AXI_*[0..2]`.

这些数组逐信号连接到 DUT 的非打包数组端口。 每个接口都配置到一个 active UVM agent，并分别设置 driver 和 monitor 的 virtual-interface 句柄。

| External side | Request owner | Response owner | ID width | DUT boundary |
|---|---|---|---:|---|
| `M_AXI_*[0..2]` | TB master agent | DUT | 4 | `fifo_{ar,aw,w}_mx[]`, `fifo_{r,b}_mx[]` |
| `S_AXI_*[0..2]` | DUT | TB slave agent | 8 | `fifo_{ar,aw,w}_sx[]`, `fifo_{r,b}_sx[]` |

参考模型复现文档中的路由窗口：

| Route | Address range | Route tag |
|---|---|---|
| S0 | `0x0000_0000–0x0000_0fff` | `01` |
| S1 | `0x0000_2000–0x0000_2fff` | `10` |
| S2 | `0x0000_4000–0x0000_4fff` | `11` |
| 默认值 | all other addresses | no real target; expect `DECERR` |

对于真实目标，期望的下游 SID 为 `{target_tag, master_tag, original_id[3:0]}`. Master 标签为 M0=`01`, M1=`10`, M2=`11`.

## 4. 组件清单

### 4.1 测试线束与公共类型

| 组件/来源 | 职责 |
|---|---|
| `tb` | 时钟/复位、接口/DUT 实例化、virtual-interface 配置、`run_test()` |
| `axi_if` | 参数化五通道信号束及 master/slave/DUT/monitor modport |
| `axi_types_pkg` | 项目位宽、端口数量、协议枚举、checker 模式 |
| `axi_req_item` | 读写请求、突发数据/字节使能、地址和 beat 时序控制 |
| `axi_rsp_item` | B/R 响应负载、突发数据/响应数组、响应时序 |
| `axi_channel_event` | 每次握手事件，包含方向、端口、通道、周期、ID 和负载 |
| `latency_gen` | 固定、零、最大、随机、突发以及可选的极限延迟生成 |

### 4.2 Agent 组件

每个 `axi_m_agent` 始终创建 monitor，active 时创建 driver 和 sequencer。master driver 使用独立的 AW/W/AR 工作队列，施加地址/数据延迟，随机化 BREADY/RREADY 延迟，并按 ID 跟踪 outstanding 请求。配置的读写 outstanding 上限必须为 1–4。

每个 `axi_s_agent` 始终创建 monitor，active 时创建 driver 和 sequencer。其 monitor 将重构的请求送入 `request_fifo`，使响应式 slave sequence 能生成 B/R 响应。slave driver 独立控制 AWREADY/WREADY/ARREADY 延迟，并对 B/R 响应排队。

两个 monitor 均发布：

- `channel_ap`：每次成功的 AW/W/B/AR/R 握手生成一个事件；
- `req_ap`：重构后的完整读写请求；
- `rsp_ap`：重构后的完整读写响应。

写事务重构会按 ID 配对 AW 与已完成的 W 突发。读事务重构会将 R 突发与先前的 AR 请求关联，并在完成时检查 beat 数量。

### 4.3 序列组织

| 层级 | 已实现策略 |
|---|---|
| 单操作 | 专用 master 单读/单写序列和简单响应式 slave 序列 |
| 阶段 2 | 场景基类支持突发、请求/响应延迟、beat 间隔、停顿、AW/W 顺序、并行读写和随机 READY 冒烟 |
| 阶段 3 | 场景基类增加多 outstanding 操作、同/不同 ID 顺序、读写乱序响应、ID 映射和 outstanding 停顿 |
| 阶段 6 | virtual sequencer 协调六个物理 sequencer；十个 virtual sequence 覆盖路由/ID 矩阵、并行目标、请求/响应仲裁、跨 master 同 ID、多端口 outstanding、默认路由和随机冒烟 |

该 package 包含 27 个可运行的具体 UVM 测试: 2 Stage 1, 7 阶段 2, 8 阶段 3, and 10 阶段 6. 另外 4 个 base test 类提供公共配置和完成检查。 逐测试追踪不在本文档的 `testbench` 范围内。

### 4.4 参考模型与检查组件

| 组件 | 启用模式 | 职责 |
|---|---|---|
| `stage1_checker` | 阶段 1 | M0↔S0 单操作通道转发、ID 恢复和响应顺序 |
| `stage2_checker` | 阶段 2 | M0↔S0 突发/通道/请求/响应比较与计数 |
| `stage3_checker` | 阶段 3 | M0↔S0 SID 映射、outstanding 深度、同 ID 与不同 ID 顺序 |
| `axi_switch_ref_model` | 阶段 3/6 使用的对象 | 地址解码、W 目标解码、SID 编解码、ID 恢复 |
| `ref_model` | 阶段 6 | 预测所有端口的目标请求、master 响应和默认响应 |
| `scoreboard` | 阶段 6 | 按端口/方向/ID 匹配期望与实际的 slave 请求和 master 响应 |
| `channel_checker` | 阶段 6 | 比较逐次转发握手和默认响应负载 |
| `m_tracker_0..2`, `s_tracker_0..2` | 阶段 6; 阶段 3 中为索引 0 | 跟踪 AW/WLAST/B 与 AR/RLAST 守恒以及最大 outstanding 数 |
| six external protocol checkers | 始终实例化 | 停顿稳定性、复位输出、X 检测、因果关系/beat 计数、outstanding、自定义 ID/路由规则 |
| 18 bound arbiter checkers | 阶段 6 名称前缀或强制启用 | one-hot/valid grant、轮询预期、指针更新、停顿锁定 |

checker 层级通过 `env_cfg.checker_mode`; 互斥选择，并非累加启用。 引脚级接口 checker 独立于该模式持续启用。

## 5. TLM 互连与数据流

| 生产者 | 消费者 | 负载 | 目的 |
|---|---|---|---|
| `m_agent_0.monitor.channel_ap` | Stage 1/2/3 checkers | upstream event | stage-specific M0 observation |
| `s_agent_0.monitor.channel_ap` | Stage 1/2/3 checkers | downstream event | stage-specific S0 observation |
| `m_agent_0.monitor.req_ap`, `s_agent_0.monitor.req_ap` | 阶段 2/3 checkers | requests | burst-level forwarding comparison |
| `m_agent_0.monitor.rsp_ap`, `s_agent_0.monitor.rsp_ap` | 阶段 2/3 checkers | responses | response comparison/order |
| every master `req_ap` | `ref_model.m_req_fifo[*]` | actual upstream request | 阶段 6 prediction input |
| every slave `rsp_ap` | `ref_model.s_rsp_fifo[*]` | actual downstream response | 阶段 6 prediction input |
| reference model request ports | scoreboard expected request FIFOs | predicted downstream request | request checking |
| every slave `req_ap` | scoreboard actual request FIFOs | observed downstream request | request checking |
| reference model response ports | scoreboard expected response FIFOs | predicted upstream response | response checking |
| every master `rsp_ap` | scoreboard actual response FIFOs | observed upstream response | response checking |
| 每个 monitor `channel_ap` | channel checker 和对应 tracker | 握手事件 | 引脚转发与守恒检查 |
| every master `req_ap` | 覆盖率 collector | request | route/direction 覆盖率 |
| 每个 slave monitor `req_ap` | 对应的 slave sequencer FIFO | 请求 | 响应式响应生成 |

## 6. 激励策略

验证环境将定向场景类与受约束的随机事务和延迟字段结合。

- Master 请求项约束合法突发属性、突发形状、W 数据/字节使能、4 KiB 边界和延迟；场景序列选择路由/默认地址窗口。
- Slave 响应式序列消费观测到的请求，并以可配置的响应/beat 间隔生成匹配的 B/R 响应。
- slave agent 上的 AW/W/AR 以及 master agent 上的 B/R 的 ready 生成彼此独立。
- 阶段 2 特意将 M0 限制为一个 outstanding 请求，并禁用请求预取。
- 阶段 3 允许 M0 最多四个 outstanding 请求，并测试顺序和 ID 行为。
- 阶段 6 启用所有端口，将 outstanding 上限设为四，启用预取，并通过 virtual sequencer 协调流量。
- 默认路由序列期望 `DECERR`；默认读期望 `LEN+1` 个 beat 的全 1 数据。

验证环境未实现可寻址 memory model。返回数据由 sequence 生成，而非从持久化存储读取。

## 7. 检查策略

检查按层次组织，以便按抽象层定位失败：

1. 接口合法性：外部引脚级 assertion 模块检查 ready-valid 稳定性、复位行为、未知控制/负载值、突发 beat 计数、响应因果关系、outstanding 边界和项目特定 ID 映射。
2. 本地 monitor 一致性：monitor 重构请求和响应，检测未匹配上下文，并要求 pending 状态在 `check_phase` 中清空。
3. 阶段专用端到端比较：阶段 1–3 逐步增加突发、outstanding 和顺序能力，对 M0↔S0 进行检查。
4. 系统预测：在阶段 6 中，参考模型独立于下游观测预测路由/SID/default 行为。
5. 系统匹配： scoreboard 比较完整请求和响应；channel checker 独立比较各次握手。
6. 计数守恒：每端口 tracker 检测 B/R 下溢和非空 outstanding 状态。
7. 仲裁内部状态：bound checker 观测内部仲裁器 grant、指针、ready、request 和锁状态。
8. 测试完成：测试等待期望响应，检查 mismatch/pending 计数器和 agent drain 状态，仅在 UVM error 为零时输出 `AXI_TC_PASS`。

阶段 6 system model 和 channel checker 都显式处理默认路由，从事务级和 beat 级交叉检查默认响应。

## 8. 覆盖率模型

已实现的功能覆盖率为 `axi_system_coverage.system_cg`，仅在阶段 6 模式下启用。它对每个观测到的 master 请求采样，包含：

- master port: bins 0, 1, 2;
- decoded route: S0, S1, S2, default;
- direction: read/write;
- cross: `master × route × direction`.

这形成 24 个预期交叉组合。它体现 source/target/direction 可达性，但未实现 `rtl/doc/axi_interconnect-testplan.md` §14 所述的更广泛覆盖率模型。具体而言，实现中没有突发长度/类型/大小、WSTRB/数据模式、响应码、SID 字段、outstanding 深度、仲裁顺序/公平性、停顿、FIFO/SID 占用、复位、默认 FSM 状态、负向场景或 checker 结果的功能覆盖点。

仿真器代码覆盖率通过 with `cov=y` in the Questa flow. 检查过的 VCS Makefile 中未提供覆盖率选项。 in the inspected VCS Makefile.

## 9. 构建与运行配置

### 9.1 Questa 配置

`sim/Makefile` 和 `sim/sim.f` 编译完整的多阶段环境及六个独立 selftest 顶层。主要控制项包括 `test`、`SEED`/`rand`、`dump`、`cov`、`UVM_VERBO` 和 `reg_times`。具名回归目标覆盖阶段 2、阶段 3、阶段 6、组合正向套件以及独立 assertion/model selftest。

默认测试为 `axi_stage1_single_write_test`。正常运行通过需要 `AXI_TC_PASS` 报告且 UVM error/fatal 为零。

### 9.2 VCS 配置

`sim_vcs/sim.f` 是聚焦于阶段 1 的配置。它替换为精简的 `axi_seq_pkg.sv` 和 `axi_test_pkg.sv`，排除阶段 2/3/6 测试及所有独立 selftest，并将 `axi_fsdb_dump` bind 到 `tb`。其控制项为 `TEST`、`SEED`、`VERBOSITY` 和 `DUMP`；`DUMP=1` 时添加 `+DUMP_FSDB` 和生成的 `+FSDB_FILE` 路径。

The two profiles are not 来源-equivalent. 结果s from the VCS 配置 must not be treated as 阶段 2/3/6 覆盖率 evidence.

## 10. 各阶段已实现能力

| Stage | Ports used by primary TLM checker | Principal capability | Main checking path |
|---|---|---|---|
| 1 | M0, S0 | single read/write closed loop | channel event checker |
| 2 | M0, S0 | bursts, delays, gaps, stalls, parallel R/W | event + request/response checker |
| 3 | M0, S0 | up to four outstanding, SID mapping, out-of-order across IDs | 阶段 3 checker + two trackers |
| 6 | M0–M2, S0–S2 | full 3×3 routing, arbitration, parallel traffic, default route | system model + scoreboard + channel checker + six trackers + bound arbiter checkers |

Stages 4 and 5 are not represented as separate checker modes or test groups in the implemented 来源 tree.

## 11. 已知缺口与评审备注

- 功能覆盖率范围明显小于 the 29-feature testplan 覆盖率 model.
- Stage 1–3 TLM checking is restricted to M0↔S0; ports 1/2 rely on external protocol checkers until 阶段 6.
- The external assertion module checks a 项目-specific AXI3 subset, not full AXI3 compliance.
- Bound arbiter checkers depend on the `UVM_TESTNAME=axi_stage6` prefix and can be skipped by test renaming.
- 验证环境没有持久 memory model, so memory semantics and read-after-write content are not verified.
- `axi_basic_event_comparator` is available but unused by the main environment.
- Six standalone selftests are compiled in the complete manifest but require alternate 仿真器 tops; they do not execute during a normal `tb` run.
- VCS 配置有意精简，与完整 Questa manifest 不一致。
- 没有统一的机器可读运行记录同时捕获 seed, selected checker mode, agent config, latency settings, build profile, and waveform/覆盖率 options together.

## 12. 源文件映射

| Area | Files |
|---|---|
| Top/interface | `dv/tb/tb.sv`, `dv/tb/axi_if.sv` |
| Common types/utilities | `dv/common/*` |
| Environment assembly | `dv/env/axi_env.sv`, `dv/env/axi_env_cfg.sv`, `dv/env/axi_env_pkg.sv` |
| Master agent | `dv/env/master/*` |
| Slave agent | `dv/env/slave/*` |
| Stage/system checkers | `dv/env/checker/*`, `dv/env/axi_outstanding_tracker.sv` |
| Reference models | `dv/env/axi_switch_ref_model.sv`, `dv/env/axi_system_ref_model.sv` |
| Pin/internal checkers | `dv/env/axi_protocol_assertions.sv`, `dv/env/axi_stage6_arbiter_assertions.sv` |
| 覆盖率 | `dv/env/axi_system_coverage.sv` |
| Sequences | `dv/seq/*` |
| Tests | `dv/tc/*` |
| Selftests | `dv/tb/*selftest.sv` |
| Complete build | `sim/sim.f`, `sim/Makefile` |
| Focused VCS 构建 | `sim_vcs/sim.f`, `sim_vcs/Makefile`, `sim_vcs/dump_fsdb.sv` |

## 13. 生成校验

| 检查项 | 结果 |
|---|---|
| Components in diagrams/inventory exist in 来源 | 通过 |
| TLM 连接匹配 `axi_env::connect_phase` | 通过 |
| 接口方向匹配 `axi_if` modports and `tb.sv` bridge | 通过 |
| DUT 协议/路由描述可追溯至 RTL 文档与模型代码 | 通过 |
| 覆盖率摘要仅描述已实现的 covergroup | 通过 |
| 构建配置差异已明确 | 通过 |
| 未将未实现的组件或覆盖点描述为已存在 | 通过 |

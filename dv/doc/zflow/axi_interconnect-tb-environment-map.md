# AXI 互连验证环境图

## 来源信息

| 字段 | 值 |
|---|---|
| 来源 | `extracted` |
| 提取模式 | `extract` |
| 项目 | `axi_interconnect` |
| 日期 | 2026-10-04 |
| 工作区 | `/home/moxiao/work/axi_interconnect` |
| 版本 | `06f257ef224e8a5e509968fbe7ef3ee3f551b364` |
| 主文件列表 | `sim/sim.f` |
| 检查过的备用构建 | `sim_vcs/sim.f`, `sim_vcs/Makefile` |
| TB 来源 root | `dv/` |
| TB 顶层 | `tb` |
| DUT 实例 | `tb.dut` (`axi_interconnect`) |
| Skill | `extract-tb-environment-map`, zsp-workflow `0.1.0+codex.20261003182554` |
| DUT 参考文档 | `rtl/doc/axi_interconnect-architecture-extracted.md`；`rtl/doc/axi_interconnect-microarchitecture-extracted.md`；`rtl/doc/` 下的组件微架构文档 |

这是一个基于文件的超集环境图。 它记录范围内源文件能够构建的每个实例，不评估具体构建配置，以符号形式保留数组边界，并将运行时激活交由运行配置决定。顶层不存在条件实例化的主要组件。但 checker 可能存在而被 `checker_mode` 或 plusarg 禁用；相关激活条件记录如下。

The installed Skill package did not contain its referenced shared format, coding-style, post-validation, or compliance-template files. This document follows the fields and checks stated directly in the Skill definition.

## 范围解析

主文件列表包含 12 个 DUT RTL 文件，并通过 package include 展开为 `dv/` 下全部 89 个 SystemVerilog/SystemVerilog 头文件。 除解析接口穿越和 DUT 侧驱动所需内容外，DUT RTL 不在提取范围内。

| 分区 | 数量 | 范围 |
|---|---:|---|
| TB | 89 | `dv/common`, `dv/env`, `dv/seq`, `dv/tb`, `dv/tc` |
| 基础设施/VIP | 0 个仓库内文件 | UVM 由仿真器安装提供 |
| DUT | 12 | 名称d by `sim/sim.f`; interface-crossing evidence only |
| 未展开的文件列表条目 | 0 | `uvm_macros.svh` is an external UVM include, not a filelist entry |

No SV/SVH file under `dv/` is present-but-unlisted relative to the recursively expanded 主文件列表.

## 静态实例拓扑

```text
tb
├── clk/rst_n generators                              [时钟/复位/电源]
├── m_if[0..AXI_DUT_NUM_MASTERS-1] : axi_if          [测试线束]
├── s_if[0..AXI_DUT_NUM_SLAVES-1]  : axi_if          [测试线束]
├── master_ports[0..AXI_DUT_NUM_MASTERS-1]
│   └── protocol_assertions : axi_protocol_assertions[协议检查器]
├── slave_ports[0..AXI_DUT_NUM_SLAVES-1]
│   └── protocol_assertions : axi_protocol_assertions[协议检查器]
├── stage6_arbiter_bindings                          [bind container]
├── dut : axi_interconnect                           [DUT]
│   ├── fifo_{ar,r,aw,w,b}_{mx,sx}[0..2]
│   ├── u_axi_crossbar
│   │   ├── u_axi_mtos_s{0,1,2,sd}
│   │   │   └── u_axi_arbiter_mtos_m3
│   │   │       ├── stage6_aw_checker               [bound]
│   │   │       ├── stage6_w_checker                [bound]
│   │   │       └── stage6_ar_checker               [bound]
│   │   ├── u_axi_default_slave
│   │   └── u_axi_stom_m{0,1,2}
│   │       └── u_axi_arbiter_stom_s3
│   │           ├── stage6_b_checker                [bound]
│   │           └── stage6_r_checker                [bound]
│   ├── u_ar_sid_buffer / u_ar_reorder
│   └── u_aw_sid_buffer / u_aw_reorder
└── run_test()                                       [factory-selected UVM test]
```

The 18 bound arbiter checker instances are present in every `tb` elaboration: four request routers × three request-channel checkers, plus three response routers × two response-channel checkers. Their checking logic is active when `ENABLE_ALWAYS=1` or when `$test$plusargs("UVM_TESTNAME=axi_stage6")` matches.

Six separately selectable selftest modules are compiled by `sim/sim.f` but are not descendants of `tb`: `axi_protocol_assertions_selftest`, `axi_stage3_protocol_assertions_selftest`, `axi_stage6_protocol_assertions_selftest`, `axi_stage6_arbiter_assertions_selftest`, `axi_switch_ref_model_selftest`, and `axi_stage6_ref_model_selftest`.

## UVM 组件拓扑

以下名称是 UVM 组件路径，而非 SystemVerilog 实例路径。

```text
uvm_test_top : <factory-selected axi_*_test>
└── env : axi_env
    ├── m_agent_0..2 : axi_m_agent
    │   ├── monitor
    │   ├── sequencer                         [present when `cfg.is_active == UVM_ACTIVE`]
    │   └── driver                            [present when `cfg.is_active == UVM_ACTIVE`]
    ├── s_agent_0..2 : axi_s_agent
    │   ├── monitor
    │   ├── sequencer                         [present when `cfg.is_active == UVM_ACTIVE`]
    │   │   └── request_fifo
    │   └── driver                            [present when `cfg.is_active == UVM_ACTIVE`]
    ├── stage1_checker
    ├── stage2_checker
    ├── stage3_checker
    ├── ref_model
    │   ├── m_req_fifo_0..2
    │   └── s_rsp_fifo_0..2
    ├── scoreboard
    │   ├── exp_s_req_fifo_0..2 / act_s_req_fifo_0..2
    │   └── exp_m_rsp_fifo_0..2 / act_m_rsp_fifo_0..2
    ├── channel_checker
    │   ├── m_event_fifo_0..2
    │   └── s_event_fifo_0..2
    ├── virtual_sequencer
    ├── 覆盖率
    │   └── m_req_fifo_0..2
    ├── m_tracker_0..2
    │   └── channel_fifo
    └── s_tracker_0..2
        └── channel_fifo
```

`tb.sv` 将六个 agent 全部设为 active。`checker_mode` 选择主要检查层级：

| 模式 | 启用组件 |
|---|---|
| `AXI_CHECKER_STAGE1` | `stage1_checker`; all other tier checkers/reference/覆盖率 disabled |
| `AXI_CHECKER_STAGE2` | `stage2_checker` |
| `AXI_CHECKER_STAGE3` | `stage3_checker`, `m_tracker_0`, `s_tracker_0` |
| `AXI_CHECKER_STAGE6` | `ref_model`, `scoreboard`, `channel_checker`, `coverage`, all six trackers |

未启用的组件仍会被构造、连接并显示在 UVM 树中；其 `enabled` 字段会抑制检查工作。

## 文件与实例位置表

Each row has one role class. A 来源 that contributes more than one role is split by instance or code region.

| 源文件 | 实例/组件路径 | 角色 | 服务对象 |
|---|---|---|---|
| `dv/tb/tb.sv` | `tb` wiring and `m_if[]`/`s_if[]` | 测试线束 | system |
| `dv/tb/tb.sv` | `tb.clk`, `tb.rst_n` initial blocks | 时钟/复位/电源 | system |
| `dv/tb/axi_if.sv` | `tb.m_if[0..AXI_DUT_NUM_MASTERS-1]`, `tb.s_if[0..AXI_DUT_NUM_SLAVES-1]` | 测试线束 | 互连 |
| `dv/env/axi_protocol_assertions.sv` | `tb.{master,slave}_ports[*].protocol_assertions` | 协议检查器 | 互连 |
| `dv/env/axi_stage6_arbiter_assertions.sv` | 18 bound `stage6_*_checker` instances | 协议检查器 | 互连 arbitration |
| `dv/env/master/axi_m_driver.sv` | `uvm_test_top.env.m_agent_*.driver` | 激励驱动器 | upstream AXI ports |
| `dv/env/slave/axi_s_driver.sv` | `uvm_test_top.env.s_agent_*.driver` | 激励驱动器 | downstream AXI ports |
| `dv/env/master/axi_m_monitor.sv` | `uvm_test_top.env.m_agent_*.monitor` | monitor | upstream AXI ports |
| `dv/env/slave/axi_s_monitor.sv` | `uvm_test_top.env.s_agent_*.monitor` | monitor | downstream AXI ports |
| `dv/env/checker/stage1_e2e_checker.sv` | `uvm_test_top.env.stage1_checker` | scoreboard | M0↔S0 single-beat path |
| `dv/env/checker/stage2_e2e_checker.sv` | `uvm_test_top.env.stage2_checker` | scoreboard | M0↔S0 突发/反压路径 |
| `dv/env/checker/stage3_e2e_checker.sv` | `uvm_test_top.env.stage3_checker` | scoreboard | M0↔S0 outstanding/order path |
| `dv/env/checker/axi_system_scoreboard.sv` | `uvm_test_top.env.scoreboard` | scoreboard | all six external ports |
| `dv/env/checker/axi_channel_forwarding_checker.sv` | `uvm_test_top.env.channel_checker` | scoreboard | all five channels on all ports |
| `dv/env/axi_basic_event_comparator.sv` | class compiled; no main-env instance | scoreboard | reusable 工具, currently unattached |
| `dv/env/axi_switch_ref_model.sv` | objects inside system model/checkers/sequences | 参考模型 | routing and SID transforms |
| `dv/env/axi_system_ref_model.sv` | `uvm_test_top.env.ref_model` | 参考模型 | all six external ports and default route |
| `dv/env/axi_outstanding_tracker.sv` | `uvm_test_top.env.{m,s}_tracker_*` | monitor | per-port outstanding accounting |
| `dv/env/axi_system_coverage.sv` | `uvm_test_top.env.coverage` | 覆盖率 | master×route×direction |
| `dv/env/axi_env.sv` | `uvm_test_top.env` | 测试线束 | system |
| `dv/env/master/axi_m_agent.sv`, `dv/env/slave/axi_s_agent.sv` | `uvm_test_top.env.{m,s}_agent_*` | 工具 | component assembly |
| `dv/env/axi_virtual_sequencer.sv` | `uvm_test_top.env.virtual_sequencer` | 激励驱动器 | coordinated multiport stimulus |
| `dv/env/master/axi_m_sequencer.sv`, `dv/env/slave/axi_s_sequencer.sv` | agent `sequencer` children | 激励驱动器 | per-port stimulus |
| `dv/seq/*.sv` | sequence objects selected by tests | 激励驱动器 | directed/random scenario generation |
| `dv/tc/*.sv` | `uvm_test_top` factory types | 测试线束 | 测试配置和通过/失败 |
| `dv/tb/*selftest.sv` | six alternate top modules | 测试线束 | checker/model unit selftests |
| `dv/common/latency_gen.sv` | driver/sequence helper objects | 工具 | 延迟和反压生成 |
| `dv/common/axi_types_pkg.sv`, `dv/common/*.svh` | packages/macros/types | 工具 | system |
| `dv/env/axi_{req,rsp}_item.sv`, `dv/env/axi_channel_event.sv` | transaction/event objects | 工具 | system |
| `dv/env/*cfg.sv`, `dv/env/{master,slave}/*cfg.sv` | configuration objects | 工具 | 系统 |
| `dv/env/axi_env_pkg.sv`, `dv/seq/axi_seq_pkg.sv`, `dv/tc/axi_test_pkg.sv` | packages | 工具 | system |

仓库内不存在总线 VIP 或 memory model 角色。 响应式 slave sequence/driver 对是响应者激励路径，而不是存储模型。

## DUT 接口穿越与责任归属

该实现是 AXI3 风格子集，而非完整的 AMBA AXI3 端口集合。协议定义来源于 `rtl/doc/axi_interconnect-architecture-extracted.md` §12；端口方向来源于 `dv/tb/axi_if.sv`；有效合法性检查实现在 `dv/env/axi_protocol_assertions.sv`。DUT 侧边界结构记录于 `rtl/doc/axi_interconnect-top-microarchitecture.md` §§3–5。

| DUT 端口组 | 协议 | 权威规格/来源 | 上游 master | DUT 侧驱动模块 | TB observer | 各方向合法性责任方 |
|---|---|---|---|---|---|---|
| `M_AXI_*[0]` | AXI3-style subset | 架构 §12; `axi_if` modports; `axi_protocol_assertions` rule set | `uvm_test_top.env.m_agent_0.driver` | `tb.dut.fifo_{ar,aw,w}_mx[0].u_fifo_*` drives ready; `fifo_{r,b}_mx[0].u_fifo_*` drives response payload/valid | `tb.master_ports[0].protocol_assertions`; `uvm_test_top.env.m_agent_0.monitor` | TB owns AW/W/AR payload+VALID and B/R READY; DUT owns AW/W/AR READY and B/R payload+VALID |
| `M_AXI_*[1]` | AXI3-style subset | same 来源s | `uvm_test_top.env.m_agent_1.driver` | same boundary FIFO groups at index 1 | `tb.master_ports[1].protocol_assertions`; `uvm_test_top.env.m_agent_1.monitor` | same directional ownership as M0 |
| `M_AXI_*[2]` | AXI3-style subset | same 来源s | `uvm_test_top.env.m_agent_2.driver` | same boundary FIFO groups at index 2 | `tb.master_ports[2].protocol_assertions`; `uvm_test_top.env.m_agent_2.monitor` | same directional ownership as M0 |
| `S_AXI_*[0]` | AXI3-style subset | 架构 §12; `axi_if` modports; `axi_protocol_assertions` rule set | DUT routes from M0/M1/M2 through `u_axi_crossbar.u_axi_mtos_s0` | `tb.dut.fifo_{ar,aw,w}_sx[0].u_fifo_*` drives request payload/valid; `fifo_{r,b}_sx[0].u_fifo_*` drives response ready | `tb.slave_ports[0].protocol_assertions`; `uvm_test_top.env.s_agent_0.monitor` | DUT owns AW/W/AR payload+VALID and B/R READY; TB owns AW/W/AR READY and B/R payload+VALID |
| `S_AXI_*[1]` | AXI3-style subset | same 来源s | DUT routes from M0/M1/M2 through `u_axi_crossbar.u_axi_mtos_s1` | same boundary FIFO groups at index 1 | `tb.slave_ports[1].protocol_assertions`; `uvm_test_top.env.s_agent_1.monitor` | same directional ownership as S0 |
| `S_AXI_*[2]` | AXI3-style subset | same 来源s | DUT routes from M0/M1/M2 through `u_axi_crossbar.u_axi_mtos_s2` | same boundary FIFO groups at index 2 | `tb.slave_ports[2].protocol_assertions`; `uvm_test_top.env.s_agent_2.monitor` | same directional ownership as S0 |

The pin-level observers use these parameters:

| Observer 模式 | `ADDR_WIDTH` | `DATA_WIDTH` | `ID_WIDTH` | `LEN_WIDTH` | `MAX_OUTSTANDING` | 其他参数 |
|---|---:|---:|---:|---:|---:|---|
| `tb.master_ports[*].protocol_assertions` | 32 | 32 | 4 | 4 | 4 | `TB_IS_MASTER=1`, `STAGE3_CHECKS=1`, `STAGE6_CHECKS=1`, `PORT_INDEX=index` |
| `tb.slave_ports[*].protocol_assertions` | 32 | 32 | 8 | 4 | 4 | `TB_IS_MASTER=0`, `STAGE3_CHECKS=1`, `STAGE6_CHECKS=1`, `PORT_INDEX=index` |

这些是内部实现的子集检查器，不是完整的第三方 AXI 协议 VIP。 失败归因遵循上表的通道责任方；检查器、模型或配置本身仍可能存在缺陷，尤其涉及自定义 4/8 位 ID 编码时。

## 信号与检查数据流

```text
Master sequences → m_agent[*].driver → m_if[*] → DUT → s_if[*]
                                                   ↓
Reactive slave sequences ← s_agent[*].sequencer ← s_agent[*].monitor
              ↓                    ↑
       s_agent[*].driver ──────────┘

m/s monitor.channel_ap ─→ stage1/2/3 checker (port 0, selected mode)
                       ├→ channel_checker (all ports, 阶段 6)
                       └→ outstanding trackers
m monitor.req_ap ──────→ system reference model ─→ expected slave requests
s monitor.req_ap ─────────────────────────────────→ actual slave requests
s monitor.rsp_ap ──────→ system reference model ─→ expected master responses
m monitor.rsp_ap ─────────────────────────────────→ actual master responses
expected/actual streams ──────────────────────────→ system scoreboard
m monitor.req_ap ─────────────────────────────────→ system 覆盖率
```

## 控制旋钮

### 激励与配置

| 名称 | 类型 | 默认值 | 作用 | 消费者 |
|---|---|---|---|---|
| `+UVM_TESTNAME=<name>` / `test` / `TEST` | plusarg / Make variable | Questa: `axi_stage1_single_write_test`; VCS: `axi_stage1_single_read_test` | Selects factory test; names beginning `axi_stage6` also enable bound arbiter checker logic | UVM factory; bound arbiter checkers |
| `SEED`, `rand` | Make 变量 | Questa: `SEED=0` when `rand=n`; VCS: `SEED=1` | 控制随机化种子；`rand=y` 时生成新的 Questa 种子 | 仿真器 |
| `reg_times` | Make variable | 20 | Iteration count for repeated regression | `sim/Makefile` `regress` target |
| `env_cfg.checker_mode` | 配置对象枚举 | `AXI_CHECKER_STAGE1` | 选择阶段 1/2/3/6 检查层级 | `axi_env` |
| `m_cfg[*].is_active`, `s_cfg[*].is_active` | 配置对象枚举 | `UVM_ACTIVE` | 控制 driver/sequencer 的构造；monitor 始终存在 | agent |
| `m_cfg[*].port_index`, `s_cfg[*].port_index` | config-object integer | array index | Tags monitor events with 来源 port | monitors |
| `m_cfg[*].drv_vif`, `mon_vif`; `s_cfg[*].drv_vif`, `mon_vif` | virtual-interface 字段 | `null`, assigned by `tb` | 将每个 agent 绑定到对应接口 | driver 与 monitor |
| `m_cfg[*].max_read_outstanding` | config-object integer | 4; 阶段 2 sets M0 to 1 | Throttles accepted AR requests; legal range 1–4 | master drivers |
| `m_cfg[*].max_write_outstanding` | config-object integer | 4; 阶段 2 sets M0 to 1 | Throttles accepted AW/W requests; legal range 1–4 | master drivers |
| `m_cfg[*].request_prefetch_enabled` | config-object bit | 1; 阶段 2 sets M0 to 0 | Allows next sequence item before previous response completion | master drivers |
| latency generator `mode/min_delay/max_delay/fixed_delay/...` | object fields | random-capable, `fixed_delay=5`, cap 200 | Controls AW/W/AR ready and B/R ready delay and sequence gaps | drivers and scenario sequences |
| `TOP`, `FILELIST` | Make 变量 | `tb`, `sim.f` | 选择展开顶层和源文件清单 | 两个构建系统 |
| `UVM_HOME`, `UVM_LIB` | Make 变量 | local Questa defaults | Selects external UVM headers/library | Questa build |
| `VCS`, `SIM`, `VERDI_HOME` | Make 变量 | 仓库工具默认值 | 选择 VCS 仿真器和 Verdi 安装 | VCS 构建 |

All 来源-level `` `ifdef``/`` `ifndef`` `dv/` 中的条件编译均为 include guard，不会选择验证环境功能或实例。

### 可观测性

| 名称 | 类型 | 默认值 | 作用 | 消费者 |
|---|---|---|---|---|
| `dump` | Questa Make variable | `n` | When `y`, logs `tb.m_if/*`, `tb.s_if/*`, and `tb.dut/*` into WLF | `sim/Makefile` |
| `cov` | Questa Make 变量 | `n` | 启用仿真器代码/语句/表达式/FSM/翻转覆盖率并保存 UCDB | `sim/Makefile` |
| `UVM_VERBO` / `VERBOSITY` | Make variable → plusarg | `UVM_LOW` | Sets UVM report verbosity | UVM report system |
| `DUMP` | VCS Make variable | `0` | When `1`, emits `+DUMP_FSDB` and `+FSDB_FILE=...` | `sim_vcs/Makefile` |
| `+DUMP_FSDB` | plusarg | absent | Enables bound FSDB dumping | `sim_vcs/dump_fsdb.sv` |
| `+FSDB_FILE=<path>` | value plusarg | `wave.fsdb` fallback | Selects FSDB output path | `sim_vcs/dump_fsdb.sv` |
| `WORK_DIR`, `BUILD_DIR`, `LOG_DIR`, `WAVE_DIR`, `COV_DIR` | Make 变量 | 工具专用子目录 | Redirects compiled artifacts, logs, waves, and 覆盖率 | 构建系统 |

## 可观测性缺口

1. 每组外部 DUT AXI 端口都同时具备引脚级 checker 和 UVM monitor；不存在未观测的外部 DUT 端口组。
2. 所有 observer 到接口穿越的关系均已解析。未解析的协议/规格/合法性字段：**0**。
3. 功能覆盖率仅包含 `master × route × direction`. 不会采样 突发长度/类型/大小、响应类别、outstanding 深度、同 ID 与不同 ID 的顺序、反压持续时间、仲裁胜者/公平性、复位交互或 assertion/checker 结果.
4. Stage 1–3 end-to-end checkers consume only M0 and S0. Ports 1 and 2 are pin-monitored and assertion-checked but do not receive equivalent stage-specific TLM checking until 阶段 6 mode.
5. Bound arbitration checkers activate from a test-name prefix rather than `checker_mode`, so a renamed 阶段 6 test can silently disable them unless `ENABLE_ALWAYS` is overridden.
6. The pin-level protocol checker covers the implemented AXI3 subset and custom ID rules; it is not a complete AXI3 compliance VIP.
7. `axi_basic_event_comparator` 已编译但未在主环境中实例化.
8. Six selftest 来源 files are alternate top modules and are not reachable as instances from `tb`; they are reached only when selected explicitly as 仿真器 tops.
9. 不存在 memory model。 Reactive slave responses are sequence-driven and do not maintain addressable storage semantics.
10. 仓库内不存在总线 VIP；UVM 本身由外部基础设施提供。
11. The main Questa build can record broad DUT/interface waveforms, while the alternate VCS 构建 provides bound FSDB dumping. There is no common run metadata artifact that records all effective Make/config-object settings for later triage.

## 文件清单与角色统计

范围内的 89 个文件 are accounted for as follows:

- `common/` (4): `axi_types_pkg.sv`, `common_defines.svh`, `common_typedef.svh`, `latency_gen.sv` — 工具.
- `env/` root (14): packages, config, transaction/event types, environment assembly, protocol/bound checkers, reference models, outstanding monitor, virtual sequencer, 覆盖率, comparator — roles split in the location table.
- `env/master/` (5): agent/config/sequencer 工具 and driver/monitor roles.
- `env/slave/` (5): agent/config/sequencer 工具 and driver/monitor roles.
- `env/checker/` (5): scoreboard role.
- `seq/` (25): 激励驱动器 role, including package manifest.
- `tc/` (23): 测试线束 role, including package manifest.
- `tb/` (8): interface and primary/alternate harnesses; the primary top also supplies clock/reset and checker instances.

缺失的角色类别：`memory-model`、`bus-vip`。已存在的角色类别：`dut`（仅接口穿越引用）、`protocol-checker`、`monitor`、`scoreboard`、`reference-model`、`stimulus-driver`、`coverage`、`clock-reset-power`、`test-harness`、`utility`。

## 校验记录

| 检查项 | 结果 | 证据 |
|---|---|---|
| No phantom instances | 通过 | Every SV path is rooted in `tb.sv`, a UVM `type_id::create`/constructor call, or an explicit `bind` in `axi_stage6_arbiter_assertions.sv` |
| No phantom files | 通过 | All mapped `dv/` files resolve through `sim/sim.f` and recursive package includes |
| Interface 覆盖率 | 通过 | M0/M1/M2/S0/S1/S2 each appear exactly once in the crossing table |
| No per-assertion inventory | 通过 | The map records checker instances and capability boundaries only |
| Unresolved accounting | 通过 | 0 unresolved fields; Gaps §2 records the same count |
| File scope accounting | 通过 | `4 + 14 + 5 + 5 + 5 + 25 + 23 + 8 = 89` |

## Skill 合规性

| 要求 | 状态 | 证据 |
|---|---|---|
| Resolve scope before extraction | 通过 | 范围解析 identifies filelist, top, DUT, partitions, and counts |
| 保留符号数组和配置超集 | 通过 | 拓扑保留参数化/数组表示，不评估运行配置 |
| Separate SV and UVM namespaces | 通过 | Dedicated topology sections |
| Record clock/reset and binds | 通过 | Static topology includes both |
| Classify files/instances by one role per row | 通过 | 文件与实例位置表 |
| Map every DUT 端口组 and directional blame | 通过 | Six-row crossing table |
| Inventory plusargs, defines, config fields, and Make controls | 通过 | 控制旋钮 sections; include guards explicitly identified |
| Report observability and role gaps without inventing data | 通过 | 可观测性缺口和角色统计 |
| Exclude per-assertion inventory | 通过 | Only checker instances/capability classes are recorded |
| Add provenance and post-generation validation | 通过 | 来源信息 and 校验记录 sections |
| 共享模板/指令可用 | 不可用 | 已安装 plugin 包中缺少被引用文件；已直接遵循 Skill 要求 |

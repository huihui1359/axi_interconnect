# BUG：SID 随机激励未约束地址与 ID 一致，覆盖要求包含非法组合

**Author**: Codex, ?
**Created**: 2026-10-25 17:20
**Current Version**: v1.1

**Version Changelog**:
- **v1.1** (2026-10-25 17:50): 按用户确认的 DUT 契约重新定性为激励和覆盖模型错误；恢复地址/ID 一致性断言，约束正向随机 ID，修正合法组合分母并补充负向自检和本轮回归结果。
- **v1.0** (2026-10-25 17:20): 初版将问题判断为读 ID 断言误报；该判断依据不足，相关结论已由 v1.1 撤销。

---

## 1. 结论与本次更正

**本问题是正向随机测试违反 DUT 输入契约，以及覆盖要求包含非法组合。原有 AR 地址/ID 一致性断言应保留。**

用户于 2026-10-25 明确：master 给出的 AW/AR 地址与对应 ID 的目标编码必须一致；AWID、ARID、WID 的高两位表示访问的 slave。W 本身没有地址，必须匹配对应 AW 事务。不能把“ARADDR 指向 S1、ARID 高两位指向 S2”作为合法请求。

v1.0 从“RTL 的 ARSELECT 只看地址”推导出“ARID 可独立于地址任意取值”，混淆了实现中的选择逻辑与系统对合法输入的要求。此前放宽 AR/R 断言、把每个目标上的全部 16 个原始读 ID 当作合法组合的方案已撤销；此前基于该方案的 PASS 不能用于证明满足本次明确的输入契约。

保留原文件名是为了保持已有文档链接有效，当前标题、正文和 v1.1 结论为准。

| 项目 | 内容 |
| --- | --- |
| 问题编号 | BUG-20261025-01 |
| 类型 | DV 正向激励与覆盖建模错误 |
| 状态 | 已修正，已按地址/ID 一致性要求重新验证 |
| 发现用例 | `tp_sid_random`，seed=0，10,000 笔事务 |
| 当前修改范围 | CR 配置、SID 测试激励/覆盖、断言自检及相关文档 |
| 协议断言处理 | 撤销本次先前的放宽修改，恢复原有检查逻辑 |
| RTL 修改 | 无 |

## 2. 先理解 DUT 的输入契约

### 2.1 路由选择和输入合法性是两个层次

| 通道 | RTL 如何选择目标 | master 必须满足的条件 |
| --- | --- | --- |
| AW | 按 AWADDR 译码 | AWID[3:2] 编码同一个目标 |
| AR | 按 ARADDR 译码 | ARID[3:2] 编码同一个目标 |
| W | 按 WID[3:2]，并受已登记 AW SID 资格约束 | WID 与对应 AWID 匹配，目标与该 AW 地址一致 |

不能因为 AW/AR 的地址译码表达式不读取 ID，就认为 ID 与地址可以不一致。RTL 可以依赖上游满足输入契约，而验证环境必须检查这份契约。

### 2.2 每个真实目标有哪些合法 ID

当前配置为 4 位原始 ID，其中高两位是目标编码，低两位是目标内事务 tag：

```text
原始 AWID / ARID / WID

        [3:2]                  [1:0]
  +------------------+-------------------+
  | 目标 slave 编码  | 目标内事务 tag    |
  +------------------+-------------------+
```

| 目标 | 地址窗口 | ID 高两位 | 合法原始 ID |
| --- | --- | --- | --- |
| S0 | 0x0000..0x0fff | 01 | 0x4、0x5、0x6、0x7 |
| S1 | 0x2000..0x2fff | 10 | 0x8、0x9、0xa、0xb |
| S2 | 0x4000..0x4fff | 11 | 0xc、0xd、0xe、0xf |

这是项目确认的约定。default 的 ID 编码尚未由用户确认，不能自行把 `00` 解释为已经实现并验证的 default 编码。本次正向 CR 仅包含三个真实目标。

### 2.3 内部 SID 的扩展不取消原始 ID 的约束

读请求转发到 slave 时仍使用以下形式：

```text
SID[7:0] = {目标 tag[1:0], 来源 master tag[1:0], 原始 ARID[3:0]}

对于合法真实目标请求：
SID[7:6] = 原始 ARID[3:2]
```

例如，M0 访问 S1：

```text
ARADDR = 0x2100
ARID   = 0x8 = {S1 目标码 10, 事务 tag 00}
SID    = {10, 01, 1000} = 0x98
```

地址和 ID 均表示 S1，因此合法。如果保持 `ARADDR=0x2100`，却给出 `ARID=0xc`，ID 高两位表示 S2，该输入违反契约，即使 RTL 的地址选择逻辑仍会选 S1。

原始 ID 仍参与事务识别和 SID 登记。准确的解释是“高两位编码目标，低两位区分目标内事务”，不能将全部 4 位解释为与目标无关的不透明字段。

## 3. 失败现象及定位过程

### 3.1 原始日志

seed=0 的首错发生在 master 侧 AR 握手，日志时间单位为 ps：

```text
UVM_ERROR @ 55000: reporter [AXI_ASSERT_AR_ID]
Offending 'valid_stage3_id(arid)'

UVM_ERROR @ 55000: reporter [AXI_ASSERT_AR_ROUTE]
Offending 'id_matches_address(arid, araddr)'
```

随后 slave 侧 AR、返回 R 和 master 侧 R 也触发相关检查：

| 报错 ID | 原始 seed=0 次数 | 按确认后的契约解释 |
| --- | ---: | --- |
| AXI_ASSERT_AR_ID | 4,887 | 原始目标码非法，或内部 SID 与原始目标码不一致 |
| AXI_ASSERT_AR_ROUTE | 3,697 | 地址译码的目标与 ID 编码不一致 |
| AXI_ASSERT_AR_SLAVE_TAG | 3,697 | 内部目标 tag 与原始 ID 高两位不一致 |
| AXI_ASSERT_R_ID | 4,887 | 返回 ID/SID 继续暴露同一编码违规 |
| AXI_ASSERT_R_SLAVE_TAG | 3,697 | 返回 SID 的目标编码关系不满足契约 |

最终为 20,865 个 UVM_ERROR 和 1 个 UVM_FATAL。这些断言是在不同位置重复检查输入契约，不能通过屏蔽它们来让正向测试通过。

### 3.2 根因一：正向激励遗漏 ID/地址关联约束

[axi_cr_cfg.sv](../../seq/axi_cr_cfg.sv) 原来默认 `constrain_read_id_to_route=0`，`tp_sid_random` 也没有开启它。

[axi_cr_op.sv](../../seq/axi_cr_op.sv) 已有以下条件约束：

```systemverilog
if ((local::selected_dir == AXI_READ) &&
    local::constrain_read_id_to_route)
  id[AXI_M_ID_WIDTH-1 -: 2] == local::route_tag;
```

开关关闭时，该约束不生效，读 ID 会在全部 16 个值中随机。对固定目标而言，只有 4 个 ID 满足要求，其他 12 个组合都不应作为正向输入。其他正向随机用例此前显式开启该约束，因而没有暴露同样的问题。

### 3.3 根因二：覆盖目标要求每个目标出现 16 个原始读 ID

[tp_sid_random.sv](../../tc/tp_sid_random.sv) 原来要求每个 master、每个 slave 都出现全部 16 个读 ID。

这使测试包含两个相互矛盾的要求：协议断言要求 ID 高两位匹配目标，而覆盖闭合却要求不匹配目标的 ID 也出现。仅恢复约束而不修改覆盖分母，会继续因缺少非法组合而失败。

正确的正向覆盖分母为：

```text
每方向：3 masters × 3 targets × 4 local tags = 36 个合法组合
读写合计：36 + 36 = 72 个合法组合
```

更正分母的依据是已确认 DUT 契约；每个合法组合仍须命中。非法组合保留在独立负向自检中，检查它们是否被断言识别。

## 4. 如何修改

### 4.1 恢复一致性断言

[axi_protocol_assertions.sv](../../env/axi_protocol_assertions.sv) 恢复先前的检查行为：

- master 侧 AR 握手时，原始 ARID 目标码必须有效，并与 ARADDR 目标匹配。
- slave 侧 SID 的真实目标字段必须匹配物理端口，来源 master tag 必须合法。
- SID 的目标字段必须与原始 ID 高两位一致。
- R 通道保留对应 ID 编码检查，事务配对、beat 数、LAST 和 payload 稳定性检查继续执行。

本轮不是让 RTL 增加按 ARID 选择路由的逻辑，而是让正向激励满足现有 DUT 输入要求。

### 4.2 在公共配置和 SID 用例中约束正向输入

公共 `axi_cr_cfg` 将 `constrain_read_id_to_route` 默认设为 1，并在 `validate()` 中拒绝关闭该约束。该类当前只服务正向 CR；将来的非法组合测试需要单独的 expected-error 流程。

`tp_sid_random::configure_cr_cfg()` 也显式设置该字段，便于读代码时直接看到该用例的输入假设。

### 4.3 检查全部合法读写组合

读写统一按目标和低两位 tag 构造覆盖检查下标：

```systemverilog
for (int unsigned tag = 0; tag < 4; tag++) begin
  legal_id = ((slave + 1) << 2) | tag;
  // 检查 planned_id_count[master][slave][read/write][legal_id] 非零。
end
```

完整测试仍运行 10,000 笔事务，并检查每个 master、目标、方向和合法 local tag。计划组合统计与响应 scoreboard、pending 排空共同作为通过依据；组合统计不能替代端到端响应检查。

### 4.4 定向自检验证“合法通过、违规报错”

[axi_stage6_protocol_assertions_selftest.sv](../../tb/axi_stage6_protocol_assertions_selftest.sv) 同时使用 4 位 master 检查器和 8 位 slave 检查器。

| 自检输入 | 预期 |
| --- | --- |
| S2，3 个 master tag × 4 个合法 local tag，ID=0xc..0xf | 12 笔完整读事务无意外错误 |
| SID=0x9c、地址=0x4100，在 S2 检查器上 | 内部目标 tag 错误，相关断言报错 |
| SID=0xcc、地址=0x4100 | 来源 master tag=00，相关断言报错 |
| SID=0xe8、地址=0x4100 | 内部目标与地址均为 S2，但原始 ID 高两位为 S1；master AR 路由断言和 slave AR/R tag 断言均报错 |

最后一项专门验证本次确认的要求：即使内部 SID 的新增目标字段正确，也必须检查原始 ID 与地址一致。检查前清零相关标志，避免之前的预期错误使该场景假通过。

report catcher 捕获这些预期错误，最终检查预期报错确实发生，并以 `AXI_STAGE6_ASSERT_SELFTEST_PASS` 表示自检通过。

## 5. 本轮验证结果

以下结果来自恢复原有一致性断言、约束正向 ID 之后的重新运行：

| 项目 | 结果 |
| --- | --- |
| VCS 编译 | PASS |
| tp_sid_random，seed=0，10,000 笔 | PASS，UVM_ERROR/UVM_FATAL 均为 0 |
| tp_sid_random，历史 seed=3027，10,000 笔 | PASS，UVM_ERROR/UVM_FATAL 均为 0 |
| 修改后的 Stage 6 协议断言自检 | PASS，包含原始 ID 与地址不一致负向场景 |
| 全部用例，seed=0 | 30/30 PASS |
| 背压修复兼容性 | 五通道 stall mask 均为 11111，B/R 最大 stall 均为 20 拍 |

先前“任意原始读 ID”的自检和回归只作为被撤销方案的历史记录，不作为本轮验收证据。本轮未重新运行全部六项 selftest；重新执行的是修改后的 Stage 6 协议断言自检，以及完整 30 项集成回归。本轮未收集覆盖率数据库，也未验证 default 编码与 default 写路径。

## 6. 运行命令与证据

在 `sim_vcs/` 中执行：

```sh
make sim test=tp_sid_random SEED=0
make sim test=tp_sid_random SEED=3027
make selftest SELFTEST=axi_stage6_protocol_assertions_selftest
make regress suite=full nseeds=1 SEED=0
```

| 证据 | 文件 |
| --- | --- |
| 最初失败回归 | [regress_20261025_164444_C68lZY.log](../../../sim_vcs/work/log/regress_20261025_164444_C68lZY.log) |
| 最初失败单测 | [tp_sid_random_0.log](../../../sim_vcs/work/log/debug_20261025_before/tp_sid_random_0.log) |
| 本轮 seed=0 | [tp_sid_random_0.log](../../../sim_vcs/work/log/tp_sid_random_0.log) |
| 本轮 seed=3027 | [tp_sid_random_3027.log](../../../sim_vcs/work/log/tp_sid_random_3027.log) |
| 本轮断言自检 | [contract_stage6_selftest.out](../../../sim_vcs/work/log/contract_stage6_selftest.out) |
| 本轮完整回归 | [regress_20261025_175028_gOlZ0t.log](../../../sim_vcs/work/log/regress_20261025_175028_gOlZ0t.log) |
| 被撤销方案的单测与自检快照 | [before_route_contract](../../../sim_vcs/work/log/before_route_contract) |

生成目录中的日志可能被后续同名运行覆盖或被清理。本文内嵌的关键数字和契约说明用于保留问题学习所需的上下文。

## 7. 工程师应从这个问题学到什么

调试协议断言时，应先确认项目输入契约，再解释 RTL 的实现机制。实现使用哪个字段选择目标，与调用方必须保证哪些字段一致，是两项需要分别核对的事实。

修改 checker 之前，还应检查激励约束和覆盖分母是否来自同一份契约。如果激励生成非法组合，而覆盖又要求这些组合出现，放宽断言只能隐藏矛盾。正确处理是修正正向输入及合法覆盖集合，并用 expected-error 自检保留对非法输入的检测能力。

本项目的权威契约与计划已同步记录于 [架构规格](../../../rtl/doc/axi_interconnect-architecture-extracted.md)、[验证计划](../zflow/axi_interconnect-testplan.md)、[testbench plan](../zflow/axi_interconnect-testbench-plan.md) 和 [随机测试实施计划](../zflow/axi_interconnect-random-test-implementation-plan.md)。

另一个独立问题见 [响应 READY 延迟提前消耗](bug_20261025_02_response-ready-delay-before-valid.md)。

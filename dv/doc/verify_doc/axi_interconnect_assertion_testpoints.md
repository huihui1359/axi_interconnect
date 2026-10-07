# AXI Interconnect 断言测试点说明

**Author**: Sun Menghui, Codex, GPT-5.6 sol
**Created**: 2026-10-07 12:34
**Current Version**: v1.1

**Version Changelog**:
- **v1.1** (2026-10-07 16:59): 纳入 `axi_protocol_assertions` 的8个辅助函数和47个断言测试点，区分并发SVA、复位SVA、协议立即断言、ID/路由检查及顺序/outstanding检查，并补充对应回归入口。
- **v1.0** (2026-10-07 12:34): 建立可扩展的项目级断言测试点目录，首批纳入 Stage 6 arbiter 的 grant合法性、round-robin顺序、指针更新和反压稳定性检查。

---

## 1. 文档目的

本文档统一记录 AXI interconnect 验证环境中的断言测试点、适用范围、判定条件和失败报告 ID。当前版本包含 arbiter 和 AXI protocol 断言；后续新增其他内部模块断言时，继续在本文档中按功能域扩展。

断言负责局部、周期级规则检查；端到端路由、事务数据比较、ID 映射和复杂 outstanding 行为继续由 UVM reference model 与 scoreboard 检查。

## 2. Arbiter 断言模块

### 2.1 实现与绑定

- SVA 实现：`dv/env/axi_stage6_arbiter_assertions.sv`
- 断言容器：`axi_stage6_rr_pointer_checker`
- 绑定容器：`axi_stage6_arbiter_bindings`
- 绑定对象：
  - `axi_arbiter_mtos_m3`：AW、W、AR，仲裁宽度为 3
  - `axi_arbiter_stom_s3`：B、R，仲裁宽度为 4
- 时钟：`clk` 上升沿
- 关闭条件：复位未可靠释放，或当前测试未启用 Stage 6 arbiter 断言
- 启用条件：参数 `ENABLE_ALWAYS=1`，或者命令行存在以 `UVM_TESTNAME=axi_stage6` 开头的 plusarg

`locked` 连接到 round-robin 模块的 `pending_valid`。当 `locked=1` 时，arbiter 正在保持一个尚未接受的选择，不重新执行组合 round-robin 结果检查。

`accept` 表示当前 grant 已完成一次有效传输接受：

```systemverilog
accept = |(grant & valid & ready);
```

### 2.2 断言测试点

| 测试点 ID | Property / Assertion | 检查目标 | SVA 判定关系 | 失败报告后缀 |
|---|---|---|---|---|
| ARB-SVA-001 | `p_grant_onehot` / `a_grant_onehot` | grant 为 zero-hot 或 one-hot，禁止同时授予多个请求端 | `$onehot0(grant)` | `GRANT_ONEHOT` |
| ARB-SVA-002 | `p_grant_has_request` / `a_grant_has_request` | 非锁定状态下，不得向未请求端口发出 grant | `!locked \|-> ((grant & ~request) == '0)` | `GRANT_WITHOUT_REQUEST` |
| ARB-SVA-003 | `p_round_robin_order` / `a_round_robin_order` | 非锁定状态下，实际 grant 符合由 `request` 和 `last_winner` 决定的 round-robin 顺序 | `!locked \|-> grant == expected_grant(request, last_winner)` | `ROUND_ROBIN_ORDER` |
| ARB-SVA-004 | `p_pointer_updated_on_accept` / `a_pointer_updated_on_accept` | 接受一次 grant 后，公平性指针记录本次获胜端口 | `accept \|=> last_winner == $past(grant)` | `POINTER_NOT_UPDATED_ON_HANDSHAKE` |
| ARB-SVA-005 | `p_pointer_stable_without_accept` / `a_pointer_stable_without_accept` | 没有接受 grant 时，公平性指针不得提前推进 | `!accept \|=> $stable(last_winner)` | `POINTER_CHANGED_WITHOUT_HANDSHAKE` |
| ARB-SVA-006 | `p_grant_stable_while_stalled` / `a_grant_stable_while_stalled` | grant 尚未接受时，下一周期继续保持相同获胜端口 | `((\|grant) && !accept) \|=> $stable(grant)` | `GRANT_CHANGED_WHILE_STALLED` |

完整的 UVM 报告 ID 格式为：

```text
AXI_STAGE6_ARB_<通道名>_<失败报告后缀>
```

例如，AW 通道在没有 accept 时错误更新 pointer，报告 ID 为：

```text
AXI_STAGE6_ARB_AW_POINTER_CHANGED_WITHOUT_HANDSHAKE
```

### 2.3 各通道覆盖范围

| 通道 | 数据流方向 | 仲裁候选数 | `request` 来源 | `accept` 来源 | `locked` 来源 |
|---|---|---:|---|---|---|
| AW | Master 到 Slave | 3 | `AWSELECT & AWVALID` | `AWGRANT & AWVALID & AWREADY` 的归约或 | `u_arbiter_aw.pending_valid` |
| W | Master 到 Slave | 3 | `WSELECT & WVALID` | `WGRANT & WVALID & WREADY` 的归约或 | `u_arbiter_w.pending_valid` |
| AR | Master 到 Slave | 3 | `ARSELECT & ARVALID` | `ARGRANT & ARVALID & ARREADY` 的归约或 | `u_arbiter_ar.pending_valid` |
| B | Slave 到 Master | 4 | `BSELECT & BVALID` | `BGRANT & BVALID & BREADY` 的归约或 | `u_arbiter_b.pending_valid` |
| R | Slave 到 Master | 4 | `RSELECT & RVALID` | `RGRANT & RVALID & RREADY` 的归约或 | `u_arbiter_r.pending_valid` |

## 3. AXI Protocol 断言模块

### 3.1 实现与例化范围

- 实现文件：`dv/env/axi_protocol_assertions.sv`
- 断言容器：`axi_protocol_assertions`
- 采样时钟：`ACLK` 上升沿
- Master侧：3个实例，`ID_WIDTH=4`、`TB_IS_MASTER=1`
- Slave侧：3个实例，`ID_WIDTH=8`、`TB_IS_MASTER=0`
- 顶层当前统一配置：`MAX_OUTSTANDING=4`、`STAGE3_CHECKS=1`、`STAGE6_CHECKS=1`
- `PORT_INDEX`：标识当前Master/Slave端口，用于Stage 6 SID路由字段检查

基础稳定性、X/Z和复位检查始终生效；ID、顺序和outstanding检查受 `STAGE3_CHECKS` 控制；地址与ID路由匹配检查进一步受 `STAGE6_CHECKS` 控制。

### 3.2 辅助函数

| 函数 | 职责 | 是否直接产生断言报告 |
|---|---|---|
| `report_assertion_error()` | 将断言失败统一转换为带指定report ID的 `UVM_ERROR` | 是，所有断言统一调用 |
| `write_outstanding()` | 汇总所有ID尚未返回B响应的写地址事务数量 | 否，供ORD-IMM-015使用 |
| `read_outstanding()` | 汇总所有ID尚未完成R响应的读地址事务数量 | 否，供ORD-IMM-016使用 |
| `valid_stage3_id()` | 按Stage、接口ID位宽和端口检查完整ID编码是否合法 | 否，供ID-IMM系列使用 |
| `valid_stage3_master_tag()` | 检查8-bit SID中的master tag是否合法 | 否，供ID-IMM系列使用 |
| `valid_stage3_slave_tag()` | 检查8-bit SID中的源slave tag与路由slave tag是否一致 | 否，供ID-IMM系列使用 |
| `id_matches_address()` | 根据地址窗口生成route tag，并与ID高位路由字段比较 | 否，供ID-IMM-004/011使用 |
| `pair_write_context()` | 按ID配对AWLEN和已完成W burst beat数 | 是，执行ORD-IMM-001 |

### 3.3 通道并发SVA

| 测试点 ID | Property / Assertion | 检查目标 | 判定关系 | 报告 ID |
|---|---|---|---|---|
| AXI-SVA-001 | `p_aw_stable` / `a_aw_stable` | AW反压期间保持VALID及payload | `awvalid && !awready \|=> awvalid && $stable(AW payload)` | `AXI_ASSERT_AW_STABLE` |
| AXI-SVA-002 | `p_w_stable` / `a_w_stable` | W反压期间保持VALID及payload | `wvalid && !wready \|=> wvalid && $stable(W payload)` | `AXI_ASSERT_W_STABLE` |
| AXI-SVA-003 | `p_b_stable` / `a_b_stable` | B反压期间保持VALID及payload | `bvalid && !bready \|=> bvalid && $stable(B payload)` | `AXI_ASSERT_B_STABLE` |
| AXI-SVA-004 | `p_b_causality` / `a_b_causality` | BVALID必须存在已完成W burst的因果上下文 | `bvalid \|-> b_eligible_count != 0`，或本周期完成W burst | `AXI_ASSERT_B_CAUSALITY` |
| AXI-SVA-005 | `p_ar_stable` / `a_ar_stable` | AR反压期间保持VALID及payload | `arvalid && !arready \|=> arvalid && $stable(AR payload)` | `AXI_ASSERT_AR_STABLE` |
| AXI-SVA-006 | `p_r_stable` / `a_r_stable` | R反压期间保持VALID及payload | `rvalid && !rready \|=> rvalid && $stable(R payload)` | `AXI_ASSERT_R_STABLE` |

上述属性在 `ARESETn !== 1'b1` 时通过 `disable iff` 关闭。

### 3.4 复位并发SVA

| 测试点 ID | Property / Assertion | 适用实例 | 检查目标 | 报告 ID |
|---|---|---|---|---|
| RST-SVA-001 | `p_master_outputs_reset` / `a_master_outputs_reset` | `TB_IS_MASTER=1` | 复位期间 `AWVALID/WVALID/BREADY/ARVALID/RREADY` 均为0 | `AXI_ASSERT_MASTER_RESET_OUTPUTS` |
| RST-SVA-002 | `p_slave_outputs_reset` / `a_slave_outputs_reset` | `TB_IS_MASTER=0` | 复位期间 `AWREADY/WREADY/BVALID/ARREADY/RVALID` 均为0 | `AXI_ASSERT_SLAVE_RESET_OUTPUTS` |

### 3.5 协议与X/Z立即断言

| 测试点 ID | 触发条件 | 检查目标 | 报告 ID |
|---|---|---|---|
| AXI-IMM-001 | 复位释放后的每个ACLK上升沿 | 五通道VALID/READY控制信号均不包含X/Z | `AXI_ASSERT_CONTROL_X` |
| AXI-IMM-002 | AW握手 | AWID、AWADDR、AWLEN、AWSIZE、AWBURST均不包含X/Z | `AXI_ASSERT_AW_PAYLOAD_X` |
| AXI-IMM-003 | W握手 | WID、WDATA、WSTRB、WLAST均不包含X/Z | `AXI_ASSERT_W_PAYLOAD_X` |
| AXI-IMM-004 | AR握手 | ARID、ARADDR、ARLEN、ARSIZE、ARBURST均不包含X/Z | `AXI_ASSERT_AR_PAYLOAD_X` |
| AXI-IMM-005 | B握手 | BID、BRESP均不包含X/Z | `AXI_ASSERT_B_PAYLOAD_X` |
| AXI-IMM-006 | R握手 | RID、RDATA、RRESP、RLAST均不包含X/Z | `AXI_ASSERT_R_PAYLOAD_X` |

### 3.6 ID与路由立即断言

| 测试点 ID | 通道 | 检查目标 | 使能条件 | 报告 ID |
|---|---|---|---|---|
| ID-IMM-001 | AW | AWID完整编码合法 | `STAGE3_CHECKS` | `AXI_ASSERT_AW_ID` |
| ID-IMM-002 | AW | AWID master tag合法 | `STAGE3_CHECKS` | `AXI_ASSERT_AW_MASTER_TAG` |
| ID-IMM-003 | AW | AWID源slave tag与路由slave tag一致 | `STAGE3_CHECKS` | `AXI_ASSERT_AW_SLAVE_TAG` |
| ID-IMM-004 | AW | AWID目标路由字段匹配AWADDR窗口 | `STAGE3_CHECKS && STAGE6_CHECKS` | `AXI_ASSERT_AW_ROUTE` |
| ID-IMM-005 | W | WID完整编码合法 | `STAGE3_CHECKS` | `AXI_ASSERT_W_ID` |
| ID-IMM-006 | W | WID master tag合法 | `STAGE3_CHECKS` | `AXI_ASSERT_W_MASTER_TAG` |
| ID-IMM-007 | W | WID源slave tag与路由slave tag一致 | `STAGE3_CHECKS` | `AXI_ASSERT_W_SLAVE_TAG` |
| ID-IMM-008 | AR | ARID完整编码合法 | `STAGE3_CHECKS` | `AXI_ASSERT_AR_ID` |
| ID-IMM-009 | AR | ARID master tag合法 | `STAGE3_CHECKS` | `AXI_ASSERT_AR_MASTER_TAG` |
| ID-IMM-010 | AR | ARID源slave tag与路由slave tag一致 | `STAGE3_CHECKS` | `AXI_ASSERT_AR_SLAVE_TAG` |
| ID-IMM-011 | AR | ARID目标路由字段匹配ARADDR窗口 | `STAGE3_CHECKS && STAGE6_CHECKS` | `AXI_ASSERT_AR_ROUTE` |
| ID-IMM-012 | B | BID完整编码合法 | `STAGE3_CHECKS` | `AXI_ASSERT_B_ID` |
| ID-IMM-013 | B | BID master tag合法 | `STAGE3_CHECKS` | `AXI_ASSERT_B_MASTER_TAG` |
| ID-IMM-014 | B | BID源slave tag与路由slave tag一致 | `STAGE3_CHECKS` | `AXI_ASSERT_B_SLAVE_TAG` |
| ID-IMM-015 | R | RID完整编码合法 | `STAGE3_CHECKS` | `AXI_ASSERT_R_ID` |
| ID-IMM-016 | R | RID master tag合法 | `STAGE3_CHECKS` | `AXI_ASSERT_R_MASTER_TAG` |
| ID-IMM-017 | R | RID源slave tag与路由slave tag一致 | `STAGE3_CHECKS` | `AXI_ASSERT_R_SLAVE_TAG` |

### 3.7 Burst、顺序与Outstanding立即断言

| 测试点 ID | 检查目标 | 使能/触发条件 | 报告 ID |
|---|---|---|---|
| ORD-IMM-001 | 已完成W burst的beat数等于配对AWLEN加1 | 同ID的AW长度和W完成记录均存在 | `AXI_ASSERT_W_COUNT` |
| ORD-IMM-002 | 一个未完成W burst内WID保持不变 | W握手且已有active W burst | `AXI_ASSERT_WID_STABLE` |
| ORD-IMM-003 | WLAST不得早于AWLEN指定beat | W beat数小于期望值 | `AXI_ASSERT_WLAST_EARLY` |
| ORD-IMM-004 | WLAST不得晚于AWLEN指定beat | W beat数等于期望值 | `AXI_ASSERT_WLAST_MISSING` |
| ORD-IMM-005 | W beat数不得超过AWLEN加1 | W beat数大于期望值 | `AXI_ASSERT_W_COUNT_EXCESS` |
| ORD-IMM-006 | B响应存在同ID的AW和完整W上下文 | B握手且 `STAGE3_CHECKS` | `AXI_ASSERT_B_NO_PENDING` |
| ORD-IMM-007 | B响应不得使写地址outstanding下溢 | B握手且找到部分同ID上下文 | `AXI_ASSERT_B_AW_UNDERFLOW` |
| ORD-IMM-008 | B响应前同ID W burst已经完成 | B握手且找到部分同ID上下文 | `AXI_ASSERT_B_SAME_ID_ORDER` |
| ORD-IMM-009 | 新R burst存在同ID的未完成AR上下文 | 首个R beat握手 | `AXI_ASSERT_R_CAUSALITY` |
| ORD-IMM-010 | 一个未完成R burst内RID保持不变 | R握手且已有active R burst | `AXI_ASSERT_RID_STABLE` |
| ORD-IMM-011 | RLAST不得早于ARLEN指定beat | R beat数小于期望值 | `AXI_ASSERT_RLAST_EARLY` |
| ORD-IMM-012 | RLAST不得晚于ARLEN指定beat | R beat数等于期望值 | `AXI_ASSERT_RLAST_MISSING` |
| ORD-IMM-013 | R beat数不得超过ARLEN加1 | R beat数大于期望值 | `AXI_ASSERT_R_COUNT_EXCESS` |
| ORD-IMM-014 | RLAST完成时读outstanding不得下溢 | RLAST握手 | `AXI_ASSERT_R_UNDERFLOW` |
| ORD-IMM-015 | 全部ID的写outstanding总量不超过配置上限 | 每周期且 `STAGE3_CHECKS` | `AXI_ASSERT_WRITE_OUTSTANDING` |
| ORD-IMM-016 | 全部ID的读outstanding总量不超过配置上限 | 每周期且 `STAGE3_CHECKS` | `AXI_ASSERT_READ_OUTSTANDING` |

## 4. 采样语义与边界

- ARB-SVA-001～003 在同一个 `posedge clk` 采样点检查当前组合仲裁结果。
- ARB-SVA-004～006 使用非重叠蕴含 `|=>`，检查当前事件对下一采样周期状态的影响。
- `$past(grant)` 表示产生 `accept` 的那个采样周期的 grant。
- `$stable(last_winner)` 和 `$stable(grant)` 比较相邻两个有效采样周期。
- `disable iff` 在复位期间及断言未启用期间终止属性求值，避免复位和非 Stage 6 测试产生无效报告。
- ARB-SVA-003 的 `expected_grant()` 是独立、参数化的期望值计算函数，用于检查仲裁结果；它不保存 DUT 状态。
- AXI-SVA-001～006使用并发SVA采样语义；其中反压稳定性使用非重叠蕴含，在下一ACLK采样点检查VALID和payload。
- RST-SVA-001～002在 `ARESETn === 1'b0` 的ACLK采样点检查接口输出复位值。
- `AXI-IMM`、`ID-IMM` 和 `ORD-IMM` 是 `always @(posedge ACLK)` 中的立即断言，使用过程块当前采样到的信号和内部tracker状态。
- ID/route检查只在对应通道完成握手且ID已知时执行；unknown payload由独立的 `AXI-IMM` 测试点报告。

这些属性检查有限周期内可直接观察的安全性和功能关系，不替代以下事务级检查：

- 地址到目标 Slave 的端到端路由；
- AW/W/B 与 AR/R 的事务关联；
- 跨接口的ID映射、同ID端到端顺序及完整outstanding transaction数据比较；
- 跨多个已接受事务的系统级公平性统计。

## 5. 验证与回归入口

- 基础protocol断言负向selftest：`make assertion_selftest`
- Stage 3 protocol断言负向selftest：`make stage3_assertion_selftest`
- Stage 6 protocol断言负向selftest：`make stage6_assertion_selftest`
- Stage 6 arbiter断言负向selftest：`make stage6_arbiter_selftest`
- Stage 6 全量回归：`make stage6_regress`
- 单用例运行：`make sim test=<axi_stage6_test_name> SEED=<seed>`

`dv/tb/axi_protocol_assertions_selftest.sv`、`dv/tb/axi_stage3_protocol_assertions_selftest.sv` 和 `dv/tb/axi_stage6_protocol_assertions_selftest.sv` 分别注入基础协议、Stage 3及Stage 6非法场景并捕获预期report ID。`dv/tb/axi_stage6_arbiter_assertions_selftest.sv` 通过非法修改 `last_winner`，确认 ARB-SVA-005能够产生并被捕获的错误报告。其余合法场景由Stage 1～6定向测试和回归流量持续检查。

## 6. 后续断言测试点扩展规则

后续添加其他断言时，应为每个测试点补充以下信息：

1. 全局唯一测试点 ID；
2. property 和 assertion label；
3. 被检查模块、接口及信号；
4. 时钟、复位和禁用条件；
5. 前件、后件及时序窗口；
6. 失败报告 ID；
7. 正向回归用例和负向 selftest；
8. 与 reference model、scoreboard 或 coverage 的职责边界。

建议后续测试点按以下功能域编号：

| 功能域 | 建议前缀 | 示例范围 |
|---|---|---|
| Arbiter | `ARB-SVA-xxx` | grant、pointer、stall、公平性 |
| AXI并发协议属性 | `AXI-SVA-xxx` | VALID/READY及payload稳定性 |
| AXI过程式协议检查 | `AXI-IMM-xxx` | 控制和payload X/Z检查 |
| ID与路由 | `ID-IMM-xxx` | ID编码、tag及地址路由匹配 |
| Outstanding / ordering | `ORD-IMM-xxx` | burst长度、outstanding上限、同ID顺序、响应因果 |
| Reset | `RST-SVA-xxx` | 复位值、复位期间输出、复位恢复 |
| Internal FIFO | `FIFO-SVA-xxx` | overflow、underflow、指针和占用量 |

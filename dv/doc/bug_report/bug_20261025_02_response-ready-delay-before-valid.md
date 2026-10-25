# BUG：响应 READY 延迟提前消耗，随机背压测试无法覆盖长 stall

**Author**: Codex, ?
**Created**: 2026-10-25 17:20
**Current Version**: v1.1

**Version Changelog**:
- **v1.1** (2026-10-25 17:50): 同步 SID 问题按用户输入契约重新定性后的关联报告与验证边界，保留 READY 延迟修复和背压统计依据。
- **v1.0** (2026-10-25 17:20): 记录 B/R 长 stall 桶缺失，解释 READY 延迟与有效背压的时序差异、driver 计时起点修改、零延迟处理和回归证据。

---

## 1. 问题概览

| 项目 | 内容 |
| --- | --- |
| 问题编号 | BUG-20261025-02 |
| 类型 | DV 背压激励时序与覆盖目标不一致 |
| 状态 | 已修复，已完成用例验证、组件自检与完整回归 |
| 发现用例 | `tp_backpressure_random`，`SEED=0`，10,000 笔事务 |
| 直接修改位置 | master driver 的 `receive_b()`、`receive_r()` |
| 配套修改 | master agent 配置对象、背压测试配置 |
| RTL 修改 | 无 |

测试把 READY 延迟设置为 `0..20` 拍，希望覆盖大于 15 拍的 stall。旧 driver 在响应 VALID 到来前就开始等待，延迟被响应传输时间部分或全部消耗，导致 B/R 通道实际观察到的长 stall 不足。修复使该测试从响应 VALID 到来后再计算 READY 延迟。

## 2. 先读懂失败日志

原始 seed=0 日志的关键内容如下：

```text
[AXI_CR_STALL_COV]
AW=11111 W=11111 B=01111 AR=11111 R=01111
max=190/185/9/196/11

UVM_ERROR [AXI_CR_STALL_COV]
Full backpressure campaign missed one or more AW/W/B/AR/R stall buckets

UVM_FATAL [AXI_TC_FAIL] tp_backpressure_random failed: uvm_errors=1
```

`max` 的五个数字按 AW、W、B、AR、R 排列。B 通道最大有效 stall 为 9 拍，R 通道为 11 拍，均未到达 16 拍。

五位 hit mask 按 bit4 到 bit0 打印，定义见 [axi_cr_base_test.sv](../../tc/axi_cr_base_test.sv) 的 `stall_bucket()`：

| bit | stall 长度 | `01111` 中的含义 |
| --- | --- | --- |
| 4 | ≥16 拍 | 0，未命中 |
| 3 | 6..15 拍 | 1，已命中 |
| 2 | 2..5 拍 | 1，已命中 |
| 1 | 1 拍 | 1，已命中 |
| 0 | 0 拍 | 1，已命中 |

因此，直接失败原因是覆盖检查未通过。日志中这一个 UVM_ERROR 来自 `AXI_CR_STALL_COV`；它没有报告数据比较错误。这里的覆盖是测试自身维护的 stall 桶统计，即使运行参数为 `COV=n` 仍会执行。

## 3. READY 拉低不一定等于产生背压

### 3.1 什么周期才计为 stall

在本测试的上升沿采样规则中：

```text
VALID=1，READY=0：当前有待传输数据，接收端阻止传输，计 1 拍 stall。
VALID=1，READY=1：完成握手，按此前连续 stall 长度命中相应桶。
VALID=0：没有有效传输等待接收，不计 stall；清零该通道的连续计数。
```

例如，BREADY 连续拉低 20 拍，但这 20 拍中 BVALID 一直为 0，B 通道并没有经历 20 拍背压。要产生长背压，READY 拉低必须与有效响应的等待区间重叠。

本用例的采样位置也很重要：AW/W/AR 在 **slave 接口**采样，B/R 在 **master 接口**采样。中间 FIFO 可以暂时吸收响应，不能仅从 slave 发出响应的时刻推断 master 侧已经出现 VALID。

### 3.2 一个解释用时序示例

下面使用抽象周期区间说明延迟重叠关系，不是原始失败波形的逐周期还原：

```text
旧 driver 开始等待                    master 侧响应到达
       │                                  │
       ▼                                  ▼
时间   0              12                  20
       ├───────────────┼────────────────────┤
READY  0...................................1...
VALID  0...............1........................
       <--- 无响应 ---><--- 实际 stall ----->

配置延迟：20 拍
有效等待：只有 VALID 到来后剩余的约 8 拍
```

在忽略边沿对齐细节的简化模型中，若 READY 等待时间为 `D`，VALID 比计时起点晚 `L` 拍出现，则有效 stall 约为：

```text
stall ≈ max(0, D - L)
```

| 配置延迟 D | 响应到达时间 L | 简化模型中的有效 stall |
| ---: | ---: | ---: |
| 20 | 12 | 8 |
| 20 | 25 | 0，READY 已先到 |
| 5 | 10 | 0，READY 已先到 |

由此可见，把随机数范围设为 `0..20`，并不能保证被测接口实际经历 `0..20` 拍背压。

## 4. 旧代码的问题在哪里

问题位于 [axi_m_driver.sv](../../env/master/axi_m_driver.sv)。旧 `receive_b()` 的执行顺序可简化为：

```systemverilog
bready <= 0;
// 此时并不等待 BVALID。
randomize_bready_delay();
repeat (delay_cycles) @(posedge ACLK);
bready <= 1;
// READY 拉高后，才等待 BVALID 完成握手。
```

`receive_r()` 采用相同顺序。计时可能在 reset 释放后、上一笔响应完成后立即开始，而下一笔响应还要经过请求发送、slave 处理、仲裁和 FIFO 传输等过程。

这类 driver 行为可以产生合法的 READY-before-VALID 时序；本次错误在于，背压用例拿这种延迟策略来保证“VALID 出现后的长 stall”覆盖。激励参数和覆盖统计采用了不同的计时起点。

随机事务数量增加不一定能解决这种偏差。扩大延迟上限可能偶然填满桶，但无法准确表达“让有效响应等待指定拍数”的测试意图。

## 5. 如何修改

### 5.1 增加明确的 READY 延迟模式

在 [axi_m_agent_cfg.sv](../../env/master/axi_m_agent_cfg.sv) 中增加：

```systemverilog
bit response_ready_delay_from_valid;
```

该字段登记进 UVM 配置对象的 field automation，构造时默认设为 `0`。在 [tp_backpressure_random.sv](../../tc/tp_backpressure_random.sv) 的 `build_phase()` 中，对全部 master agent 开启它：

```systemverilog
super.build_phase(phase);
foreach (env_cfg.m_cfg[index])
  env_cfg.m_cfg[index].response_ready_delay_from_valid = 1'b1;
```

这样可以把“从 VALID 开始计时”表达为明确的用例策略。其他用例继续使用已有 READY 时序，仍可产生 READY 先到的合法相位。

### 5.2 修改 B/R 接收线程的等待起点

开启新模式后，B 通道的顺序调整为：

```text
READY 拉低
    ↓
等待 reset 释放
    ↓
在下降沿观察到 BVALID=1
    ↓
随机选择 delay_cycles
    ↓
等待 delay_cycles 个上升沿，保持 READY=0
    ↓
READY 拉高
    ↓
在上升沿完成 VALID && READY 握手
    ↓
进入下一轮
```

实际新增代码位于原有随机延迟逻辑之前：

```systemverilog
if (cfg.response_ready_delay_from_valid) begin
  do begin
    @(negedge vif.ACLK);
  end
  while ((vif.ARESETn === 1'b1) && (vif.bvalid !== 1'b1));
  if (vif.ARESETn !== 1'b1)
    continue;
end
```

R 通道同样等待 `RVALID`。原来的延迟随机化、READY 驱动与握手等待逻辑继续使用；等待 VALID 期间检测到 reset 则重新进入循环。

### 5.3 为什么选择下降沿观察 VALID

这是本次修改中容易遗漏的细节。该环境的同步发送端在上升沿更新信号，driver 使用非阻塞赋值驱动 READY。

如果等到上升沿才首次发现 VALID，然后即使延迟为 0 也执行 `READY <= 1`，当前上升沿的采样通常已经看到旧的 READY=0，就会额外产生一拍 stall，难以命中 0 拍桶。

下降沿观察有两个作用：

1. 上一个握手上升沿的非阻塞更新已经完成，接收线程可以看到更新后的 VALID，避免直接使用上一笔握手时的旧值。
2. 延迟为 0 时，可以在下一个上升沿之前拉高 READY，使首个有效采样沿直接完成握手。

以新模式观察到 VALID 后的采样沿编号为例，在当前同步 VALID 保持条件下：

| 随机延迟 | 第一个有效上升沿 | 后续行为 | 有效 stall |
| ---: | --- | --- | ---: |
| 0 | READY 已为 1，直接握手 | 进入下一轮 | 0 |
| 1 | READY=0，计 1 拍；随后拉高 READY | 第二个沿握手 | 1 |
| 20 | READY=0 | 前 20 个沿计 stall，第 21 个沿握手 | 20 |

该解释以发送端遵守 AXI 的 VALID 保持要求为前提；stall 期间的 payload/VALID 稳定性仍由协议断言检查。

### 5.4 修改范围

| 文件 | 修改内容 |
| --- | --- |
| `dv/env/master/axi_m_agent_cfg.sv` | 增加模式字段、默认值及 UVM field 登记 |
| `dv/env/master/axi_m_driver.sv` | 在 `receive_b()`、`receive_r()` 中按模式等待 VALID |
| `dv/tc/tp_backpressure_random.sv` | 在全部 master agent 上开启该模式 |

五个 stall 桶的划分、10,000 笔完整测试的覆盖要求、`ready_delay=0..20` 范围和通过门槛均沿用原定义。修复使激励真正产生所需场景。

## 6. 修复前后结果

### 6.1 seed=0 的直接对比

| 项目 | 修复前 | 修复后 |
| --- | --- | --- |
| 请求数 | 10,000 | 10,000 |
| READY 延迟配置 | 0..20 | 0..20 |
| AW hit mask | `11111` | `11111` |
| W hit mask | `11111` | `11111` |
| B hit mask | `01111` | `11111` |
| AR hit mask | `11111` | `11111` |
| R hit mask | `01111` | `11111` |
| AW/W/B/AR/R 最大 stall | `190/185/9/196/11` | `190/185/20/196/20` |
| UVM_ERROR / UVM_FATAL | 1 / 1 | 0 / 0 |
| 结果 | FAIL | PASS |

修复后的关键日志：

```text
[AXI_CR_STALL_COV]
AW=11111 W=11111 B=11111 AR=11111 R=11111
max=190/185/20/196/20
[AXI_TC_PASS] tp_backpressure_random passed
```

所有 mask 都为 `11111`，说明包括 0、1、短 stall 和 ≥16 拍长 stall 在内的五个桶均已实际命中。不能只看最大值为 20，就推断中间各桶也都被覆盖。

### 6.2 补充验证与适用边界

| 项目 | 实测结果 |
| --- | --- |
| 历史失败 `tp_backpressure_random SEED=3026` | PASS，五通道 mask 均为 `11111`，B/R 最大 stall 均为 20 |
| 完整用例集合，所有用例使用 seed=0 | 30/30 PASS |
| 六项组件 selftest | 6/6 PASS |
| 协议断言、响应匹配及排空检查 | 上述集成用例结束时通过，UVM_ERROR/UVM_FATAL 均为 0 |

当前随机基础配置为单 beat，读写 outstanding 各为 1。本次长背压桶闭合直接验证的是上述配置；多 beat、更多 outstanding 与 reset 中断的完整交叉场景不由这组结果单独签核。

本报告 v1.0 所引用的完整回归发生在地址/ID 契约纠正前，不能作为新契约下的验收依据。按用户补充要求恢复一致性断言后的最新验证记录见关联 SID 报告 v1.1；本问题的 READY 延迟修复继续保留。

本次未收集覆盖率数据库。`11111` 只证明用例定义的五通道 stall 桶闭合，不代表所有功能覆盖、FIFO 占用交叉或所有随机 seed 均已闭合。

## 7. 复现命令与证据位置

在仓库的 `sim_vcs/` 中执行：

```sh
make sim test=tp_backpressure_random SEED=0
make sim test=tp_backpressure_random SEED=3026
make regress suite=full nseeds=1 SEED=0
make selftests
```

以上命令保留完整 10,000 笔背压测试。`AXI_CR_NUM_TXN` 若被设为小于 10,000，测试会跳过完整 stall 桶闭合要求，因此短 smoke PASS 不能作为本问题已修复的充分证据。

当前源码下这些命令用于验证修复；旧现象见保留的失败日志。若需要波形，可在单测命令中加 `dump=y`；本报告的时序示例是代码推导示意，本次结论来自源码与日志验证。

| 证据 | 路径 |
| --- | --- |
| 最初失败回归 | [regress_20261025_164444_C68lZY.log](../../../sim_vcs/work/log/regress_20261025_164444_C68lZY.log) |
| 修复前单测日志快照 | [tp_backpressure_random_0.log](../../../sim_vcs/work/log/debug_20261025_before/tp_backpressure_random_0.log) |
| 修复后 seed=0 | [tp_backpressure_random_0.log](../../../sim_vcs/work/log/tp_backpressure_random_0.log) |
| 修复后历史 seed | [tp_backpressure_random_3026.log](../../../sim_vcs/work/log/tp_backpressure_random_3026.log) |
| 完整回归 | [regress_20261025_171603_cpNqls.log](../../../sim_vcs/work/log/regress_20261025_171603_cpNqls.log) |
| 六项自检输出 | [debug_selftests.out](../../../sim_vcs/work/log/debug_selftests.out) |

`sim_vcs/work/` 是生成目录，同名日志会被后续运行覆盖，也可能被清理。本文已内嵌关键结果以保留学习所需的证据。

## 8. 工程师阅读与排查提示

遇到“配置了长延迟，但长 stall 桶未命中”的问题，先把三件事放在同一时间轴上：延迟从何时开始、被测接口何时出现 VALID、monitor 在哪个边沿统计 `VALID && !READY`。如果计时起点不同，即使随机参数覆盖范围正确，实际总线场景也可能始终不足。

检查覆盖闭合时，应同时看 hit mask、最大连续 stall、协议稳定性与事务匹配。修复激励后，还应保留 0 拍场景并确认边沿调度没有额外引入一拍等待。

与本报告同时发现的另一个问题见 [SID 随机激励违反地址与 ID 一致性契约](bug_20261025_01_read-id-assertion-write-route-assumption.md)。

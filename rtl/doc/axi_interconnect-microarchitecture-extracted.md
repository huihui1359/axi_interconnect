# AXI Interconnect 整体微架构（RTL 反向提取）

**Author**: Wang Jianghao, Codex, GPT-5.6-Solar
**Created**: 2026-10-04 20:10
**Current Version**: v1.1

**Version Changelog**:
- **v1.1** (2026-10-07 00:19): 更新请求与响应仲裁状态描述，反映round-robin内部pending保持及逐beat accept提交行为。
- **v1.0** (2026-10-04 20:10): 初版 RTL 反向提取整体微架构，整理模块层次、缓冲结构、接口契约、时序风险、前向进展和模块职责。

---

> 当前实现基线：`axi_interconnect`，3 initiators × 3 targets，单时钟域。带 **TOVERIFY** 的结论无法仅由 RTL 确认为设计意图。

## 1. 概述与设计目标

实现一个带通道缓冲、地址路由、轮询仲裁、默认错误从设备和有限 outstanding-ID 过滤的 AXI3 风格交叉开关。**TOVERIFY：** 目标频率、面积、功耗和协议覆盖目标未见于 RTL。

## 2. 模块层次

```text
axi_interconnect
  +-- 30 x axi_fifo_sync (5 channels x 3 endpoints x 2 sides)
  +-- axi_crossbar
  |    +-- 4 x axi_mtos_m3 (S0/S1/S2/default route)
  |    |    +-- 3 x round_robin_m2s through axi_arbiter_mtos_m3
  |    +-- axi_default_slave
  |    +-- 3 x axi_stom_s3 (M0/M1/M2 return route)
  |         +-- 2 x round_robin_s2m through axi_arbiter_stom_s3
  +-- 2 x sid_buffer (read AR/R and write AW/W)
  +-- 2 x reorder (registered membership/eligibility check)
```

设计模块共 12 种；testbench 不属于综合层次。

## 3. 关键实现决策

**TOVERIFY：**

- 在所有 30 条外部通道边界放置 4 深度 FWFT 同步 FIFO，解耦互连与端点反压。
- 每个目标各自完成地址译码和 M→S 仲裁；每个发起端各自完成 S→M 返回仲裁。
- 扩展 8 位 SID 同时携带目标、发起端和原始 ID，用位切片完成返回路由。
- 读地址/读末 beat、写地址/写末 beat 各共享一个 4 项 ID 表，限制 outstanding 并为 R/W 通道提供资格过滤。

## 4. 性能、面积、延迟与带宽

**TOVERIFY：** 每个非争用通道目标吞吐上限 1 beat/cycle；30 个 FIFO 共存储 120 个通道项，数据位总量取决于通道宽度。默认 32 位配置下 FIFO宽度：AR/AW 上游 45、下游 49，W 上游 41、下游 45，R 下游入口 43、上游出口 39，B 下游入口 10、上游出口 6 位。严格端到端延迟不是常量，至少受两个 FIFO边界、仲裁和 registered eligibility 影响。

## 5. 存储结构

| 结构 | 数量 | 深度×宽度 | 用途 |
|---|---:|---|---|
| 上游 AR FIFO | 3 | 4×45 | 发起端读地址入口 |
| 下游 AR FIFO | 3 | 4×49 | 目标端读地址出口 |
| 下游 R FIFO | 3 | 4×43 | 目标端读数据入口 |
| 上游 R FIFO | 3 | 4×39 | 发起端读数据出口 |
| 上游 AW FIFO | 3 | 4×45 | 发起端写地址入口 |
| 下游 AW FIFO | 3 | 4×49 | 目标端写地址出口 |
| 上游 W FIFO | 3 | 4×41 | 发起端写数据入口 |
| 下游 W FIFO | 3 | 4×45 | 目标端写数据出口 |
| 下游 B FIFO | 3 | 4×10 | 目标端写响应入口 |
| 上游 B FIFO | 3 | 4×6 | 发起端写响应出口 |
| AR SID 表 | 1 | 4×8 | 已接受读事务 ID |
| AW SID 表 | 1 | 4×8 | 已接受写事务 ID |

FIFO `Mem` 无 ECC/parity；读为组合式首字直出，写为时钟沿写入。

## 6. 功耗意图

**TOVERIFY：** 无 power domain、isolation、retention 或 clock gating 描述。空闲时组合译码/仲裁仍可能随输入翻转。

## 7. 约束与假设

**TOVERIFY：**

- 固定 3×3，默认位宽组合才是实际验证路径。
- 地址窗口不重叠并按 `2^ADDR_LENGTH` 对齐。
- 发起端保持 valid 与 payload 直到握手。
- WID 的高两位按 RTL 自定义约定编码目标；下游返回扩展 ID 不得损坏。
- 目标最终产生 `RLAST/WLAST/B` 并接受反压，否则 SID 表可能永久占用。
- 扩展 SID 的全零值被 `sid_buffer` 当空槽；正常编码应避免产生全零 SID。

## 8. 时钟、复位与空闲

单一 `AXI_CLK`。`axi_fifo_sync`、仲裁器和默认从设备异步低有效复位；`sid_buffer`/`reorder` 同步采样低有效复位。无显式 idle 输出。系统空闲可推断为所有 FIFO 空、SID 表空、FSM 在 RUN/IDLE，但 RTL 未汇总该条件。

## 9. 与上一版设计比较

不适用——由现有 RTL 反向提取。

## 10. 潜在时序关键区

**TOVERIFY：**

- 地址高位比较 → 三路请求 → round-robin 优先选择 → 宽 payload mux → FIFO ready。
- 四路扩展 ID 比较/返回选择，以及 SID 对四个表项的并行比较。
- 顶层多个 ready 信号的 OR 汇聚。
- 32/45/49 位宽 mux 本身不深，但跨层组合传播需要综合时序报告确认。

## 11. 前向进展与死锁

**TOVERIFY：** grant 在受反压时锁定，避免 payload 来源切换；轮询器减少公平性风险。ID 表形成地址与数据/响应之间的资源依赖；缺少末 beat 或 ID 不匹配会阻止释放。没有 watchdog、timeout 或 flush。

## 12. 缓冲与流控

所有 FIFO以 `wr_rdy=!full`、`rd_vld=!empty` 实现。空 FIFO不做 fall-through bypass；满 FIFO同拍 pop 时仍拒绝 push。SID 表满或同拍正在清除时会反压地址登记；一次只仲裁一个 push 和一个 clear。由于数组由两个 always 块更新，同拍 push/clear 的结果依赖综合语义，属于实现风险。

## 13. 参数缩放影响

**TOVERIFY：** 数据宽度能传播到 FIFO payload，但 `3` 个端点、`4` 项 SID、`8` 位 SID、`WID[3:2]`、2 位 MID 和特定拼接均硬编码。`NUM_MASTER/NUM_SLAVE/WIDTH_*` 不构成全范围可缩放契约。

## 14. 可观测性与调试

外部可观察每个 AXI通道的 valid/ready、ID和响应。没有性能计数器、状态输出或硬件 trace。仿真专用 `$display` 仅覆盖默认从设备 WLAST 和 ID mismatch；testbench 可输出 FSDB。

## 15. 接口契约

顶层接口按 3 元素 unpacked array 聚合。AW/AR 携带 `ID,ADDR,LEN,SIZE,BURST`; W 携带 `ID,DATA,STRB,LAST`; B 携带 `ID,RESP`; R 携带 `ID,DATA,RESP,LAST`。各组均用 ready/valid。未实现 AXI 属性侧带信号。

内部契约：

- `axi_mtos_m3`：3 个请求源到 1 个目标，输出 one-hot grant 和扩展 SID。
- `axi_stom_s3`：4 个响应源到 1 个发起端，按 SID.MID 过滤。
- `sid_buffer`：接受已握手地址 ID；当前实现见到候选 `VALID & LAST` 即删除匹配 ID，并未检查最终 FIFO ready。
- `reorder`：下一拍输出各输入 ID 是否存在于 4 项表内。

## 16. 实例拓扑

`axi_crossbar` 内 S0/S1/S2/default 各有独立 `axi_mtos_m3`；default 路由接 `axi_default_slave`。M0/M1/M2 各有独立 `axi_stom_s3`，每个都能从 S0/S1/S2/default 取响应。正常路径没有模块共享仲裁状态。

## 17. 模块摘要

### 17.1 `axi_interconnect`

- 职责：顶层端口适配、30 个 FIFO、crossbar 实例、两套 SID 跟踪。
- 状态：仅子模块状态；顶层自身为 wiring/组合门控。
- 流水：外部输入 FIFO → crossbar → 外部输出 FIFO。
- assertion：0。
- 详见 `axi_interconnect-top-microarchitecture.md`。

### 17.2 `axi_crossbar`

- 职责：固定 3×3 路由矩阵、默认从设备、返回路径。
- 算法：对每个目标建立 M→S 路由器，对每个发起端建立 S→M 路由器。
- assertion：0。
- 详见 `axi_crossbar-routing-microarchitecture.md`。

### 17.3 `axi_mtos_m3` / `axi_arbiter_mtos_m3`

- 职责：地址译码、AW/W/AR 三个独立三选一仲裁与 mux。
- 仲裁状态：各round-robin内部以`pending_valid/pending_winner`保存反压期间的grant，accept时提交`last_winner`。
- assertion：0。

### 17.4 `axi_stom_s3` / `axi_arbiter_stom_s3`

- 职责：按 MID 选择 B/R，四选一仲裁与 mux。
- 仲裁状态：B/R各自在round-robin内部保持pending grant；逐beat握手后释放并推进轮询指针。
- assertion：0。

### 17.5 `sid_buffer` / `reorder`

- 职责：4 项 outstanding-ID 集合和注册式成员匹配。
- 算法：固定优先级单项 push/clear；删除时压缩数组。
- assertion：0。
- 详见 `axi_ordering-buffering-microarchitecture.md`。

### 17.6 `axi_default_slave`

- 职责：未命中访问的多 beat DECERR 响应。
- FSM：写 `IDLE→RUN→WAIT→RSP`，读 `IDLE→RUN→WAIT→END`。
- assertion：0；有两处仿真 `$display`。

### 17.7 `axi_fifo_sync`

- 职责：参数化同步 FWFT FIFO。
- 状态：head/tail/next 指针、item count、存储阵列。
- assertion：0。

### 17.8 `round_robin_m2s` / `round_robin_s2m`

- 职责：3 路/4 路 one-hot 轮询选择。
- 状态：`last_winner`；存在请求即更新，而非成功握手才更新。
- assertion：0。

## 18. 错误与异常路径

未命中进入默认从设备并产生 DECERR。设计没有 parity/ECC、timeout、interrupt、poison、retry 或 fatal error 输出。协议错误大多静默；默认写路径的两个检查仅在非综合仿真中打印。

## 19. 软件寄存器

无 CSR、地址可编程寄存器或软件中断接口。

## 20. 设计意图未知项

- 性能：目标频率、允许的 burst interleave、延迟界限是什么？
- 功耗：是否允许/需要时钟门控或 SRAM 替代 flop FIFO？
- 参数：是否只支持默认 3×3/4-bit ID/32-bit data？
- 协议：自定义 WID 目标编码是否为系统级强制约束？
- 顺序：是否只要求“已 outstanding 的 ID 可通行”，还是要求严格事务顺序？SID clear 是否应改为完整末 beat 握手？
- 复位：异步输入如何同步释放？
- 错误：地址窗口重叠、SID 表异常和协议违例应如何上报？

## 21. 文件结构

| 文件 | 类型 | 说明 |
|---|---|---|
| `axi_interconnect.v` | 综合 RTL | 顶层、FIFO和 SID 跟踪集成 |
| `axi_crossbar.v` | 综合 RTL | 3×3 核心矩阵 |
| `axi_mtos_m3.v` | 综合 RTL | 请求路由 |
| `axi_stom_s3.v` | 综合 RTL | 响应路由 |
| `axi_arbiter_mtos_m3.v` | 综合 RTL | AW/W/AR 三路 grant 锁定 |
| `axi_arbiter_stom_s3.v` | 综合 RTL | B/R 四路 grant 锁定 |
| `round_robin_m2s.v` | 综合 RTL | 3 路轮询原语 |
| `round_robin_s2m.v` | 综合 RTL | 4 路轮询原语 |
| `axi_fifo_sync.v` | 综合 RTL | 同步 FIFO |
| `sid_buffer.v`, `reorder.v` | 综合 RTL | outstanding-ID 资格跟踪 |
| `axi_default_slave.v` | 综合 RTL | 默认错误目标 |
| `axi_interconnect_tb.v` | 仿真 | 非自检定向激励 |
| `filelist.f` | 构建输入 | 文件清单，TB 路径需校正 |

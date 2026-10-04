# Crossbar、路由与仲裁微架构

**Author**: Wang Jianghao, Codex, GPT-5.6-Solar
**Created**: 2026-10-04 20:10
**Current Version**: v1.0

**Version Changelog**:
- **v1.0** (2026-10-04 20:10): 初版 crossbar 路由与仲裁微架构，描述 3×3/default 请求平面、四来源响应平面、SID 构造、仲裁锁定与已知风险。

---

## 1. `axi_crossbar`

### 1.1 目的和层次

`axi_crossbar` 展开固定 3×3 连接矩阵：四个 M→S 请求路由器对应 S0/S1/S2/default，三个 S→M 响应路由器对应 M0/M1/M2。它把多个局部 READY 做 OR 汇聚，并用三个真实目标的 select OR 值生成 default select。

### 1.2 参数与地址映射

默认 `ADDR_BASE0/1/2=0x0/0x2000/0x4000`，`ADDR_LENGTH*=12`；宽度参数与顶层一致。`NUM_MASTER=3`、`NUM_SLAVE=3` 仅部分使用，实例数量固定。

### 1.3 请求平面

每个真实目标实例 `axi_mtos_m3(SLAVE_DEFAULT=0)`，自行比较三路 AW/AR 地址。default 实例 `SLAVE_DEFAULT=1`，选择未被任一真实目标选中的请求。四个路由器并行观察所有发起端；每个发起端的最终 AW/W/ARREADY 是四路局部 ready 的 OR。

### 1.4 响应平面

每个 `axi_stom_s3` 观察 S0/S1/S2/default 的 B/R，根据 SID 内 MID 过滤本发起端候选并仲裁。每个目标的 B/RREADY 是三个发起端局部 ready 的 OR。

### 1.5 实例

- `u_axi_mtos_s0`, `u_axi_mtos_s1`, `u_axi_mtos_s2`, `u_axi_mtos_sd`
- `u_axi_default_slave`
- `u_axi_stom_m0`, `u_axi_stom_m1`, `u_axi_stom_m2`

无内部 RAM、无自有 FSM、无 assertion。

## 2. `axi_mtos_m3`

### 2.1 端口契约

输入三套 M0/M1/M2 的 AW/W/AR 和 2 位 MID；输出一套扩展 SID 的 S AW/W/AR；输出真实目标 AW/AR select，default 模式输入三个真实目标 select；输入 `w_order_grant[2:0]`。

### 2.2 译码

- 正常 AW/AR：比较 `ADDR[WIDTH_AD-1:ADDR_LENGTH]` 与 `ADDR_BASE` 对应高位。
- default AW/AR：`~SELECT_IN & VALID`。
- W：比较 `WID[3:2]` 与 `ADDR_BASE[14:13]+1`，再与 `w_order_grant` 相与。

### 2.3 SID 构造

- AW/AR：`{ADDR_BASE[14:13]+1, MID[1:0], original_ID[3:0]}`。
- W：`{WID[3:2], MID[1:0], WID[3:0]}`。

仲裁 grant 驱动 one-hot 宽 payload mux；无 grant 时所有输出清零。

## 3. `axi_arbiter_mtos_m3`

AW、AR、W 各有独立 round-robin 选择和 RUN/WAIT 状态。RUN 时使用组合选择；若有 grant 但未 ready，保存 grant 并进入 WAIT；WAIT 直到 `grant & valid & ready`，然后回 RUN。W 不等待 `WLAST`，逐 beat 释放。

| 通道 | 状态寄存器 | 保存寄存器 | 请求 |
|---|---|---|---|
| AR | `stateAR[1:0]` | `argrant_reg[2:0]` | `ARSELECT & ARVALID` |
| AW | `stateAW[1:0]` | `awgrant_reg[2:0]` | `AWSELECT & AWVALID` |
| W | `stateW` | `wgrant_reg[3:0]`（实际 grant 3 位） | `WSELECT & WVALID` |

注意：AR/W case 无 default；`wgrant_reg` 比需要多 1 位。无 assertion。

## 4. `axi_stom_s3`

### 4.1 选择与 mux

B/R 分别比较四个来源 SID 的 `[WIDTH_ID+1:WIDTH_ID]` 与本实例 `M_MID`。R 的三个真实目标选择额外与 `r_order_grant` 相与，default 路径永远可候选。B 输出低 `WIDTH_ID` 位；R 保留完整 SID 到顶层。

### 4.2 仲裁与反压

四选一 grant 选择 payload；被选来源 READY=`grant & M_READY`。无 grant 时输出清零。

## 5. `axi_arbiter_stom_s3`

B、R 各有 RUN/WAIT 状态和保存 grant。逻辑与 M→S 仲裁同构。R 逐 beat 释放而非保持到 `RLAST`，因此可能跨 ID 交织。四路轮询包含 default 来源。

## 6. 仲裁公平性与锁定语义

`round_robin_*` 根据 `last_winner` 从下一请求者开始扫描，实现循环优先级。它在任意 `rr_vld` 周期记录 `curr_winner`，没有 handshake 输入。外层 WAIT FSM 在反压时锁住 grant，从而保证 payload 稳定。**TOVERIFY：** 在持续请求且 downstream 可接受时，轮询按请求周期前进；可认为有公平意图，但不能从 RTL给出绝对延迟界限。

## 7. hazard、错误与风险

- 地址窗口重叠会让一个发起端被多个目标同时选中，顶层 READY OR 无法防止重复接受。
- default select 只看三个真实目标，依赖互斥译码。
- W 路由依赖 WID 高位而不是关联 AW 的内部目标记录。
- R/W 仲裁不锁整个 burst。
- 所有模块 assertion 数为 0；无 one-hot、stable-under-stall、window-disjoint 检查。

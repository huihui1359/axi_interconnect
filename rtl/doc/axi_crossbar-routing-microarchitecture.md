# Crossbar、路由与仲裁微架构

**Author**: Wang Jianghao, Codex, GPT-5.6-Solar
**Created**: 2026-10-04 20:10
**Current Version**: v1.1

**Version Changelog**:
- **v1.1** (2026-10-07 00:19): 记录 wrapper grant/FSM 移除、round-robin内部pending保持、五通道accept提交条件及握手驱动的公平性语义。
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

AW、AR、W 各有独立的 handshake-aware round-robin。wrapper生成`grant & VALID & READY`提交条件；round-robin内部用`pending_valid/pending_winner`保持尚未握手的grant，并只在accept时提交`last_winner`。W不等待`WLAST`，逐beat释放。

| 通道 | 请求 | accept | pending保持位置 |
|---|---|---|---|
| AR | `ARSELECT & ARVALID` | `\|(ARGRANT & ARVALID & ARREADY)` | `u_arbiter_ar`内部 |
| AW | `AWSELECT & AWVALID` | `\|(AWGRANT & AWVALID & AWREADY)` | `u_arbiter_aw`内部 |
| W | `WSELECT & WVALID` | `\|(WGRANT & WVALID & WREADY)` | `u_arbiter_w`内部 |

wrapper不再保存grant，也不再包含仲裁RUN/WAIT状态机。

## 4. `axi_stom_s3`

### 4.1 选择与 mux

B/R 分别比较四个来源 SID 的 `[WIDTH_ID+1:WIDTH_ID]` 与本实例 `M_MID`。R 的三个真实目标选择额外与 `r_order_grant` 相与，default 路径永远可候选。B 输出低 `WIDTH_ID` 位；R 保留完整 SID 到顶层。

### 4.2 仲裁与反压

四选一 grant 选择 payload；被选来源 READY=`grant & M_READY`。无 grant 时输出清零。

## 5. `axi_arbiter_stom_s3`

B、R使用与M→S相同的内部pending保持和accept提交规则。R逐beat释放而非保持到`RLAST`，因此可能跨ID交织。四路轮询包含default来源。

## 6. 仲裁公平性与锁定语义

`round_robin_*`根据`last_winner`从下一请求者开始扫描，实现循环优先级。无pending时输出组合`curr_winner`；若该winner未握手，则在时钟沿保存到`pending_winner`，直到accept前保持grant和payload来源不变。`last_winner`只在accept时更新为实际grant，因此公平顺序按成功服务次数推进，而不受stall周期数影响。

## 7. hazard、错误与风险

- 地址窗口重叠会让一个发起端被多个目标同时选中，顶层 READY OR 无法防止重复接受。
- default select 只看三个真实目标，依赖互斥译码。
- W 路由依赖 WID 高位而不是关联 AW 的内部目标记录。
- R/W 仲裁不锁整个 burst。
- 所有模块 assertion 数为 0；无 one-hot、stable-under-stall、window-disjoint 检查。

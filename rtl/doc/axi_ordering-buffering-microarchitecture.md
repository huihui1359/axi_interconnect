# Outstanding-ID 跟踪微架构

**Author**: Wang Jianghao, Codex, GPT-5.6-Solar
**Created**: 2026-10-04 20:10
**Current Version**: v1.0

**Version Changelog**:
- **v1.0** (2026-10-04 20:10): 初版 outstanding-ID 跟踪微架构，澄清 sid_buffer/reorder 的集合过滤语义、push/clear 算法、顺序契约和资源风险。

---

## 1. 命名与真实语义

RTL 将 `sid_buffer + reorder` 注释为 transaction reorder。实际实现没有 sequence number、head-only grant、数据暂存或重排输出；它维护一个最多 4 项的 ID 集合，并注册产生“候选 ID 是否属于集合”的资格位。因此本文称其为 outstanding-ID tracker/filter。

## 2. 两个独立实例

| 实例 | 登记事件 | 候选资格 | 删除事件 |
|---|---|---|---|
| 读 `u_ar_sid_buffer/u_ar_reorder` | 目标侧 AR 准备写 FIFO | 三个真实目标的 R SID | 候选 `RVALID & RLAST`，未检查最终 FIFO ready |
| 写 `u_aw_sid_buffer/u_aw_reorder` | 目标侧 AW 准备写 FIFO | 三个发起端构造的 W SID | 候选 `WVALID & WLAST`，未检查最终 FIFO ready |

default read 不受 `r_order_grant` 门控，但其末 beat仍会从读 SID 表清项。default write 的 W 通过 default M→S 路由器，仍受 `w_order_grant`。

## 3. `sid_buffer`

### 3.1 端口

- 三组 push：`sN_axid[7:0]`, `sN_axid_vld`, `sN_fifo_rdy`, `sN_push_rdy`。
- 三组 clear：`last_N`, `sid_N[7:0]`, `sid_N_vld`, `sid_N_clr_rdy`。
- 输出：`sid_buffer[0:3][7:0]`。
- 参数 `NUM=3` 只用于内部固定优先级函数宽度。

### 3.2 Push 算法

`push_select[N]=axid_vld & fifo_rdy`；固定优先级 `0>1>2` 每拍选一个。只有没有 clear grant 且表未满时才 `clr_rdy=1`，被选项获得 `push_rdy`。数据写入第一个等于零的槽。

### 3.3 Clear 算法

`clr_select[N]=last_N & sid_N_vld`；同样固定优先级 `0>1>2`。获选 SID 与四槽并行比较，匹配槽被删除，后续项左移压缩。clear ready 使未获选的同时请求受反压。输入中没有真正的 downstream/FIFO ready，所以“候选末 beat存在”而非“末 beat握手”触发删除。

### 3.4 状态与复位

四个 8 位寄存槽以零表示空。两个 `always @(posedge clk)` 块都写同一数组：一个负责 push/同步复位，另一个负责 clear/压缩。复位不是异步。

### 3.5 重要边界行为

- 表满判断仅看槽 3 是否非零，依赖数组始终压紧。
- push 与任何 clear 同拍互斥，因为 `clr_rdy` 在有 clear grant 时为 0。
- 多个 clear 同拍只处理最低编号来源。
- clear 比较可同时命中重复 SID 的多个槽，但压缩 `if/else` 只按最低索引处理一次。
- SID=0 无法可靠存储；默认编码应使正常 SID 非零，仍需约束。
- 同一数组的多 always 写入会造成综合可移植性和写冲突风险。
- 末 beat遭最终出口 FIFO反压时仍可能清项，随后同一 beat继续保持 VALID，但已失去 outstanding 资格；这是高优先级正确性风险。

## 4. `reorder`

### 4.1 算法

对每个 `sid_N` 做四项相等比较，并与 `sid_N_vld` 相与；结果在上升沿写入 `order_grant[N]`。低有效 `rstn` 在时钟沿同步清零。

```text
order_grant[N] <= sid_N_vld &&
                  (sid_N==slot0 || sid_N==slot1 ||
                   sid_N==slot2 || sid_N==slot3)
```

### 4.2 流水

候选 ID 和 SID 表在周期 N 被采样，资格位在周期 N+1 生效。候选源必须依赖其前级 FIFO保持 payload/valid，直到后续握手。表可能在相邻周期变化，RTL没有附带 ID 重新校验 assertion。

## 5. 顺序契约

当前逻辑保证的只是：真实目标 R 或 W 候选的扩展 SID 曾经被相应地址通道登记。它不保证：

- 只允许表头事务先完成；
- 同 ID 的多个事务能被区分；
- 返回数据被缓存后重新排列；
- AWLEN/ARLEN 与观察到的 beat 数一致；
- B 必须对应仍在表内的写事务。

因此“最多 4 项 outstanding-ID 资格过滤”是准确描述，“4-entry ROB”不是。

## 6. 前向进展与资源风险

当 4 项均占用后，新 AR/AW 被反压。匹配 SID 的候选末 beat能清项；错误 SID、遗漏 LAST 或永不返回会永久耗尽容量。反压末 beat又可能提前清项。无 timeout/flush。固定优先级 push/clear 在某一路持续请求时可使高编号来源延迟；不过未获选来源通过 ready 反压保持请求，前提是对端遵守握手。

## 7. Assertions 与建议检查

当前两个模块 assertion 数均为 0。验证至少应覆盖：表不含零/非法 ID、占用数 0..4、无重复或明确定义重复语义、push/clear one-hot、只有已登记 ID 可通行、末 beat恰好清一次、满表最终释放，以及 registered eligibility 对 payload stability 的依赖。

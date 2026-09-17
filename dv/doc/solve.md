# AXI Interconnect 完备验证环境下的潜在 RTL 问题与解决建议

> 文档状态：验证前风险预测，不代表问题已经由回归确认  
> 分析基础：当前 RTL 源码、`dv/doc/arbiter_switch_imple.md` 中的仲裁和路由机制，以及后续多 Master、多 Slave、outstanding、乱序、交织、backpressure 和 runtime reset 验证目标  
> 使用原则：实际失败必须以 monitor、assertion、scoreboard、波形和最小复现为准，不应仅凭本文直接判定 RTL 缺陷

## 1. 文档目的

本文预测完备 DV 环境投入后，当前 RTL 最可能暴露的问题，并为每类问题整理：

- 触发场景；
- 可能出现的日志或波形现象；
- 源码根因；
- 推荐 RTL 修复方案；
- 修复后的定向回归点。

本文把问题分成三种置信度：

| 标记 | 含义 |
|---|---|
| 高 | 源码中已经存在明确条件，构造相应场景后大概率能够稳定复现 |
| 中 | 源码行为明确，但是否判错取决于设计规格、Slave 能力或 checker 策略 |
| 低 | 更偏向性能、参数化、工具兼容性或极端边界风险 |

严重度建议：

| 等级 | 含义 |
|---|---|
| P0 | 可能导致死锁、数据错误、响应错误路由或破坏基本协议语义，应优先修复 |
| P1 | 可能导致顺序、公平性、reset 或复杂场景失败 |
| P2 | 主要影响吞吐率、可配置性、代码质量或异常输入处理 |

## 2. 预测结论摘要

预计完备环境最先发现的问题如下：

| 编号 | 预测问题 | 置信度 | 严重度 | 典型现象 |
|---|---|---|---|---|
| SOLVE-01 | Default 写路径没有可靠 W 路由 | 高 | P0 | unmatched AW 后 W/B 永久等待，或出现 X |
| SOLVE-02 | W 路由绑定 `WID[3:2]`，随机写 ID 与地址不兼容 | 高 | P0 | AW 已完成但 WREADY 永久不来，测试 timeout |
| SOLVE-03 | 寄存的 `order_grant` 可能错误作用于下一 FIFO 队首 | 高 | P0 | 未满足顺序资格的 W/R 被提前放行 |
| SOLVE-04 | SID buffer 在 LAST+VALID 而非真实握手时提前清除 | 高 | P1 | backpressure 下 tracker 状态提前释放、容量或顺序异常 |
| SOLVE-05 | 同一上游 RID、不同 Slave 被当作不同顺序域 | 高 | P0/P1 | 同 ID 跨 Slave 响应乱序 |
| SOLVE-06 | RR 指针不按握手更新，WAIT 中继续漂移 | 高 | P1 | winner 与标准 RR 预测不一致，特定 stall 下可能长期偏置 |
| SOLVE-07 | W/R 每 beat 重新仲裁，未锁定到 LAST | 中 | P1 | burst beat 发生交织；若目标不支持则失败 |
| SOLVE-08 | `sid_buffer` 多时序块写同一数组且 reset 风格不一致 | 高 | P1 | lint/综合报错，runtime reset 后出现残留或竞态风险 |
| SOLVE-09 | B 缺少 order/outstanding 资格检查，非法 SID 无隔离 | 中 | P1 | 伪响应被转发或无合法 MID 的响应永久堵塞 |
| SOLVE-10 | 全局 4-entry tracker 和单 push/clear 端口限制并发 | 高 | P2 | 不同 Slave 可并行时仍出现固定优先级反压 |
| SOLVE-11 | 参数化表面存在、内部大量固定 3/4/8-bit 假设 | 高 | P2 | 改参数后编译失败、截断或路由错误 |
| SOLVE-12 | 地址窗口、Default tag 和 burst 边界缺少保护 | 中 | P1/P2 | 重叠窗口重复转发、跨窗口 burst 行为不明确 |
| SOLVE-13 | FIFO 满状态不能同周期 pop+push | 高 | P2 | 满载持续流量出现额外气泡和吞吐下降 |

最需要优先构造的四组定向测试是：

1. 每个地址窗口遍历全部 4-bit 写 ID；
2. unmatched write 和 unmatched read；
3. 两个不同 SID 紧邻出现在同一 W/R FIFO 队首；
4. 同一 Master、同一 RID、不同 Slave 的多个 outstanding read。

## 3. SOLVE-01：Default 写路径不能可靠完成

### 3.1 触发场景

- AWADDR 不命中 S0/S1/S2；
- Default `axi_mtos_m3` 接收 AW；
- Master 随后发送对应 W burst，并等待 DECERR B。

### 3.2 预期失败现象

- 上游 AW 已握手，但 WREADY 长期为 0；
- Default Slave 一直停在等待 W 的状态；
- BVALID 永远不产生，outstanding write 不归零；
- protocol timeout 或 test timeout；
- 开启 X 检查时，Default WSELECT/WGRANT 相关信号可能出现 X 或历史值。

### 3.3 根因

`axi_mtos_m3` 在 `SLAVE_DEFAULT=1` 分支只赋值 AWSELECT 和 ARSELECT，没有赋值 WSELECT。W 通道本身没有地址，当前 RTL 也没有保存 unmatched AW 的目标供 W 查询。

Default 的 `ADDR_BASE` 又使用默认值 0，其 SID 高位与 S0 都可能为 `01`，无法作为可靠的 Default 标志。

### 3.4 推荐修复

首选结构性修复：

1. 明确定义 2-bit target tag：Default=`00`、S0=`01`、S1=`10`、S2=`11`；
2. AW 握手时把 `{master, AWID, target}` 写入 write-route tracker；
3. W 到来时按 `{master, WID}` 查询最早未完成 AW 的 target；
4. WLAST 真实握手后弹出对应 route entry；
5. Default AW 和 W 都进入 Default Slave，并返回 DECERR B；
6. Default B 参加正常回程仲裁和同 ID 顺序检查。

临时最小修复可以把 `WID[3:2]==00` 解释为 Default 并显式给 WSELECT 全赋值，但它仍保留写 ID 高位被占用的问题，不建议作为最终架构。

### 3.5 修复后回归

- Default 单拍写；
- Default 1～16 beat burst write；
- W 先于 AW、AW 先于 W、AW/W 同周期；
- Default 与 S0/S1/S2 并发；
- BREADY 长 backpressure；
- 相同 ID 的正常地址与 Default 地址顺序测试；
- 所有场景必须返回一次且仅一次 DECERR B。

## 4. SOLVE-02：写 ID 被用作目标 Slave 编码

### 4.1 触发场景

让写事务使用合法 AXI ID，但不满足当前隐藏约束。例如：

```text
AWADDR 命中 S0，AWID/WID = 4'h1
AWADDR 命中 S1，AWID/WID = 4'h5
AWADDR 命中 S2，AWID/WID = 4'h9
```

### 4.2 预期失败现象

- AW 可以正常路由并进入 AW SID buffer；
- W 根据 `WID[3:2]` 被送到另一个 Slave，或者没有目标；
- 扩展 WID 与 AW SID 不相等，`w_order_grant` 不产生；
- WREADY 永久为 0，AW/W tracker 和 Master outstanding 不归零；
- 随机 ID 回归出现大量 timeout，而固定使用 `4'h5` 的旧用例继续通过。

### 4.3 根因

当前 W 路由为：

```text
WID[3:2] = 01 -> S0
WID[3:2] = 10 -> S1
WID[3:2] = 11 -> S2
```

同时 `reorder` 要求：

```text
{WID[3:2], MID, WID} == {slave_tag(AWADDR), MID, AWID}
```

因此写事务实际要求 `WID==AWID` 且 ID 高两位等于目标 Slave tag。上游 4-bit ID 不再是自由 ID，而被地址目标分区。

### 4.4 推荐修复

不要再由 WID 位段直接生成 route。应建立 AW 到 W 的路由关联：

```text
key   = {master_index, AXI_ID}
value = 按 AW 接收顺序排列的 target queue
```

AXI3 中 WID 用于关联写地址。若同一 Master、同一 ID 有多个 outstanding write，则对应 target 必须排队；该 WID 的 W burst 使用队首 target，WLAST 握手后再弹出。

扩展 ID 仍可使用：

```text
SID = {target_tag, master_tag, original_axi_id}
```

但 target tag 应来自 route tracker，而不是从 original ID 中截取。

### 4.5 修复后回归

- 对 S0/S1/S2/Default 分别遍历 ID `0x0～0xF`；
- 地址固定、ID 随机；ID 固定、地址随机；
- 同一 ID 连续访问不同 Slave；
- 同一 Master 不同 WID 交织；
- 三个 Master 使用相同原始 ID；
- 检查下游 SID 和上游 BID 恢复均正确。

## 5. SOLVE-03：`order_grant` 与 FIFO 新队首错位

### 5.1 触发场景

同一个候选 FIFO 中连续放置两个不同 SID：

1. 第一个 SID 当前有资格，`order_grant=1`；
2. 第一个 beat/事务本周期握手并使 FIFO head 前移；
3. 新队首 SID 当前不应有资格；
4. 下游 READY 保持为 1，使新队首可以在紧邻周期尝试握手。

该场景同时适用于：

- Master W 输入 FIFO 的 WID 切换；
- Slave R 输入 FIFO 的 RID 切换。

### 5.2 预期失败现象

- 新 WID 在对应 AW 尚未进入 tracker 时被提前送往 Slave；
- 后发的同 ID R 或尚未登记的 RID 被提前返回；
- scoreboard 报告 response before request、same-ID order mismatch 或 unexpected W route；
- 失败集中在零 gap、持续 READY 的背靠背流量，插入一个空闲周期后可能消失。

### 5.3 根因

`reorder.order_grant` 在时钟块中寄存。发生握手的时钟沿上，它仍根据握手前的旧 FIFO head 计算 grant；同一时钟沿 FIFO head 前移后，该寄存 grant 会在下一周期直接作用到新的 SID。

也就是说，grant 只携带“候选端口编号”，没有携带它对应的 SID。端口队首改变时，旧资格可能被错误复用。

### 5.4 推荐修复

优先方案：把资格判断改为组合逻辑，始终由当前 FIFO head SID 和当前 tracker 内容计算。

如果必须寄存，则同时寄存并校验 SID：

```text
grant_valid
grant_sid
current_sid == grant_sid
```

队首改变时旧 grant 必须失效，不能仅凭同一个 source index 继续使用。

更稳妥的结构是让 tracker 直接输出当前候选的 `eligible`，而不是把 eligibility 当作一个可以跨队首保存的 grant。

### 5.5 修复后回归

- eligible SID 后紧跟 ineligible SID；
- 两个不同 WID 零 gap；
- 两个不同 RID 零 gap；
- 第一项在 READY=1 和 READY 长 stall 两种情况下切换；
- FIFO 从一项变为空、从两项变一项、满状态 pop 后切换；
- assertion：`eligible` 必须对应当前采样 SID。

## 6. SOLVE-04：SID 在未握手时提前清除

### 6.1 触发场景

- WLAST 或 RLAST 已经拉高；
- 对应 VALID=1；
- 后级输出 FIFO 已满或最终 READY=0；
- LAST beat 在接口上持续 stall 多个周期。

### 6.2 预期失败现象

- 外部 LAST beat 尚未握手，SID buffer 中的 entry 已消失；
- buffer 过早腾出空间并接收新的 AW/AR；
- 同 ID 后续事务提前获得资格；
- 内部 outstanding 计数、scoreboard 和 RTL tracker 状态出现短暂或持续不一致；
- 某些失败只在输出 FIFO 被填满时出现。

### 6.3 根因

`sid_buffer` 的 clear 候选为：

```systemverilog
clr_select = last & sid_vld;
```

`clr_idx` 没有直接使用最终 `VALID && READY` fire。只要 LAST+VALID 被看见，entry 就可能在时钟沿清除，即使 beat 仍未真正进入后级 FIFO。

### 6.4 推荐修复

所有 tracker 状态变化必须由真实握手事件驱动：

```text
clear_fire = valid && ready && last
```

由于当前 `sid_*_clr_rdy` 又参与 READY 门控，修复时应避免组合环。推荐做法：

1. 先用独立仲裁选出允许 clear 的 source；
2. 用原始后级 FIFO ready 生成该 source 的最终 ready；
3. 用 `grant && valid && raw_fifo_ready && last` 更新 tracker；
4. 不让 tracker 的删除条件反向依赖它自己生成的 READY。

同时将 push、pop 和 reset 合并到一个 `always_ff` 中，用显式 next-state 处理同周期 push/pop。

### 6.5 修复后回归

- WLAST/RLAST stall 1、2、4、16、100 周期；
- buffer 空、半满、满状态下的 LAST stall；
- 同周期一个 entry clear、另一个 entry push；
- 多个 source 同周期 LAST；
- assertion：没有 `valid && ready && last` 时 tracker 数量不得减少。

## 7. SOLVE-05：同一上游 ID 跨 Slave 的响应顺序

### 7.1 触发场景

同一 Master 使用相同 ARID 依次访问不同目标：

```text
AR0: M0, ARID=5, target=S0
AR1: M0, ARID=5, target=S1
```

让 S1 比 S0 更早返回 R。也应覆盖正常 Slave 与 Default Slave 的组合。

### 7.2 预期失败现象

- 后发 AR1 的 R 先出现在 M0；
- 两个响应在上游都恢复为 RID=5，scoreboard 报 same-ID order mismatch；
- Default R 因绕过 `r_order_grant`，更容易越过较早的正常请求。

### 7.3 根因

当前 `reorder` 以完整 8-bit SID 为顺序 key：

```text
{slave_tag, master_tag, original_id}
```

同一上游 `{master_tag, original_id}` 只要目标 Slave 不同，就被视为不同 SID，可以同时获得资格。Default 响应甚至完全绕过真实 Slave 的 R order gate。

如果项目遵循同一 Master、同一上游 ID 必须保持响应顺序的 AXI 语义，这一实现会失败。

### 7.4 推荐修复

把“路由身份”和“上游顺序身份”拆开：

```text
route identity = {slave_tag, master_tag, original_id}
order key      = {master_tag, original_id}
```

每个 tracker entry 保存：

```text
valid
target/source
master_tag
original_id
sequence/order position
```

R 只有在它对应的是该 order key 最早未完成 entry 时才有资格返回。Default 也必须进入同一 tracker，而不能绕过。

写 ID 路由修复后，同一写 ID 也可能访问不同 Slave，因此 B 通道应增加相同上游 ID 的顺序资格检查。

### 7.5 修复后回归

- 同一 RID：S0->S1、S1->S2、S2->S0；
- 同一 RID：正常 Slave->Default、Default->正常 Slave；
- 不同 RID 允许乱序，证明没有过度串行化；
- 三个 Master 使用相同原始 RID，证明 MID 隔离正确；
- 同一 ID 4 个 outstanding，Slave 逆序产生响应计划。

## 8. SOLVE-06：Round-robin 指针与握手脱钩

### 8.1 触发场景

- 多个候选持续 request；
- 当前 winner 的目标 READY 拉低；
- WAIT 持续不同周期数后再拉高 READY；
- 重复该模式并统计每个候选成功握手次数。

### 8.2 预期失败现象

- arbiter checker 若按“成功服务后更新指针”建模，会与 RTL winner 不一致；
- 同样的请求序列仅因 stall 长度不同，解除 WAIT 后的下一 winner 不同；
- 某些周期性 READY 模式下，同一个候选反复获胜，其他持续请求候选长期得不到服务；
- 公平性 coverage 分布严重偏斜。

### 8.3 根因

`round_robin_m2s/s2m` 在 `|req` 时每周期更新 `last_winner`，不要求 grant fire，并且在外层 arbiter 处于 WAIT 时仍更新。

例如三路请求全部持续有效时，锁定 grant 保持不变，但内部组合 winner 和 `last_winner` 仍按 M0/M1/M2 循环。释放时的指针位置取决于 stall 周期数。

### 8.4 推荐修复

由外层 arbiter 统一拥有 RR 指针，只有成功服务时更新：

```text
fire = |(grant & valid & ready)
if fire:
    last_winner <= grant
```

WAIT 期间指针保持。解除 WAIT 的同一个时钟沿，把完成握手的 held grant 记录为 last winner。

建议删除 round-robin 子模块内部独立的时序指针，改成：

- 无状态的 `rr_scan(req, last_winner)` 组合函数；
- 外层统一维护 `last_winner`、`held_grant` 和 WAIT。

### 8.5 修复后回归

- 2 路和 3/4 路持续竞争；
- stall 长度遍历 0～`2*N+2`；
- WAIT 中新增请求、撤销未选请求；
- winner stall 时其他请求持续有效；
- 每次成功握手后的下一选择严格从 winner 下一项开始；
- 在合理 READY 假设下增加有界无饥饿 assertion。

## 9. SOLVE-07：W/R 的 burst 锁定策略不明确

### 9.1 触发场景

- 两个或多个不同 WID 的 W burst 同时到达同一 Slave；
- 两个或多个 Slave 向同一 Master 返回不同 RID 的 R burst；
- 每个 beat 后都保持下一候选 VALID。

### 9.2 预期现象

当前 RTL 在每个 W/R beat 握手后重新仲裁，不等待 WLAST/RLAST。因此外部可能观察到：

```text
WID A beat0 -> WID B beat0 -> WID A beat1 -> ...
RID A beat0 -> RID B beat0 -> RID A beat1 -> ...
```

这不一定是 RTL bug。AXI3 可以支持不同 ID 的数据交织，但是否允许取决于项目规格和下游 Slave 能力。

### 9.3 根因

W 和 R arbiter 中原本与 LAST 相关的条件被注释，状态机在任意 beat fire 后回到 RUN。

### 9.4 解决决策

必须先冻结架构要求：

- 若支持 AXI3 W/R interleaving：保留逐 beat 仲裁，增加同 ID beat 顺序、不同 ID 合法切换和 Slave capability 检查；
- 若不支持 burst 内切换：grant 必须保持到 `valid && ready && last`；
- 若不同 Slave 能力不同：增加 per-slave `interleave_enable` 或 capability 配置。

不建议仅为通过当前 checker 而注释或恢复 LAST 条件。checker 和 RTL 必须共同服从明确的项目策略。

### 9.5 回归要求

- interleaving enable/disable 两类配置；
- 相同 ID 不得错误交织两个事务；
- 不同 ID 的合法 beat 交织；
- 任意 beat stall 时 payload 和 winner 保持；
- LAST 只结束所属 ID 的 burst。

## 10. SOLVE-08：SID buffer 的时序写入和 reset 风险

### 10.1 可能现象

- lint 或综合报告一个寄存器被多个 procedural block 驱动；
- runtime reset 后 `sid_buffer` 与 `order_grant` 清理时刻不同；
- reset 恰好与 push/clear 重叠时出现 X、残留 entry 或计数不一致；
- 仿真可通过，但换工具或综合后行为不一致。

### 10.2 根因

- `sid_buffer` 的 push/reset 和 clear 分别在两个时序块中写同一数组；
- `sid_buffer` 和 `reorder` 使用同步 `if(!rstn)`，而 FIFO、arbiter 等大量模块使用异步 `negedge rstn`；
- entry 使用数值 0 表示空，没有独立 valid bit；
- 固定数组和多处比较使同时 push/pop 边界难以证明。

### 10.3 推荐修复

1. 每组状态只由一个 `always_ff` 驱动；
2. 使用 next-state 同时处理 reset、push、pop 和 push+pop；
3. 每个 entry 使用独立 `valid`，不要用 SID=0 表示空；
4. 统一 reset 语义；若顶层声明 AXI_RSTn 异步，则 tracker 也使用异步清零；
5. 维护显式 count、head/tail 或结构化 entry queue；
6. 增加内部一致性 assertion：`count == valid entry 数量`。

### 10.4 修复后回归

- reset 在 idle、半满、满、WAIT、LAST stall 时插入；
- reset 与 push、pop、push+pop 同周期；
- 短 reset pulse 和正常多周期 reset 分别按规格检查；
- reset 后首个同 ID 和不同 ID 事务；
- lint、仿真和综合规则检查均无多驱动。

## 11. SOLVE-09：响应合法性和 B 顺序保护不足

### 11.1 触发场景

- Slave 返回不存在 outstanding request 的 BID/RID；
- SID `[5:4]` 为未使用的 `00` 或包含 X；
- 多个 Slave 对同一 Master、同一上游 BID 返回响应；
- 修复写 ID 路由后，同一写 ID 可访问不同 Slave。

### 11.2 可能现象

- B 只要 MID 命中就被转发，即使没有对应 AW/W；
- 无合法 MID 的响应没有任何 Master 拉 READY，永久堵在输入 FIFO；
- Default R 绕过 order tracker；
- 写 ID 解耦后，同 BID 跨 Slave 可能乱序。

### 11.3 推荐修复

正常功能路径至少增加：

- B/R SID 合法性 assertion；
- response 必须命中一个且仅一个 Master；
- response 必须能够关联已有 outstanding entry；
- 同一上游 ID 的 B/R 顺序资格；
- 非法响应的明确处理策略：仿真报错、丢弃、错误汇聚端口或系统 error，不允许静默永久阻塞。

如果系统假设 Slave 永远合法，也应保留 assertion 和 timeout，以便 DV 快速定位错误来源，而不必把所有防御逻辑放入数据通路。

### 11.4 回归要求

- 正常响应零误报；
- 无 outstanding 的 B/R 负向注入；
- MID=00、未知 MID、X/Z ID；
- 同 BID/RID 跨 Slave 顺序；
- 响应输入 FIFO 满和 Master READY 长 stall。

## 12. SOLVE-10：全局 tracker 限制并发和公平性

### 12.1 触发场景

- M0/M1/M2 同周期向不同 Slave 发 AW 或 AR；
- 三个目标输出 FIFO 都有空间；
- 长时间维持独立无冲突流量；
- outstanding 总量超过 4。

### 12.2 可能现象

- 本来可以并行接受的 S0/S1/S2 请求被串行化；
- 同周期 tracker push 固定优先 S0>S1>S2；
- S2 在高负载下得到明显更高延迟；
- 全局 4-entry 满后所有真实 Slave 的 AW/AR 同时被反压；
- 性能 checker 报吞吐率或公平性不达标，但数据功能仍可能正确。

### 12.3 根因

读写各只有一个 4-entry 全局 SID buffer，每周期最多 push 一个、clear 一个，且使用固定优先级。它成为 crossbar 并行数据路径之外的串行瓶颈。

### 12.4 推荐修复

根据性能目标选择：

- 若项目只要求功能正确：把“全局最多 4、每周期一个 push/clear”写入正式规格，DV 不应把它判成功能错误，但要覆盖 backpressure；
- 若要求 3x3 并行吞吐：tracker 必须支持多端口更新，或改为 per-master/per-ID/per-slave 分层队列；
- 固定优先级应改成 RR，或者证明不会造成饥饿；
- 容量参数应与允许的全局 outstanding 数一致，而不是硬编码 4。

### 12.5 回归要求

- 三个 Master 到三个不同 Slave 同周期请求；
- S0/S1/S2 持续满负载，统计接受延迟；
- tracker 深度边界 3/4/5；
- 满状态下完成一个响应并同时到达一个新请求；
- 性能指标与规格中的理论上限一致。

## 13. SOLVE-11：参数化不完整

### 13.1 可能现象

修改 `WIDTH_ID`、`WIDTH_CID`、`NUM_MASTER`、`NUM_SLAVE` 或地址映射后：

- 编译出现位宽 warning/error；
- ID 被截断或补零；
- round-robin 端口宽度不匹配；
- `sid_buffer/reorder` 仍固定为 8-bit、3 source、4 entry；
- W route 仍固定读取 `[3:2]`；
- Slave tag 仍由固定地址位 `[14:13]` 推导。

当前 `wgrant_reg` 声明为 `[NUM:0]`，在 NUM=3 时为 4 bit，而 WGRANT 是 3 bit，也属于明确的位宽不一致。

### 13.2 推荐修复

项目需要先二选一：

1. 固定 3x3/4-bit/8-bit 配置：删除误导性的无效参数，在 elaboration 添加参数断言；
2. 真正参数化：使用 `$clog2` 计算 MID/SID/target 宽度，所有数组和 arbiter 使用参数循环生成，并把 tag 映射从地址位推导中解耦。

若短期目标仅为当前芯片配置，推荐先冻结参数并清除所有位宽 warning；等功能稳定后再单独开展参数化重构。

### 13.3 回归要求

- 当前正式配置必须 zero width warning；
- 若宣称支持参数化，至少建立 2x2、3x3、4x4 编译和基础仿真矩阵；
- 不同 ID 宽度下执行 SID encode/decode 自测；
- 静态断言检查 tag 数量、地址窗口和 SID 总宽度。

## 14. SOLVE-12：地址译码和 burst 边界

### 14.1 风险点

- 当前地址窗口不重叠，但 RTL 没有 one-hot 命中检查；
- tag 由 `ADDR_BASE[14:13]+1` 生成，地址参数变化后可能重复；
- Default tag 与 S0 可能相同；
- 只检查 burst 起始 AWADDR/ARADDR，没有检查 burst 是否越过 4 KiB 或目标窗口；
- 非法 burst 由哪个端口返回错误没有明确策略。

### 14.2 可能现象

- 重叠窗口配置导致一个请求被两个 Slave 接受；
- burst 起点在 S0、后续地址进入空洞或另一窗口，但所有 beat 仍由 S0 处理；
- ref_model 按逐 beat 地址路由而 RTL 按首地址路由，造成大量误比对；
- Default 响应无法仅靠 slave tag 识别。

### 14.3 推荐修复

- 地址 decoder 输出 one-hot target，并增加 `$onehot0` assertion；
- target tag 使用显式常量或配置表，不从地址位隐式计算；
- 对合法 stimulus，sequence 和 protocol assertion 禁止 burst 跨 4 KiB/目标窗口；
- 如果 DUT 必须防御非法 burst，则在 AW/AR 接收时计算末地址，非法请求整体送 Default/DECERR，不能把一个 burst 拆到多个 Slave；
- ref_model 与 RTL 统一采用“以地址请求决定整个 burst 目标”的规则。

### 14.4 回归要求

- 每个窗口首地址、末地址和边界外一字节；
- 地址空洞；
- FIXED/INCR/WRAP 的合法边界；
- 4 KiB 边界前后；
- 重叠配置的 elaboration/assertion 负向测试。

## 15. SOLVE-13：FIFO 满载吞吐气泡

### 15.1 触发场景

- FIFO 已满；
- 同周期读端 READY=1，可以 pop；
- 写端 VALID=1，希望同时补入一个新 entry。

### 15.2 预期现象

`wr_rdy=~full`，所以满状态即使本周期会 pop，也拒绝新 write。持续满载流量会出现额外一个周期 backpressure，吞吐率低于允许同周期 pop+push 的 FIFO。

这通常不是功能错误，但可能使性能目标、READY 时序预测或无气泡测试失败。

### 15.3 推荐修复

若性能要求允许满状态同周期替换，可定义：

```text
pop_fire  = rd_vld && rd_rdy
wr_rdy    = !full || pop_fire
push_fire = wr_vld && wr_rdy
```

并重新整理 pointer/count 的四种组合：无操作、只 push、只 pop、push+pop。若不修复，应把该气泡写入微架构规格，DV 只检查不丢数据而不要求满吞吐。

### 15.4 回归要求

- empty、one entry、full-1、full；
- full 状态同时 push/pop；
- 连续数百周期 push/pop；
- 指针回绕；
- 数据顺序、count、full/empty assertion。

## 16. 推荐的 RTL 重构架构

不要分别对每个 timeout 打补丁。建议以路由、顺序、仲裁三个层次重构。

### 16.1 统一 ID 和 route 定义

```text
target_tag:
    00 = Default
    01 = S0
    10 = S1
    11 = S2

master_tag:
    01 = M0
    10 = M1
    11 = M2

downstream_sid = {target_tag, master_tag, original_axi_id}
```

所有 encode/decode 使用同一个 package/function，不在多个模块中重复拼接和切片。

### 16.2 写 route tracker

AW fire 时按 `{master, AWID}` 保存 target。W 使用 `{master, WID}` 查询队首 target，WLAST fire 后释放。这样：

- 原始 ID 不再承担 target 编码；
- Default W 可以正常路由；
- 同 ID 多 outstanding 使用队列保持次序；
- 下游 WID 与 AWID 可以统一由 tracker target 生成。

### 16.3 响应 order tracker

AR/AW entry 同时保存 target 和上游可见 order key：

```text
order key = {master_tag, original_id}
```

R/B 只有在属于该 key 的最早 entry 时才有资格。不同 ID 可以乱序，相同 ID 跨 Slave 仍保持顺序。Default 必须进入同一顺序体系。

### 16.4 仲裁器

每个仲裁域只维护：

```text
last_completed_grant
held_grant
waiting
```

RR 指针只在 fire 更新；VALID stall 时 held grant 不变。W/R 是否持有到 LAST 由明确 capability 配置决定。

### 16.5 Tracker 实现

- 独立 valid bit；
- 单一 `always_ff`；
- push/pop 都由 fire 驱动；
- 支持同周期 push+pop；
- eligibility 对当前 SID 组合计算，或绑定已寄存 SID；
- 容量参数与系统 outstanding 配置一致；
- count、entry 唯一性和不下溢/不溢出 assertion。

## 17. 推荐修复顺序

### 17.1 第一批：解除功能死锁

1. 冻结 target tag 和 SID 格式；
2. 修复 AW-to-W route，解除 WID 高位与目标绑定；
3. 修复 Default write；
4. 修复 `order_grant` 与新队首错位；
5. clear 改为真实 LAST fire。

### 17.2 第二批：修复协议顺序

1. order key 改为上游 `{MID, ID}`；
2. Default R 纳入顺序 tracker；
3. 增加 B order/outstanding tracker；
4. 冻结 W/R interleaving 策略。

### 17.3 第三批：公平性和 reset

1. RR 指针改为握手更新；
2. `sid_buffer` 单时序块重写；
3. 统一 runtime reset 行为；
4. 增加内部一致性 assertion。

### 17.4 第四批：性能和工程质量

1. 决定是否支持 tracker 多 push/pop；
2. 决定 FIFO 满状态同周期 pop+push；
3. 清除位宽 warning；
4. 冻结或真正完成参数化；
5. 增加非法 SID、重叠地址和跨边界保护。

每一批修复都应单独提交和回归，避免同时改动路由、顺序、仲裁和 FIFO 后无法定位新问题。

## 18. 完备 DV 环境中的定向用例建议

| 用例 | 主要目标 |
|---|---|
| `rtl_random_write_id_route_test` | 各 Slave 遍历全部 AWID/WID，暴露 ID 与 target 耦合 |
| `rtl_default_write_read_test` | Default DECERR、W 路由和回程 |
| `rtl_order_grant_head_change_test` | 紧邻 SID 切换，检查 stale grant |
| `rtl_last_stall_tracker_test` | LAST 长 stall，检查 tracker 不提前释放 |
| `rtl_same_id_cross_slave_read_test` | 同 RID 跨 Slave 顺序 |
| `rtl_same_id_default_read_test` | 正常与 Default 的同 RID 顺序 |
| `rtl_rr_backpressure_fairness_test` | WAIT 长度扫描和无饥饿检查 |
| `rtl_wr_interleave_policy_test` | W/R beat 切换是否符合冻结策略 |
| `rtl_tracker_full_parallel_test` | 4-entry 满、并发 push/clear、固定优先级 |
| `rtl_runtime_reset_stress_test` | 各内部状态下 reset |
| `rtl_invalid_response_id_test` | 非法 MID、无 outstanding response |
| `rtl_address_boundary_test` | 窗口边界、空洞、4 KiB 和 overlap |
| `rtl_fifo_full_throughput_test` | 满状态 push+pop 和持续流量 |

随机回归还应交叉覆盖：

```text
master x slave x direction x original_id
outstanding_depth x response_order x backpressure_length
RR contention_degree x WAIT_length x winner
tracker_occupancy x push_count x clear_count
reset_phase x channel_phase x outstanding_nonzero
```

## 19. 失败后的定位流程

完备环境第一次发现失败时，建议按以下顺序处理：

1. 确认 stimulus 是否满足已经冻结的 AXI 和项目约束；
2. 确认 monitor 只在真实 `VALID && READY` 时发布 event；
3. 区分 timeout、路由错误、ID 错误、顺序错误、仲裁错误和 reset 清理错误；
4. 从 scoreboard 的第一个不一致向前追踪，不要只看最终 timeout；
5. 同时打印 `{master, target, original_id, SID, channel, sample_cycle}`；
6. 对仲裁失败打印 req、route select、order eligible、grant、ready、last winner 和 WAIT；
7. 对 tracker 失败打印所有 entry、valid、push fire、clear fire 和 count；
8. 固定 seed 并缩减为最少 Master、最少 Slave、最少事务；
9. 修复 RTL，而不是降低 checker 严格度来隐藏差异；
10. 先跑问题定向用例，再跑 Stage 1/2 基础回归，最后跑完整随机回归。

若失败来自“RTL 当前行为”和“设计期望”不一致，应先更新并审核规格决策，再同步修改 RTL 与 checker。不能让 reference model 同时承担“镜像现有缺陷”和“判断协议正确性”两个相互冲突的角色。

## 20. 修复完成条件

只有满足以下条件，才认为相关 RTL 问题已经真正解决：

- 定向复现用例从稳定失败变为稳定通过；
- 新增 assertion 在正向回归中零失败；
- Stage 1/2 基础功能无回退；
- Stage 3 outstanding 和乱序测试通过；
- Stage 4 W/R 交织按冻结策略通过；
- 三主三从并发、长 backpressure 和 tracker 满场景通过；
- runtime reset 后没有残留 outstanding、grant、FIFO entry 或 tracker entry；
- 全部 expected/actual 队列在测试结束时为空；
- 无额外、重复、遗漏或错误路由的 AW/W/B/AR/R；
- lint 不再报告多驱动、锁存器或关键位宽截断；
- 随机回归在多个 seed 下不再依赖固定 ID 或固定 READY 模式才能通过。

## 21. 总结

当前 RTL 在固定 M0->S0、固定写 ID、低 outstanding、有限 backpressure 的场景下可以工作，但完备环境扩大到随机 ID、Default 路径、多 Master、多 Slave、同 ID 跨目标、连续 FIFO 队首切换和 runtime reset 后，预计会集中暴露以下结构性问题：

```text
写路由依赖 ID 位段
    + Default W 未定义
    + 顺序 grant 与当前 SID 未绑定
    + tracker 状态不完全由握手驱动
    + 上游同 ID 顺序 key 选择错误
    + RR 指针更新与真实服务脱钩
```

最有效的解决方式不是逐项增加特殊判断，而是重新明确三个边界：

- switch 只负责 route 和 ID 转换；
- order tracker 只负责 outstanding 因果和同 ID 顺序；
- arbiter 只负责 eligible 候选之间的公平选择和 stall 锁定。

完成这三个边界的重构后，Default、随机 ID、outstanding、乱序和 beat 交织才能在同一套规则下稳定扩展。

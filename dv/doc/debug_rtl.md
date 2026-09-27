# RTL 问题调试记录

## 第一部分：reorder 完整 SID 匹配错误

### 1. reorder 模块实现的功能

`reorder` 根据 outstanding buffer 中保存的完整 SID，判断当前 W/R 候选是否属于一笔已经接收的合法事务。读通道将三个 Slave 返回的 `RID` 与已接收的 `ARID` 比较，写通道将三个 Master 发出的 `WID` 与已接收的 `AWID` 比较。完整 SID 匹配成功后，模块输出对应的 `order_grant`，允许该候选参与后续仲裁和传输。

`rob_buffer[0:3]` 表示最多保存 4 笔 outstanding 事务，每个条目保存一个 8-bit SID。SID 包含目标 Slave、来源 Master 和原始 AXI ID，因此应当作为一个完整 ID 进行匹配。

### 2. 之前代码存在的问题

#### 2.1 验证环境如何发现问题

`axi_stage3_read_ooo_test` 向同一个 Slave 连续发送 4 笔来自同一个 Master、transaction tag 不同的读事务。对应内部 SID 为 `8'h54`～`8'h57`，请求按 tag `0、1、2、3` 发出，Slave reactive sequence 则按 tag `2、0、3、1`，即 SID `56、54、57、55` 的顺序返回，用于验证不同完整 ID 可以乱序完成。

故障运行中，4 笔 AR 请求已经被 DUT 和 Slave 侧验证环境接收，Slave Driver 也已经拉高 `RVALID` 并给出计划中的 `RID`，但端到端 checker 的读响应计数不再增长，最终触发测试超时。超时诊断的关键现象是：

```text
Slave 侧 RVALID = 1
Slave 侧 RID    = 某个已记录的非首位 outstanding SID
Slave 侧 RREADY = 0
Master 侧没有对应的 R 通道握手
```

这说明问题不是“没有产生响应”，而是 DUT 收到合法响应后持续施加反压。由于 AXI 要求 `RVALID=1` 且未握手时保持 `RID` 和 payload 稳定，Slave 不能撤回当前响应并改发 buffer 首位事务，因此系统进入永久等待。

#### 2.2 如何锁定根因

按照反压路径从输出向内部逐级追踪：

```text
S_RREADY = 0
  <- 没有对应 RGRANT
  <- RSELECT 被 r_order_grant 屏蔽
  <- reorder 没有认可当前 RID
```

检查 `ar_sid_buffer` 后确认当前 `RID` 的完整 8-bit SID 确实存在于 buffer 的非首位条目中，因此可以排除请求未记录、SID 编码错误和 Slave 返回未知 ID。继续检查旧 `reorder`，发现它没有直接比较完整 SID，而是分别生成高四位和低四位匹配向量，并要求两个向量以相同的唯一优先位置命中。这种实现忽略了同一个 Master 可以向同一个 Slave 发出多笔 outstanding 事务：这些事务的 SID 高四位相同，低四位事务 ID 不同。

例如三笔 outstanding 事务的 SID 分别为 `8'h54`、`8'h55`、`8'h56`，当前返回 `8'h56` 时：

```text
高四位匹配向量 = 3'b111
低四位匹配向量 = 3'b100
完整 SID 匹配   = 3'b100
```

完整 SID 明明匹配 `rob_buffer[2]`，但旧代码要求高、低匹配向量同时为 `3'b100`，因此错误地输出 `order_grant=0`。前面条目的高四位部分匹配阻塞了后续条目的完整 SID 匹配，最终形成 `RVALID=1、RREADY=0` 的死锁。

旧代码错误地把“相同完整 ID 需要保序”扩大成“同一 Master、同一 Slave 的所有 ID 都需要保序”。而当前模块只保存 SID，没有缓存响应 payload，也无法要求 Slave 改发首位事务，所以这种阻塞不能实现重排序，只会造成死锁。写通道复用了同一个 `reorder`，因此同样存在 AW buffer 中非首位 WID 被错误阻塞的风险。

### 3. 对代码进行的修改

#### 3.1 修改方案

删除高四位和低四位的独立匹配及优先判断，改为将每个有效的 8-bit SID 直接与 4 个 outstanding buffer 条目进行完整比较。只要任意一个条目完整匹配，就置位对应的 `order_grant`。

```systemverilog
order_grant[0] <= sid_0_vld &&
                  ((sid_0 == rob_buffer[0]) ||
                   (sid_0 == rob_buffer[1]) ||
                   (sid_0 == rob_buffer[2]) ||
                   (sid_0 == rob_buffer[3]));
```

修改后的判断直接表达设计意图：候选 SID 有效且存在于 outstanding buffer 中时允许通过。它既支持同一 Master 向同一 Slave 发出的多笔不同 ID outstanding 事务，也避免把字段级部分匹配误认为事务级顺序约束。

#### 3.2 如何验证问题已经解决

验证采用“模块定向检查、原失败用例回归、兼容性回归”三层闭环：

1. 模块定向检查：设置 `rob_buffer={8'h54, 8'h55, 8'h56}`，同时输入三个有效候选 `56、55、54`，检查 `order_grant=3'b111`；再输入不存在的 SID 或拉低 `sid_vld`，检查 grant 为 0。该检查已经通过，证明同高四位的非首位完整 SID 能正常命中，同时未知 SID 仍会被拒绝。
2. 原失败用例回归：重新运行 `axi_stage3_read_ooo_test`，不仅检查用例不再 timeout，还应确认 4 笔读响应全部被 checker 匹配、实际完成顺序与请求顺序不同、最终 outstanding 数量归零。
3. 兼容性回归：运行 write OOO、mixed R/W、outstanding stall 和 same-ID order 用例，再执行 Stage1/Stage2 回归，确认修改没有放过未知 SID，也没有破坏相同完整 ID 的顺序要求及原有基本传输。

当前完整 RTL/DV 编译为 0 error、0 warning，模块定向检查通过。`latency_gen` 的调用端已改用 `randomize() with` 约束延迟模式和范围，不再依赖缺失的配置方法。原失败用例 `axi_stage3_read_ooo_test`、Stage3 全部 8 个用例、Stage2 全部 7 个用例以及 Stage1 两个基本用例均已通过，端到端问题完成闭环。

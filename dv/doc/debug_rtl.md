# RTL 问题调试记录

## 第一部分：reorder 完整 SID 匹配错误

### 1. reorder 模块实现的功能

`reorder` 的核心功能是根据 outstanding buffer 中保存的完整 SID，判断当前 W/R 候选是否属于一笔已经接收的合法事务，并把合法候选送入后续仲裁器。

`reorder` 用于判断当前候选事务的 SID 是否存在于 outstanding buffer 中。读通道将三个 Slave 返回的 `RID` 与已接收的 `ARID` 比较，写通道将三个 Master 发出的 `WID` 与已接收的 `AWID` 比较。完整 SID 匹配成功后，模块输出对应的 `order_grant`，允许该事务继续参与后续仲裁和传输。

`rob_buffer[0:3]` 表示最多保存 4 笔 outstanding 事务，每个条目保存一个 8-bit SID。SID 包含目标 Slave、来源 Master 和原始 AXI ID，因此应当作为一个完整 ID 进行匹配。

### 2. 之前代码存在的问题

之前的代码将 8-bit SID 拆成高四位和低四位，分别产生匹配向量，再要求两个匹配向量以相同的唯一优先位置命中。这种实现忽略了同一个 Master 可以向同一个 Slave 发出多笔 outstanding 事务：这些事务的 SID 高四位相同，低四位事务 ID 不同。

例如三笔 outstanding 事务来自同一个 Master 并访问同一个 Slave 时，可能出现 `s0_rid_high[2:0] = 3'b111`。当返回 SID 完整匹配 `rob_buffer[2]` 时，低四位匹配结果可能是 `3'b100`，但旧代码要求高、低匹配结果同时为 `3'b100`，因此会错误地拒绝该合法事务。其本质是前面条目的高四位部分匹配阻塞了后续条目的完整 SID 匹配，导致不同 ID 之间无法正常乱序返回。

综合来看，旧代码可能想实现保序和 outstanding 合法性检查，但错误地对 SID 的高、低字段分别实施了最早匹配约束，把“同完整 ID 保序”扩大成了“同 Master、同 Slave 保序”。即使这是有意的保守设计，现有架构也无法安全实现，可能因合法乱序响应导致死锁。因此应当认定为设计实现错误。

### 3. 对代码进行的修改

删除高四位和低四位的独立匹配及优先判断，改为将每个有效的 8-bit SID 直接与 4 个 outstanding buffer 条目进行完整比较。只要任意一个条目完整匹配，就置位对应的 `order_grant`。

修改后的判断直接表达了设计意图：候选 SID 有效且存在于 outstanding buffer 中时允许通过。这样既支持同一 Master 向同一 Slave 发出的多笔不同 ID outstanding 事务，也使代码更简洁、清楚且易于维护。

# AXI Interconnect Arbiter 与 Switch 机制说明

> 本文只描述当前 RTL 采用的机制原理，用于指导 DV 中的 arbiter model 和 switch reference model。  
> RTL 的具体代码实现、已知问题和修复建议不在本文展开，统一参考 `dv/doc/solve.md`。

## 1. 总体机制

当前 interconnect 的处理过程可以抽象为：

```text
请求方向：Master请求 -> 目标路由 -> 顺序资格 -> 目标内仲裁 -> Slave
响应方向：Slave响应 -> 顺序资格 -> Master路由 -> Master内仲裁 -> Master
```

三个功能的边界为：

- switch：决定事务去哪个 Slave，或响应回哪个 Master；
- order tracker：决定候选当前是否有发送资格；
- arbiter：在同一目标的多个合法候选中选择 winner。

DV 中应分别实现这三个功能，不要把路由、顺序和仲裁合并为一个模型。

## 2. Arbiter 机制

### 2.1 仲裁域

当前设计采用局部仲裁，不使用一个全局 3x3 仲裁器。

请求侧按目标 Slave 仲裁：

| 目标 | 候选 | 通道 |
|---|---|---|
| S0/S1/S2/Default | M0、M1、M2 | AW、W、AR各自独立 |

响应侧按目标 Master 仲裁：

| 目标 | 候选 | 通道 |
|---|---|---|
| M0/M1/M2 | S0、S1、S2、Default | B、R各自独立 |

不同目标和不同通道维护各自独立的仲裁状态。

### 2.2 候选资格

进入 arbiter 的候选必须同时满足：

```text
VALID
AND 路由命中当前目标
AND 顺序资格成立
```

其中 AW、AR、B 不需要额外的 W/R 顺序资格；W 必须关联已接受的 AW，R 必须关联已接受的 AR。

### 2.3 Round-robin 原理

同一仲裁域采用 round-robin：

1. 记录上一次被服务的候选；
2. 下一次从该候选的下一项开始循环搜索；
3. 找到的第一个 eligible 候选成为 winner；
4. 搜索到末尾后回到候选 0；
5. 没有候选时不产生 grant。

请求侧轮询顺序：

```text
M0 -> M1 -> M2 -> M0 -> ...
```

响应侧轮询顺序：

```text
S0 -> S1 -> S2 -> Default -> S0 -> ...
```

reset 后第一次竞争从最低下标开始，即请求侧从 M0 开始，响应侧从 S0 开始。

### 2.4 Backpressure 锁定

winner 选出后，如果对端 READY=0，必须锁定当前 winner 和 payload：

```text
VALID=1、READY=0：保持当前 winner
VALID=1、READY=1：本次服务完成，允许重新仲裁
```

锁定期间即使出现新的候选，也不能切换输出。

### 2.5 仲裁粒度

| 通道 | 仲裁单位 |
|---|---|
| AW | 一个地址请求 |
| AR | 一个地址请求 |
| B | 一个写响应 |
| W | 一个数据 beat |
| R | 一个数据 beat |

因此 W/R 可以在 beat 边界重新选择其他 ID 的候选；是否在测试中主动产生 beat 交织，可由验证阶段控制。

### 2.6 DV 所需状态

每个仲裁域只需保存：

```text
last_winner
grant_locked
locked_winner
```

输入为 eligible vector 和 READY，输出为 one-hot grant。arbiter model 不负责地址译码、ID 转换和 outstanding 管理。

本文定义的是 round-robin 机制原理。若需要逐周期复刻当前 RTL 的内部指针更新细节，应另设 RTL compatibility mode；这些实现偏差不应混入通用机制模型。

## 3. Switch 机制

### 3.1 请求路由

AW 和 AR 根据地址选择目标 Slave：

| 目标 | 地址范围 |
|---|---|
| S0 | `0x0000_0000` - `0x0000_0FFF` |
| S1 | `0x0000_2000` - `0x0000_2FFF` |
| S2 | `0x0000_4000` - `0x0000_4FFF` |
| Default | 未命中上述窗口的地址 |

整个 burst 的目标由 AW/AR 地址请求确定，不在数据 beat 之间重新译码。

指向同一 Slave 的多个 Master 请求进入该 Slave 的仲裁域。arbiter 选出 winner 后，switch 转发 winner 的 payload，并且只向 winner 返回 READY。

### 3.2 下游 SID 格式

Master 标记为：

| Master | `master_tag` |
|---|---:|
| M0 | `01` |
| M1 | `10` |
| M2 | `11` |

正常 Slave 标记为：

| Slave | `slave_tag` |
|---|---:|
| S0 | `01` |
| S1 | `10` |
| S2 | `11` |

下游 8-bit SID 的逻辑格式为：

```text
SID = {slave_tag, master_tag, original_id}
       [7:6]      [5:4]       [3:0]
```

AW/AR 除 ID 扩展外，其余地址和控制 payload 保持不变。

### 3.3 W 路由

当前 RTL 的 W 通道使用 `WID[3:2]` 选择目标：

| `WID[3:2]` | 目标 |
|---:|---|
| `01` | S0 |
| `10` | S1 |
| `11` | S2 |

下游 WID 为：

```text
downstream WID = {WID[3:2], master_tag, original WID}
```

要与 AW 记录对应，当前机制要求：

```text
WID == AWID
WID[3:2] == slave_tag(AWADDR)
```

因此，在验证当前 RTL 时，写 ID 高两位同时承担目标 Slave 编码。若 RTL 后续改为 AW route lookup，reference model 也应同步改为查表路由。

### 3.4 响应路由

B/R 根据下游 SID 的 `master_tag` 返回原 Master：

| `SID[5:4]` | 目标 Master |
|---:|---|
| `01` | M0 |
| `10` | M1 |
| `11` | M2 |

指向同一 Master 的 S0、S1、S2 和 Default 响应进入该 Master 的 B/R 仲裁域。

响应转发到 Master 时恢复原始 ID：

```text
upstream BID/RID = downstream SID[3:0]
```

BRESP、RDATA、RRESP、RLAST 等 payload 保持不变，READY 只返回给当前 winner。

### 3.5 Default 路径

未命中正常地址窗口的请求进入 Default 路径。机制上 Default 应返回原请求 ID和 DECERR。

当前 RTL 的 Default read 可以按该原则建模；Default write 路由存在已知限制，验证时应作为风险场景处理，详见 `dv/doc/solve.md`。

## 4. 顺序资格机制

### 4.1 AW/W

W 只有在存在对应的已接受 AW 时才 eligible。AW 与 W 使用扩展后的完整 SID 关联。

最后一个 W beat 完成后，对应 AW/W 顺序记录释放。

### 4.2 AR/R

R 只有在存在对应的已接受 AR 时才 eligible。

当前机制遵循：

```text
相同完整 SID：保持请求顺序
不同完整 SID：允许乱序返回并参与仲裁
```

最后一个 R beat 完成后，对应 AR/R 顺序记录释放。

### 4.3 与 arbiter 的关系

```text
order tracker：产生 eligible vector
arbiter：从 eligible 候选中选择 one-hot winner
switch：转发 winner 并完成 ID 转换
```

eligible 可以同时有多位为 1；grant 必须是 one-hot。

## 5. DV 实现边界

### 5.1 Arbiter model

负责：

- 独立维护每个目标、每个通道的 round-robin 状态；
- 从 eligible vector 中选择 winner；
- READY=0 时锁定 winner；
- 按 AW/AR/B 事务或 W/R beat 的完成边界推进。

### 5.2 Switch reference model

建议提供：

```text
decode_address(address) -> S0/S1/S2/DEFAULT
decode_w_target(wid)    -> S0/S1/S2/INVALID
encode_sid(master, slave, original_id) -> SID
decode_master(sid)      -> M0/M1/M2/INVALID
restore_id(sid)         -> original_id
```

它负责路由和 ID 转换，不负责选择竞争 winner。

### 5.3 Order tracker

负责：

- 记录已接受 AW/AR；
- 生成 W/R eligible；
- 保持相同顺序 key 的先后关系；
- 在 WLAST/RLAST 完成后释放记录；
- reset 时清空全部记录。

## 6. 机制摘要

```text
Arbiter：
每个目标独立 round-robin；从上次 winner 的下一项开始；
backpressure 时锁定 winner；W/R 以 beat 为仲裁单位。

Switch：
AW/AR 按地址选择 Slave；W 按 WID[3:2] 选择 Slave；
下游 ID 扩展为 {Slave, Master, Original ID}；
B/R 按扩展 ID 中的 Master 标记回程，并恢复原始 ID。

Ordering：
W 关联已接受 AW，R 关联已接受 AR；
相同完整 SID 保序，不同完整 SID 允许乱序竞争。
```

验证环境只需要围绕这些规则实现 arbiter model、switch reference model 和 order tracker，不需要复制 RTL 的模块层次或具体状态机代码。

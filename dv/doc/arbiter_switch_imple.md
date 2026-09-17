# AXI Interconnect Arbiter 与 Switch 实现机制说明

> 文档性质：当前 RTL 行为分析与 DV 实现参考  
> 适用配置：3 Master、3 Slave、4-bit 上游 ID、8-bit 下游扩展 ID  
> 主要源码：`axi_interconnect.v`、`axi_crossbar.v`、`axi_mtos_m3.v`、`axi_stom_s3.v`、`axi_arbiter_mtos_m3.v`、`axi_arbiter_stom_s3.v`、`round_robin_m2s.v`、`round_robin_s2m.v`、`sid_buffer.v`、`reorder.v`

## 1. 目的与结论

本文说明当前 RTL 中 round-robin 仲裁、请求/响应 switch 和 W/R 顺序资格过滤的实际机制，为后续 DV 实现提供依据。

建议把 DV 功能拆成三个相互独立的部分：

1. `arbiter_model`：只负责候选请求之间的 round-robin 选择和 backpressure 锁定；
2. `ref_model`：负责地址路由、ID 扩展/恢复和 payload 转换；
3. `order_tracker`：负责 AW 到 W、AR 到 R 的同 SID 顺序资格。

`order_tracker` 可以属于 reference model，但不应与 round-robin 状态机混在一起。`order_grant` 表示“有资格参与”，真正的 one-hot winner 仍由 arbiter 产生。

## 2. 总体结构

RTL 不是一个全局 3x3 arbiter，而是由多个局部仲裁域构成：

```text
请求方向：

M0/M1/M2 输入 FIFO
        +--> S0：路由判定 + 3选1 AW/W/AR 仲裁 --> S0 输出 FIFO
        +--> S1：路由判定 + 3选1 AW/W/AR 仲裁 --> S1 输出 FIFO
        +--> S2：路由判定 + 3选1 AW/W/AR 仲裁 --> S2 输出 FIFO
        `--> Default：路由判定 + 3选1 AW/W/AR 仲裁 --> Default Slave

响应方向：

S0/S1/S2 响应 FIFO + Default Slave
        +--> M0：按 SID 选路 + 4选1 B/R 仲裁 --> M0 输出 FIFO
        +--> M1：按 SID 选路 + 4选1 B/R 仲裁 --> M1 输出 FIFO
        `--> M2：按 SID 选路 + 4选1 B/R 仲裁 --> M2 输出 FIFO
```

结构上的仲裁器数量如下：

| 方向 | 仲裁域 | 候选 | 通道 | 数量 |
|---|---|---|---|---:|
| Master 到 Slave | 每个 S0/S1/S2/Default 独立 | M0/M1/M2 | AW、W、AR | 4 x 3 = 12 |
| Slave 到 Master | 每个 M0/M1/M2 独立 | S0/S1/S2/Default | B、R | 3 x 2 = 6 |

总计 18 个独立仲裁状态。不同目标、不同通道之间不共享 round-robin 指针或 WAIT 状态。Default W 路径虽然有结构实例，但当前实现存在缺陷，见第 8 节。

主要模块的职责对应关系如下：

| 模块 | 职责 |
|---|---|
| `axi_mtos_m3` | 一个目标 Slave 的 AW/W/AR 译码、3 路仲裁和请求 mux |
| `axi_stom_s3` | 一个目标 Master 的 B/R MID 译码、4 路仲裁和响应 mux |
| `axi_arbiter_mtos_m3` | 请求侧 AW/W/AR 的 RUN/WAIT 锁定状态机 |
| `axi_arbiter_stom_s3` | 响应侧 B/R 的 RUN/WAIT 锁定状态机 |
| `round_robin_m2s` | M0/M1/M2 三路轮询选择 |
| `round_robin_s2m` | S0/S1/S2/Default 四路轮询选择 |
| `sid_buffer`、`reorder` | W/R 仲裁前的完整 SID 顺序资格过滤 |

## 3. FIFO 边界

`axi_interconnect` 在外部接口和 `axi_crossbar` 两侧插入同步 FIFO：

- 每个 Master 的 AW/W/AR 输入 FIFO；
- 每个真实 Slave 的 AW/W/AR 输出 FIFO；
- 每个真实 Slave 的 B/R 输入 FIFO；
- 每个 Master 的 B/R 输出 FIFO。

FIFO 均以 `FAW=2` 实例化，深度为 4，并采用 first-word fall-through 输出。仲裁器看到的是输入 FIFO 队首，不是外部接口当周期新握手的事务。

因此：

- Master 侧 AW/W/AR 握手只表示进入输入 FIFO，不表示已经赢得 crossbar 仲裁；
- crossbar 内部选中的事务还可能先进入输出 FIFO，稍后才被外部 Slave 观察到；
- 只靠外部 transaction 时间戳无法总是唯一恢复内部某周期 grant。

周期精确检查应建模 FIFO 队首、容量和出入队，或者绑定/采样 crossbar 内部 request、grant、ready。纯端到端 checker 应检查实际输出属于合法候选集合，不应在信息不足时强制唯一 winner。

## 4. Round-robin 仲裁

### 4.1 最终请求向量

请求侧 `axi_arbiter_mtos_m3` 使用：

```systemverilog
AWREQ = AWSELECT & AWVALID;
WREQ  = WSELECT  & WVALID;
ARREQ = ARSELECT & ARVALID;
```

响应侧 `axi_arbiter_stom_s3` 使用：

```systemverilog
BREQ = BSELECT & BVALID;
RREQ = RSELECT & RVALID;
```

其中 WSELECT 已经与 `w_order_grant` 相与，RSELECT 已经与 `r_order_grant` 相与。换言之，arbiter 的输入应是经过路由、VALID 和顺序资格过滤后的最终候选集合。

### 4.2 候选编号

请求侧 3 路 one-hot 含义：

| 位 | 候选 |
|---:|---|
| 0 | M0 |
| 1 | M1 |
| 2 | M2 |

响应侧 4 路 one-hot 含义：

| 位 | 候选 |
|---:|---|
| 0 | S0 |
| 1 | S1 |
| 2 | S2 |
| 3 | Default Slave |

### 4.3 搜索顺序

`round_robin_m2s` 和 `round_robin_s2m` 保存 one-hot `last_winner`，从其下一项开始循环查找第一个有效 request。

3 路请求侧顺序：

| `last_winner` | 搜索顺序 |
|---|---|
| reset/0/非法值 | M0 -> M1 -> M2 |
| M0 | M1 -> M2 -> M0 |
| M1 | M2 -> M0 -> M1 |
| M2 | M0 -> M1 -> M2 |

4 路响应侧顺序：

| `last_winner` | 搜索顺序 |
|---|---|
| reset/0/非法值 | S0 -> S1 -> S2 -> Default |
| S0 | S1 -> S2 -> Default -> S0 |
| S1 | S2 -> Default -> S0 -> S1 |
| S2 | Default -> S0 -> S1 -> S2 |
| Default | S0 -> S1 -> S2 -> Default |

`round_robin_s2m` 没有显式的 Default winner 分支，最终 `else` 同时承担 Default 后回绕、reset 值和非法值处理。

### 4.4 RUN/WAIT 锁定

每个通道 arbiter 在组合 round-robin 外还有独立的两态 FSM：

- `RUN`：输出当前组合选择；
- `WAIT`：输出保存的 one-hot grant。

行为为：

1. RUN 中存在 grant 且选中目标 READY=1，本周期直接握手，继续停留 RUN；
2. RUN 中存在 grant 但选中目标 READY=0，保存 grant 并进入 WAIT；
3. WAIT 中忽略新的组合 winner，持续输出保存的 grant；
4. 被锁定候选发生 `VALID && READY` 握手后，下一周期返回 RUN。

伪代码如下：

```text
rr_sel = rr_scan(req, last_winner)
grant  = waiting ? held_grant : rr_sel

on clock edge:
    if RUN and grant != 0 and selected_ready == 0:
        held_grant = grant
        state = WAIT
    else if WAIT and selected_valid and selected_ready:
        held_grant = 0
        state = RUN
```

WAIT 保证 VALID 已经暴露而 READY 未到来时，mux 不切换候选。若源端违规撤销 VALID，arbiter 不会改选其他候选，而会一直等待被锁定源重新满足握手。

### 4.5 仲裁粒度

| 通道 | 实际释放粒度 | 说明 |
|---|---|---|
| AW | 每个 AW 握手 | 一个地址对应一次仲裁 |
| AR | 每个 AR 握手 | 一个地址对应一次仲裁 |
| B | 每个 B 握手 | 一个响应对应一次仲裁 |
| W | 每个 W beat 握手 | WLAST 条件在 RTL 中被注释 |
| R | 每个 R beat 握手 | RLAST 条件在 RTL 中被注释 |

所以 W/R 不是锁定整个 burst，而是逐 beat 重新仲裁。多个持续有效的不同 WID/RID 可以在 beat 边界切换。Stage 3 可以不主动产生 beat 交织，但周期级 arbiter model 必须按 beat 建模。

### 4.6 `last_winner` 的实际更新规则

当前 round-robin 在 `|req` 为 1 时，每个时钟沿都执行：

```systemverilog
last_winner <= curr_winner;
```

该更新不要求实际握手，也不知道外层 FSM 是否处于 WAIT。因此：

- 输出 grant 被 backpressure 锁定时，内部 `last_winner` 仍可能每周期变化；
- 多个 request 持续有效时，WAIT 持续周期数会影响解除锁定后的下一 winner；
- 指针由“request 存在的周期”推进，而不是严格由“已完成的 grant”推进。

DV 若要与当前 RTL 周期精确一致，应实现 `rtl_compatible` 模式并复制该规则。另行实现“仅握手后更新”的理想模式时，必须使用独立配置，不能拿它判断当前 RTL 的精确 winner。

### 4.7 无请求状态

request 全 0 时，组合选择和 grant 为 0，`last_winner` 保持，mux 输出清零，所有返回候选的 READY 为 0。

## 5. 请求侧 Switch：Master 到 Slave

每个目标实例化一个 `axi_mtos_m3`。它先判断 M0/M1/M2 中哪些请求属于该目标，再进行 3 路仲裁，最后用 one-hot mux 转发 winner 的完整 payload。

### 5.1 AW/AR 地址译码

正常 Slave 使用：

```systemverilog
select = (AxADDR[31:ADDR_LENGTH] == ADDR_BASE[31:ADDR_LENGTH]);
```

当前映射为：

| 目标 | 地址范围 | `ADDR_LENGTH` | `slave_tag` |
|---|---|---:|---:|
| S0 | `0x0000_0000` - `0x0000_0FFF` | 12 | `2'b01` |
| S1 | `0x0000_2000` - `0x0000_2FFF` | 12 | `2'b10` |
| S2 | `0x0000_4000` - `0x0000_4FFF` | 12 | `2'b11` |
| Default | 非上述范围，包括地址空洞 | - | 见第 8 节 |

Default AW/AR 选择是三个正常 Slave 命中结果的补集，并与对应 Master VALID 相与。当前窗口互不重叠；RTL 没有额外的多命中保护，未来若参数改成重叠窗口，同一请求可能被多个目标同时选中。

### 5.2 下游扩展 ID

三个 Master 的固定 MID 为：

| Master | MID |
|---|---:|
| M0 | `2'b01` |
| M1 | `2'b10` |
| M2 | `2'b11` |

正常 AW/AR 的 8-bit 下游 SID 为：

```text
SID[7:6] = slave_tag
SID[5:4] = master_tag/MID
SID[3:0] = upstream AWID/ARID
```

即：

```systemverilog
S_AWID = {slave_tag_from_addr, MID, M_AWID};
S_ARID = {slave_tag_from_addr, MID, M_ARID};
```

正常 Slave 的 tag 由 `ADDR_BASE[14:13] + 1` 得到，当前依次为 S0=`01`、S1=`10`、S2=`11`。

### 5.3 W 路由及写 ID 约束

W 没有地址，RTL 也没有在 switch 中保存 AW 到目标 Slave 的映射。W 的目标只由上游 `WID[3:2]` 决定：

```text
WID[3:2] == 01 -> S0
WID[3:2] == 10 -> S1
WID[3:2] == 11 -> S2
```

下游 WID 为：

```systemverilog
S_WID = {M_WID[3:2], MID, M_WID};
```

W 还必须通过 `w_order_grant`，也就是完整 8-bit WID 必须匹配已经接受的 AW SID。因此正常写事务至少满足：

```text
WID == AWID
WID[3:2] == slave_tag(AWADDR)
```

当前上游写 ID 空间实际按目标分区：

| AW 目标 | 可正常匹配的 AWID/WID |
|---|---|
| S0 | `4'h4` - `4'h7`，即 `01xx` |
| S1 | `4'h8` - `4'hB`，即 `10xx` |
| S2 | `4'hC` - `4'hF`，即 `11xx` |

这是当前 RTL 的特殊 ID 契约，不是通用 AXI3 crossbar 规则。sequence、reference model 和 scoreboard 必须显式体现该约束。

### 5.4 Mux 和 READY

AW/W/AR 各有独立 one-hot mux。winner 的 payload 和 VALID 被转发；无 winner 时输出总线清零。READY 只返回 winner：

```systemverilog
M_i_AWREADY = AWGRANT[i] & S_AWREADY;
M_i_WREADY  = WGRANT[i]  & S_WREADY;
M_i_ARREADY = ARGRANT[i] & S_ARREADY;
```

同一 Master 来自 S0/S1/S2/Default 的 READY 分量最后做 OR。当前地址窗口互斥，正常情况下只会有一个目标返回 READY。

### 5.5 请求示例

M1 发出 `AWADDR=0x0000_4020`、`AWID=4'hD`：

```text
目标       = S2
slave_tag  = 11
master_tag = M1 = 10
S_AWID     = {11,10,1101} = 8'hED
```

对应 W beat 使用 `WID=4'hD` 时：

```text
S_WID = {WID[3:2],M1_MID,WID} = {11,10,1101} = 8'hED
```

因此能够通过 AW/W 完整 SID 匹配。

## 6. 响应侧 Switch：Slave 到 Master

每个目标 Master 实例化一个 `axi_stom_s3`。它查看 S0/S1/S2/Default 的队首响应，先按 SID 中的 MID 判断是否属于该 Master，再由 4 路 arbiter 选择源。

### 6.1 B/R 回程选择

B 和 R 都使用 SID `[5:4]`：

```systemverilog
BSELECT[source] = (source_BID[5:4] == target_MID);
RSELECT[source] = (source_RID[5:4] == target_MID);
```

回程不依赖保存的地址，也不使用 SID `[7:6]` 选择 Master。Slave 必须原样返回完整扩展 ID。

### 6.2 ID 恢复

B 在 `axi_stom_s3` 中直接恢复：

```systemverilog
M_BID = selected_BID[3:0];
```

R 在 crossbar 内暂时保留完整 `M_RSID`，写入 Master 输出 FIFO 时只保留低 4 位：

```systemverilog
M_AXI_RID = selected_RID[3:0];
```

BRESP、RDATA、RRESP、RLAST 和 VALID 由 winner 原样转发。

### 6.3 响应 READY

READY 只送到 winner：

```systemverilog
S_i_BREADY = BGRANT[i] & M_BREADY;
S_i_RREADY = RGRANT[i] & M_RREADY;
```

同一 Slave 来自 M0/M1/M2 的 READY 分量最后做 OR。正常 MID 只命中一个 Master。

例如 S2 返回 `BID=8'hED={11,10,1101}`，只有 M1 的 BSELECT 命中；若赢得 M1 的 4 路 B 仲裁，M1 外部最终观察到 `BID=4'hD`。

## 7. 顺序资格过滤

### 7.1 基本关系

顺序逻辑先产生 eligibility，arbiter 再产生 winner：

```text
route_select & valid & order_grant（仅 W/R）
                      |
                      v
                round-robin request
                      |
                      v
                  one-hot winner
```

`order_grant` 可以多位同时为 1，不是最终 one-hot grant。

### 7.2 AW 到 W

写方向维护一个全局 4-entry `aw_sid_buffer`：

- 真实 S0/S1/S2 的 AW 被下游 AW FIFO 接受时，扩展 AWID 入队；
- 三个 Master 当前 WID 被扩展成完整 8-bit SID；
- `reorder` 判断每个候选是否匹配该 SID 的最早未完成记录；
- 通过者获得对应 `w_order_grant`；
- 真实 Slave 侧最后一个 W beat 出现后删除相应 SID。

因此 W 同时受 WID 目标译码和 AW 顺序记录约束。

### 7.3 AR 到 R

读方向维护一个全局 4-entry `ar_sid_buffer`：

- 真实 S0/S1/S2 的 AR 被下游 AR FIFO 接受时，扩展 ARID 入队；
- 三个真实 Slave 的当前 RID 与 buffer 比较；
- 相同完整 SID 只允许最早记录对应的响应通过；
- 不同完整 SID 可以同时具备资格，再由目标 Master 的 R arbiter 选择；
- Master 侧最后一个 R beat 出现后删除相应 SID。

顺序 key 是完整 8-bit SID，而不只是外部 4-bit RID。同一 Master、相同原始 RID、不同 `slave_tag` 的读事务会被当作不同顺序域，RTL 允许它们相互乱序。

### 7.4 容量和固定优先级

AW、AR SID buffer 均固定为 4 entry，以 8'h00 作为空标志。同周期多个真实 Slave 尝试 push 时，只允许一个，固定优先级为：

```text
S0 > S1 > S2
```

这不是 round-robin。buffer 满时阻止新 AW/AR；存在 clear 候选的周期也阻止 push。`reorder.order_grant` 为寄存器输出，输入或 buffer 改变后在时钟沿后更新。

同周期存在多个 clear 候选时也只处理一个，优先级同样是下标 0 > 1 > 2：写方向对应 S0 > S1 > S2，读方向对应 M0 > M1 > M2。

### 7.5 B 没有 reorder gate

B 通道只有 MID 路由、VALID 过滤和 round-robin，没有 `b_order_grant`。写响应顺序依赖 Slave 行为、响应 FIFO 和当前写 ID 约束，reference model 不应添加 RTL 中不存在的 B reorder 逻辑。

## 8. Default Slave

### 8.1 Default read

未命中正常窗口的 AR 进入内部 Default Slave。其响应为：

- `RRESP=2'b11`，即 DECERR；
- `RDATA` 全 1；
- RID 沿用收到的扩展 ARID。

Default R 是响应侧第 4 路候选，不受 `r_order_grant` 限制：

```systemverilog
RSELECT_in = RSELECT & {1'b1, r_order_grant};
```

### 8.2 Default write 已知问题

未命中的 AW 可以选择 Default，但 `axi_mtos_m3` 在 `SLAVE_DEFAULT=1` 分支没有给 `WSELECT` 赋值。W 又没有地址，所以当前源码没有形成可靠的 Default W 路由。

可能结果包括：

- unmatched AW 被 Default 接受；
- 对应 W 不能稳定到达 Default；
- Default 一直等待 W，不能产生预期 DECERR B；
- 仿真中出现未赋值组合变量引起的 X 或历史值。

DV 应把 unmatched write 记录为已知 RTL 缺陷/负向场景，不应在 reference model 中假设其能正常完成。修复 RTL 时必须同时定义 Default W 编码或建立 AW 到 W 的显式关联。

### 8.3 Default 的 SID 高位

Default `axi_mtos_m3` 的 `ADDR_BASE` 使用模块默认值 0，其 AW/AR bus 生成式得到 `SID[7:6]=01`，与 S0 相同。回程只检查 MID `[5:4]`，所以不影响返回 Master；但 DV 不能用 SID `[7:6]` 作为识别 Default 响应的唯一依据。

## 9. DV 实现建议

### 9.1 `arbiter_model`

每个仲裁域维护：

```text
last_winner
run_or_wait
held_grant
```

推荐周期算法：

```text
1. 用旧 last_winner 和当前 req 计算 rr_sel。
2. 用旧 FSM 状态决定本周期 grant：RUN 取 rr_sel，WAIT 取 held_grant。
3. 用本周期 grant、VALID、READY计算握手及下一 FSM 状态。
4. 时钟沿只要 req 非零，就把 last_winner 更新为 rr_sel，即使处于 WAIT。
5. W/R 每个 beat 握手后均允许重新仲裁，不等待 LAST。
```

arbiter model 只负责选择和锁定，不负责地址、ID、outstanding、因果关联和 payload 预测。

### 9.2 `ref_model` 中的 switch API

建议提供以下纯功能方法：

```text
route_aw(addr) -> S0/S1/S2/DEFAULT
route_ar(addr) -> S0/S1/S2/DEFAULT
route_w(wid)   -> S0/S1/S2/INVALID

master_tag(master_index) -> 01/10/11
slave_tag(slave_index)    -> 01/10/11

encode_aw_sid(master, target, awid) -> 8-bit SID
encode_ar_sid(master, target, arid) -> 8-bit SID
encode_w_sid(master, wid)           -> 8-bit SID
decode_response_master(sid)         -> M0/M1/M2/INVALID
decode_upstream_id(sid)             -> sid[3:0]
```

ref_model 负责：

- 按地址把 AW/AR 放入目标队列；
- 按 WID 高位决定 W 目标；
- 生成下游 SID并检查 AWID/WID/目标一致性；
- 按响应 MID 选择返回 Master；
- 恢复 4-bit BID/RID；
- 保持除 ID 外 payload 不变；
- 标记 Default read 预期和 Default write 不支持状态。

ref_model 不直接决定竞争时的 winner，而是把同一仲裁域的合法候选交给 arbiter model，或向 scoreboard 提供合法候选集合。

### 9.3 `order_tracker`

order tracker 至少维护：

- 已被真实 Slave 侧接受的 AW SID 队列；
- 已被真实 Slave 侧接受的 AR SID 队列；
- 每个完整 SID 的最早未完成位置；
- WLAST/RLAST 对应的释放；
- 周期兼容模式下的 4-entry 容量。

不要把 `order_grant` 当作 one-hot arbiter grant。

### 9.4 推荐检查分层

1. `arbiter_checker`：周期级检查 request、grant、ready、WAIT 锁定和 RR 指针；最好采样内部信号；
2. `switch/ref_model + scoreboard`：事务级检查地址目标、ID 转换、payload、响应回程和端到端因果关系。

若只观察外部 Master/Slave 接口，switch 功能可以可靠检查，但内部 grant 不一定能唯一恢复。此时不要对不可见的内部仲裁周期作过强假设。

## 10. RTL 兼容建模要点

| 编号 | 当前行为 | DV 影响 |
|---|---|---|
| RTL-ARB-01 | `last_winner` 在 `|req` 时更新，不要求握手 | backpressure 周期数会影响后续 winner |
| RTL-ARB-02 | WAIT 锁住已选 grant 直到该候选握手 | stall 期间不得改选 |
| RTL-ARB-03 | W/R 按 beat 释放，不按 LAST 锁 burst | 必须支持 beat 间重新仲裁 |
| RTL-SW-01 | AW/AR 按地址路由，W 按 WID[3:2] 路由 | W 不能只从 AW 地址推断 |
| RTL-SW-02 | 写 ID 高两位同时承担 Slave 编码 | 合法写 ID 空间按目标分区 |
| RTL-SW-03 | 响应按 SID[5:4] 回 Master，按 [3:0] 恢复 ID | 回程 key 必须包含 MID |
| RTL-ORD-01 | W/R 顺序使用完整 8-bit SID | 不同 slave tag 属于不同顺序域 |
| RTL-ORD-02 | SID buffer 深度 4，push 固定 S0>S1>S2 | 会产生额外反压，不是 RR |
| RTL-DEF-01 | Default WSELECT 未赋值 | unmatched write 不能按正常路径建模 |
| RTL-FIFO-01 | 仲裁器两侧存在深度 4 FIFO | 外部握手时刻不等于内部仲裁时刻 |

## 11. 应作为验证目标的问题

以下特征不应被功能模型无提示地“合理化”：

1. Default 分支未赋值 `WSELECT`；
2. W/R arbiter 的 LAST 条件被注释；
3. round-robin 指针不按成功握手更新，WAIT 期间可能漂移；
4. `sid_buffer` 使用 8'h00 表示空 entry，无法表示合法 0 值；
5. `sid_buffer` 清除判定使用 LAST 和 VALID，但内部 `clr_idx` 没有直接以最终 READY/握手限定，stall 边界可能提前清除；
6. `sid_buffer` 的 push 和 clear 时序块写同一组数组寄存器，应定向验证同时边界；
7. 请求侧 W grant 保存寄存器声明为 `[NUM:0]`，NUM=3 时为 4 bit，而 WGRANT 为 3 bit，当前依赖截断；
8. 多处向量宽度固定为 3 或 4，不能把当前源码视为通用 N 路实现。

建议区分两类检查结果：

- RTL compatibility checker：实际观察是否符合当前源码；
- protocol/architecture checker：实际行为是否符合预期 AXI 和设计规则。

错误信息应区分“DV 模型与 RTL 不一致”和“RTL 本身违反设计意图”。

## 12. 实现评审清单

- [ ] 3 路 reset 首选顺序为 M0、M1、M2；
- [ ] 4 路 reset 首选顺序为 S0、S1、S2、Default；
- [ ] 每个目标的 AW/W/AR 指针独立；
- [ ] 每个 Master 的 B/R 指针独立；
- [ ] WAIT 期间 grant 和选中 payload 保持；
- [ ] RTL 兼容模式在 WAIT 中仍按 request 更新 `last_winner`；
- [ ] W/R 按 beat 而非 burst 释放；
- [ ] AW/AR 严格按 `[31:12]` 地址窗口路由；
- [ ] W 按 `WID[3:2]` 路由并通过完整 SID 的 AW 顺序检查；
- [ ] 下游 ID 为 `{slave_tag, master_tag, original_id}`；
- [ ] B/R 按 SID `[5:4]` 回程并按 `[3:0]` 恢复 ID；
- [ ] Default read 与 Default write 使用不同支持状态；
- [ ] order tracker 和 round-robin arbiter 是独立模块/类；
- [ ] 只观察外部接口时，不对无法唯一推导的内部 grant 作周期精确假设；
- [ ] 覆盖同时请求、持续请求、winner backpressure、WAIT 中新请求加入、beat 交织和 SID buffer 满。

## 13. 最终机制摘要

```text
请求方向：按地址/WID分流 -> W顺序资格过滤 -> 每个目标独立3路RR -> mux转发
响应方向：按扩展ID的MID分流 -> R顺序资格过滤 -> 每个Master独立4路RR -> ID恢复
```

在 DV 中，switch/ref_model 回答“事务去哪里、ID 如何变化、响应回到哪里”；order tracker 回答“当前候选是否有资格”；arbiter model 回答“多个有资格候选中本周期选谁、stall 时怎样锁定”。三者分开后可以独立验证，也能避免把路由、outstanding、顺序和仲裁混成一个状态机。

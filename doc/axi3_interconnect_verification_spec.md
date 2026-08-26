# 三主三从 AXI3 Interconnect 验证规格说明

| 项目 | 内容 |
|---|---|
| 文档状态 | 验证基线 SPEC |
| 版本 | 1.0 |
| 日期 | 2026-08-24 |
| DUT | 三主三从 AXI Interconnect |
| 协议定位 | 赛题接口所定义的 AXI3 数据传输子集 |
| 文档用途 | 指导 UVM 验证环境架构设计，并作为后续 testplan 的需求来源 |

## 1. 文档目的

本 SPEC 定义三主三从 AXI Interconnect 的验证目标和期望行为。验证环境应以本 SPEC 为判断依据，而不能以当前 RTL 的已有行为反向定义正确结果。当前 RTL 对某项要求尚未实现时，验证环境应报告对应错误，之后再修改 RTL，不得通过降低 checker、assertion 或 stimulus 的要求规避问题。

本文中的“必须”表示需要形成 pass/fail 检查；“允许”表示 checker 必须接受的合法行为；“不保证”表示非法输入下不对 DUT 返回结果作功能判定，但仍可由协议断言报告输入违规。

## 2. 需求来源与范围

### 2.1 需求来源

本 SPEC 综合以下信息：

1. 赛题要求中的三路 AXI 读写请求、仲裁、路由和三主三从交叉矩阵功能。
2. 赛题明确列出的 outstanding transaction、incrementing burst、wrapping burst、out of order、interleaving 和 4KB 边界处理。
3. 赛题要求的 AXI slave interface 各通道 FIFO、AXI master interface 数据流转换、轮询仲裁和 switch 路由。
4. 赛题接口表规定的 32-bit 地址、32-bit 数据、4-bit ID 和 4-bit `AWLEN/ARLEN`。
5. 当前项目已经确认的地址映射、三主三从配置和 outstanding 上限。

### 2.2 验证范围

验证范围包括：

- 三个上游 AXI Master 同时访问三个下游 AXI Slave。
- AXI3 五个独立通道的传输、缓冲、背压和响应。
- 地址译码、switch 路由、请求及响应仲裁。
- burst、outstanding、乱序、交织、ID 路由和 4KB 边界处理。
- 非法地址的默认 Slave 响应。
- 功能正确性、协议正确性、公平性和可观察吞吐量。

### 2.3 不在本 SPEC 范围内

- AXI2AHB bridge、APB config 及其他附加模块。
- 综合、面积、功耗、APR、CTS、布线、STA、netlist、DEF、LIB 等后端内容。
- AXI3 锁定/独占访问及 `AxLOCK`、`AxCACHE`、`AxPROT` 等当前赛题接口未提供的边带功能。
- AXI4 专有功能。

因此，本项目验证的是赛题裁剪后的 AXI3 数据传输子集，不声明为完整 AMBA AXI3 全功能实现。

## 3. DUT 架构与数据流

### 3.1 外部连接关系

```text
上游 Master 0 ─┐                         ┌─ 下游 Slave 0
上游 Master 1 ─┼─> 通道 FIFO -> Switch/Arbiter ─┼─ 下游 Slave 1
上游 Master 2 ─┘                         └─ 下游 Slave 2
                         │
                         └─ Default Slave（非法地址 DECERR）

写响应和读数据沿相反方向，经响应路由与仲裁返回原请求 Master。
```

### 3.2 模块职责要求

- Slave-facing interface：接收三个上游 Master 发出的 AXI 请求，各 AXI 通道具有独立缓冲或行为等价的弹性存储能力。
- Switch：根据 AW/AR 地址选择目标 Slave，并保证请求、数据和响应走到正确端口。
- Arbiter：当多个请求竞争同一资源时执行轮询仲裁。
- Master-facing interface：将仲裁后的各通道数据流发送到三个下游 Slave，并接收其响应。
- Response routing：根据扩展 ID/源 Master 信息将 `B`、`R` 响应返回正确的上游 Master。
- Default Slave：处理未映射地址并返回 `DECERR`。

## 4. 接口与参数定义

### 4.1 基本参数

| 参数 | 要求 |
|---|---|
| 上游 Master 数量 | 3 |
| 下游 Slave 数量 | 3 |
| 地址宽度 | 32 bit |
| 数据宽度 | 32 bit |
| `WSTRB` 宽度 | 4 bit |
| 上游 AXI ID 宽度 | 4 bit |
| 当前下游扩展 ID 宽度 | 8 bit |
| `AWLEN/ARLEN` 宽度 | 4 bit |
| 最大 burst 长度 | 16 beats |
| 时钟 | 单时钟域 |
| 复位 | 低有效 |

上游 Master 侧对应当前 RTL 的 `M_AXI_*[0:2]`，下游 Slave 侧对应 `S_AXI_*[0:2]`。端口方向均以 DUT 为参考。

### 4.2 五通道信号组

| 通道 | DUT 上游侧方向 | 主要信号 | 功能 |
|---|---|---|---|
| AW | 输入请求、输出 READY | `AWID/AWADDR/AWLEN/AWSIZE/AWBURST/AWVALID/AWREADY` | 写地址和 burst 属性 |
| W | 输入数据、输出 READY | `WID/WDATA/WSTRB/WLAST/WVALID/WREADY` | AXI3 写数据及交织标识 |
| B | 输出响应、输入 READY | `BID/BRESP/BVALID/BREADY` | 写响应 |
| AR | 输入请求、输出 READY | `ARID/ARADDR/ARLEN/ARSIZE/ARBURST/ARVALID/ARREADY` | 读地址和 burst 属性 |
| R | 输出数据、输入 READY | `RID/RDATA/RRESP/RLAST/RVALID/RREADY` | 读数据及读响应 |

## 5. 地址映射

| 目标 | 地址范围 | 大小 |
|---|---|---|
| Slave 0 | `0x0000_0000` ～ `0x0000_0FFF` | 4KB |
| Slave 1 | `0x0000_2000` ～ `0x0000_2FFF` | 4KB |
| Slave 2 | `0x0000_4000` ～ `0x0000_4FFF` | 4KB |
| Default Slave | 上述范围以外 | 未映射空间 |

`AWADDR` 和 `ARADDR` 必须分别独立译码。映射到某个 Slave 的合法 burst 必须完整发送至该 Slave，不能把同一个 burst 拆到多个 Slave。未映射地址必须由 Default Slave 处理，不能错误访问任一正常 Slave。
地址映射关系由DUT所规定。

## 6. AXI3 通用协议要求

### AXI3-P01：VALID/READY 握手

- 每个通道仅在 `VALID && READY` 的上升沿完成一次 beat 或事务信息传输。
- `VALID` 不得依赖 `READY` 才拉高。
- `READY` 可以对 `VALID` 施加背压。
- 在 `VALID=1 && READY=0` 时，发送方必须保持该通道 payload 及 `VALID` 稳定，直到握手完成。
- 一次握手只能被计数一次，不得丢失或重复。

### AXI3-P02：通道独立性及依赖关系

- AW、W、B、AR、R 五通道必须独立握手，验证环境不得假设地址与数据在同一周期到达。
- Master 不得等待 `AWREADY` 后才产生 `WVALID`；DUT 不得依赖这种非协议行为才能工作。
- 写响应只能在对应写地址及全部写数据被接收后产生。
- 读数据只能对应已接收的读地址事务。
- 读写通道之间不规定全局先后顺序。

### AXI3-P03：复位

- 复位有效期间不能向接口输出有效响应事务。
- 复位必须清除内部未完成事务、FIFO 状态、仲裁保持状态和 ID 路由状态。
- 复位解除后不能返回复位前遗留的 `B` 或 `R` 响应。
- 验证环境必须支持空闲时复位和存在未完成事务时复位。

### AXI3-P04：响应编码与透传

- 下游 Slave 返回的 `BID/BRESP` 和 `RID/RRESP` 必须被正确送回源 Master。
- `OKAY`、`SLVERR`、`DECERR` 必须保持语义，不得被无故改写。
- 本接口不提供独占访问控制信号，因此不要求产生 `EXOKAY`。

## 7. Burst 传输要求

### AXI3-B01：长度定义

- `AWLEN/ARLEN` 为 4 bit，编码为 `beats - 1`。
- 合法范围为 `4'h0`～`4'hF`，即 1～16 beats。
- 第 `LEN+1` 个数据 beat 必须完成该 burst。
- 写通道的 `WLAST`、读通道的 `RLAST` 必须仅在最后一个 beat 有效。

### AXI3-B02：传输大小

32-bit 数据总线支持：

| `AxSIZE` | 每 beat 字节数 | 状态 |
|---|---:|---|
| `3'b000` | 1 | 合法 |
| `3'b001` | 2 | 合法 |
| `3'b010` | 4 | 合法 |
| `3'b011`～`3'b111` | 大于总线宽度 | 非法输入 |

窄传输或非对齐传输时，地址字节偏移和 `WSTRB` 必须对应正确的数据 byte lane。

### AXI3-B03：FIXED burst

- `AxBURST=2'b00`。
- 每个 beat 使用相同地址。
- 数据 beat 数量和 `LAST` 必须与 `LEN` 一致。

### AXI3-B04：INCR burst

- `AxBURST=2'b01`。
- 每个 beat 地址增加 `2^AxSIZE` 字节。
- 必须支持 1～16 beats。
- 赛题明确要求 incrementing burst，该类型必须形成完整的功能与覆盖率检查。

### AXI3-B05：WRAP burst

- `AxBURST=2'b10`。
- 合法 beat 数量仅为 2、4、8、16，对应 `AxLEN=1、3、7、15`。
- 起始地址必须按单 beat 字节数对齐。
- 回绕区域大小为 `beats × bytes_per_beat`。
- 地址到达回绕区域上边界后必须返回该区域下边界。
- 所有 beat 必须落在同一个目标 Slave 和同一个 4KB 地址窗口内。

### AXI3-B06：非法 burst 属性

- `AxBURST=2'b11`、超出总线宽度的 `AxSIZE`、非法 WRAP 长度或对齐均属于 Master 协议违规。
- 正常功能序列不得随机产生上述非法组合。
- 可以使用专门的负向序列和 assertion 检测违规；除 4KB 边界条款明确规定外，不对 DUT 面对非法 Master 输入时的行为作保证。

## 8. Switch 与路由要求

### XBAR-R01：请求路由

- 每次 AW/AR 握手必须依据地址映射选择唯一目标。
- 未映射地址必须选择 Default Slave。
- AW 和 AR 路由必须彼此独立。
- 一个请求不得同时发送到多个 Slave，也不得发送到错误 Slave。
- 下游输出的地址、长度、大小、burst 类型和原始 ID 信息不得被破坏。

### XBAR-R02：写数据路由

- W 数据必须发送到与对应 AW 事务相同的目标 Slave。
- `WID` 用于标识 AXI3 写事务，不得被当作地址译码的替代品。
- 多个 outstanding 写事务存在时，DUT 必须维护 AW、W 和 B 之间的正确关联。

### XBAR-R03：响应路由与 ID 恢复

- Interconnect 可以在下游侧扩展 ID，以携带源 Master 和原始 AXI ID 信息。
- 返回上游时必须恢复原始 4-bit `BID/RID`。
- 每个 B/R 响应必须返回发起事务的唯一 Master。
- 不能因不同 Master 使用相同原始 ID 而产生响应串扰。

## 9. FIFO 与接口数据流要求

### XBAR-F01：通道独立缓冲

- 赛题要求 AXI slave interface 对 AXI 各通道分别存入 FIFO；允许采用行为等价实现，但外部必须表现为独立弹性缓冲。
- AW、W、B、AR、R 通道之间不得共用会破坏通道独立性的单一阻塞状态。
- FIFO 必须保持先入先出，不得丢失、复制或篡改 payload。

### XBAR-F02：满空与背压

- FIFO 无空间时必须通过 `READY` 及时施加背压，不能发生覆盖或溢出。
- FIFO 为空时不得输出虚假 `VALID` 数据。
- 下游长时间不接收时，上游已接受的数据必须保持完整。
- 背压解除后所有已接受事务必须继续完成。

### XBAR-F03：数据流转换

- Master-facing interface 必须把仲裁后的通道数据流完整发送到目标 Slave。
- FIFO 入队与出队可以引入延迟，但不能改变事务内容、beat 数量、ID 关联或响应语义。
- 不同通道可同时运行，不能因一个无关通道停顿而永久阻塞其他通道。

## 10. 仲裁要求

### XBAR-A01：请求仲裁

- 当多个 Master 同时访问同一 Slave 时，对 AW、AR 和 W 竞争分别执行轮询仲裁。
- 同一资源同一时刻最多授予一个请求，grant 必须 one-hot 或全零。
- 当获胜方遭遇 `READY=0` 时，grant 和被选择 payload 必须保持，直到该次握手完成。
- 只有目标相同的请求互相竞争；访问不同 Slave 的 Master 应能够并行传输。

### XBAR-A02：公平性

- 在请求持续有效且目标 Slave 能持续完成握手的前提下，任何 Master 都不得饥饿。
- 三个 Master 持续竞争时，每个 Master 应在最多三个已完成的同级有效 grant 内获得一次服务。
- 轮询位置应在一次有效服务完成后更新，而不能仅因 request 存在就无条件更新。

### XBAR-A03：响应仲裁

- 多个 Slave 或 Default Slave 同时向同一个 Master 返回响应时，B/R 返回路径也必须执行公平仲裁。
- 响应仲裁不得破坏 ID 顺序、burst beat 连续性要求和 `LAST` 对应关系。
- 在允许读数据交织的情况下，R 仲裁可以在不同 RID 的 beat 之间切换，但必须满足第 12 节顺序要求。

## 11. Outstanding transaction

### AXI3-O01：计数上限

- 每个 Master 最多支持 4 笔读 outstanding。
- 每个 Master 最多支持 4 笔写 outstanding。
- 读写 outstanding 分别统计，互不占用对方额度。
- 三个 Master 的 outstanding 状态必须隔离。

### AXI3-O02：事务建立与释放

- 写事务在 AW 握手后计入 write outstanding，在对应 B 握手后释放。
- 读事务在 AR 握手后计入 read outstanding，在对应 `RLAST && RVALID && RREADY` 后释放。
- 达到上限后，DUT 可以对新的地址请求施加背压；已有事务必须仍能向前完成，不能形成死锁。
- outstanding 计数、ID 映射和响应匹配不能因背压或乱序而提前释放或重复释放。

## 12. 顺序、乱序与交织

### AXI3-ORD01：同 ID 保序

- 同一 Master、同一方向、相同 ID 的多个事务必须按照地址事务接受顺序返回。
- 同 RID 的不同读 burst 不能互相穿插到无法区分 burst 边界。
- 同 BID 的写响应顺序必须与对应写事务顺序一致。

### AXI3-ORD02：不同 ID 乱序

- 不同 ID 的 B 响应允许乱序返回。
- 不同 ID 的 R burst 允许乱序返回。
- DUT 不要求主动制造乱序，但必须能正确透传下游产生的合法乱序响应。
- Scoreboard 必须按 Master、方向和 ID 分队列匹配，不能只按全局到达顺序比较。

### AXI3-INT01：写数据交织

- 赛题要求支持 interleaving，因此不同 `WID` 的写 burst 数据 beat 允许在 W 通道交替传输。
- DUT 必须利用 `WID` 将每个 beat 路由到对应 AW 事务的目标 Slave。
- 同一 WID 内的数据顺序必须保持，每个 burst 的 `WLAST` 必须对应自己的最后一个 beat。
- 验证环境应支持 2～4 个不同 ID 的写数据流交织，并能分别维护其 beat 计数和期望数据。

### AXI3-INT02：读数据交织

- 不同 `RID` 的 R beat 允许在返回通道交替出现。
- 同一 RID 内必须保持事务和 beat 顺序。
- 每个 RID 的 `RLAST` 和 `RRESP` 必须属于正确 burst。
- Interconnect 必须将交织后的每个 beat 返回正确 Master，不得混淆不同 Master 的同值原始 ID。

## 13. 4KB 边界处理

### AXI3-4K01：合法 burst

- 正常 AXI3 burst 不得跨越 4KB 地址边界。
- INCR burst 应先计算 `aligned_start = floor(start_addr / bytes_per_beat) × bytes_per_beat`，并满足 `aligned_start[11:0] + beats × bytes_per_beat <= 4096`；这样也适用于合法的非对齐起始地址。
- FIXED burst 的每个 beat 使用同一地址，但单 beat 的所有有效字节仍必须位于同一 4KB 区域。
- WRAP burst 的完整回绕区域必须位于同一 4KB 区域。
- 正常随机 sequence 必须约束生成满足该规则的事务，输入协议 assertion 也必须检查该规则。

### AXI3-4K02：赛题要求的非法跨界处理

为使“支持 4K 边界处理”具有可判定结果，本项目定义：

- DUT 必须检测跨 4KB 的 AW/AR burst，且不得把该事务发送到任何正常 Slave。
- 非法写事务应被安全接收/排空，并返回一次相同原始 ID 的 `BRESP=DECERR`。
- 非法读事务应返回与 `ARLEN` 一致的 beat 数，`RRESP=DECERR`，并在最后一个 beat 给出 `RLAST`。
- DUT 不要求自动将跨界 burst 拆分成两个下游 burst。
- 该功能由专门负向测试验证；当前 RTL 若未实现，应正常产生验证失败，待后续修复 RTL。

## 14. 默认 Slave 与非法地址

### XBAR-E01：未映射写地址

- 未映射 AW 不得到达 Slave 0～2。
- DUT 必须接收/排空对应写数据并返回一次 `BRESP=DECERR`。
- 返回 `BID` 必须等于源 Master 的原始 AWID。

### XBAR-E02：未映射读地址

- 未映射 AR 不得到达 Slave 0～2。
- DUT 必须返回 `ARLEN+1` 个读 beat。
- `RRESP` 必须为 `DECERR`，`RID` 必须匹配原始 ARID，最后一个 beat 必须给出 `RLAST`。

## 15. 并行性、死锁与吞吐量

### XBAR-PERF01：并行传输

- 三个 Master 访问三个不同 Slave 时，DUT 必须允许读写请求并行推进。
- 读和写路径必须能够并行工作。
- 单个端口或通道的背压不能造成无关联端口永久停顿。

### XBAR-PERF02：无死锁与最终完成

- 在输入事务合法、下游最终提供 READY/响应的前提下，所有已接受事务最终必须完成。
- outstanding、FIFO 满、交织、乱序和竞争的组合不能形成内部死锁。
- 公平仲裁条件满足时，持续请求不能永久得不到服务。

### XBAR-PERF03：吞吐量观测

赛题要求评估数据吞吐量，但未给出数值门限。因此验证环境必须测量并报告，而暂不以固定数值作为 pass/fail 条件：

- 单 Master/单 Slave、无背压时的读写吞吐量和首响应延迟。
- 三个 Master 访问不同 Slave 时的聚合吞吐量。
- 三个 Master 竞争同一 Slave 时各 Master 获得的带宽和公平性。
- 不同背压比例、burst 长度和 outstanding 深度下的吞吐变化。

如后续赛题补充明确性能门限，应在 testplan 中将对应测量项升级为 pass/fail 检查。

## 16. 验证环境能力要求

本节规定验证环境必须具备的能力，不规定具体类名。

### 16.1 激励侧

- 三个相互独立的 active AXI3 Master agent。
- 支持独立控制 AW/W/AR 时序、随机延迟和背压无关的 VALID 产生。
- 支持 FIXED、INCR、WRAP、1～16 beats、窄传输、不同地址映射和 ID。
- 支持每个 Master 最多 4 读加 4 写 outstanding。
- 支持不同 WID 写数据交织。
- 支持定向产生非法地址和跨 4KB 事务。

### 16.2 下游响应侧

- 三个独立 reactive AXI3 Slave agent。
- 支持随机 `AWREADY/WREADY/ARREADY` 背压。
- 支持可配置响应延迟、`BREADY/RREADY` 相关压力和不同 ID 合法乱序。
- 支持不同 RID 的读数据交织。
- 支持返回 `OKAY/SLVERR/DECERR`，用于检查响应透传。
- 每个 Slave 应具有独立内存模型或等价数据存储模型。

### 16.3 监测、参考模型与检查

- 上游和下游两侧都必须由 monitor 基于实际握手重建事务。
- Reference model 根据地址映射、burst 地址算法、ID、WSTRB 和期望 memory 内容生成预测结果。
- Scoreboard 必须按 Master、Slave、方向、ID 和 burst 维护关联队列。
- Scoreboard 必须检查路由、数据、响应、beat 数、`LAST`、ID 恢复、顺序、乱序、交织和最终完成。
- Outstanding tracker 必须分别统计每个 Master 的读写事务。
- Arbitration checker 必须检查 one-hot、保持、公平性及无饥饿。
- Protocol assertions 必须覆盖五通道握手稳定性、响应依赖、`LAST`、4KB 和复位规则。
- 功能覆盖率必须由 monitor 发布的已完成握手事务采样，不能依据 driver 的意图值代替实际 DUT 行为。

## 17. 功能覆盖率最低维度

后续 testplan 至少应覆盖并交叉以下维度：

- Master × Slave × 读写方向。
- burst 类型 × burst 长度 × transfer size。
- 地址区域及区域首地址、末地址、4KB 边界附近地址。
- ID 值及同 ID/不同 ID 组合。
- read/write outstanding 深度 0～4。
- 无竞争、双 Master 竞争、三 Master 竞争。
- 无背压、Master 侧背压、Slave 侧背压、双向随机背压。
- 同 ID 保序、不同 ID 乱序。
- 2～4 个 ID 的写数据交织和读数据交织。
- 正常 Slave 响应、`SLVERR` 透传、未映射地址 `DECERR`、跨 4KB `DECERR`。
- 空闲复位、传输中复位和复位恢复。
- 单端口与三端口并行吞吐场景。

覆盖率只能说明场景是否被观察到，不能替代 scoreboard 和 assertion 的正确性判定。

## 18. 验证完成判据

一个回归结果只有同时满足以下条件才可以判定通过：

1. 所有已接受事务均完成，仿真结束时 scoreboard 和 outstanding 队列清空。
2. 不存在数据丢失、重复、错误路由、错误 ID、错误响应、错误 beat 数或错误 `LAST`。
3. 不存在未豁免的 protocol assertion failure。
4. 不存在未豁免的 UVM error/fatal。
5. 所有 SPEC requirement ID 均在后续 testplan 中映射到 stimulus、checker/assertion 和 coverage。
6. 功能覆盖率达到 testplan 后续确定的关闭目标。

当前 RTL 对高级机制出现失败不构成验证环境失败。只要 stimulus 合法、参考模型正确且错误定位清楚，该失败应作为 RTL defect 记录并推动设计修复。

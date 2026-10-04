# `axi_interconnect` 顶层与边界 FIFO 微架构

## 1. 职责与边界

`axi_interconnect` 是综合顶层。它把 3 组数组化上游端口和 3 组数组化下游端口接入 `axi_crossbar`，在每个通道的两侧插入 FIFO，并在交叉开关旁路上维护读/写 outstanding SID。

## 2. 参数

| 参数 | 默认值 | 依赖 |
|---|---:|---|
| `WIDTH_CID` | 4 | `WIDTH_SID` |
| `WIDTH_ID` | 4 | 外部 ID、`WIDTH_SID` |
| `WIDTH_AD` | 32 | AW/AR payload；但 FIFO实例宽度中写死 32 |
| `WIDTH_DA` | 32 | W/R payload；但 FIFO实例宽度中写死 32 |
| `WIDTH_DS` | `WIDTH_DA/8` | WSTRB；但 FIFO实例宽度中写死 4 |
| `WIDTH_SID` | `WIDTH_CID+WIDTH_ID` | 下游 ID；但若干逻辑写死 8 |

所以默认以外的宽度仅部分参数化，**TOVERIFY**。

## 3. 端口分组

每组 `[0:2]` 表示三个端点。

| 通道 | 上游 `M_AXI` 方向与 payload | 下游 `S_AXI` 方向与 payload |
|---|---|---|
| AW | 输入 `ID[WIDTH_ID], ADDR[WIDTH_AD], LEN[4], SIZE[3], BURST[2], VALID`；输出 READY | 输出 `ID[WIDTH_SID]` 及同类属性/VALID；输入 READY |
| W | 输入 `ID[WIDTH_ID], DATA[WIDTH_DA], STRB[WIDTH_DS], LAST, VALID`；输出 READY | 输出扩展 ID 及 DATA/STRB/LAST/VALID；输入 READY |
| B | 输出 `ID[WIDTH_ID], RESP[2], VALID`；输入 READY | 输入 `ID[WIDTH_SID], RESP[2], VALID`；输出 READY |
| AR | 与 AW 同形 | 与 AW 同形 |
| R | 输出 `ID[WIDTH_ID], DATA[WIDTH_DA], RESP[2], LAST, VALID`；输入 READY | 输入扩展 ID 及 DATA/RESP/LAST/VALID；输出 READY |

时钟/复位为 `AXI_CLK` 和低有效 `AXI_RSTn`。

## 4. FIFO 组织

每类通道使用两个方向相反但结构相同的 FIFO层：

```text
M_AXI request -> fifo_*_mx -> crossbar -> fifo_*_sx -> S_AXI request
M_AXI response <- fifo_*_mx <- crossbar <- fifo_*_sx <- S_AXI response
```

所有实例 `FAW=2`，即深度 4。每个通道每侧 3 个实例，总数 `5×2×3=30`。payload 不包含 VALID；FIFO用自身 `rd_vld` 重建 VALID。

### 4.1 请求宽度

- AR/AW 发起端侧：`4+32+4+3+2=45`。
- AR/AW 目标侧：`8+32+4+3+2=49`。
- W 发起端侧：`4+32+4+1=41`。
- W 目标侧：`8+32+4+1=45`。

### 4.2 响应宽度

- R 目标入口：`8+32+2+1=43`；发起端出口：`4+32+2+1=39`。
- B 目标入口：`8+2=10`；发起端出口：`4+2=6`。

## 5. SID 门控数据路径

读侧：

1. crossbar 产生 `S_AR*`。
2. `sid_buffer` 仅在目标 AR FIFO 可写并获 push grant 时允许地址前进。
3. 地址握手形成的 8 位 SID 放入 4 项 `ar_sid_buffer`。
4. `reorder` 把三个候选 R SID 与全部四项并行比较，注册输出 `r_order_grant`。
5. crossbar 的每个返回路由器以该 grant 门控真实目标 R；default R 不受它门控。
6. 当前 RTL 在 crossbar 出现候选 `RVALID & RLAST` 时即从表中删除 SID；该条件没有包含发起端出口 FIFO 的 raw ready，因此可能早于真正握手。

写侧同构：AW 登记，W SID 成员匹配；候选 `WVALID & WLAST` 即删除，不检查目标出口 FIFO raw ready。B 不参与删除。

## 6. 反压组合

地址目标侧 FIFO写条件额外与 `s_push_*id_rdy` 相与；read response 发起端 FIFO写条件额外与 `m*_rsid_clr_rdy` 相与；write data 目标侧 FIFO写条件额外与 `s*_wsid_clr_rdy` 相与。此门控将 ID 表容量和单项 clear 冲突反压到 crossbar。

## 7. 时序与流水

入口 FIFO为空时，push 在一个上升沿写存储并更新指针，随后 `rd_vld` 有效；交叉开关本体主要组合，仲裁器仅在反压时保存 grant；出口 FIFO再引入一次存储边界。`reorder.order_grant` 是寄存输出，因此 R/W 资格从候选可见到 grant 至少一拍。

## 8. 状态、hazard 与保护

- 结构 hazard：同一目标同一通道每拍只能选一个发起端；同一发起端同一返回通道每拍只能选一个来源。
- 资源 hazard：AR/AW SID 表只有 4 项；满时阻塞新地址。
- 顺序 hazard：W/R 候选 ID 不在表中时被阻塞；但命中任意项即可，不限表头。
- 同拍多个 SID push/clear 采用固定优先级，其他请求被反压。
- clear 仅由 `VALID & LAST` 触发；若最终 FIFO不 ready，表项可能在数据真正转移前释放。
- 顶层无 assertion；无 overflow、地址重叠、one-hot 或 ID 完整性检查。

## 9. 实例连接清单

- `fifo_ar_mx[0:2]`, `fifo_ar_sx[0:2]`
- `fifo_r_sx[0:2]`, `fifo_r_mx[0:2]`
- `fifo_aw_mx[0:2]`, `fifo_aw_sx[0:2]`
- `fifo_w_mx[0:2]`, `fifo_w_sx[0:2]`
- `fifo_b_sx[0:2]`, `fifo_b_mx[0:2]`
- `u_axi_crossbar`
- `u_ar_sid_buffer`, `u_ar_reorder`
- `u_aw_sid_buffer`, `u_aw_reorder`

## 10. 已知实现注意项

- FIFO实例宽度表达式硬编码默认宽度，顶层参数修改后可能截断或补位。
- R 通道内部保留 8 位 `M_RSID`，最后才在输出 FIFO截成低 4 位；B 在返回 mux 内直接截低 4 位。
- testbench 中多个场景被注释，当前激励存在索引等待错误的可疑代码，且无 scoreboard，因此不能作为完整规格证据。
- assertion 数：0。

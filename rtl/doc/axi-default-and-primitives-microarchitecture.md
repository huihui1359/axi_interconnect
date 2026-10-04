# 默认从设备与基础单元微架构

## 1. `axi_default_slave`

### 1.1 目的与接口

接收未命中正常地址窗口的完整 AW/W/B/AR/R 通道。参数为 `WIDTH_CID=4, WIDTH_ID=4, WIDTH_AD=32, WIDTH_DA=32, WIDTH_DS=WIDTH_DA/8, WIDTH_SID=WIDTH_CID+WIDTH_ID`。

### 1.2 写 FSM

| 状态 | 行为 | 转移 |
|---|---|---|
| `STW_IDLE` | 等待 AWVALID，拉高 AWREADY | 见 VALID 后到 RUN |
| `STW_RUN` | 完成 AW 握手，保存 AWID/AWLEN，打开 WREADY | 握手后到 WAIT |
| `STW_WAIT` | 接收 W beat，计数；到 AWLEN 或见 WLAST 时产生 BVALID | 到 RSP |
| `STW_RSP` | 保持 `BRESP=DECERR` 和 BID | BREADY 后接下一 AW 或回 IDLE |

只允许一个写事务在处理。`countW/awlen_reg` 为 5 位。若到声明长度仍未见 WLAST，仿真打印错误但硬件仍结束；WID 与保存 AWID 不同也只打印。

### 1.3 读 FSM

| 状态 | 行为 | 转移 |
|---|---|---|
| `STR_IDLE` | 等待 ARVALID，拉高 ARREADY | 见 VALID 后到 RUN |
| `STR_RUN` | 完成 AR 握手，保存 ID/长度，立即建立首个 R | 到 WAIT |
| `STR_WAIT` | 每次 RREADY 推进计数，在最后 beat置 RLAST | 完成后到 END |
| `STR_END` | 接受下一 AR 或回 IDLE | RUN/IDLE |

每个 R beat固定 `RRESP=DECERR`、`RDATA=all-ones`。一次只处理一个读事务。

### 1.4 风险

- FSM 输出主要为寄存信号，延迟取决于状态切换。
- 不检查 SIZE/BURST/address alignment。
- 写计数以 `WVALID` 推进；因 WREADY 在 WAIT 为高而等价于握手，但代码没有显式与 WREADY。
- 无 default case、无 assertion；只有仿真 `$display`。

## 2. `axi_fifo_sync`

### 2.1 结构

参数 `FDW=32`, `FAW=5`；深度 `FDT=1<<FAW`。顶层统一覆盖为 `FAW=2`。状态包括 `fifo_head/fifo_tail/next_head/next_tail[FAW:0]`、`item_cnt[FAW:0]` 和 `Mem[0:FDT-1][FDW-1:0]`。

### 2.2 握手

- push：`wr_vld && !full`。
- pop：`rd_rdy && !empty`。
- `wr_rdy=!full`, `rd_vld=!empty`。
- `rd_dout=Mem[head]`，first-word fall-through 指存储首项组合可见，不代表空态输入直通输出。

计数器对纯 push 加一、纯 pop 减一、正常并行 push/pop保持。满态同拍 pop 时禁止写并计数减一；空态同拍 push 时禁止读并计数加一。

### 2.3 复位与综合

指针和计数器异步低有效复位；Mem 不复位。`initial` 清指针/Mem 被 `translate_off` 包围，仅用于仿真。空状态使未初始化 Mem 不对协议可见。无 assertion。

## 3. `round_robin_m2s`

三路请求，输出 one-hot `sel[2:0]`。复位后 `last_winner=0`，初始优先级 0>1>2；此后从上次 winner 的下一项循环扫描。任何请求存在时就在时钟沿记录组合 `curr_winner`，不关心真正握手。

## 4. `round_robin_s2m`

四路版本，顺序 0→1→2→3→0。复位后初始优先级 0>1>2>3。行为与三路版本相同。

## 5. 仲裁原语的使用约束

由于轮询器没有 ready/accept 输入，调用者必须在反压时保存 grant；两个 `axi_arbiter_*` 正是这样做的。若未来独立复用轮询器，不得假设 `last_winner` 表示“最后成功服务者”，它只表示“最后一次组合选中者”。两个原语 assertion 数均为 0。


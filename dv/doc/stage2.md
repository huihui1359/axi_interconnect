# AXI3 Interconnect UVM验证环境Stage 2执行工单

> 状态：Stage 2A/2B已实施、待审核冻结
> 前置条件：`dv/doc/stage1.md`已经审核冻结，当前M0到S0单端口、单笔、单拍DUT闭环可以独立编译和运行  
> 代码风格：本阶段所有新增和修改代码必须遵守`dv/doc/code_style.md`

## 1. 文档目的和阶段概述

### 1.1 Stage 1已经完成的内容

Stage 1已经完成验证环境基础组件和最小DUT闭环：

- 建立参数化的request item、response item和按握手发布的`axi_channel_event`。
- 建立Master/Slave Driver、Monitor、Sequencer、Agent和基础cfg。
- Master Driver能够发送单笔单拍AW/W或AR请求，并接收B/R响应。
- Slave Driver能够驱动AWREADY/WREADY/ARREADY，并发送单笔B/R响应。
- Slave Monitor能够从真实AW/W或AR握手重建单拍request，并通过reactive sequence产生响应。
- `stage1_e2e_checker`能够检查M0到S0的单拍转发、4-bit/8-bit ID变换和响应返回。
- `dv/tb/tb.sv`已经例化真实AXI Interconnect DUT，只启用M0和S0，其余物理端口确定性置为空闲。
- `axi_stage1_single_write_test`和`axi_stage1_single_read_test`已经在QuestaSim 10.6c下通过。

Stage 1当前只支持单拍、零delay/gap和持续READY，尚未实现多拍burst、可运行的事务时序、通道backpressure、完整response重建和常驻协议断言。

### 1.2 Stage 2要完成的功能

Stage 2在现有M0到S0最小闭环上增加：

- FIXED、INCR和WRAP burst传输。
- 1～16个W beat和1～16个R beat。
- `addr_delay`、`w_start_delay`、`wbeat_gap[]`、`rsp_delay`和`rbeat_gap[]`运行机制。
- AW、W、AR、B、R五个通道独立的READY延迟和backpressure。
- READY早于VALID、晚于VALID以及与VALID同周期拉高。
- AW先于W、W先于AW和AW/W并行。
- 读写事务并行工作。
- Master/Slave Monitor对完整request和response burst的重建。
- 基于断言的接口协议检查。
- `stage2_e2e_checker`对每拍转发和完整burst进行端到端检查。

### 1.3 Stage 2A和Stage 2B划分

Stage 2分成两个连续实施阶段：

1. **Stage 2A：组件能力扩展。** 完成所有组件代码、断言、Checker、TLM端口和编译入口的修改。本阶段不建立或运行功能测试，只进行代码审核、Questa编译和elaboration检查。
2. **Stage 2B：功能测试和闭环验收。** 集中建立组件场景测试、协议断言测试和真实DUT端到端测试。只有Stage 2B全部通过后，Stage 2才能审核冻结。

Stage 2A编译通过只表示代码可以进入测试，不表示burst、delay、READY或Checker功能已经验证正确。

### 1.4 Stage 2能力边界

本阶段保持以下限制：

- 同一时间最多存在一个未完成写事务。
- 同一时间最多存在一个未完成读事务。
- 一个读事务和一个写事务可以同时进行。
- 不支持多个outstanding、不同ID响应乱序或同ID多事务排队。
- 不支持不同WID写数据交织或不同RID读数据交织。
- 不扩展为三主三从完整环境，不验证跨端口仲裁和Default Slave。
- 不建立最终Reference Model、outstanding Tracker和系统级Scoreboard。
- 不要求Master Driver向Master sequence返回独立response，`S0-OPEN-01`继续保留。
- 不验证burst进行中reset、stall期间reset及复杂运行时reset恢复。
- M0到S0写闭环继续保留`S1-LIMIT-01`，定向写测试使用`original_id=4'h5`和`expanded_id=8'h55`。

# 第一部分：Stage 2需要完成的任务

## 2. S2-01：扩展五通道运行能力

### 2.1 五通道任务总表

| Channel | 发送方需要完成 | 接收方需要完成 | Monitor/Checker需要完成 |
|---|---|---|---|
| AW | Master Driver实现`addr_delay`并独立驱动AWVALID和payload | Slave Driver使用独立`latency_gen`产生AWREADY延迟，READY拉高后保持到握手 | 两侧Monitor发布AW event并保存写地址上下文；Checker检查属性和ID扩展 |
| W | Master Driver发送`len+1`拍，执行`w_start_delay`和`wbeat_gap[]`，派生WID/WLAST | Slave Driver使用独立generator产生逐次WREADY backpressure | 两侧Monitor逐拍发布W event并重建完整W burst；Checker逐拍及整包比较 |
| B | Master Driver使用独立generator产生BREADY backpressure并在B握手后释放写上下文 | Slave Driver执行`rsp_delay`，驱动BID/BRESP/BVALID | 两侧Monitor发布B event并重建写响应；Checker检查响应因果、RESP和ID恢复 |
| AR | Master Driver实现`addr_delay`并独立驱动ARVALID和payload | Slave Driver使用独立generator产生ARREADY延迟，READY拉高后保持到握手 | 两侧Monitor发布AR event并重建读请求；Checker检查属性和ID扩展 |
| R | Master Driver使用独立generator产生逐beat RREADY backpressure，最后一拍后释放读上下文 | Slave Driver发送`len+1`拍，执行`rsp_delay`和`rbeat_gap[]`，派生RID/RLAST | 两侧Monitor逐拍发布R event并重建完整R burst；Checker逐拍及整包比较 |

### 2.2 信号所有权

信号所有权只按AXI角色划分，后续各节重点说明驱动时机：

| 驱动者 | 唯一负责驱动的信号 |
|---|---|
| Master Driver | `AWID/AWADDR/AWLEN/AWSIZE/AWBURST/AWVALID`、`WID/WDATA/WSTRB/WLAST/WVALID`、`BREADY`、`ARID/ARADDR/ARLEN/ARSIZE/ARBURST/ARVALID`、`RREADY` |
| Slave Driver | `AWREADY`、`WREADY`、`BID/BRESP/BVALID`、`ARREADY`、`RID/RDATA/RRESP/RLAST/RVALID` |
| Monitor | 只采样全部五通道信号，不驱动接口 |
| `tb.sv` | 只桥接`m_if/s_if`与DUT端口，不生成协议行为 |

Master侧看到的B/R响应由Slave Driver产生并经过DUT返回。因此Master Driver驱动`WLAST`，但只读取`RLAST`；Master Driver驱动`BREADY`，但只读取`BID/BRESP/BVALID`。

### 2.3 AW通道驱动时序

| 时机 | 信号行为 |
|---|---|
| reset期间 | `AWVALID=0`，AW payload清零，`AWREADY=0` |
| request进入AW worker | AW和W引用同一个写快照；AW独立开始计算`addr_delay`，不等待W |
| AWVALID拉高 | `addr_delay`计满后，在第一个可发送时钟边界装载`AWID=req.id`、`AWADDR=req.addr`、`AWLEN=req.len`、`AWSIZE=req.size`和`AWBURST=req.burst`，同时拉高AWVALID；`addr_delay==0`时不插入额外空闲周期 |
| `AWVALID && !AWREADY` | AWVALID及全部AW payload保持不变 |
| `AWVALID && AWREADY` | AW握手完成；下一驱动边界撤销AWVALID并清零AW payload |

AWREADY按照第3.4节READY task独立运行，可以早于或晚于AWVALID。AW握手只完成地址通道，不能单独触发B响应。

### 2.4 W通道驱动时序

一个写burst发送`req.len+1`个beat。对于beat `i`：

| 时机 | 信号行为 |
|---|---|
| reset期间 | `WVALID=0`，`WID/WDATA/WSTRB/WLAST=0`，`WREADY=0` |
| 写request进入W worker | 开始计算`w_start_delay`；W路径不等待AW握手 |
| 第一拍发送前 | `w_start_delay`结束后继续计算`wbeat_gap[0]` |
| 第一拍WVALID拉高 | `w_start_delay+wbeat_gap[0]`全部计满后，装载beat 0 payload并拉高WVALID；两个值都为0时不插入额外空闲周期 |
| 后续WVALID拉高 | beat `i-1`握手后计算`wbeat_gap[i]`；gap计满后装载beat `i`的payload并拉高WVALID |
| 任意beat装载 | 驱动`WID=req.id`、`WDATA=req.wdata[i]`、`WSTRB=req.wstrb[i]`；当且仅当`i==req.len`时驱动`WLAST=1` |
| `WVALID && !WREADY` | 保持WVALID和当前beat全部payload，`i`不变 |
| 非最后一拍握手 | `i++`并计算下一拍`wbeat_gap[i]`；gap为0时允许下一周期连续握手，gap大于0时WVALID保持0 |
| 最后一拍握手 | 撤销WVALID，清零W payload，结束当前W burst |

因此WLAST的实现规则固定为：

```text
WLAST = 0，beat 0 ～ beat len-1
WLAST = 1，beat len，也就是burst最后一拍
```

WREADY在每个W握手后进入下一轮随机延迟，可以在burst任意beat形成backpressure。

### 2.5 B通道驱动时序

| 时机 | 信号行为 |
|---|---|
| reset期间 | `BVALID=0`，`BID/BRESP=0`，`BREADY=0` |
| Slave Monitor收到AW和全部W beat | 重建完整写request并发送给reactive sequence |
| reactive sequence创建写response | `rsp.id`使用完整写request的扩展ID，`rsp.bresp`由当前用例确定 |
| response进入Slave Driver | 保存快照并开始计算`rsp_delay` |
| BVALID拉高 | response快照进入B发送路径且`rsp_delay`计满后，在第一个可发送时钟边界装载`BID=rsp.id`和`BRESP=rsp.bresp`，同时拉高BVALID，不等待BREADY；`rsp_delay==0`时不插入额外空闲周期 |
| `BVALID && !BREADY` | 保持BVALID、BID和BRESP不变 |
| `BVALID && BREADY` | B握手完成；Slave Driver撤销BVALID并清零BID/BRESP，Master Driver检查返回ID/RESP并释放写上下文 |

BREADY按照第3.4节READY task独立运行。B响应必须等待当前写burst的AW和最后一拍W都完成，不能在只收到AW或部分W beat时产生。

### 2.6 AR通道驱动时序

| 时机 | 信号行为 |
|---|---|
| reset期间 | `ARVALID=0`，AR payload清零，`ARREADY=0` |
| request进入AR worker | 独立开始计算`addr_delay`，不等待写通道 |
| ARVALID拉高 | `addr_delay`计满后，在第一个可发送时钟边界装载`ARID=req.id`、`ARADDR=req.addr`、`ARLEN=req.len`、`ARSIZE=req.size`和`ARBURST=req.burst`，同时拉高ARVALID；`addr_delay==0`时不插入额外空闲周期 |
| `ARVALID && !ARREADY` | ARVALID及全部AR payload保持不变 |
| `ARVALID && ARREADY` | AR握手完成；下一驱动边界撤销ARVALID并清零AR payload；Slave Monitor可以据此发布完整读request |

ARREADY按照第3.4节READY task独立运行，AR能够与AW/W并行推进。

### 2.7 R通道驱动时序

一个读response发送`rsp.len+1`个beat。对于beat `i`：

| 时机 | 信号行为 |
|---|---|
| reset期间 | `RVALID=0`，`RID/RDATA/RRESP/RLAST=0`，`RREADY=0` |
| reactive sequence收到读request | 创建相同ID和LEN的完整`axi_rsp_item`并交给Slave Driver |
| response进入R worker | 第一拍开始计算`rsp_delay` |
| 第一拍RVALID拉高 | response快照进入R发送路径且`rsp_delay`计满后，在第一个可发送时钟边界装载beat 0 payload并拉高RVALID；`rsp_delay==0`时不插入额外空闲周期 |
| 后续RVALID拉高 | beat `i-1`握手后计算`rbeat_gap[i-1]`；gap计满后装载beat `i` payload并拉高RVALID |
| 任意beat装载 | `RID=rsp.id`、`RDATA=rsp.rdata[i]`、`RRESP=rsp.rresp[i]`；当且仅当`i==rsp.len`时拉高RLAST |
| `RVALID && !RREADY` | 保持RVALID和当前beat全部payload，`i`不变 |
| 非最后一拍握手 | `i++`；gap为0时允许下一周期连续握手，gap大于0时RVALID保持0 |
| 最后一拍握手 | 撤销RVALID，清零R payload；Master Driver检查RLAST并释放读上下文 |

因此RLAST的实现规则固定为：

```text
RLAST = 0，beat 0 ～ beat len-1
RLAST = 1，beat len，也就是读burst最后一拍
```

RREADY在每个R握手后进入下一轮随机延迟。Master侧逐beat读取RID/RDATA/RRESP/RLAST，但不驱动这些信号。

### 2.8 接口信号驱动通用规则

- Driver通过`m_drv_mp`或`s_drv_mp`直接访问`vif.signal`，不使用clocking block。
- 所有时序驱动在`@(posedge vif.ACLK)`边界使用非阻塞赋值。
- 每个接口信号只有一个长期task作为验证环境驱动源，不允许reset task和通道task同时驱动同一信号。
- 发送方在拉高VALID时同时锁定本beat payload；VALID不得等待READY才拉高。
- 发送方只在`VALID && READY`握手后撤销当前VALID或切换到下一beat。
- 接收方READY task按照第3.4节循环驱动READY；READY拉高后保持到看到VALID并完成握手。
- Monitor只在时钟边界读取信号，只在`VALID===1'b1 && READY===1'b1`时发布event，不驱动任何接口信号。
- `tb.sv`的连续赋值只完成验证接口与DUT端口方向一致的bridge，不能形成第二个协议驱动源。
- reset值、正常发送值、stall保持值和握手后空闲值必须在对应通道task中清楚分支，不使用复杂条件表达式把多个阶段压缩为一次赋值。

## 3. S2-02：使用`latency_gen`产生时序数值

### 3.1 generator实例划分

每个需要独立随机状态的位置使用独立的`latency_gen`对象，不共享同一个generator：

```text
Master request sequence
├── addr_latency
├── w_start_latency
└── w_gap_latency

Slave reactive sequence
├── rsp_latency
└── r_gap_latency

Master Driver
├── bready_latency
└── rready_latency

Slave Driver
├── awready_latency
├── wready_latency
└── arready_latency
```

同一种generator在每次需要新数值时重新调用`randomize()`；需要限制模式或范围时允许直接使用`randomize() with`。本阶段不增加统一的`next_delay()`封装。

推荐调用形式：

```systemverilog
assert(latency.randomize() with {
  mode      == LAT_MODE_RANDOM;
  min_delay == 0;
  max_delay == 10;
});
delay_cycles = latency.get_delay();
```

随机化失败必须给出明确UVM错误或fatal，不能继续使用旧的`delay`值。

### 3.2 delay/gap生成和消费位置

| 字段 | 生成者 | 保存位置 | 消费者 | 数组要求 |
|---|---|---|---|---|
| `addr_delay` | Master sequence的`addr_latency` | `axi_req_item` | Master Driver AW或AR worker | 标量 |
| `w_start_delay` | Master sequence的`w_start_latency` | `axi_req_item` | Master Driver W worker | 标量 |
| `wbeat_gap[i]` | Master sequence的`w_gap_latency`逐beat生成 | `axi_req_item` | Master Driver W worker | 写请求长度为`len+1` |
| `rsp_delay` | Slave reactive sequence的`rsp_latency` | `axi_rsp_item` | Slave Driver B或R worker | 标量 |
| `rbeat_gap[i]` | Slave reactive sequence的`r_gap_latency`逐间隔生成 | `axi_rsp_item` | Slave Driver R worker | 读响应长度为`len` |

sequence先确定`dir/len`和payload数组尺寸，再使用对应generator填写时序字段；填写完成后不得再次随机化item并覆盖这些结果。

### 3.3 READY不使用mode

Stage 2不使用READY mode。需要从代码中删除：

```text
axi_ready_mode_e
bready_mode
rready_mode
awready_mode
wready_mode
arready_mode
```

如果`axi_ready_mode_e`已经没有其他引用，应从`axi_types_pkg.sv`删除。`latency_gen`自身的`LAT_MODE_FIXED/RANDOM/BURST`仍然保留，它是延迟数值生成策略，不是READY运行模式。

Stage 2不向Master/Slave cfg增加五套READY cycle、min/max或script数组。五个READY worker直接持有各自的generator。Stage 2B测试在run phase开始前约束对应generator，以形成无背压、固定backpressure或随机backpressure。

### 3.4 READY task行为

AWREADY、WREADY、ARREADY、BREADY和RREADY分别由独立长期task驱动。task行为统一参考以下形式，只把直接调用`$urandom_range()`替换为对应`latency_gen`的随机结果：

```systemverilog
task drive_channel_ready();
  int unsigned delay_cycles;

  wait (vif.ARESETn === 1'b1);

  forever begin
    vif.channel_ready <= 1'b0;

    if (!channel_ready_latency.randomize() with {
      mode      == LAT_MODE_RANDOM;
      min_delay == 0;
      max_delay == 100;
    })
      `uvm_fatal("READY_LATENCY", "Failed to randomize READY latency")

    delay_cycles = channel_ready_latency.get_delay();
    repeat (delay_cycles)
      @(posedge vif.ACLK);

    vif.channel_ready <= 1'b1;

    do begin
      @(posedge vif.ACLK);
    end
    while (vif.channel_valid !== 1'b1);
  end
endtask
```

上述代码是五个READY task的共同结构，正式实现仍使用各通道的真实信号名和generator名。因为task已经把READY保持为1，所以在正常运行且没有运行中reset的Stage 2范围内，观察到`VALID===1'b1`就表示当前时钟边界完成`VALID && READY`握手。代码也可以在`do/while`条件中显式写出`VALID && READY`，使握手含义更直接。

每轮行为固定为：

1. 将READY拉低。
2. 对本通道独立的`latency_gen`执行一次`randomize()`或`randomize() with`。
3. READY保持低电平`delay_cycles`个完整周期。
4. READY拉高并保持，直到本通道VALID出现并完成一次握手。
5. 握手后立即进入下一轮，重新拉低READY并产生新的随机延迟。

- 无backpressure时，将每次随机结果约束为`delay_cycles==0`。
- 定向stall使用`LAT_MODE_FIXED`或与现有`latency_gen`约束不冲突的inline constraint产生指定值。
- 随机stall使用`LAT_MODE_RANDOM`，参考任务的随机范围为0～100周期。
- 定向测试可以使用inline constraint把范围收敛为指定值或更小区间。
- READY拉高后不再重新随机，保持到本次握手结束。
- WREADY和RREADY在每个beat握手后进入下一轮，因此可以对burst中的每个beat产生不同延迟。
- 五个READY task必须使用五个独立generator，不能共享`delay_cycles`或随机状态。

独立随机的VALID和READY能够自然产生READY早于VALID、晚于VALID或与VALID同周期拉高三种关系。`randomize() with`可以约束两侧delay，但数值大小只有在两侧从同一个时钟边界开始计数时才能直接决定先后关系。对于计数起点不同的第一个AW/AR/B/R，Stage 2B必须结合实际VALID/READY拉高周期进行控制和判定，不能只比较两个delay数值。对于从上一beat握手后分别重新计数的后续W/R beat，可以更直接地通过约束两侧delay构造三种关系。

## 4. S2-03：支持完整burst和通道并行

### 4.1 burst范围

- FIXED和INCR支持1～16拍。
- WRAP支持2、4、8、16拍，并继续遵守Stage 0已经确定的对齐约束。
- `len`仍表示`beat_count-1`。
- 本阶段检查接口上burst属性和各beat payload的完整转发，不建立跨beat地址路由Reference Model。
- 非法SIZE、非法WRAP长度和4KB边界由item约束阻止进入正常sequence；本阶段不建立完整非法请求测试集。

### 4.2 AW/W独立关系

Stage 2必须支持：

1. AW先完成，W随后开始或完成。
2. W先开始，并可在AW之前完成部分或全部beat。
3. AWVALID和第一拍WVALID同周期拉高。
4. AW和W分别遭遇不同长度的READY stall。
5. AW已握手而W仍在发送，或W已经完成而AW仍在stall。

Slave Monitor不得假设AW一定先于W。写请求只有在AW上下文和完整W burst均已观察到后才完成重建。

### 4.3 读写并行

- `write_busy`和`read_busy`继续独立维护。
- 写事务等待B期间可以发送和完成读事务。
- 读事务等待RLAST期间可以发送和完成写事务。
- AW/W/B路径不得阻塞AR/R路径，AR/R路径不得阻塞AW/W/B路径。
- 本阶段仍不允许第二笔写事务绕过未完成B，也不允许第二笔读事务绕过未完成RLAST。

# 第二部分：测试点、时序约束和协议检查

## 5. S2-04：冻结delay/gap周期语义

### 5.1 通用计数规则

- 所有delay/gap以完整`ACLK`周期为单位。
- 只在`ARESETn===1'b1`且当前上下文已经具备发送资格时计数。
- `N==0`表示在第一个可工作时钟边界拉高VALID或READY。
- `N==1`表示先保持一个完整空闲周期，再在下一可工作时钟边界拉高。
- VALID一旦拉高，原delay/gap已经消费完毕；READY stall期间不得重新计数。
- READY一旦拉高，在握手前不得重新生成延迟。
- reset周期不计入delay/gap。

### 5.2 请求时序

- 写请求的AW和W计数彼此独立。
- `addr_delay`从AW或AR快照进入对应worker并具备调度资格后开始。
- `w_start_delay`从写快照进入W worker并具备调度资格后开始。
- `wbeat_gap[0]`是`w_start_delay`结束后到第一拍WVALID前的附加空闲周期。
- 对于`i>0`，`wbeat_gap[i]`从第`i-1`拍W握手后的下一个可工作周期开始。
- `w_start_delay`和`wbeat_gap[0]`是累加关系，不能相互覆盖。

### 5.3 响应时序

- `rsp_delay`从Slave Driver成功保存response快照并使其进入B或R发送路径后开始。
- 写响应只使用`rsp_delay`控制BVALID首次拉高。
- 读响应使用`rsp_delay`控制第一拍RVALID首次拉高。
- `rbeat_gap[i]`从第`i`拍R握手后的下一个可工作周期开始。
- `rbeat_gap[]`不包含第一拍，因此长度为`len`。

### 5.4 READY时序

- READY task先等待启动reset释放，然后进入永久循环。
- 每轮开始时先将READY拉低，再随机产生本轮`delay_cycles`。
- 第一轮READY延迟从task观察到reset释放后开始。
- 后续READY延迟从上一笔或上一beat握手结束、task进入下一轮后开始。
- READY的delay与VALID侧delay独立产生，不要求两个task具有相同计数起点。
- READY延迟结束后拉高并保持；看到VALID时完成握手并进入下一轮。
- READY先拉高时保持高电平等待VALID；VALID先拉高时由VALID侧稳定性断言保证payload不变。
- Stage 2不注入运行中reset，因此READY task不需要在每个repeat周期内增加重复reset检查。

## 6. S2-05：提取Stage 2测试点

### 6.1 burst基本测试点

| 测试点 | 预期结果 |
|---|---|
| W burst长度1～16 | 实际W握手数等于`len+1`，数据和WSTRB顺序正确 |
| R burst长度1～16 | 实际R握手数等于`len+1`，数据和RESP顺序正确 |
| FIXED burst | AW/AR属性保持FIXED并完整转发 |
| INCR burst | AW/AR属性保持INCR并完整转发 |
| WRAP 2/4/8/16拍 | 合法WRAP属性和全部beat完整转发 |
| 第一拍/中间拍/最后一拍stall | VALID和当前beat payload保持稳定，解除stall后只前进一拍 |
| WLAST/RLAST | 仅最后一个beat为1 |

### 6.2 delay/gap测试点

- 每一种delay/gap分别覆盖0、1和大于1。
- `w_start_delay`与`wbeat_gap[0]`同时非0时检查累加结果。
- 相邻W beat使用不同gap。
- 相邻R beat使用不同gap。
- VALID侧gap与READY侧stall同时存在时，确认二者独立且不会重复计数。
- 第一拍W和第一拍R的时序分别与后续beat间隔区分检查。
- delay/gap随机结果必须记录在transaction打印或测试日志中，失败时能够定位具体beat。

### 6.3 READY与VALID关系测试点

五个通道都需要覆盖：

- READY早于VALID。
- READY晚于VALID。
- READY与VALID同周期拉高。
- READY延迟为0。
- READY固定延迟大于0。
- READY随机延迟。
- VALID已拉高而READY保持低时，VALID和payload稳定。
- READY已拉高而VALID未到达时，READY保持高直到握手。

随机测试根据实际信号周期统计三种先后关系。定向测试允许使用`randomize() with`约束generator，但必须同时考虑VALID和READY各自的计数起点；不能仅凭两个delay数值相等就判定二者一定同周期拉高。

### 6.4 AW/W和读写并行测试点

- AW先于第一拍W。
- 第一拍W先于AW。
- AW和第一拍W同周期。
- 完整W burst先于AW握手结束。
- AW已完成而W仍遭遇逐beat stall。
- 一个读burst和一个写burst并行。
- 写事务等待B时读事务仍能推进。
- 读事务等待RLAST时写事务仍能推进。

### 6.5 Monitor重建测试点

- 每个真实握手只发布一个新的channel event。
- 多拍W/R连续握手时每拍均发布独立event。
- AW先、W先和同周期情况下只发布一个完整写request。
- W burst全部先于AW时仍能正确保存所有beat。
- AR握手后发布一个完整读request。
- B握手后发布一个写response。
- R持续采样到RLAST后才发布完整读response。
- 重建对象中的delay/gap统一归零，不尝试从接口间隔反推sequence意图。
- reset期间不发布event并清除未完成重建状态。

## 7. S2-06：使用断言完成协议检查

### 7.1 断言部署

新增参数化`axi_protocol_assertions.sv`，分别针对4-bit ID的`m_if`和8-bit ID的`s_if`例化。断言直接观察接口信号，不从Driver、sequence或Checker取得预期值。

建议该文件作为独立SystemVerilog module放在`dv/env`，由`sim/sim.f`在`tb.sv`之前编译，在`tb.sv`中完成两个接口实例的连接。

### 7.2 五通道stall稳定性

每个通道都必须包含以下并发断言：

```text
VALID && !READY |=> VALID保持为1且payload保持稳定
```

payload范围如下：

| Channel | 稳定字段 |
|---|---|
| AW | AWID、AWADDR、AWLEN、AWSIZE、AWBURST |
| W | WID、WDATA、WSTRB、WLAST |
| B | BID、BRESP |
| AR | ARID、ARADDR、ARLEN、ARSIZE、ARBURST |
| R | RID、RDATA、RRESP、RLAST |

断言在reset期间关闭；reset释放后开始生效。

### 7.3 有效值和握手检查

- 正常工作期间参与握手的VALID和READY不能为X/Z。
- 握手时当前通道有效payload不能包含X/Z。
- VALID拉高后，在握手或reset前不得撤销。
- Testbench负责驱动的VALID/READY在reset期间必须为0。
- 不要求READY在VALID之前或之后固定拉高。

### 7.4 burst协议检查

- 一个非交织W burst内WID保持一致。
- 一个非交织R burst内RID保持一致。
- W握手数量与对应AWLEN+1一致。
- R握手数量与对应ARLEN+1一致。
- WLAST只在最后一个W beat握手时为1。
- RLAST只在最后一个R beat握手时为1。
- 提前LAST、缺失LAST、LAST后继续发送beat均必须触发断言错误。

因为允许W早于AW，LAST与LEN的关联不能假设AW已经先到。断言模块可以保存单笔AW/W观察状态，并在地址和完整数据burst均到达后执行状态相关的立即断言。该观察状态只用于协议断言，不生成端到端expected transaction。

### 7.5 断言和其他检查的边界

- 接口时序协议由断言检查，不在Driver、Monitor和`stage2_e2e_checker`中重复实现。
- Driver只保留运行所必需的response关联和本地busy状态检查。
- Monitor只保留完成burst重建所必需的ID、beat数量和LAST一致性处理。
- 端到端Checker检查DUT转发和完整性，不检查固定周期延迟。
- delay/gap是否符合测试给定数值由Stage 2B时序测试支架检查，它不是AXI协议断言。

## 8. S2-07：Reset和异常场景边界

### 8.1 本阶段Reset要求

- reset期间Master Driver撤销AWVALID/WVALID/ARVALID/BREADY/RREADY并清零主动payload。
- reset期间Slave Driver撤销AWREADY/WREADY/ARREADY/BVALID/RVALID并清零主动payload。
- READY generator不得在reset期间推进内部延迟状态。
- reset释放后重新产生第一段READY延迟。
- Monitor在reset期间不发布event或完整item。
- Checker和断言在启动reset之后进入空状态。

### 8.2 本阶段不验证的Reset场景

- burst中途reset。
- VALID stall期间reset。
- delay/gap计数中reset。
- 运行中reset后的Checker统一清理和事务恢复。
- 多outstanding、乱序和交织状态清理。

这些内容留到后续复杂reset阶段。本阶段正常回归只在启动reset完成后发送事务。

# 第三部分：各组件需要完成的内容

## 9. S2-08：组件修改总览

| 文件/组件 | Stage 2A需要完成 |
|---|---|
| `dv/common/latency_gen.sv` | 作为所有delay/gap和READY延迟的数值生成器，支持调用方每次`randomize()`或`randomize() with` |
| `axi_req_item.sv` | 保持完整burst数组和请求时序字段，删除与Stage 1单拍能力相关的运行限制 |
| `axi_rsp_item.sv` | 保持完整R burst数组和响应时序字段，删除与Stage 1单拍能力相关的运行限制 |
| `axi_m_agent_cfg.sv` | 删除BREADY/RREADY mode字段，不增加五套READY周期参数 |
| `axi_s_agent_cfg.sv` | 删除AWREADY/WREADY/ARREADY mode字段，不增加五套READY周期参数 |
| `axi_m_driver.sv` | 多拍W、请求delay/gap、B/R READY generator和多拍R完成跟踪 |
| `axi_s_driver.sv` | 多拍R、响应delay/gap和三个请求READY generator |
| `axi_m_monitor.sv` | channel event以及完整request/response burst重建 |
| `axi_s_monitor.sv` | channel event以及完整request/response burst重建，完整request继续驱动reactive链路 |
| `axi_s_sequencer.sv` | 保持请求观察FIFO和response sequencer职责 |
| Master sequence | 产生合法burst payload并用generator填写请求delay/gap |
| Reactive Slave sequence | 根据真实完整请求产生B或完整R response，并填写响应delay/gap |
| `axi_protocol_assertions.sv` | 五通道稳定性、X/Z、VALID保持及burst LAST/数量检查 |
| `stage2_e2e_checker.sv` | 上下游event及完整request/response比较 |
| `axi_env_pkg.sv`/`axi_seq_pkg.sv`/`axi_test_pkg.sv` | 更新include、typedef和factory入口 |
| `tb.sv`/`sim.f`/`Makefile` | 例化断言、加入新增文件并提供Stage 2B测试入口 |

## 10. S2-09：`latency_gen`和transaction

### 10.1 `latency_gen`

- 每个调用位置创建独立对象，不跨不同通道或不同时序字段共享随机状态。
- 调用方负责在每次取值前执行`randomize()`。
- 允许使用inline constraint选择`LAT_MODE_FIXED`、`LAT_MODE_RANDOM`或`LAT_MODE_BURST`。
- `get_delay()`继续返回本次已经随机化的`delay`并更新现有burst状态。
- 不建立统一wrapper，不把所有调用强制收敛成一个新接口。
- READY随机延迟按参考任务使用0～100周期；其他delay/gap的范围由对应sequence场景单独约束。

### 10.2 request item

- 写请求保证`wdata/wstrb/wbeat_gap`长度均为`len+1`。
- 读请求对应写数据数组为空。
- FIXED、INCR和合法WRAP约束继续有效。
- `WID`和`WLAST`仍由Driver派生，不作为item字段。
- sequence在item payload随机化后使用generator填写时序字段。
- Driver不增加集中式合法性函数，不恢复`valid_stage1_request()`一类检查。

### 10.3 response item

- 读响应保证`rdata/rresp`长度为`len+1`，`rbeat_gap`长度为`len`。
- 写响应的读数组为空。
- `RID/BID`来自`id`，`RLAST`由Driver派生。
- reactive sequence使用独立generator填写`rsp_delay/rbeat_gap[]`。
- READY不进入request或response item。

## 11. S2-10：Master Driver

### 11.1 线程和所有权

继续保持独立长期task：

```text
accept_request
drive_aw
drive_w
drive_ar
receive_b / drive_bready
receive_r / drive_rready
watch_reset
```

如果接收响应和READY生成需要拆分，必须确保BREADY只有一个task驱动、RREADY只有一个task驱动。长期task只保留一个外层永久循环，当前握手可以使用`do/while`，不得嵌套第二个永久循环。

### 11.2 请求快照

- reset释放后再调用`get_next_item()`。
- 取得request后立即clone。
- 写快照在`item_done()`前同时放入AW和W mailbox。
- 读快照在`item_done()`前放入AR mailbox。
- `item_done()`不等待AW/W/AR或B/R握手。
- Stage 2仍使用`write_busy/read_busy`限制每个方向最多一个未完成事务。

### 11.3 AW/AR发送

- AW worker执行request的`addr_delay`后驱动`AWID/AWADDR/AWLEN/AWSIZE/AWBURST/AWVALID`。
- AR worker执行request的`addr_delay`后驱动`ARID/ARADDR/ARLEN/ARSIZE/ARBURST/ARVALID`。
- delay结束后锁定对应payload并拉高VALID，不能等待READY。
- VALID被READY阻塞时只等待握手，不重新进入delay逻辑。
- 握手后对应worker撤销VALID并清零本通道payload。
- AW和AR互不等待，能够并行。

### 11.4 W发送

- 先执行`w_start_delay`。
- 对每个beat执行对应`wbeat_gap[i]`。
- 对beat `i`驱动`WID=req.id`、`WDATA=req.wdata[i]`、`WSTRB=req.wstrb[i]`和`WLAST=(i==req.len)`。
- 锁定该beat的WID/WDATA/WSTRB/WLAST后拉高WVALID，不等待WREADY。
- stall期间保持WVALID及全部W payload，不能提前改变WLAST或beat索引。
- 当前beat握手后才能进入下一beat。
- 最后一个beat握手后结束W worker中的当前快照，但写busy保持到B响应。
- W worker不得读取AW worker完成状态作为发送条件。

### 11.5 B/R READY

- 创建独立`bready_latency`和`rready_latency`。
- 两个READY task在启动reset释放后进入“拉低、随机delay、拉高、等待VALID”的永久循环。
- 每轮调用各自generator的`randomize()`或`randomize() with`，再使用`get_delay()`取得本轮延迟。
- BREADY/RREADY在delay结束后拉高，并保持到对应VALID出现和握手完成。
- B握手和每个R beat握手后，对应task进入下一轮并重新产生延迟。
- 无本地写上下文时收到B、无本地读上下文时收到R，仍属于运行所需的关联错误。
- B握手检查返回ID后释放写上下文。
- R路径维护当前beat计数，只在预期最后一拍且RLAST握手后释放读上下文。

## 12. S2-11：Slave Driver

### 12.1 READY worker

- 分别创建`awready_latency/wready_latency/arready_latency`。
- reset期间三个READY均为0。
- 三个READY task在启动reset释放后分别进入“拉低、随机delay、拉高、等待VALID”的永久循环。
- 每轮使用本通道generator重新随机，不能共享delay变量或等待其他请求通道。
- READY delay结束后拉高并保持，直到看到本通道VALID并完成握手。
- 每次AW/AR握手以及每个W beat握手后，对应task进入下一轮并重新产生延迟。
- WREADY不得依赖AW已经握手。
- 不再检查或使用任何READY mode。

### 12.2 response快照

- reset释放后取得response item并立即clone。
- 写response在`item_done()`前进入B mailbox。
- 读response在`item_done()`前进入R mailbox。
- response sequence的`finish_item()`不等待B/R接口握手。

### 12.3 B发送

- 执行`rsp_delay`后驱动`BID=rsp.id`、`BRESP=rsp.bresp`并拉高BVALID。
- BVALID不等待BREADY；`BVALID && !BREADY`期间保持BID/BRESP/BVALID。
- B握手后撤销BVALID并清零BID/BRESP。

### 12.4 R发送

- 执行`rsp_delay`后发送第一拍。
- 后续每拍执行`rbeat_gap[i-1]`。
- 对beat `i`驱动`RID=rsp.id`、`RDATA=rsp.rdata[i]`、`RRESP=rsp.rresp[i]`和`RLAST=(i==rsp.len)`。
- 当前beat payload锁定后拉高RVALID，不等待RREADY。
- RVALID被RREADY阻塞时保持当前beat全部payload。
- 只有当前beat握手后才前进数组索引。
- 最后一拍握手后撤销RVALID并清零RID/RDATA/RRESP/RLAST。

## 13. S2-12：Master/Slave Monitor

### 13.1 共同输出

Stage 2后两个Monitor均提供：

```text
channel_ap：每个真实通道握手发布一个axi_channel_event
req_ap：发布重建完成的axi_req_item
rsp_ap：发布重建完成的axi_rsp_item
```

Master Monitor使用4-bit ID类型，Slave Monitor使用8-bit ID类型。每次发布使用新对象；Checker或FIFO需要保存时必须clone。

### 13.2 request重建

- AR握手后可以立即创建完整读request。
- 写请求分别缓存一个AW上下文和一个W burst上下文。
- 支持AW先、W先和同周期。
- W上下文按握手顺序保存每个WDATA/WSTRB。
- 观察到WLAST后标记W burst完成。
- AW和完整W burst均具备后，检查ID及beat数量并发布一次完整写request。
- 发布后的`addr_delay/w_start_delay/wbeat_gap[]`归零。

### 13.3 response重建

- B握手后创建一个完整写response。
- R握手后逐beat保存RID/RDATA/RRESP。
- 观察到RLAST后创建完整读response。
- 根据已经观察到的读请求上下文填写`len`；本阶段每个方向只有一个未完成事务。
- 发布后的`rsp_delay/rbeat_gap[]`归零。

### 13.4 Slave reactive连接

Slave Monitor的`req_ap`继续连接：

```text
Slave Monitor req_ap
        ↓
Slave sequencer request_fifo.analysis_export
        ↓
Reactive Slave sequence
        ↓
Slave Driver seq_item_port
```

`req_ap`可以同时连接`stage2_e2e_checker`。Monitor不得直接调用Slave Driver。

## 14. S2-13：Sequence、Sequencer和Agent

### 14.1 Master sequence

- 产生FIXED、INCR和合法WRAP请求。
- 支持1～16拍写数据数组。
- 每个具体testcase单独控制方向、len、burst、地址和数据模式。
- 使用独立generator填写请求时序。
- 不直接驱动READY或访问Monitor结果。
- 不调用`get_response()`，保持Stage 2 response边界。

### 14.2 Reactive Slave sequence

- 写请求只生成一个B response。
- 读请求生成与request相同`id/len`的完整R response。
- 推荐读数据使用`base_data+beat_index`，避免相同数据掩盖beat丢失、重复或交换。
- 默认使用OKAY，错误响应场景不作为Stage 2主验收目标。
- 使用独立generator填写`rsp_delay/rbeat_gap[]`。

### 14.3 Agent和cfg

- active/passive组件组成和Stage 1保持一致。
- 删除五个READY mode字段及相关Stage 1 mode检查。
- 不增加五套READY delay参数。
- READY generator属于对应Driver，不属于transaction。
- Stage 2B测试在run phase之前取得并约束generator，不能在READY worker已经运行后修改当前延迟策略。

## 15. S2-14：`stage2_e2e_checker`

### 15.1 定位

`stage2_e2e_checker`是M0到S0单端口Stage 2专用Checker，用于检查真实DUT两侧的数据流、ID变换、完整burst和响应因果关系。它不是最终三主三从Scoreboard，也不取代协议断言。

保留`stage1_e2e_checker`用于Stage 1回归，Stage 1/Stage 2 checker统一放在：

```text
dv/env/checker/stage1_e2e_checker.sv
dv/env/checker/stage2_e2e_checker.sv
```

### 15.2 输入端口

Checker至少接收：

```text
upstream_channel_export
downstream_channel_export
upstream_req_export
downstream_req_export
upstream_rsp_export
downstream_rsp_export
```

其中upstream使用4-bit ID对象，downstream使用8-bit ID对象。analysis实现收到对象后必须clone再入队。

### 15.3 Expected和Actual来源

| 检查方向 | Expected来源 | Actual来源 |
|---|---|---|
| AW/W/AR请求转发 | Master Monitor观察到的上游event/request | Slave Monitor观察到的下游event/request |
| B/R响应返回 | Slave Monitor观察到的下游event/response | Master Monitor观察到的上游event/response |

sequence item、Driver快照、reactive response计划不能作为端到端actual。Checker只使用真实接口Monitor输出。

### 15.4 channel event检查

#### AW

- 上下游`addr/len/size/burst_raw`一致。
- 下游ID等于`{2'b01,2'b01,upstream_id}`。
- 每个上游AW event只匹配一个下游AW event。

#### W

- 每个beat的DATA、STRB和LAST一致。
- 下游WID按M0到S0规则扩展。
- 同一个burst内保持FIFO beat顺序。
- 不要求AW已经先匹配。

#### AR

- 上下游`addr/len/size/burst_raw`一致。
- 下游ID按M0到S0规则扩展。

#### B

- 下游BID属于已完成的写请求。
- 上下游BRESP一致。
- 上游BID恢复为原始4-bit ID。
- B不能早于完整下游写请求。

#### R

- 每个beat的DATA、RESP和LAST一致。
- 下游RID属于已完成的读请求。
- 上游RID恢复为原始4-bit ID。
- R beat顺序保持一致。

event比较使用4-state比较，不比较固定`sample_cycle`，不要求DUT上下游存在固定周期差。

### 15.5 完整request比较

写request比较：

```text
dir
id及ID扩展
addr
len
size
burst
wdata[]长度和每个元素
wstrb[]长度和每个元素
```

读request比较：

```text
dir
id及ID扩展
addr
len
size
burst
写数据数组为空
```

不比较`addr_delay/w_start_delay/wbeat_gap[]`，因为Monitor重建对象中的这些字段统一归零。

### 15.6 完整response比较

写response比较：

```text
dir
id及ID恢复
bresp
```

读response比较：

```text
dir
id及ID恢复
len
rdata[]长度和每个元素
rresp[]长度和每个元素
```

不比较`rsp_delay/rbeat_gap[]`。

### 15.7 状态和因果关系

在单outstanding边界下，Checker分别维护一个写上下文和一个读上下文：

- 写上下文分别记录AW匹配、W beat数量、WLAST、完整写request匹配和B响应匹配。
- 读上下文记录AR匹配、R beat数量、RLAST、完整读request和response匹配。
- AW/W可以任意先后进入，只有两部分均完整时才标记完整写请求。
- B必须关联已经完成的下游写请求。
- R必须关联已经完成的下游读请求。
- 一个读和一个写上下文可以同时存在。

### 15.8 结束检查

测试结束时必须确认：

- 上下游所有channel event队列为空。
- 上下游完整request/response队列为空。
- 没有只有AW而没有完整W的请求。
- 没有孤立W burst。
- 没有未匹配B的完整写请求。
- 没有未完成或未匹配的R burst。
- event计数、完整item计数和测试期望事务数一致。
- Slave sequencer request FIFO为空。

### 15.9 不属于Checker的内容

- VALID stall稳定性和X/Z检查。
- READY何时拉高以及READY generator是否产生指定值。
- sequence给出的delay/gap是否精确执行。
- 固定DUT流水延迟。
- 多outstanding、乱序、W/R交织、跨端口路由和仲裁。

这些内容分别由协议断言、Stage 2B时序测试或后续Stage负责。

## 16. S2-15：TLM和文件组织

### 16.1 Stage 2连接关系

```text
Master sequence
      │ axi_req_item
      ▼
Master sequencer → Master Driver → m_if → DUT → s_if
                         ▲                  │
                         │ B/R              ▼
                         │           Slave Monitor
                         │             │ req_ap
                         │             ▼
                         │       request_fifo
                         │             │
                         │             ▼
                         └──── Slave reactive sequence → Slave Driver

Master Monitor ── channel/req/rsp ──┐
                                    ├── stage2_e2e_checker
Slave Monitor  ── channel/req/rsp ──┘

m_if ── axi_protocol_assertions(4-bit ID)
s_if ── axi_protocol_assertions(8-bit ID)
```

### 16.2 文件组织

- 可复用Driver、Monitor、Agent和断言放在`dv/env`。
- sequence放在`dv/seq`。
- `stage1_e2e_checker`和`stage2_e2e_checker`放在`dv/env/checker`，由唯一的`axi_env`例化并连接。
- Stage 2B场景sequence放在`dv/seq`，`dv/tc`中的对应test只负责配置、启动sequence和检查结果。
- 每个具体testcase单独一个文件。
- `axi_base_test`只负责公共env、reset等待和结果汇总。
- `sim/sim.f`保持公共类型、interface、package、RTL、断言和tb的正确编译顺序。
- 所有新增方法遵循类内`extern`声明、同文件类外实现的风格。
- 不增加当前Stage不需要的重复状态、防御性检查或集中式request合法性函数。

### 16.3 实施后的项目目录

```text
dv/
├── common/
│   ├── axi_types_pkg.sv
│   ├── common_defines.svh
│   ├── common_typedef.svh
│   └── latency_gen.sv
├── env/
│   ├── checker/
│   │   ├── stage1_e2e_checker.sv
│   │   └── stage2_e2e_checker.sv
│   ├── master/
│   │   ├── axi_m_agent.sv
│   │   ├── axi_m_agent_cfg.sv
│   │   ├── axi_m_driver.sv
│   │   ├── axi_m_monitor.sv
│   │   └── axi_m_sequencer.sv
│   ├── slave/
│   │   ├── axi_s_agent.sv
│   │   ├── axi_s_agent_cfg.sv
│   │   ├── axi_s_driver.sv
│   │   ├── axi_s_monitor.sv
│   │   └── axi_s_sequencer.sv
│   ├── axi_channel_event.sv
│   ├── axi_env.sv
│   ├── axi_env_cfg.sv
│   ├── axi_env_pkg.sv
│   ├── axi_protocol_assertions.sv
│   ├── axi_req_item.sv
│   └── axi_rsp_item.sv
├── seq/
│   ├── axi_m_single_read_seq.sv
│   ├── axi_m_single_write_seq.sv
│   ├── axi_s_single_reactive_seq.sv
│   ├── axi_stage2_scenario_seq.sv
│   ├── axi_stage2_burst_write_seq.sv
│   ├── axi_stage2_burst_read_seq.sv
│   ├── axi_stage2_aw_w_order_seq.sv
│   ├── axi_stage2_delay_gap_seq.sv
│   ├── axi_stage2_channel_stall_seq.sv
│   ├── axi_stage2_read_write_parallel_seq.sv
│   ├── axi_stage2_ready_random_smoke_seq.sv
│   └── axi_seq_pkg.sv
├── tc/
│   ├── axi_base_test.sv
│   ├── axi_stage2_base_test.sv
│   ├── axi_stage1_single_write_test.sv
│   ├── axi_stage1_single_read_test.sv
│   ├── axi_stage2_burst_write_test.sv
│   ├── axi_stage2_burst_read_test.sv
│   ├── axi_stage2_aw_w_order_test.sv
│   ├── axi_stage2_delay_gap_test.sv
│   ├── axi_stage2_channel_stall_test.sv
│   ├── axi_stage2_read_write_parallel_test.sv
│   ├── axi_stage2_ready_random_smoke_test.sv
│   └── axi_test_pkg.sv
└── tb/
    ├── axi_if.sv
    ├── axi_protocol_assertions_selftest.sv
    └── tb.sv
```

项目中只存在一个`axi_env`。`axi_base_test`直接例化该env，所有TLM连接统一在`axi_env::connect_phase`完成；不再保留`axi_test_env`或`dv/tc/support`层。

# 第四部分：Stage 2验证和验收

## 17. A2-01：Stage 2A代码审核

Stage 2A不运行功能测试，只完成以下审核：

- 所有新增和修改文件符合`dv/doc/code_style.md`。
- READY mode及五个mode配置字段已经删除。
- 五个READY通道各自使用独立`latency_gen`。
- request和response delay/gap由对应sequence中的独立generator产生。
- Master Driver已经具备多拍W和多拍R接收状态。
- Slave Driver已经具备多拍R和五通道READY延迟状态。
- 两个Monitor已经具备完整request/response输出。
- Slave reactive链路仍只响应真实Monitor请求。
- 协议断言和`stage2_e2e_checker`已经加入正确编译入口。
- 没有加入多outstanding、乱序、交织或三主三从逻辑。

Stage 2A最低工具门槛：

```text
Questa编译0 error
elaboration 0 error
无新增非预期warning
```

该结果只能标记为“Stage 2A代码可进入测试”。

## 18. A2-02：Stage 2B基础burst测试

Stage 2B首先验证组件和单端口闭环的基本burst能力：

- 写burst长度1～16逐一执行。
- 读burst长度1～16逐一执行。
- FIXED和INCR覆盖1～16拍。
- WRAP覆盖2、4、8、16拍。
- 每个W beat的数据和WSTRB可区分。
- 每个R beat使用可区分数据模式。
- WLAST和RLAST只在最后一拍。
- Monitor重建数组长度、内容和顺序正确。
- Checker的event和完整item计数一致。

## 19. A2-03：Stage 2B delay/gap测试

分别对以下字段执行0、1和大于1周期的定向测试：

```text
addr_delay
w_start_delay
wbeat_gap[0]
wbeat_gap[i>0]
rsp_delay
rbeat_gap[i]
```

重点组合：

- `w_start_delay`与`wbeat_gap[0]`同时非0。
- 多个W beat使用不同gap。
- 多个R beat使用不同gap。
- B响应delay与BREADY stall叠加。
- 第一拍R delay与RREADY stall叠加。
- 中间R gap与RREADY stall叠加。

测试支架根据generator结果和接口实际边界检查精确周期数。端到端Checker不承担该检查。

## 20. A2-04：Stage 2B五通道READY测试

AWREADY、WREADY、ARREADY、BREADY和RREADY分别执行：

1. delay为0，无主动backpressure。
2. 固定delay为1。
3. 固定delay为多个周期。
4. READY早于VALID。
5. READY晚于VALID。
6. READY与VALID同周期。
7. 随机delay范围0～100。
8. 定向固定stall 100周期。

WREADY和RREADY还必须在第一拍、中间拍和最后一拍分别制造stall。定向场景使用`randomize() with`约束相关generator，并结合两侧实际计数起点协调激励；不能只依赖特定随机seed偶然命中目标关系。

对于计数起点相同的场景，可以直接约束两个generator的delay大小；对于第一笔AW/AR/B/R等计数起点不同的场景，测试必须根据实际拉高周期协调激励并判定先后关系。随机场景通过实际采样结果确认覆盖，不能只根据generator数值推断READY与VALID关系。

## 21. A2-05：Stage 2B并行和顺序测试

- AW先于W。
- W先于AW。
- AW/W同周期。
- 完整W burst先于AW完成。
- AW与W遭遇不同stall。
- 读写burst同时启动。
- 写等待B期间完成读burst。
- 读等待RLAST期间完成写burst。

每种场景都必须检查通道没有不必要的串行依赖。

## 22. A2-06：Stage 2B协议断言验收

正常回归要求所有协议断言零失败。断言本身至少通过专用测试支架验证：

- VALID stall时保持稳定不会误报。
- 故意改变stall期间payload能够触发对应断言。
- 故意提前WLAST/RLAST能够触发断言。
- 故意缺失WLAST/RLAST能够触发断言。
- 故意制造beat数量不符能够触发断言。
- 故意注入握手payload X能够触发断言。

负向断言自测必须能够区分“预期断言触发”和“测试失败”，不能混入正常正向回归结果。

## 23. A2-07：Stage 2B端到端测试清单

建议至少建立以下独立testcase：

```text
axi_stage2_burst_write_test
axi_stage2_burst_read_test
axi_stage2_aw_w_order_test
axi_stage2_delay_gap_test
axi_stage2_channel_stall_test
axi_stage2_read_write_parallel_test
axi_stage2_ready_random_smoke_test
```

并继续回归：

```text
axi_stage1_single_write_test
axi_stage1_single_read_test
```

每个testcase只配置本场景数据、generator约束、启动sequence并等待统一结果汇总，不在一个文件中堆积所有测试实现。

## 24. A2-08：Stage 2B端到端检查结果

每个正向DUT测试必须满足：

- 预期AW/W/B/AR/R握手数量全部匹配。
- 上游4-bit ID正确扩展为下游8-bit ID。
- 下游响应ID正确恢复为上游4-bit ID。
- 所有W/R beat数据、STRB、RESP和LAST一致。
- 完整request/response重建内容一致。
- 没有额外、重复或遗漏event。
- 没有未完成写/读上下文。
- Slave request FIFO为空。
- 协议断言零非预期失败。
- `UVM_WARNING=0`、`UVM_ERROR=0`、`UVM_FATAL=0`。
- 测试明确打印统一PASS标记并正常退出。

## 25. A2-09：运行入口和回归要求

Stage 2沿用当前QuestaSim入口：

```text
cd sim
make com
make sim test=<testname>
make stage2_regress
make positive_regress
make assertion_selftest
```

如果Makefile当前使用其他变量名指定testname，以实际脚本为准，但不得新增第二套仿真目录或重复文件列表。

Stage 2B需要提供能够连续运行全部Stage 1和Stage 2正向测试的回归入口。所有日志、波形和覆盖率数据库继续存放在`sim/work`下，不向`dv`目录写入仿真生成物。

## 26. Stage 2完成条件

只有同时满足以下条件，Stage 2才能审核冻结：

1. Stage 2A全部代码完成并通过代码风格审核。
2. Questa编译和elaboration无错误。
3. FIXED、INCR和WRAP burst测试通过。
4. 1～16拍W/R测试通过。
5. 所有delay/gap精确时序测试通过。
6. 五通道READY早于、晚于和同周期场景通过。
7. AW/W独立推进和读写并行测试通过。
8. 两侧Monitor完整request/response重建通过。
9. `stage2_e2e_checker`的event、完整item和结束状态检查通过。
10. 正向回归协议断言零失败。
11. Stage 1单拍读写回归继续通过。
12. 没有提前实现Stage 3及以后能力。

## 27. 审核记录

| 审核项 | 当前状态 | 说明 |
|---|---|---|
| Stage 2范围 | 已实施 | M0到S0的burst、delay/gap和五通道backpressure |
| Stage 2A/2B划分 | 已实施 | 2A完成组件，2B sequence和test分层实现 |
| Burst范围 | 已通过 | FIXED/INCR 1～16拍，WRAP 2/4/8/16拍 |
| Delay生成 | 已通过 | 独立`latency_gen`；W/R非均匀gap定向检查通过 |
| READY策略 | 已通过 | 零延迟、固定延迟、五通道长stall和0～100随机delay通过 |
| 协议检查 | 已通过 | 正向回归零非预期失败；负向断言自测独立通过 |
| Monitor输出 | 已通过 | 两侧channel event及完整request/response由checker闭环匹配 |
| Stage 2 Checker | 已通过 | 每拍event、完整burst、计数和结束pending状态全部通过 |
| Reset范围 | 已实施 | 只覆盖启动reset，复杂运行时reset留后续Stage |
| `S0-OPEN-01` | 继续保留 | Stage 2不向Master sequence返回独立response |
| `S1-LIMIT-01` | 继续保留 | M0到S0写闭环使用ID 4'h5，不污染通用约束和Driver |
| 代码与仿真结果 | 已通过 | QuestaSim 10.6c编译、9项正向回归和断言自测通过 |

### 27.1 实际运行记录

- 工具：QuestaSim 10.6c，UVM 1.1d。
- 编译：`cd sim && make com`，结果为0 error、0 warning。
- 正向回归：`make positive_regress`，Stage 1两个单拍用例及Stage 2七个用例全部PASS，每项均为`UVM_WARNING=0`、`UVM_ERROR=0`、`UVM_FATAL=0`。
- 断言自测：`make assertion_selftest`，预期断言触发全部命中，未出现非预期断言，打印`AXI_ASSERT_SELFTEST_PASS`。
- 日志：`sim/work/log/<testname>.log`和`sim/work/log/axi_protocol_assertions_selftest.log`。
- 波形：`sim/work/wave/<testname>.wlf`。
- RTL：本次实施未修改`rtl`目录。

严格AXI3的B响应因果检查只以最后一个W beat完成握手作为`BVALID`资格条件，不把AW握手作为强制前提；断言自测同时覆盖W先于AW完成后发送B响应的合法场景。

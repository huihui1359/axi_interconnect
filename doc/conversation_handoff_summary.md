# AXI Interconnect项目对话交接摘要

editor：孙梦晖  
date：2026-08-31  
版本号：v1

## 1. 项目目标与赛题要求

本项目验证对象是一个三主三从AXI Interconnect。当前只考虑交叉矩阵本体，不考虑AXI2AHB、APB config等附加模块，也不考虑综合、面积、功耗、APR、STA等后端内容。

赛题要求Interconnect包含或实现：

- AXI slave/master interface及各通道FIFO和数据流转换。
- Switch完成Master ports与Slave ports之间的路由。
- Arbiter对竞争request执行round-robin仲裁。
- Outstanding transaction、INCR burst、WRAP burst、out-of-order、interleaving和4KB边界处理。
- 三路读写请求的仲裁、路由和多路并行传输。
- 数据吞吐量评估，但赛题没有给出数值门限。

项目定位为赛题裁剪后的AXI3数据传输子集，不是完整AXI3。当前接口没有`AxLOCK/AxCACHE/AxPROT`等边带信号。

## 2. 已确认的规格

- 3个上游Master、3个下游Slave，32-bit地址、32-bit数据、4-bit上游ID。
- `AWLEN/ARLEN`已从8 bit修改为4 bit，表示`beats-1`，支持1～16 beats；RTL、接口、transaction、assertion和覆盖率相关宽度已同步，RTL编译检查通过。
- 每个Master最多验证4笔读outstanding和4笔写outstanding，读写分别统计。
- 不同ID允许乱序，同ID必须保序。
- 支持AXI3写数据交织和读数据交织；同ID内部仍保持顺序。
- 正常burst不得跨4KB；专门非法跨4KB测试暂定期望DUT不向正常Slave转发并返回`DECERR`，不要求拆分burst。
- Round-robin复位后的第一次winner不限定，以实际首次winner初始化，后续严格检查轮询。
- 吞吐量只测量和报告，当前不设置硬门限。

当前RTL默认地址映射为：

| 目标 | 地址范围 |
|---|---|
| S0 | `0x0000_0000～0x0000_0FFF` |
| S1 | `0x0000_2000～0x0000_2FFF` |
| S2 | `0x0000_4000～0x0000_4FFF` |
| Default Slave | 其他未映射地址，返回`DECERR` |

每个窗口为4KB是因为RTL使用`ADDR_LENGTH=12`并比较地址高位。地址不连续不是AXI要求，而是当前RTL设计选择；RTL还使用`WID[3:2]`编码目标Slave，这是非通用AXI3做法，后续验证环境应按AW地址和ID关联独立预测W路由，以暴露该问题。

## 3. 现有文档

- 验证SPEC：[axi3_interconnect_verification_spec.md](./axi3_interconnect_verification_spec.md)，当前版本v2。它定义协议、路由、FIFO、仲裁、outstanding、ordering、interleaving、4KB、错误响应和验证方法。
- 初版Testplan：[axi3_interconnect_testplan.md](./axi3_interconnect_testplan.md)，当前版本v1。它定义UVM框架、组件职责、TLM连接、68个测试点、建议testcase、覆盖率和实现里程碑。

注意：`axi3_interconnect_verification_spec.md`是SPEC，不是testplan；实际初版testplan是`axi3_interconnect_testplan.md`。

## 4. 验证方法与环境架构

已决定采用“黑盒端到端验证为主、关键内部断言为辅”的灰盒方法，但当前首先完成黑盒环境：

- 3个active Master agent。
- 3个reactive Slave agent，可产生READY背压、响应延迟、乱序和交织。
- `axi_xbar_ref_model`：独立完成地址译码、Switch路由、AW-W-B/AR-R关联、ID扩展恢复和burst预测。
- `axi_arbiter_checker`：独立维护round-robin状态、请求矩阵、expected winner和公平性检查，不建议全部塞进ref_model。
- `axi_scoreboard`：比较上下游实际事务、数据、ID、响应、LAST及无丢失/重复。
- `axi_outstanding_order_tracker`：跟踪每Master、方向和ID的outstanding与顺序。
- `axi_funcov`：只采样monitor观察到的实际握手事件。
- Interface assertions：检查VALID/READY、stall稳定、LAST、4KB、复位和响应依赖。

逻辑关系为：

```text
地址译码确定每个请求的目标Slave
        ↓
按目标Slave建立request matrix
        ↓
每个Slave独立round-robin仲裁
        ↓
Switch/MUX转发winner事务
```

Ref model回答“去哪个Slave/返回哪个Master”，arbiter checker回答“多个候选中谁先走”，scoreboard回答“实际事务内容是否正确”。验证expected不能读取DUT内部select、grant或FIFO状态。

## 5. FIFO与event的约定

- 黑盒UVM环境不复制DUT硬件FIFO，但必须通过填充、排空和随机背压检查无丢失、无重复、顺序、payload稳定和通道独立性。
- 验证环境中的SystemVerilog queue只是保存expected、response和outstanding状态，不是DUT FIFO模型。
- 精确FIFO深度、指针、full/empty和occupancy以后通过灰盒`bind assertion`检查。
- Testplan中的“channel event”是握手观察对象，不是SystemVerilog原生`event`。实际实现建议命名为`axi_channel_obs`，继承`uvm_sequence_item`并通过`analysis_port`发送。
- 原生SystemVerilog `event`只适合线程同步通知，不携带事务且不会保存历史触发；AXI事务通信应使用analysis port/TLM FIFO。

## 6. 后续建议顺序

1. 重构为每个agent处理单端口、单事务的transaction，不再用一个transaction保存三个Master数组。
2. 完成3M/3S agent、virtual sequencer、tb_top和五通道monitor。
3. 完成协议assertion和基础smoke传输。
4. 完成Switch route model、ID关联和端到端scoreboard。
5. 完成request/response matrix及独立arbiter checker。
6. 再实现burst、FIFO行为、outstanding、ordering、乱序、交织、4KB、覆盖率和随机回归。
7. 黑盒环境稳定后增加FIFO/Arbiter/Switch灰盒bind assertion。

当前旧UVM环境的组件职责、monitor和scoreboard存在明显问题，后续应按SPEC/Testplan重建，不能为了适配现有RTL行为而降低checker要求。


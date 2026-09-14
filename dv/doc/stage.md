# AXI3 Interconnect UVM验证环境分阶段搭建计划

## 1. 文档目的

本文档定义AXI3 Interconnect UVM验证环境的分阶段搭建过程，用于指导后续组件实现、功能扩展和环境集成。

验证环境不采用“所有组件一次性实现完成后统一联调”的方式，而采用以下总体思路：

1. 先明确组件职责、接口契约和公共基础设施。
2. 对Driver、Monitor、Scoreboard等组件进行最小能力的独立验证。
3. 尽早建立单端口、单拍、无背压的最小纵向闭环。
4. 按burst、背压、outstanding、乱序、交织等协议能力逐层扩展。
5. 每增加一项能力，先完善相关组件，再进入集成环境。
6. 单端口环境稳定后，再扩展到三主三从完整环境。

本文中的Stage表示项目实现阶段，不是UVM的`build_phase`、`connect_phase`或`run_phase`等仿真phase。

## 2. 总体搭建路线

```text
公共基础和组件契约
        ↓
组件最小能力、独立测试支架及单端口最小纵向闭环
        ↓
burst、delay和通道stall
        ↓
多outstanding和响应乱序
        ↓
AXI3写数据/读数据交织
        ↓
完整READY策略、容量管理和复杂reset
        ↓
三主三从完整环境及回归
```

## 3. Stage 0：公共基础和组件契约

本阶段建立后续组件共同依赖的基础，并冻结对整体架构影响较大的设计决策。

预期完成：

- 完成公共AXI类型、参数、枚举和typedef的组织。
- 完成`axi_req_item`和`axi_rsp_item`事务模型。
- 完成单端口`axi_if`、clocking block和modport定义。
- 定义Master/Slave agent配置对象及环境配置对象的基本结构。
- 定义Master/Slave sequencer类型及其与Driver的连接类型。
- 明确不同ID宽度对应的virtual interface类型。
- 明确Driver、Monitor、sequence、tracker和scoreboard的职责边界。
- 明确transaction的clone/copy、对象所有权和生命周期原则。
- 明确`get_next_item()`、`item_done()`以及可选response返回的基本策略。
- 明确Driver内部长期线程、通道worker和队列的总体划分。
- 明确delay/gap字段的时序语义和计数基准。
- 明确reset边界和各组件在reset期间的基本行为。
- 建立package、文件include顺序和最小编译框架。

## 4. Stage 1：基础组件和单端口最小纵向闭环

本阶段完成基础验证环境搭建：先实现Driver、Monitor、sequence和基础比较组件的最小能力并分别进行独立验证，再将已通过组件级验收的组件组装为单端口、单笔、单拍、无主动背压的请求—响应闭环。

Stage 1划分为两个连续的内部验收门槛。Stage 1A通过后才能进入Stage 1B；只有两个门槛全部通过，Stage 1才算完成。

### 4.1 Stage 1A：组件最小能力和独立测试支架

预期完成：

- 实现Master Driver的单笔、单拍读写能力。
- 实现Slave Driver的单笔B响应和单拍R响应能力。
- Master侧BREADY/RREADY采用`ALWAYS_READY`。
- Slave侧AWREADY/WREADY/ARREADY采用`ALWAYS_READY`。
- Master Driver内部建立可继续扩展的AW、W、AR发送路径和B、R接收路径。
- Slave Driver内部建立可继续扩展的AW、W、AR接收控制路径和B、R发送路径。
- 实现Master Monitor和Slave Monitor的单次通道握手采样能力。
- 实现最简单的Master请求sequence和Slave response sequence。
- 实现Scoreboard或基础比较组件的最小对象匹配能力。
- 建立Driver组件测试支架，使用简单pin-level对端检查Driver的接口输出，不以正式Monitor作为唯一判断依据。
- 建立Monitor组件测试支架，使用确定性pin-level接口波形检查Monitor发布的观察对象，不以正式Driver作为唯一激励源。
- 建立Scoreboard或基础比较组件的对象级测试支架，允许直接注入预期对象和实际对象。
- 验证transaction快照、对象所有权和`item_done()`只调用一次且不等待总线响应的契约。
- 加入基础协议检查能力，为后续组件调试提供独立观察依据。

### 4.2 Stage 1B：单端口最小纵向闭环

预期完成：

- 组装一个Master agent和一个Slave agent。
- 完成sequencer、Driver和Monitor之间的连接。
- 完成Monitor analysis port与响应生成、比较路径的连接。
- 实现最小reactive Slave response sequence。
- 在DUT上只启用一个Master端口和一个目标Slave端口，其余端口保持确定性空闲。
- 跑通单拍写请求、写响应、单拍读请求和读响应。
- 跑通Slave Monitor到reactive Slave sequence再到Slave Driver的响应因果链路。
- 建立最小的端到端Scoreboard或基础比较数据流。
- 完成单端口环境中的`uvm_config_db`配置、virtual interface分发和组件层次组织。
- 完成基础phase、objection、reset启动、统一timeout和仿真退出流程。
- 验证上游原始ID、下游扩展ID及其返回路径能够在最小环境中正确流转。

### 4.3 Stage 1能力边界和验收原则

- 本阶段保持单笔、单拍和无主动背压，不加入burst、delay/gap运行机制、多outstanding、乱序和交织。
- READY运行策略只使用`ALWAYS_READY`；`RANDOM_READY`和`SCRIPTED_READY`留到后续Stage。
- Stage 1A的独立组件测试必须保留为Stage 1B及后续Stage的回归内容，不能用端到端闭环测试替代组件级验收。
- Stage 1B只建立一个Master端口到一个Slave端口的最小闭环，不扩展为三主三从完整环境。
- 最小比较路径只需支持本阶段的确定性单笔单拍场景，不提前实现完整路由、仲裁、outstanding和交织检查。

## 5. Stage 2：Burst、Delay和通道Backpressure

本阶段在最小纵向闭环基础上增加完整burst传输、事务时序字段以及确定性通道背压。

预期完成：

- Master Driver支持1～16个W beat并正确产生WID和WLAST。
- Slave Driver支持1～16个R beat并正确产生RID和RLAST。
- Master/Slave Monitor支持多beat采样和burst重建。
- Scoreboard和相关观察对象支持完整burst比较。
- 实现`addr_delay`和`w_start_delay`。
- 实现`wbeat_gap[]`、`rsp_delay`和`rbeat_gap[]`。
- 支持AW、W和AR通道独立推进以及读写通道并行工作。
- 支持AW先于W、W先于AW以及AW/W并行的场景。
- 为AW、W、AR、B、R五个通道分别加入确定性stall能力。
- 保证VALID stall期间VALID和payload稳定，握手完成后才推进到下一beat或事务。
- 扩展相关sequence，使其能够生成定向burst、delay和gap场景。

本阶段仍以每个方向最多一笔outstanding为主，避免burst问题与多事务调度问题同时引入。

## 6. Stage 3：多Outstanding和响应乱序

本阶段增加每个端口的多事务并发能力，以及基于方向和ID的请求/响应关联。

预期完成：

- Master Driver支持读写分别最多4笔outstanding。
- 建立读写独立的outstanding计数、限制和释放机制。
- 达到配置上限后停止发出新的同方向请求，同时继续接收已有B/R响应。
- Driver异步保存事务时使用稳定快照，避免sequence对象复用造成内容变化。
- Master侧建立B/R响应与已发出请求的关联机制。
- Slave侧保存尚未发送的B/R响应计划。
- Monitor、tracker和Scoreboard按端口、方向和ID维护outstanding上下文。
- 相同ID按照请求接受顺序关联。
- 不同ID允许响应乱序返回。
- 支持B通道与R通道并行工作。
- 明确并实现是否向Master sequence返回独立`axi_rsp_item`。
- 扩展sequence以产生多ID、多请求和不同返回顺序场景。

本阶段先实现事务级outstanding和乱序；同一burst的beat仍可保持连续发送，暂不加入beat级交织。

## 7. Stage 4：AXI3写数据和读数据交织

本阶段实现AXI3中风险较高的beat级交织和调度机制。

预期完成：

- Master Driver支持不同WID写数据按beat交织。
- Slave Driver支持不同RID读响应按beat交织。
- 为W通道和R通道建立合法候选保存及选择机制。
- 保持相同ID的事务顺序和beat顺序。
- 允许不同ID之间按照配置或调度策略重新选择发送顺序。
- 当前beat已经拉高VALID后，若READY为0，则锁定当前事务、ID和payload。
- 只有当前beat握手完成后才允许重新仲裁其他候选。
- Monitor能够依据WID、RID、WLAST和RLAST重建多个交织事务。
- Tracker和Scoreboard能够正确处理合法交织，而不使用单一全局FIFO强制所有ID同序。
- 扩展定向sequence以控制交织深度、ID组合和beat切换方式。

## 8. Stage 5：完整READY策略、容量管理和复杂Reset

本阶段完善背压策略、验证环境内部容量保护、复杂reset和异常处理。

预期完成：

- Master侧BREADY和RREADY分别支持`ALWAYS_READY`、`RANDOM_READY`和`SCRIPTED_READY`。
- Slave侧AWREADY、WREADY和ARREADY分别支持三种READY模式。
- 各READY通道能够独立配置和独立变化。
- 实现RANDOM READY的配置字段和状态变化规则。
- 实现SCRIPTED READY的确定性周期窗口表达方式。
- 建立Slave请求和响应缓存的容量管理机制。
- 将容量状态与AWREADY、WREADY、ARREADY协调，避免验证环境自身队列无界增长或溢出。
- 明确reset、容量门控和随机策略之间的优先级。
- 完善VALID stall、burst中途、outstanding未完成以及队列非空时发生reset的处理。
- 统一清理Driver线程状态、通道锁、内部队列和outstanding计数。
- 保证reset不会造成sequencer握手永久挂起，也不会自动重放已经部分握手的事务。
- 增加超时、错误报告、日志verbosity和内部状态一致性检查。

## 9. Stage 6：三主三从完整环境和回归扩展

本阶段将稳定的单端口组件扩展到三主三从完整AXI3 Interconnect验证环境，并补齐系统级检查能力。

预期完成：

- 实例化三个Master agent和三个Slave agent。
- 为六个agent分发各自独立的单端口virtual interface和配置对象。
- 组装完整`axi_env`、virtual sequencer和virtual sequence。
- 支持多个Master端口同时发起读写请求。
- 支持多个Slave端口独立产生响应和背压。
- 实现地址路由reference model。
- 完善跨端口outstanding tracker和端到端Scoreboard。
- 加入仲裁检查、ID扩展与恢复检查以及Default Slave路径检查。
- 加入完整协议assertion和functional coverage。
- 扩展定向测试、随机测试、压力测试和reset测试。
- 建立覆盖单拍、burst、背压、outstanding、乱序、交织、仲裁和异常场景的分层回归集合。

单端口Driver和Monitor在本阶段不应改为直接操作全局端口数组。三主三从能力应主要通过组件实例化、配置、连接和跨端口检查实现。

## 10. 阶段推进原则

整体实现遵循以下原则：

- 每个Stage只引入一组边界清晰的新能力。
- 新能力先在相关组件的独立测试支架中实现，再进入集成环境。
- 已通过的基础功能持续保留为后续Stage的回归内容。
- 不用临时串行Driver替代最终并发架构；早期阶段可以限制能力，但应保留可扩展的线程和队列边界。
- 不使用正式Monitor作为Driver独立验证的唯一依据，也不使用正式Driver作为Monitor独立验证的唯一激励源。
- Monitor基于接口真实握手重建事务，Scoreboard不使用Driver内部意图代替实际观察结果。
- 后续Stage应在前一Stage框架稳定的基础上增量实现，避免多个复杂机制同时首次引入。

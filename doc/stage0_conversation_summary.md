# AXI3 Interconnect UVM验证环境搭建讨论总结

date：2026-09-10

## 1. 文档目的

本文档总结本轮关于AXI3 Interconnect UVM验证环境搭建方式、Stage划分、Stage 0设计与实施、Driver事务握手、配置对象以及Tracker职责的讨论结论，作为后续Stage继续实施时的上下文记录。

## 2. 验证环境总体搭建思想

已确认不再采用“先把所有组件全部搭好，最后统一连接和调试”的方式。该方式容易在最终联调失败时无法区分问题来自Driver、Monitor、interface、配置、Scoreboard还是其他组件。

后续统一采用：

```text
组件职责和公共契约
        ↓
组件最小能力及独立测试
        ↓
单端口、单拍、无背压最小纵向闭环
        ↓
逐步增加burst、背压、outstanding、乱序和交织
        ↓
扩展到三主三从完整环境
```

基本原则如下：

- Driver、Monitor和Scoreboard先分别建立可独立验证的最小能力。
- 不使用正式Monitor作为Driver独立验证的唯一判断依据，也不使用正式Driver作为Monitor独立验证的唯一激励源。
- 尽早建立`sequence → driver → interface/DUT → monitor → scoreboard`最小纵向闭环。
- 后续每增加一项协议能力，先完成相关组件级验证，再进入集成环境。
- 早期可以限制功能，但不得采用后续必须整体推翻的临时串行架构。
- 已通过的基础测试持续保留为后续Stage的回归内容。

## 3. Stage总体划分

已经在`dv/doc/stage.md`中确定Stage 0～Stage 7：

| Stage | 主要目标 |
|---|---|
| Stage 0 | 公共类型、interface、transaction、config、sequencer和组件契约 |
| Stage 1 | Driver、Monitor等组件的单笔单拍最小能力及独立测试支架 |
| Stage 2 | 单端口、单拍、无背压最小纵向闭环 |
| Stage 3 | Burst、delay/gap和确定性通道backpressure |
| Stage 4 | 多outstanding、ID关联和不同ID响应乱序 |
| Stage 5 | AXI3 W/R beat交织及调度 |
| Stage 6 | 完整READY策略、容量管理、复杂reset和异常处理 |
| Stage 7 | 三主三从完整环境、reference model、scoreboard、assertion和coverage |

这里的Stage是项目实施阶段，不是UVM的`build_phase`、`connect_phase`或`run_phase`。

## 4. Stage 0工单和边界

已创建并审核`dv/doc/stage0.md`。Stage 0只完成公共基础，不实现总线功能组件。

Stage 0纳入：

- 公共AXI参数、枚举和READY模式类型。
- 参数化`axi_req_item`和`axi_rsp_item`。
- 参数化单端口`axi_if`及clocking block/modport。
- 参数化Master/Slave agent cfg和环境cfg。
- 参数化Master/Slave sequencer。
- 对象所有权、`item_done()`、delay/gap和reset契约。
- 后续Driver线程、队列和信号所有权规划。
- 独立编译入口和基础对象smoke。

Stage 0明确不实现：

- Master/Slave Driver。
- Master/Slave Monitor。
- Master/Slave Agent。
- DUT bridge和完整环境组装。
- READY运行策略。
- outstanding、乱序和交织调度。
- Tracker、reference model、Scoreboard、assertion和coverage。

## 5. ID宽度决策

已确认当前DUT上下游ID宽度不同：

```text
上游Master侧原始ID：4 bit
下游Slave侧扩展ID：8 bit
```

RTL顶层定义：

```text
WIDTH_ID  = 4
WIDTH_SID = WIDTH_CID + WIDTH_ID = 8
```

Interconnect在下游ID中加入路由和来源Master信息。Slave必须原样返回全部8-bit BID/RID，Interconnect再利用扩展信息选择目标Master并恢复上游4-bit ID。因此验证环境不能把下游interface固定为4位。

当前`axi_req_item`、`axi_rsp_item`和`axi_if`都通过`ID_WIDTH`参数支持两种specialization：

- Master请求和上游interface使用4位。
- Slave响应、下游观察对象和下游interface使用8位。

## 6. Config架构决策

Stage 0采用三种config class，而不是一个包含所有角色字段的统一`axi_cfg`：

```text
axi_m_agent_cfg    单个Master agent配置类型
axi_s_agent_cfg    单个Slave agent配置类型
axi_env_cfg        整个环境的聚合配置类型
```

运行时通常创建：

- 1个`axi_env_cfg`对象。
- 3个`axi_m_agent_cfg`对象。
- 3个`axi_s_agent_cfg`对象。

不将Master/Slave cfg融合为一个class，原因是：

- Master和Slave使用不同的Driver modport类型。
- Master ID为4位，Slave ID为8位。
- Master配置BREADY/RREADY及请求outstanding。
- Slave配置AWREADY/WREADY/ARREADY。
- 统一class会产生大量无效字段，并把类型错误从编译期推迟到运行期。

`axi_env_cfg`也不与agent cfg融合。环境cfg负责聚合，单端口agent cfg负责隔离每个物理端口的virtual interface和策略。

`axi_env_pkg.sv`不是cfg。它负责组织、include和导出类型；不能用package全局静态变量代替每个端口独立的运行期cfg对象。

当前决定保留三个cfg类型。如果后续只希望减少参数列表书写，可增加项目默认typedef，而不是牺牲Master/Slave类型隔离。

## 7. 文件组织决策

Master和Slave agent专属文件分别存放，便于管理：

```text
dv/env/
├── axi_env_pkg.sv
├── axi_env_cfg.sv
├── axi_req_item.sv
├── axi_rsp_item.sv
├── master/
│   ├── axi_m_agent_cfg.sv
│   ├── axi_m_sequencer.sv
│   ├── axi_m_driver.sv      后续Stage
│   ├── axi_m_monitor.sv     后续Stage
│   └── axi_m_agent.sv       后续Stage
└── slave/
    ├── axi_s_agent_cfg.sv
    ├── axi_s_sequencer.sv
    ├── axi_s_driver.sv      后续Stage
    ├── axi_s_monitor.sv     后续Stage
    └── axi_s_agent.sv       后续Stage
```

共享transaction和环境级cfg保留在`dv/env/`根目录。

## 8. `item_done()`时机决策

已确定`item_done()`的语义是：

> Driver已经完整复制并接管item，而不是AXI请求已经握手完成，也不是B/R响应已经返回。

推荐流程：

```text
get_next_item
        ↓
clone/copy原始item
        ↓
建立Driver内部上下文
        ↓
成功登记到内部队列或调度结构
        ↓
item_done，仅调用一次
        ↓
通道worker异步处理
```

这样可以避免sequence在`item_done()`后复用原始对象导致Driver队列内容变化，同时允许sequence继续提供后续请求，支持多outstanding。

具体规则：

- `item_done()`必须在clone和内部登记完成之后调用。
- `item_done()`不等待AW/W/AR握手，也不等待B/R响应。
- 只有item接收线程能够调用`item_done()`；AW/W/AR/B/R worker不得调用。
- 写请求只建立一个共享上下文，AW和W worker共同引用该上下文。
- Slave Driver接收`axi_rsp_item`时采用相同原则：响应快照进入B/R队列后调用`item_done()`，不等待总线发送完成。
- reset时不得让已取得的item造成sequencer永久挂起，也不得自动重放部分握手事务。

## 9. Master Response待讨论项

`S0-OPEN-01`仍未关闭：

```text
Master Driver是否默认向Master sequence返回独立axi_rsp_item？
```

当前已经预留Master sequencer的REQ/RSP类型接口，但没有决定默认开启、默认关闭或配置可选。

无论最终选择哪种方式，都必须遵守：

- B或RLAST后创建独立`axi_rsp_item`。
- 不修改原始`axi_req_item`。
- 不第二次调用`item_done()`。
- 如果返回response，应使用异步response通道和原请求的sequence/transaction ID进行路由。
- Driver产生的response不能替代Monitor实际观察结果进入Scoreboard。

该问题应在Stage 4实现Master响应关联前关闭。

## 10. Delay/Gap和Reset契约

Delay/gap采用完整clocking event计数：

- `N=0`表示上下文具备调度资格后的第一个可工作clocking event即可拉高VALID。
- `N=1`表示先经历一个VALID为0的完整可工作周期。
- AW和W时序彼此独立，W不得等待AW握手才开始计数。
- `wbeat_gap[0]`位于`w_start_delay`之后、第一拍WVALID之前。
- `rbeat_gap[i]`从第i拍R握手后开始，控制下一拍RVALID。
- VALID拉高后不再重新计算delay/gap，stall期间必须保持payload。

Reset基础边界：

- reset优先于正常驱动、READY策略和delay/gap。
- reset期间所有Testbench主动VALID/READY及payload为0。
- reset释放后至少保持一个clocking event空闲。
- reset前未完成或部分握手的事务不自动重放。
- Driver、Monitor、Tracker和Scoreboard采用一致reset边界。

## 11. Tracker职责结论

Tracker用于维护请求到响应之间的长期事务上下文：

- 按端口、方向和ID保存outstanding请求。
- 将B响应关联到写请求。
- 将RID/RLAST关联到读请求及对应beat。
- 保证同ID请求/响应顺序。
- 允许不同ID乱序。
- 支持W/R交织场景的上下文管理。
- 检查无请求响应、错误顺序及reset后的旧事务残留。

Tracker与其他组件的边界：

```text
Monitor：记录这一拍实际发生了什么
Tracker：判断这一拍属于哪一笔未完成事务
Reference Model：预测事务应该被怎样路由和变换
Scoreboard：比较expected和actual并判断功能正确性
```

Tracker的功能对于完整三主三从、多outstanding、乱序和交织环境是必要的，但不要求在Stage 0实现，也不要求早期一定作为独立组件存在。

当前计划：

- Stage 1不实现Tracker。
- Stage 2单笔闭环可使用最简单的匹配方式。
- Stage 4加入多outstanding时实现正式Tracker。
- Stage 5扩展其交织处理。
- Stage 6加入复杂reset清理。
- Stage 7扩展为完整跨端口跟踪。

对于当前项目，最终建议使用独立Tracker，避免把outstanding、顺序和交织状态全部塞进Scoreboard。

## 12. Stage 0验收策略调整

Stage 0没有Driver、Monitor和最小端到端环境，因此验收已经简化为：

1. 文档和职责审核。
2. 新`dv`环境独立编译。
3. 少量基础对象smoke。
4. Stage边界和完成检查。

以下测试已后移到具备对应组件或小环境的Stage：

- 大规模transaction随机化。
- 非法参数负向测试。
- 六端口完整config映射。
- Driver/sequencer连接及`item_done()`行为。
- Interface握手、stall和reset。
- Monitor重建和analysis数据流。
- burst、outstanding、乱序和交织。
- Scoreboard、assertion和coverage。

## 13. 已完成工作

### 13.1 文档

- 完成`dv/doc/stage.md`，记录Stage 0～Stage 7总体规划。
- 完成并审核`dv/doc/stage0.md`，记录Stage 0详细工单和简化验收方案。
- `stage0.md`状态已更新为“Stage 0已实施并通过基础验收”。

### 13.2 Stage 0代码

- 更新`dv/common/axi_types_pkg.sv`：
  - 增加Master 4-bit和Slave 8-bit ID参数。
  - 增加Master/Slave数量参数。
  - 增加三种READY模式枚举。
- 保留并确认参数化`axi_req_item`、`axi_rsp_item`和`axi_if`。
- 新增`axi_m_agent_cfg`和`axi_s_agent_cfg`。
- 新增聚合`axi_env_cfg`，默认创建3个Master cfg和3个Slave cfg。
- 新增参数化`axi_m_sequencer`和`axi_s_sequencer`。
- 更新`axi_env_pkg.sv`的include顺序。
- 新增Stage 0独立文件列表、Makefile、测试package和测试顶层。
- 未创建Driver、Monitor或Agent实现文件，保持Stage边界。

### 13.3 Stage 0验证结果

使用：

```text
QuestaSim 10.6c
UVM 1.1d
```

执行：

```powershell
cd dv\sim
make run
```

结果：

- 从清理后的构建目录重新编译和运行成功。
- 编译0 error、0 warning。
- UVM输出`STAGE0_PASS`。
- UVM报告0 warning、0 error、0 fatal。
- 新`dv`文件列表没有引用旧`uvm_tb`环境。
- 生成的`work/build`产物已清理。

## 14. 当前状态和后续事项

当前状态：

```text
Stage 0：已完成
Stage 1：尚未编写详细工单，尚未实施
```

建议下一步：

1. 编写并审核Stage 1详细工单。
2. 明确Stage 1各组件的最小功能和独立测试支架边界。
3. 实现Master/Slave Driver的单笔单拍能力和ALWAYS_READY。
4. 实现Monitor单次握手采样及独立pin-level测试方式。
5. 保持burst、outstanding、乱序、交织和正式Tracker在后续Stage实现。

继续保留的待讨论问题：

- `S0-OPEN-01`：Master Driver默认是否返回独立response给Master sequence。
- Tracker的最终内部数据结构和analysis连接方式，在Stage 4工单中确定。

# BUG：AXI轮询仲裁指针在成功握手前更新

**Author**: Wang Jianghao, Codex, ?
**Created**: 2026-09-29 09:15
**Current Version**: v1.1

**Version Changelog**:
- **v1.1** (2026-10-07 00:19): 实施round-robin内部pending保持和accept提交方案，记录最小修改范围、兼容约束及完整回归结果。
- **v1.0** (2026-09-29 09:15): 初版问题报告，记录`last_winner`在成功握手前提前更新的现象、影响和修复方向。

---

| 字段 | 内容 |
|---|---|
| 类型 | bug |
| 文档版本 | v1.1 |
| 创建时间 | 2026-09-28（UTC+8） |
| 更新时间 | 2026-10-07（UTC+8） |
| 状态 | 已修复并通过回归 |
| 发现用例 | `axi_stage6_multi_master_write_arb_test` |
| 影响模块 | `round_robin_m2s`、`round_robin_s2m`及其AW/W/AR/B/R实例 |
| 失败日志 | `sim/work/log/axi_stage6_multi_master_write_arb_test.log` |

## 版本记录

| 版本 | 时间 | 类型 | 简短记录 |
|---|---|---|---|
| v1.0 | 2026-09-28（UTC+8） | 创建 | 记录`last_winner`在请求出现后、成功握手前提前更新的问题，并给出握手提交方向的初步建议。 |
| v1.1 | 2026-10-06～2026-10-07（UTC+8） | 更新/实施 | 采用“移除wrapper外层grant保持寄存器，将pending winner保持与握手提交集中到round-robin模块内部”的方案；补充最小修改范围并记录编译、自检、Stage 1～3及Stage 6回归结果。 |

## 1. 现象

`axi_stage6_multi_master_write_arb_test`让三个Master同时向S0发起写事务，并将S0的AWREADY延迟3个周期。在AW请求已经产生但尚未完成VALID/READY握手时，bind仲裁Checker观察到内部轮询指针`last_winner`发生变化：

~~~text
UVM_ERROR @ 95000
[AXI_STAGE6_ARB_AW_POINTER_CHANGED_WITHOUT_HANDSHAKE]
Stage 6 bound arbitration assertion failed
~~~

问题可由RTL直接定位：

- `rtl/round_robin_m2s.v`在`rr_vld == 1'b1`时执行`last_winner <= curr_winner`，其中`rr_vld`仅表示三路`req`至少一路有效。
- `rtl/round_robin_s2m.v`采用相同实现，只是请求和指针宽度为4位。
- 两个round-robin模块都没有接收READY或“事务已接受”信号，因此请求一出现就会更新指针，即使当前grant仍因下游READY为0而被wrapper锁定。
- `axi_arbiter_mtos_m3`和`axi_arbiter_stom_s3`虽然用`*_grant_reg`保持stall期间的实际grant，但这一锁定机制没有阻止round-robin模块内部`last_winner`继续按请求状态更新。

因此，失败不是测试超时或Scoreboard误报，而是“轮询指针只在winner成功握手后更新”这一仲裁约束被RTL违反。

同一环境下使用`SEED=1`执行Stage 6用例，还观察到以下仲裁bind Checker失败，说明问题不限于最初发现用例：

| 测试用例 | `UVM_ERROR`数量 | 涉及通道 |
|---|---:|---|
| `axi_stage6_route_matrix_test` | 94 | AW、W、AR |
| `axi_stage6_multi_master_write_arb_test` | 1 | AW |
| `axi_stage6_multiport_outstanding_test` | 83 | AR |
| `axi_stage6_random_smoke_test` | 6 | AW、W、AR |

以上数量只用于记录当前复现基线，不作为修复后的固定期望值；修复后的期望值为相关仲裁错误全部归零。

## 2. 影响

- 轮询历史记录的是“曾被组合逻辑选中”的端口，而不是“真正完成传输”的端口，下一次winner的起始位置可能错误。
- 在READY backpressure期间，外部实际grant由`*_grant_reg`保持，但内部指针可能已经前移，导致锁定状态与轮询历史不一致。
- 多请求持续竞争时，服务次序和有界公平性可能偏离设计要求；请求撤销、新请求加入或stall解除后尤其容易暴露错误。
- `round_robin_m2s`被AW、W、AR通道复用，`round_robin_s2m`被B、R通道复用，因此缺陷不只影响当前AW失败用例，而是可能影响五个通道。
- wrapper对grant的保持可能使部分端到端事务仍能传输正确，所以只看事务Scoreboard可能无法发现该问题；内部bind Checker的指针检查必须保留。
- 在RTL修复并通过仲裁回归前，Stage 6的轮询顺序、stall稳定性和公平性验收不能关闭；DV侧不应通过放宽或屏蔽断言规避失败。

## 3. 已确认修复方案

### 3.1 设计原则

采用以下最终方案：

1. 从`axi_arbiter_mtos_m3`和`axi_arbiter_stom_s3`中移除五组外层`*_grant_reg`及对应RUN/WAIT保持状态。
2. 将“已经选出但尚未成功握手”的pending winner保持行为移入`round_robin_m2s`和`round_robin_s2m`。
3. `last_winner`只在当前对外grant成功完成VALID/READY握手时更新，更新值直接使用round-robin模块自身对外输出的实际grant。
4. 未完成握手时，若已经存在pending winner，则保持该winner不变；不能直接将随`request`变化的组合`curr_winner`无条件输出到外部。

该方案移除的是wrapper中的重复保持逻辑，不是取消grant保持能力。pending状态仍然必须存在，否则新request在backpressure期间加入时可能改变MUX选择，造成AXI输出VALID保持而payload变化。

### 3.2 `round_robin_m2s`和`round_robin_s2m`修改

保留现有模块名、实例名、`req`/`sel`端口语义、`last_winner`信号名和轮询优先级表，只进行以下局部扩展：

- 新增一个标量握手提交输入，建议命名为`accept`。
- 保留`curr_winner`作为由`req`和`last_winner`计算得到的组合候选结果。
- 新增`pending_winner`和`pending_valid`，用于保存尚未握手的实际输出winner。
- 实际输出定义为：

~~~text
actual_grant = pending_valid ? pending_winner : curr_winner
~~~

- 时序更新规则定义为：

~~~text
reset:
    last_winner   = 0
    pending_winner = 0
    pending_valid  = 0

accept:
    last_winner  = actual_grant
    pending_valid = 0

存在actual_grant但尚未accept，且当前没有pending:
    pending_winner = actual_grant
    pending_valid  = 1

其余情况:
    last_winner、pending_winner和pending_valid保持
~~~

`accept`发生时，`actual_grant`就是本次真正完成握手的winner，因此round-robin模块内部可以直接执行`last_winner <= actual_grant`，不再需要wrapper回传多位`accepted_winner`。

### 3.3 `axi_arbiter_mtos_m3`修改

修改范围限定在AW、W、AR三个仲裁实例周围：

- 保留现有`AWREQ = AWSELECT & AWVALID`、`WREQ = WSELECT & WVALID`和`ARREQ = ARSELECT & ARVALID`。
- 分别生成提交条件：

~~~text
AWACCEPT = |(AWGRANT & AWVALID & AWREADY)
WACCEPT  = |(WGRANT  & WVALID  & WREADY)
ARACCEPT = |(ARGRANT & ARVALID & ARREADY)
~~~

- 将三个`*ACCEPT`分别连接到对应round-robin实例新增的`accept`端口。
- round-robin的`sel`直接作为wrapper对外的`AWGRANT`、`WGRANT`和`ARGRANT`。
- 删除`argrant_reg`、`awgrant_reg`、`wgrant_reg`及其RUN/WAIT状态机，不改地址译码、`WSELECT_in`顺序控制和数据MUX。

### 3.4 `axi_arbiter_stom_s3`修改

对B、R通道采用同样方式：

~~~text
BACCEPT = |(BGRANT & BVALID & BREADY)
RACCEPT = |(RGRANT & RVALID & RREADY)
~~~

- 将`BACCEPT`、`RACCEPT`连接到对应round-robin实例。
- round-robin的`sel`直接驱动`BGRANT`、`RGRANT`。
- 删除`bgrant_reg`、`rgrant_reg`及其RUN/WAIT状态机，不改ID选择、响应路由和数据MUX。

本次修复保持当前W/R“按beat仲裁”的既有行为：每个成功的W或R beat握手均可提交winner。是否改为保持到`WLAST/RLAST`属于独立架构议题，不并入本bug修复。

### 3.5 断言适配

现有`axi_stage6_rr_pointer_checker`继续作为本次修复的回归判据，其检查目标不放宽：

- grant必须one-hot或全零；
- 非pending状态下grant必须符合round-robin候选结果；
- 未握手时`last_winner`必须保持；
- 握手后`last_winner`必须更新为上一拍实际grant；
- stall期间实际grant必须保持。

由于wrapper的`stateAW/stateW/stateAR/stateB/stateR`将被删除，bind连接中的`locked`来源需要最小化改为对应round-robin实例的`pending_valid`。保留`u_arbiter_aw`、`u_arbiter_w`、`u_arbiter_ar`、`u_arbiter_b`、`u_arbiter_r`实例名以及内部`last_winner`名称，避免扩大层次引用修改。

将过程式checker重写为`property/assert property`属于验证代码质量改进，不与本次RTL功能修复混合提交；后续可单独修改和评审。

## 4. 最小修改范围与可追溯性

### 4.1 计划修改文件

| 文件 | 必要修改 |
|---|---|
| `rtl/round_robin_m2s.v` | 增加`accept`和内部pending winner保持；按accept提交`last_winner`。 |
| `rtl/round_robin_s2m.v` | 与3路版本保持同一行为。 |
| `rtl/axi_arbiter_mtos_m3.v` | 生成AW/W/AR accept，删除外层grant寄存器和保持FSM，连接新接口。 |
| `rtl/axi_arbiter_stom_s3.v` | 生成B/R accept，删除外层grant寄存器和保持FSM，连接新接口。 |
| `dv/env/axi_stage6_arbiter_assertions.sv` | 仅适配删除后的状态层次引用，检查规则不放宽。 |

实现后同步更新直接描述已删除RUN/WAIT结构的`rtl/doc/axi_crossbar-routing-microarchitecture.md`、`rtl/doc/axi-default-and-primitives-microarchitecture.md`、层次/ASCII/抽取微架构文档、`rtl/ai_workflow/CODEBUDDY.md`和`dv/doc/zflow/axi_interconnect-testplan.md`。除这些直接相关文件外，不进行格式化、命名清理、参数化重构或其他顺带修改。

### 4.2 保持不变的内容

- round-robin当前复位后的初始搜索顺序；
- 3路和4路轮询优先级表；
- AW/W/AR/B/R的路由、payload MUX和ID处理；
- W/R当前按beat释放并重新仲裁的粒度；
- 现有模块名、五个`u_arbiter_*`实例名及`last_winner`层次名；
- UVM sequence、driver、monitor、reference model和scoreboard行为。

实现提交应引用本报告文件名及版本`v1.1`，并将“RTL功能修复”“断言SVA重写”等不同性质的改动拆分，便于通过git diff和回归结果分别追溯。

## 5. 验证与验收计划

1. 编译并确认五个bind实例层次解析正确。
2. 运行`axi_stage6_arbiter_assertions_selftest`，确认checker对指针提前更新的自检能力仍然有效；stall保持由后续仲裁集成用例验收。
3. 依次运行：
   - `axi_stage6_multi_master_write_arb_test`
   - `axi_stage6_multi_master_read_arb_test`
   - `axi_stage6_response_arb_test`
   - `axi_stage6_route_matrix_test`
   - `axi_stage6_multiport_outstanding_test`
   - `axi_stage6_random_smoke_test`
4. 运行完整Stage 6回归，再运行Stage 1～3兼容回归。
5. 验收条件：
   - 不再出现`POINTER_CHANGED_WITHOUT_HANDSHAKE`或`POINTER_NOT_UPDATED_ON_HANDSHAKE`；
   - 不出现`GRANT_CHANGED_WHILE_STALLED`、`ROUND_ROBIN_ORDER`、one-hot或无request grant错误；
   - AXI五通道payload稳定性断言全部通过；
   - scoreboard结果和原有功能覆盖不退化。

## 6. 实施结果

2026-10-06完成实现，2026-10-07完成补充回归，均按本报告v1.1执行：

- `round_robin_m2s`和`round_robin_s2m`增加标量`accept`、`pending_valid`和`pending_winner`；`last_winner`只在accept时更新为实际`sel`。
- `axi_arbiter_mtos_m3`删除AW/W/AR三套外层grant寄存器和RUN/WAIT状态机，直接连接round-robin grant，并分别生成`AWACCEPT/WACCEPT/ARACCEPT`。
- `axi_arbiter_stom_s3`删除B/R两套外层grant寄存器和RUN/WAIT状态机，并生成`BACCEPT/RACCEPT`。
- accept最终统一按`grant & VALID & READY`计算，不能使用包含route/order门控的`request`替代VALID；pending期间门控选择可能撤销，但AXI发送端VALID仍保持，使用request会漏记真实握手。
- bind checker直接接收各通道`*ACCEPT`，`locked`改接对应round-robin的`pending_valid`；checker仍保持过程式实现，SVA重写未混入本修复。
- 同步修正直接描述旧外层RUN/WAIT结构的微架构、层次、ASCII图、测试计划和维护说明文档。

回归结果（`SEED=1`）：

| 项目 | 结果 |
|---|---|
| Questa编译 | 0 error，0 warning |
| `axi_stage6_arbiter_assertions_selftest` | PASS |
| Stage 6全部9个测试 | 9/9 PASS，全部`UVM_ERROR=0`、`UVM_FATAL=0` |
| Stage 1全部测试 | 2/2 PASS |
| Stage 2全部测试 | 7/7 PASS |
| Stage 3全部测试 | 8/8 PASS |
| 关键Stage 6多seed补充回归 | 写仲裁、multiport outstanding、random smoke在`SEED=2/3/4`下9/9 PASS |

原复现基线中的94、83、6和1个仲裁bind Checker错误均已归零。

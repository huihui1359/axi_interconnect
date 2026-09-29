# BUG：AXI轮询仲裁指针在成功握手前更新

| 字段 | 内容 |
|---|---|
| 类型 | bug |
| 日期 | 2026-09-28 |
| 状态 | 待修复 |
| 发现用例 | `axi_stage6_multi_master_write_arb_test` |
| 影响模块 | `round_robin_m2s`、`round_robin_s2m`及其AW/W/AR/B/R实例 |
| 失败日志 | `sim/work/log/axi_stage6_multi_master_write_arb_test.log` |

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

## 2. 影响

- 轮询历史记录的是“曾被组合逻辑选中”的端口，而不是“真正完成传输”的端口，下一次winner的起始位置可能错误。
- 在READY backpressure期间，外部实际grant由`*_grant_reg`保持，但内部指针可能已经前移，导致锁定状态与轮询历史不一致。
- 多请求持续竞争时，服务次序和有界公平性可能偏离设计要求；请求撤销、新请求加入或stall解除后尤其容易暴露错误。
- `round_robin_m2s`被AW、W、AR通道复用，`round_robin_s2m`被B、R通道复用，因此缺陷不只影响当前AW失败用例，而是可能影响五个通道。
- wrapper对grant的保持可能使部分端到端事务仍能传输正确，所以只看事务Scoreboard可能无法发现该问题；内部bind Checker的指针检查必须保留。
- 在RTL修复并通过仲裁回归前，Stage 6的轮询顺序、stall稳定性和公平性验收不能关闭；DV侧不应通过放宽或屏蔽断言规避失败。

## 3. 修复建议

建议将轮询指针更新条件从“存在request”改为“当前实际winner成功握手”，并使用wrapper实际输出的grant作为提交winner：

~~~text
accept = |(actual_grant & valid & ready)

if (!reset_n)
    last_winner <= '0;
else if (accept)
    last_winner <= actual_grant;
else
    last_winner保持不变；
~~~

具体实施建议如下：

- 为`round_robin_m2s`和`round_robin_s2m`增加明确的`accept/update_en`与`accepted_winner`输入，或把`last_winner`提交状态移到各仲裁wrapper中统一维护。
- AW、AR、B分别以`grant & VALID & READY`作为提交条件；Stage 6单拍W/R同样按单拍握手提交。后续支持多拍轮转时，再按冻结后的WLAST/RLAST粒度增加限定。
- 提交值必须采用wrapper当前的实际grant，而不能直接采用组合`curr_winner`。stall期间实际winner可能来自`*_grant_reg`，此时`curr_winner`会随请求集合变化。
- 未成功握手时保持`last_winner`不变，同时继续保持stall期间grant和payload来源稳定。
- 对AW/W/AR和B/R五个实例统一修改，避免只修复当前暴露问题的AW实例。
- 修复后依次运行`axi_stage6_arbiter_assertions_selftest`、`axi_stage6_multi_master_write_arb_test`、读仲裁与响应仲裁测试，再运行完整Stage 6及Stage 1～3兼容回归；验收时bind Checker不得再出现指针提前更新、stall切换或错误next-winner报告。

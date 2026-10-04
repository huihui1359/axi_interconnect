# AXI Interconnect RTL 文档索引

本目录文档基于 `../*.v` 的 RTL 反向提取，描述的是当前实现，而不是未经验证的设计意图。标有 **TOVERIFY** 的内容需要由原设计者确认。

## 规格文档

- [整体架构](axi_interconnect-architecture-extracted.md)：功能契约、并发、地址空间、性能、错误和风险。
- [整体微架构](axi_interconnect-microarchitecture-extracted.md)：层次、接口、缓冲、时序、模块索引和实现约束。
- [顶层与 FIFO 微架构](axi_interconnect-top-microarchitecture.md)：`axi_interconnect` 和 30 个边界 FIFO。
- [交叉开关与路由仲裁微架构](axi_crossbar-routing-microarchitecture.md)：`axi_crossbar`、`axi_mtos_m3`、`axi_stom_s3` 及仲裁器。
- [顺序跟踪微架构](axi_ordering-buffering-microarchitecture.md)：`sid_buffer` 和 `reorder` 的真实语义。
- [默认从设备与基础单元微架构](axi-default-and-primitives-microarchitecture.md)：`axi_default_slave`、`axi_fifo_sync`、轮询原语。

## 学习辅助图

- [字符结构图与数据流图](axi_interconnect-ascii-diagrams.md)：独立的 ASCII 总图、读写路径、ID 编码、反压链和时序示意。

## 验证计划

- [AXI Interconnect 验证计划](axi_interconnect-testplan.md)：feature traceability、directed/constrained-random、接口、FSM、仲裁、缓冲、错误注入、stress、性能与覆盖模型。

## 范围与证据

- 设计 RTL：`axi_interconnect.v`、`axi_crossbar.v`、`axi_mtos_m3.v`、`axi_stom_s3.v`、`axi_default_slave.v`、`axi_fifo_sync.v`、两个仲裁封装、两个轮询器、`sid_buffer.v`、`reorder.v`。
- 验证参考：`axi_interconnect_tb.v`；它包含大量被注释的场景，当前活动场景是写数据交织/资格过滤，不是自检 testbench。
- `filelist.f` 中 testbench 路径为 `./sim/axi_interconnect_tb.v`，与本目录实际文件位置不同。
- 未修改任何 RTL。

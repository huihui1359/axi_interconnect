# 项目长期记忆 / Project Memory

## 项目约定 (Conventions)

### 文档 header 格式约定 (Document header rule)
- 任何为 `axi_interconnect` 项目生成的 Markdown 文档，必须在标题之后、正文之前包含如下格式的 header：

  ```text
  **Author**: [Harness] | [Model]
  **Created**: YYYY-MM-DD HH:MM
  **Current Version**: vX.Y

  **Version Changelog**:
  - **vX.Y** (YYYY-MM-DD HH:MM): 一两句话说明本次迭代的背景/内容。
  - **vX.(Y-1)** (YYYY-MM-DD HH:MM): ...
  ```

- 参考样例见 `rtl/doc/ARCHITECTURE_HIERARCHY.md:3-4`。
- `Author` 格式固定为 `[Harness] | [Model]`，例如 `CodeBuddy | Hy3-High`（`Harness`=生成工具/平台，`Model`=所用模型）。
- `Created` 必须精确到分钟：`YYYY-MM-DD HH:MM`。
- 必须包含 `Current Version` 与 `Version Changelog`；每个历史版本都要有一两句话的简要迭代说明（背景/内容），按版本号从新到旧排列。

### RTL 分析范围约束
- 分析、改动、生成 RTL 相关文档时，仅分析 `./rtl` 路径内容；不要分析 `dv/`、`uvm_tb/`、`sim/` 等其他路径。

## 关键事实 (Key facts)
- 综合顶层 `axi_interconnect.v` = 通道 FIFO 层 + `axi_crossbar` + 顶层顺序控制（`sid_buffer`+`reorder`）。
- SID（8 位）= {2 位 slave 地址, 2 位 master ID, 4 位事务 ID}。
- 路由：`axi_mtos_m3`（master→slave，3 master→1 slave）、`axi_stom_s3`（slave→master，4 个响应源→1 master）。仲裁经 `axi_arbiter_*m3` + `round_robin_m2s/s2m`，含 RUN/WAIT 保持状态机。default slave 返回 DECERR。
- 规模：13 个设计模块；DUT 展开为 1 顶层 + 1 crossbar + 4 mtos_m3 + 3 stom_s3 + 7 仲裁器 + 1 default_slave + 30 FIFO + 4 reorder + 18 RR。最大例化深度 4。
- router 仅在 `axi_crossbar` 内例化；FIFO 与 reorder 仅在顶层例化。

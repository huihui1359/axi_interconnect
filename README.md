# AXI Interconnect Overview

**Author**: Codex, GPT-6.1 Sol High
**Created**: 2026-10-25 17:09
**Current Version**: v1.0

**Version Changelog**:
- **v1.0** (2026-10-25 17:09): 建立项目简要导航，明确当前 DUT、验证环境、仿真入口及应忽略的备份和旧环境。

---

本仓库实现 AXI interconnect，并提供基于 SystemVerilog/UVM 的验证环境。后续 agent 调试时，先按以下路径定位；表内路径均相对仓库根目录 `work/axi_interconnect/`。

| 路径 | 用途 |
| --- | --- |
| `rtl/` | 当前 DUT RTL；顶层为 `rtl/axi_interconnect.v`。 |
| `dv/` | 当前验证环境；`tb/tb.sv` 为仿真顶层，`env/` 为环境，`seq/` 为序列，`tc/` 为测试，`common/` 为公共定义，`doc/` 为验证文档。 |
| `sim_vcs/` | 当前仿真运行目录。`Makefile` 提供编译和运行入口，`sim.f` 列出实际编译源文件，`README.md` 说明运行方法，`work/` 保存生成结果。 |
| 其他以 `sim_vcs` 开头的目录 | 各种备份，调试时直接忽略。 |
| `uvm_tb/` | 已过时的验证环境，调试时忽略。 |

调试从 `sim_vcs/README.md` 和 `sim_vcs/sim.f` 开始，沿文件清单定位 `rtl/` 与 `dv/` 中的实现。运行仿真时进入 `sim_vcs/`；不要根据相似目录名切换到备份或旧环境。

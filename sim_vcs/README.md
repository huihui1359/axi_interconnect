# VCS 仿真与回归

**Author**: Wang Jianghao, Codex, GPT-6.1 Sol High
**Created**: 2026-10-02 01:30
**Current Version**: v2.0

**Version Changelog**:
- **v2.0** (2026-10-25 15:39): 合并原 v1.2、v1.3 变更，统一 README 与验证环境版本为 v2.0；移除 stage/positive 分组及旧 selftest 快捷入口，采用 smoke、directed、random、full 集合和统一多 seed 回归、失败汇总；rand=y 沿用参考 date +%N 时间来源，保留构建及输出布局；命令集中前置，随后解释参数、seed、测试集合和输出规则。
- **v1.1** (2026-10-24 12:36): 清理根目录中的旧版构建、日志、波形、覆盖率和工具状态文件，删除未使用的 Stage-1 package 清单；将 .gitignore 收敛为 /work/，说明目录组织来源及与参考方案的区别。
- **v1.0** (2026-10-24 11:59): 补录版本头，创建时间取自 Git 最早记录；适配 30 个 `tp_*` 测试，采用参考 Makefile 的小写开关与所选测试重复回归，集中生成文件至 `work/`，说明兼容入口、覆盖率、清理行为及实际回归发现的测试问题。

---

**验证环境版本**：v2.0，与本 README 版本一致。

在本目录直接维护 Makefile 中的测试集合，不引入额外脚本、清单或新的
输出目录层级。`scheme.md` 保留此前方案讨论，本 README 和 Makefile
描述实际实现。

## 命令速查

以下命令均在 `sim_vcs_10251435/` 中执行。先按需要选择命令，参数默认值和
执行规则见后续章节。

### 查看帮助与用例

```sh
make help
make list-tests
```

### 编译与单次仿真

```sh
# 只编译
make com

# 运行默认读测试，默认 seed=0
make sim

# 指定测试和固定 seed
make sim test=tp_read_end_to_end SEED=7

# 开启波形及覆盖率
make sim test=tp_write_end_to_end seed=7 dump=y cov=y

# 按时间生成 seed
make sim test=tp_concurrency_random rand=y

# 调整 UVM 日志等级和用例参数
make sim test=tp_concurrency_random SEED=7 UVM_VERBO=MEDIUM SIM_EXTRA='+AXI_CR_NUM_TXN=32'
```

`compile` 是 `com` 的等价入口；`make`、`make all`、`make run` 均可编译并
运行所选测试。`make dump test=tp_read_end_to_end SEED=7` 是开启波形的单次入口。

### 集合回归与单测重复运行

| 运行范围 | 简短入口 | 指定集合的等价入口 |
| --- | --- | --- |
| 快速检查 | `make smoke_regress` | `make regress suite=smoke` |
| 全部定向 | `make directed_regress` | `make regress suite=directed` |
| 全部随机 | `make random_regress` | `make regress suite=random` |
| 完整回归 | `make full_regress` | `make regress suite=full` |

```sh
# 随机集合，每项运行 10 次，各次按时间生成 seed
make regress suite=random nseeds=10 rand=y

# 定向集合，每项分别使用 seed 100、101、102
make regress suite=directed nseeds=3 SEED=100

# 所选测试重复运行，兼容 reg_times
make regress test=tp_concurrency_random reg_times=20 rand=y

# 使用 repeat 别名，所选测试运行 3 个固定 seed
make repeat test=tp_read_end_to_end nseeds=3 BASE_SEED=100

# 回归遇到首个失败立即停止
make regress suite=full stop_on_fail=y
```

### 验证组件自检

```sh
# 全部六个独立 selftest
make selftests

# 指定一个 selftest top
make selftest SELFTEST=axi_stage6_arbiter_assertions_selftest
```

### FSDB 与 Verdi

```sh
# 先生成波形，再用同一个 test/seed 打开
make sim test=tp_read_end_to_end SEED=7 dump=y
make verdi test=tp_read_end_to_end SEED=7

# 只加载源码，进入 UVM 调试视图
make debug

# 启动交互式仿真 GUI
make dve test=tp_read_end_to_end SEED=7
```

`verdi` 打开已有 FSDB；`debug` 加载源码；`dve` 使用仿真器的 `-gui` 入口。

### 覆盖率收集、报告与查看

```sh
# 单个测试收集覆盖率
make sim test=tp_read_end_to_end SEED=7 cov=y

# 定向集合收集覆盖率
make regress suite=directed cov=y

# 完整回归收集覆盖率，每项一次
make coverage nseeds=1

# 生成 URG HTML/text 报告
make urg

# 在 Verdi 中查看已有覆盖率数据库
make cov
```

`make full_regress cov=y` 也可收集完整回归覆盖率；`make cov_report` 与
`make urg` 等价。完整回归包含文末列出的已知失败测试。

### 清理

```sh
# 删除构建产物，保留日志、波形和覆盖率
make clean

# 删除整个 work/，包括所有结果
make clean_all
```

### 复现已知失败

```sh
make sim test=tp_backpressure_random SEED=3026 cov=y
make sim test=tp_sid_random SEED=3027 cov=y
```

失败原因与历史验证范围见文末。

## 编译与参数规则

`make` / `make all` / `make run` 默认运行 `tp_read_end_to_end`。
`sim` 自动按源码依赖增量编译，`com` / `compile` 只编译。
普通构建与覆盖率构建隔离；修改额外编译选项后请先清理构建。

| 参数 | 默认值 | 含义 |
| --- | --- | --- |
| `test` | `tp_read_end_to_end` | 单个 UVM 测试类名 |
| `suite` | 空 | 回归集合：smoke / directed / random / full，与显式 test 二选一 |
| `dump` / `cov` | `n` | `y` 或 `1` 启用波形 / 覆盖率 |
| `rand` | `n` | `y` 或 `1` 时按时间自动生成 seed，与测试是否随机无关 |
| `SEED` / `seed` | `0` | 显式数字优先于 rand；大写优先于小写 |
| `nseeds` | 见下文 | 每个测试运行的 seed 数量；兼容 reg_times 和 REG_TIMES |
| `BASE_SEED` | 当前 SEED | 非时间模式的回归起始 seed |
| `stop_on_fail` | `n` | `y` 或 `1` 时遇到首个失败立即停止 |
| `UVM_VERBO` | `UVM_LOW` | 日志等级，也接受 LOW / MEDIUM 等简写 |
| `SIM_EXTRA` | 空 | 追加仿真参数，例如 `+AXI_CR_NUM_TXN=32` |
| `VCS_EXTRA` | 空 | 追加编译选项；修改后需重新编译 |

保留 `TEST`、`DUMP`、`COV`、`RAND`、`REG_TIMES`、`VERBOSITY` 大写参数，
它们优先于对应小写参数。次数优先级是 REG_TIMES > nseeds > reg_times。
集合回归默认每项 1 次；未指定 suite 的所选测试回归默认 20 次。
`repeat` 是 `regress` 的别名，`dump` 是启用波形的单次 run 入口。

## Seed 规则

普通单测默认 seed=0。`rand=y` 使用与参考相同的 `date +%N` 时间来源，
单测在 make 解析时只求值一次，回归在每次仿真前取一次时间。
实际数字传给子 make，仿真、日志、波形和覆盖率记录使用同一个 seed。
显式 SEED/seed 优先于 rand，例如 `SEED=7 rand=y` 仍使用 7。

固定 seed 回归时，每个测试使用相同的递增序列，例如
`nseeds=3 SEED=100` 或 `nseeds=3 BASE_SEED=100` 都运行 100、101、102。
因此新增或移动其他测试不会改变该测试的 seed。默认完整回归每项仅使用 0。
`rand=y` 与显式 BASE_SEED 同时出现时仍采用时间，BASE_SEED 用于非时间模式。
本方案沿用参考的时间取值，不保证时间 seed 全局唯一。

## 测试集合与回归规则

按验证意图分类，不按开发阶段分类。测试类名中已有的 stage 字样以及
实际 selftest top 的名字保留，不改变 DV 源码。

| 集合 | 当前数量 | 选择原则 |
| --- | ---: | --- |
| `smoke` | 8 | 基础读写、burst 读写、路由矩阵、同 ID 顺序、写仲裁和短背压扰动 |
| `directed` | 25 | 明确安排事务场景，允许随机数据和随机时序背景 |
| `random` | 7 | 5 个随机事务/场景用例，加 2 个定向场景中的随机时序用例 |
| `full` | 30 | directed 与 random 的并集，去重后每个测试按指定次数运行 |
| `selftests` | 6 | 独立 checker/model 自检，不计入 full 的 30 个 UVM 测试 |

`tp_backpressure_outstanding` 和 `tp_backpressure_random_stage2_smoke`
同时属于 directed 和 random；full 自动去重。随机集合的运行本身不要求
`rand=y`，固定 seed 同样会执行用例内部的随机激励。

每项检查对应测试的 `AXI_TC_PASS` 标记、零 UVM_ERROR 和零 UVM_FATAL。
回归默认继续运行其余测试，最后打印 total/passed/failed；只要有失败即返回
非零状态。`stop_on_fail=y` 恢复遇错立即停止。公共编译失败时不启动回归。

新增用例时，在 DV package 中 include/注册，再加入 Makefile 的
DIRECTED_TESTS 或 RANDOM_TESTS；可同时属于两者，full 自动包含并去重。
需要进入快速检查的用例再加入 SMOKE_TESTS。用 `make list-tests` 查看各集合。
不保留 stage*_regress 和 positive_regress 分类入口，也不新增空的 closure 入口；
覆盖缺口的定向运行直接使用 test 和 SIM_EXTRA。

## Selftest 规则

六个 selftest 来自 `dv/tb/`，使用 `selftest.f` 加各自 source，以独立模块为 top。
它们检查断言和参考模型的功能，允许构造预期违规，按各自成功标记判定。
不再保留 stage3/stage6 等逐项 selftest 快捷目标，统一用 SELFTEST 选择。

## 输出路径与工具规则

工具仍在本目录的 `work/` 下运行，布局保持不变：

```text
work/
  build/nocov/       普通 UVM 构建
  build/cov/         覆盖率 UVM 构建
  build/selftest/    各 selftest 构建
  log/               编译日志及 <test>_<seed>.log
  wave/              <test>_<seed>.fsdb
  cov/               axi_interconnect.vdb 与 report/
  ...                工具默认辅助文件
```

同一个 test/seed 再次运行会复用并覆盖对应结果路径。时间 seed 取值见 `[SIM]` 行。
源码清单使用 canonical DV packages，VCS 用 `-F` 按 filelist 所在位置解析路径。
波形继续由 `dump_fsdb.sv` 和 plusarg 控制，不生成外部 ucli.cmd。
`.gitignore` 只忽略 `/work/`，自定义至 work 外部的输出需自行管理。

`coverage` 等价于开启 cov 的 full_regress；只收集运行数据，不自动生成报告。
`urg` / `cov_report` 生成 HTML/text 报告，`cov` 在 Verdi 中打开 VDB。
保留现有 VCS O-2018 / WSL2 包装及 Verdi PLI 配置，支持覆盖工具命令和路径。

`make clean` 删除 work/build，保留结果；`make clean_all` 删除整个 work。

## 已知测试问题与历史验证记录

本版 v2.0 环境在此前完成的验证中，8 项 smoke 实测全部通过；另两次时间 seed 短读
仿真及对应 FSDB、日志命名检查通过。集合与调度检查确认 30 个已注册用例
无遗漏，完整集合无重复；使用模拟仿真命令验证了多 seed、参数优先级、
失败继续汇总、提前停止和非法参数处理。此次版本归并未重新运行仿真，既有验证未重跑全量 30 项功能仿真。

此前版本对全部 30 个 UVM 测试逐项验证得到 28 项通过、2 项失败，六个
selftest 全部通过；该结果是历史记录，不代表后续文档调整重新执行了全量验证。
测试原有通过条件保持不变，完整回归仍可能报告以下问题：

| 测试 | 复现 seed | 失败原因 |
| --- | --- | --- |
| `tp_backpressure_random` | 3026 | B 通道背压最大 11 拍，缺少大于 15 拍的 stall 区间，触发 AXI_CR_STALL_COV |
| `tp_sid_random` | 3027 | 随机读 ID 触发已有 ID/路由断言；测试源码注明相关断言需支持 0..15 |

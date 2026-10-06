# AXI Interconnect — 模块例化层次结构

**Author**: Ser-Wang, CodeBuddy, Hy3-High
**Created**: 2026-10-02 11:30
**Current Version**: v1.1

**Version Changelog**:
- **v1.1** (2026-10-07 00:19): 更新仲裁策略修改影响范围，指向round-robin候选、pending/accept状态及wrapper握手生成逻辑。
- **v1.0** (2026-10-02 11:30): 首次生成模块例化层次结构文档，含 `instance : module` 带中文注释的例化树、模块直接下级索引、例化深度、扇出说明与修改影响对照；采用 `[Harness] | [Model]` header 与版本记录格式。

---

> 范围：本文件仅依据 `./rtl` 目录下的可综合 RTL 静态例化关系整理。仿真顶层
> `axi_interconnect_tb` 不属于综合层次，仅在文末单列。

## 1. 完整例化树

方括号中的 `[0..2]` 表示 generate 展开后的 3 个实例，而不是单个数组实例。
格式：`<例化路径> : <模块名>  <注释>`，括号中的 `(n)` 为并列实例数量。

```text
axi_interconnect_tb                         仿真顶层
└── u_axi_interconnect : axi_interconnect  综合设计顶层
    ├── fifo_ar_mx[0..2].u_fifo_ar_mx : axi_fifo_sync   (3)
    ├── fifo_ar_sx[0..2].u_fifo_ar_sx : axi_fifo_sync   (3)
    ├── fifo_r_sx [0..2].u_fifo_r_sx  : axi_fifo_sync   (3)
    ├── fifo_r_mx [0..2].u_fifo_r_mx  : axi_fifo_sync   (3)
    ├── fifo_aw_mx[0..2].u_fifo_aw_mx : axi_fifo_sync   (3)
    ├── fifo_aw_sx[0..2].u_fifo_aw_sx : axi_fifo_sync   (3)
    ├── fifo_w_mx [0..2].u_fifo_w_mx  : axi_fifo_sync   (3)
    ├── fifo_w_sx [0..2].u_fifo_w_sx  : axi_fifo_sync   (3)
    ├── fifo_b_sx [0..2].u_fifo_b_sx  : axi_fifo_sync   (3)
    ├── fifo_b_mx [0..2].u_fifo_b_mx  : axi_fifo_sync   (3)
    │                                                   共 30 个 FIFO
    ├── u_axi_crossbar : axi_crossbar
    │   ├── u_axi_mtos_s0 : axi_mtos_m3                 目标 S0
    │   │   └── u_axi_arbiter_mtos_m3 : axi_arbiter_mtos_m3
    │   │       ├── u_arbiter_ar : round_robin_m2s
    │   │       ├── u_arbiter_aw : round_robin_m2s
    │   │       └── u_arbiter_w  : round_robin_m2s
    │   ├── u_axi_mtos_s1 : axi_mtos_m3                 目标 S1
    │   │   └── u_axi_arbiter_mtos_m3
    │   │       ├── u_arbiter_ar : round_robin_m2s
    │   │       ├── u_arbiter_aw : round_robin_m2s
    │   │       └── u_arbiter_w  : round_robin_m2s
    │   ├── u_axi_mtos_s2 : axi_mtos_m3                 目标 S2
    │   │   └── u_axi_arbiter_mtos_m3
    │   │       ├── u_arbiter_ar : round_robin_m2s
    │   │       ├── u_arbiter_aw : round_robin_m2s
    │   │       └── u_arbiter_w  : round_robin_m2s
    │   ├── u_axi_mtos_sd : axi_mtos_m3                 目标 default slave
    │   │   └── u_axi_arbiter_mtos_m3
    │   │       ├── u_arbiter_ar : round_robin_m2s
    │   │       ├── u_arbiter_aw : round_robin_m2s
    │   │       └── u_arbiter_w  : round_robin_m2s
    │   ├── u_axi_default_slave : axi_default_slave
    │   ├── u_axi_stom_m0 : axi_stom_s3                 返回 M0
    │   │   └── u_axi_arbiter_stom_s3 : axi_arbiter_stom_s3
    │   │       ├── u_arbiter_r : round_robin_s2m
    │   │       └── u_arbiter_b : round_robin_s2m
    │   ├── u_axi_stom_m1 : axi_stom_s3                 返回 M1
    │   │   └── u_axi_arbiter_stom_s3
    │   │       ├── u_arbiter_r : round_robin_s2m
    │   │       └── u_arbiter_b : round_robin_s2m
    │   └── u_axi_stom_m2 : axi_stom_s3                 返回 M2
    │       └── u_axi_arbiter_stom_s3
    │           ├── u_arbiter_r : round_robin_s2m
    │           └── u_arbiter_b : round_robin_s2m
    ├── u_ar_sid_buffer : sid_buffer                    读事务顺序队列
    ├── u_ar_reorder    : reorder                       读返回资格判断
    ├── u_aw_sid_buffer : sid_buffer                    写事务顺序队列
    └── u_aw_reorder    : reorder                       写数据资格判断
```

按默认参数展开时，`axi_interconnect` 下共有 67 个后代实例（不含顶层自身）；其中包括
30 个 FIFO、18 个 round-robin 基础仲裁器，以及各级封装/控制模块。

## 2. 各模块直接下级索引

| 源文件 / 模块 | 直接例化的模块 |
|---|---|
| `axi_interconnect_tb.v` / `axi_interconnect_tb` | `axi_interconnect` ×1 |
| `axi_interconnect.v` / `axi_interconnect` | `axi_fifo_sync` ×30、`axi_crossbar` ×1、`sid_buffer` ×2、`reorder` ×2 |
| `axi_crossbar.v` / `axi_crossbar` | `axi_mtos_m3` ×4、`axi_default_slave` ×1、`axi_stom_s3` ×3 |
| `axi_mtos_m3.v` / `axi_mtos_m3` | `axi_arbiter_mtos_m3` ×1 |
| `axi_arbiter_mtos_m3.v` / `axi_arbiter_mtos_m3` | `round_robin_m2s` ×3 |
| `axi_stom_s3.v` / `axi_stom_s3` | `axi_arbiter_stom_s3` ×1 |
| `axi_arbiter_stom_s3.v` / `axi_arbiter_stom_s3` | `round_robin_s2m` ×2 |
| `axi_default_slave.v` | 无子模块（叶子） |
| `axi_fifo_sync.v` | 无子模块（叶子） |
| `sid_buffer.v` | 无子模块（含 `priority_sel` 函数与 `idx_loop` genvar，叶子） |
| `reorder.v` | 无子模块（叶子） |
| `round_robin_m2s.v` | 无子模块（叶子） |
| `round_robin_s2m.v` | 无子模块（叶子） |

## 3. 例化深度

- 深度 0：`axi_interconnect`
- 深度 1：`axi_fifo_sync`、`axi_crossbar`、`sid_buffer`、`reorder`
- 深度 2（crossbar 内）：`axi_mtos_m3`、`axi_stom_s3`、`axi_default_slave`
- 深度 3（router 内）：`axi_arbiter_mtos_m3`、`axi_arbiter_stom_s3`
- 深度 4（仲裁叶子）：`round_robin_m2s`、`round_robin_s2m`

最大例化深度 = **4**（顶层 → crossbar → router → arbiter → RR）。

## 4. 连接 / 扇出说明

- `axi_crossbar` 是唯一包含 router 的地方：扇出 **4× `axi_mtos_m3`**（3 个真实 slave + 1
  个 default），扇入 **3× `axi_stom_s3`**（每个 master 一个，各自聚合 4 个响应源
  S0/S1/S2/SD）。
- 每个 `axi_mtos_m3` 是同构实例（同一模块，靠 `SLAVE_ID`/`ADDR_BASE` 参数区分）；default
  实例通过 `SLAVE_DEFAULT=1` 选中。
- FIFO 仅在 `axi_interconnect` 顶层例化 —— crossbar 与所有 router/reorder 操作的是已经
  缓冲好的点到点通道。
- `sid_buffer`+`reorder` 仅在顶层例化，横跨 crossbar 边界：`sid_buffer` 监视 crossbar
  的 slave 侧 AR/AW 接收与 master 侧 R/B 应答，`reorder` 则匹配 crossbar 的 slave 侧 R /
  master 侧 W 的 SID。

## 5. 修改影响对照

| 若修改… | 需同步检查/改动的例化 |
|---|---|
| 增/减 slave | 在 `axi_crossbar` 增加 `axi_mtos_m3`；扩大 `axi_stom_s3` 响应源数（NUM+1）→ `round_robin_s2m` 位宽；扩展 `axi_interconnect` 的 FIFO `generate` 循环 |
| 增/减 master | 扩展每个 `axi_mtos_m3` 的 master 端口组、`axi_arbiter_mtos_m3`（NUM=3→N）+ `round_robin_m2s`、FIFO 循环、`reorder`/`sid_buffer` 位宽 |
| 改变 FIFO 深度 | 仅 `axi_fifo_sync` 的 `FAW` 参数；层次不变 |
| 改变仲裁策略 | `round_robin_m2s` / `round_robin_s2m`中的候选计算、pending保持和accept提交，以及`axi_arbiter_*m3`中的通道accept生成 |
| 改变排序规则 | 顶层的 `sid_buffer` + `reorder`（及其 `w_order_grant`/`r_order_grant` 经 `axi_crossbar`、`axi_mtos_m3`/`axi_stom_s3` 的连线） |

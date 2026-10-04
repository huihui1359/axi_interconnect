# AXI Interconnect RTL 层次结构说明

**Author**: Wang Jianghao, Codex, GPT-5.6-Solar Medium
**Created**: 2026-09-27 ??:??
**Current Version**: v1.0

**Version Changelog**:
- **v1.0** (2026-09-27 ??:??): 初版 RTL 层次结构说明，整理完整例化树、各层职责、五通道路径、源文件索引和静态结构限制。

---

## 1. 文档范围与总体结论

本文依据 `rtl` 目录中 Verilog 源码的静态例化关系整理。设计是一个固定规模的 **3 个 AXI master 端口到 3 个 AXI slave 端口（3x3）** 的 crossbar，并内建一个 default slave，用于响应未命中地址空间的访问。

综合设计顶层为 `axi_interconnect`；`axi_interconnect_tb` 是仿真顶层，不属于综合层次。

数据通路可以概括为：

```text
3 个外部 master
       │
       ▼
master 侧通道 FIFO（AR/R/AW/W/B，每端口一组）
       │
       ▼
axi_crossbar
  ├─ 请求方向：按目标 slave 译码并仲裁（M→S）
  ├─ 响应方向：按来源 master ID 译码并仲裁（S→M）
  └─ default slave：处理地址未命中的访问
       │
       ▼
slave 侧通道 FIFO（AR/R/AW/W/B，每端口一组）
       │
       ▼
3 个外部 slave

并行控制路径：
  AR 接收顺序 → sid_buffer + reorder → 限制 R 返回顺序
  AW 接收顺序 → sid_buffer + reorder → 限制 W 发送顺序
```

### 1.1 模块连接与包含关系图

下面的大框表示模块的包含关系，箭头表示主要数据流。为避免连线过密，AW/W/AR 三个请求通道合并画在上半部分，B/R 两个响应通道合并画在下半部分；`×3`、`×4` 表示并列实例数量。

```text
                         axi_interconnect_tb（仿真层）
                                      │ 实例化
                                      ▼
┌────────────────────────────── axi_interconnect ───────────────────────────────┐
│                                                                                │
│  3 个外部 Master                                                              │
│  M0 / M1 / M2                                                                 │
│       │                                                                        │
│       │ AW/W/AR 请求                                                          │
│       ▼                                                                        │
│  ┌──────────────────────────┐                                                  │
│  │ Master 入口 FIFO ×9      │                                                  │
│  │ fifo_aw_mx ×3            │                                                  │
│  │ fifo_w_mx  ×3            │                                                  │
│  │ fifo_ar_mx ×3            │                                                  │
│  └────────────┬─────────────┘                                                  │
│               │                                                                │
│               ▼                                                                │
│  ┌────────────────────────────── axi_crossbar ──────────────────────────────┐  │
│  │                                                                          │  │
│  │  请求方向：3 Master → 每个目标端口                                      │  │
│  │                                                                          │  │
│  │     M0 ─┬──────────────┬──────────────┬──────────────┐                   │  │
│  │     M1 ─┼──────────────┼──────────────┼──────────────┤                   │  │
│  │     M2 ─┴──────────────┴──────────────┴──────────────┴────┐              │  │
│  │          ▼              ▼              ▼                  ▼              │  │
│  │   ┌────────────┐ ┌────────────┐ ┌────────────┐   ┌────────────┐          │  │
│  │   │axi_mtos_s0 │ │axi_mtos_s1 │ │axi_mtos_s2 │   │axi_mtos_sd │          │  │
│  │   │ 译码 + 仲裁 │ │ 译码+仲裁  │ │ 译码+仲裁  │   │ 未命中选择 │          │  │
│  │   └─────┬──────┘ └─────┬──────┘ └─────┬──────┘   └─────┬──────┘          │  │
│  │         │              │              │                ▼                 │  │
│  │         │              │              │       ┌─────────────────┐        │  │
│  │         │              │              │       │axi_default_slave│        │  │
│  │         │              │              │       │ 产生 DECERR B/R │        │  │
│  │         │              │              │       └────────┬────────┘        │  │
│  │         │              │              │                │                 │  │
│  │         ▼              ▼              ▼                │                 │  │
│  │       S0 请求         S1 请求         S2 请求            │                 │  │
│  │                                                                          │  │
│  │  响应方向：3 Slave + Default Slave → 每个目标 Master                    │  │
│  │                                                                          │  │
│  │       S0 B/R ─┬──────────────┬──────────────┐                            │  │
│  │       S1 B/R ─┼──────────────┼──────────────┤                            │  │
│  │       S2 B/R ─┼──────────────┼──────────────┤                            │  │
│  │  Default B/R ─┴──────────────┴──────────────┤                            │  │
│  │              ▼              ▼              ▼                            │  │
│  │       ┌────────────┐ ┌────────────┐ ┌────────────┐                       │  │
│  │       │axi_stom_m0 │ │axi_stom_m1 │ │axi_stom_m2 │                       │  │
│  │       │ ID译码+仲裁│ │ ID译码+仲裁│ │ ID译码+仲裁│                       │  │
│  │       └─────┬──────┘ └─────┬──────┘ └─────┬──────┘                       │  │
│  │             │              │              │                              │  │
│  └─────────────┼──────────────┼──────────────┼──────────────────────────────┘  │
│                │              │              │                                 │
│                └──────────────┴──────┬───────┘                                 │
│                                      │ B/R 响应                                │
│                                      ▼                                         │
│                         ┌──────────────────────────┐                            │
│                         │ Master 出口 FIFO ×6     │                            │
│                         │ fifo_b_mx ×3            │                            │
│                         │ fifo_r_mx ×3            │                            │
│                         └────────────┬─────────────┘                            │
│                                      ▼                                         │
│                                M0 / M1 / M2                                    │
│                                                                                │
│  对真实 Slave 的边界连接：                                                     │
│                                                                                │
│  crossbar ──AW/W/AR──▶ Slave 出口 FIFO ×9 ──▶ S0 / S1 / S2                    │
│             ◀──B/R──── Slave 入口 FIFO ×6 ◀──── S0 / S1 / S2                    │
│             fifo_aw_sx / fifo_w_sx / fifo_ar_sx / fifo_b_sx / fifo_r_sx        │
│                                                                                │
│  顶层顺序控制（与 crossbar 并列，由通道握手信息驱动）：                         │
│                                                                                │
│  AR SID ──▶ [u_ar_sid_buffer] ──▶ [u_ar_reorder] ──r_order_grant──▶ stom/R     │
│  AW SID ──▶ [u_aw_sid_buffer] ──▶ [u_aw_reorder] ──w_order_grant──▶ mtos/W     │
│                                                                                │
└────────────────────────────────────────────────────────────────────────────────┘

每个请求/响应交换单元内部还包含以下仲裁层：

  axi_mtos_m3 ×4
  └─ axi_arbiter_mtos_m3 ×1
     ├─ round_robin_m2s（AW）
     ├─ round_robin_m2s（W）
     └─ round_robin_m2s（AR）

  axi_stom_s3 ×3
  └─ axi_arbiter_stom_s3 ×1
     ├─ round_robin_s2m（B）
     └─ round_robin_s2m（R）
```

读图时需要注意：

- `axi_mtos_m3` 是以 **slave 目标** 为中心组织的。每个真实 slave 和 default slave 各有一个实例，竞争者是 3 个 master。
- `axi_stom_s3` 是以 **master 目标** 为中心组织的。每个 master 各有一个实例，竞争者是 3 个真实 slave 加 default slave。
- `sid_buffer` 和 `reorder` 不包含在 `axi_crossbar` 内，而是与 `u_axi_crossbar` 同属于 `axi_interconnect` 的直接子模块。
- default slave 完全位于 `axi_crossbar` 内部，不经过外部 slave 侧 FIFO。

## 2. 完整例化树

方括号中的 `[0..2]` 表示 generate 展开后的 3 个实例，而不是单个数组实例。

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

按默认参数展开时，`axi_interconnect` 下共有 68 个后代实例（不含顶层自身）；其中包括 30 个 FIFO、18 个 round-robin 基础仲裁器以及各级封装/控制模块。

## 3. 各层职责

### 3.1 `axi_interconnect`：接口、流水化与全局顺序控制层

文件：`axi_interconnect.v`

这是综合入口，对外提供 3 组 master-side AXI 接口和 3 组 slave-side AXI 接口。主要工作包括：

1. 在 crossbar 两侧为 AXI 五个通道插入同步 FIFO。每个 `axi_fifo_sync` 的 `FAW=2`，因此深度为 `2^2=4`。
2. 将数组形式的顶层接口拆接到标量端口形式的 `axi_crossbar`。
3. 用两套 `sid_buffer + reorder` 记录事务顺序并生成准入信号：
   - AR/R 路径：记录已被各 slave 端接受的 AR SID，只允许符合队首顺序的 R 通道继续返回。
   - AW/W 路径：记录已被各 slave 端接受的 AW SID，只允许符合队首顺序的 W 通道继续前进。

FIFO 的层次命名约定：

| generate 块 | 通道 | 位置/方向 | 数量 |
|---|---|---|---:|
| `fifo_ar_mx` | AR | 外部 master → crossbar | 3 |
| `fifo_ar_sx` | AR | crossbar → 外部 slave | 3 |
| `fifo_r_sx` | R | 外部 slave → crossbar | 3 |
| `fifo_r_mx` | R | crossbar → 外部 master | 3 |
| `fifo_aw_mx` | AW | 外部 master → crossbar | 3 |
| `fifo_aw_sx` | AW | crossbar →外部 slave | 3 |
| `fifo_w_mx` | W | 外部 master → crossbar | 3 |
| `fifo_w_sx` | W | crossbar → 外部 slave | 3 |
| `fifo_b_sx` | B | 外部 slave → crossbar | 3 |
| `fifo_b_mx` | B | crossbar → 外部 master | 3 |

### 3.2 `axi_crossbar`：互连核心组装层

文件：`axi_crossbar.v`

该模块没有用 generate 参数化拓扑，而是显式例化固定的 3 master、3 slave 结构。它由两种方向相反的交换单元组成：

- 4 个 `axi_mtos_m3`：每个实例对应一个目标端口，收集 3 个 master 的 AW/W/AR 请求并选择一路送出。三个实例对应真实 slave，第四个对应 default slave。
- 3 个 `axi_stom_s3`：每个实例对应一个 master，收集 3 个真实 slave 加 default slave 的 B/R 响应并选择一路返回。
- 1 个 `axi_default_slave`：对未命中真实地址窗口的访问产生本地 AXI 错误响应。

因此核心不是一个单体的 3x3 mux，而是“**按目标端口组织请求仲裁 + 按发起端口组织响应仲裁**”的组合。

默认地址译码为：

| 目标 | 基地址 | `ADDR_LENGTH` | 地址范围 |
|---|---:|---:|---:|
| S0 | `0x0000_0000` | 12 | `0x0000_0000`–`0x0000_0FFF` |
| S1 | `0x0000_2000` | 12 | `0x0000_2000`–`0x0000_2FFF` |
| S2 | `0x0000_4000` | 12 | `0x0000_4000`–`0x0000_4FFF` |
| SD | 未命中上述窗口 | — | default slave |

### 3.3 `axi_mtos_m3`：3 个 master 到单个目标 slave

文件：`axi_mtos_m3.v`

每个实例完成请求方向的三项工作：

1. 根据 AW/AR 地址判断各 master 是否选中本实例对应的 slave；default 实例使用其他 slave 选择结果的反码。
2. 对 AW、W、AR 三个通道分别仲裁。
3. 将获胜 master 的载荷 mux 到目标 slave，并扩展 ID。扩展后的 SID 包含目标 slave 编码、来源 master 编码和原始 AXI ID，用于后续响应路由及顺序判断。

它只处理请求通道 AW、W、AR；响应 B、R 由 `axi_stom_s3` 处理。

### 3.4 `axi_arbiter_mtos_m3` 与 `round_robin_m2s`

文件：`axi_arbiter_mtos_m3.v`、`round_robin_m2s.v`

`axi_arbiter_mtos_m3` 内含 3 个独立的 3 路 round-robin 仲裁器，分别服务 AR、AW、W。外层状态机在一次传输尚未完成时保持当前 grant，避免新的高优先级请求中途改变选择。

### 3.5 `axi_stom_s3`：4 个响应源到单个 master

文件：`axi_stom_s3.v`

模块名中的 `s3` 实际接口包含 3 个真实 slave 和 1 个 default slave，共 4 个响应源。模块根据 SID 中的来源 master 编码选择属于当前 master 的 B/R 响应，然后分别仲裁并 mux 到该 master。

R 通道还与顶层传入的 `r_order_grant` 相与，使返回数据受到全局读事务顺序控制；B 通道只按目的 master 和仲裁结果路由。

### 3.6 `axi_arbiter_stom_s3` 与 `round_robin_s2m`

文件：`axi_arbiter_stom_s3.v`、`round_robin_s2m.v`

`axi_arbiter_stom_s3` 内含两个独立的 4 路 round-robin 仲裁器，分别服务 R 和 B。外层状态机负责在握手完成前保持 grant。尽管文件名为 `s3`，底层 `round_robin_s2m` 的请求/grant 宽度是 4，以覆盖 default slave。

### 3.7 `sid_buffer` 与 `reorder`：顺序约束层

文件：`sid_buffer.v`、`reorder.v`

- `sid_buffer` 是 4 项 SID 顺序队列。它从 3 个候选入口中接收 SID，产生入口 ready；事务结束时按 SID 查找并清除表项，再压紧剩余表项。
- `reorder` 将 3 个候选 SID 与 `sid_buffer[0]`（队首）比较，输出 3 bit `order_grant`。它更接近“队首 ID 资格判断器”，本身不搬移数据。

两套实例分别用于：

| 跟踪对象 | 入队时机 | 出队/完成依据 | grant 的使用位置 |
|---|---|---|---|
| 读事务 | slave 侧 AR 被接受 | 返回 R 的 `RLAST` | `axi_stom_s3` 的 R 选择 |
| 写事务 | slave 侧 AW 被接受 | slave 侧 W 的 `WLAST` | `axi_mtos_m3` 的 W 选择 |

### 3.8 `axi_fifo_sync`：通道缓冲基础单元

文件：`axi_fifo_sync.v`

同步、单时钟、ready/valid 接口 FIFO，采用 first-word fall-through 形式。顶层将 AXI 通道载荷打包为单个 FIFO 数据字，握手信号映射到 FIFO 的写/读 ready-valid。

### 3.9 `axi_default_slave`：未命中访问终结点

文件：`axi_default_slave.v`

该模块接收 default 路径上的 AW/W/AR，并在本地生成 B/R 响应，防止未命中地址的事务悬挂。它同时处理读、写状态机；读突发按 ARLEN 产生数据拍和 RLAST，写路径接收数据至 WLAST 后产生 B 响应。

## 4. 五通道在层次中的路径

### 写地址 AW

```text
M_AXI_AW* → fifo_aw_mx → axi_crossbar
          → 对应目标的 axi_mtos_m3/AW 仲裁
          → fifo_aw_sx → S_AXI_AW*
```

AW 被目标侧接受时，扩展 SID 同时写入 `u_aw_sid_buffer`，供后续 W 通道排序。

### 写数据 W

```text
M_AXI_W* → fifo_w_mx → axi_crossbar
         → axi_mtos_m3/W 仲裁（受 w_order_grant 限制）
         → fifo_w_sx → S_AXI_W*
```

### 写响应 B

```text
S_AXI_B* → fifo_b_sx → axi_crossbar
         → 对应 master 的 axi_stom_s3/B 仲裁
         → fifo_b_mx → M_AXI_B*
```

### 读地址 AR

```text
M_AXI_AR* → fifo_ar_mx → axi_crossbar
          → 对应目标的 axi_mtos_m3/AR 仲裁
          → fifo_ar_sx → S_AXI_AR*
```

AR 被目标侧接受时，扩展 SID 同时写入 `u_ar_sid_buffer`，供后续 R 通道排序。

### 读数据 R

```text
S_AXI_R* → fifo_r_sx → axi_crossbar
         → axi_stom_s3/R 仲裁（受 r_order_grant 限制）
         → fifo_r_mx → M_AXI_R*
```

## 5. 源文件与直接下级模块索引

| 源文件 / 模块 | 直接例化的模块 |
|---|---|
| `axi_interconnect_tb.v` / `axi_interconnect_tb` | `axi_interconnect` ×1 |
| `axi_interconnect.v` / `axi_interconnect` | `axi_fifo_sync` ×30、`axi_crossbar` ×1、`sid_buffer` ×2、`reorder` ×2 |
| `axi_crossbar.v` / `axi_crossbar` | `axi_mtos_m3` ×4、`axi_default_slave` ×1、`axi_stom_s3` ×3 |
| `axi_mtos_m3.v` / `axi_mtos_m3` | `axi_arbiter_mtos_m3` ×1 |
| `axi_arbiter_mtos_m3.v` / `axi_arbiter_mtos_m3` | `round_robin_m2s` ×3 |
| `axi_stom_s3.v` / `axi_stom_s3` | `axi_arbiter_stom_s3` ×1 |
| `axi_arbiter_stom_s3.v` / `axi_arbiter_stom_s3` | `round_robin_s2m` ×2 |
| `axi_default_slave.v` | 无子模块 |
| `axi_fifo_sync.v` | 无子模块 |
| `sid_buffer.v` | 无子模块 |
| `reorder.v` | 无子模块 |
| `round_robin_m2s.v` | 无子模块 |
| `round_robin_s2m.v` | 无子模块 |

## 6. 阅读代码的建议顺序

为了最快建立整体认识，建议按以下顺序阅读：

1. `axi_interconnect.v`：先看接口、10 组 FIFO generate 块、crossbar 接线和两套 reorder 控制。
2. `axi_crossbar.v`：看 4 个请求汇聚点和 3 个响应汇聚点如何拼成 3x3 拓扑。
3. `axi_mtos_m3.v`：理解地址译码、SID 扩展和请求 mux。
4. `axi_stom_s3.v`：理解响应如何依据 SID 返回原 master。
5. 两个 `axi_arbiter_*` 和两个 `round_robin_*`：理解通道锁定与公平性。
6. `sid_buffer.v`、`reorder.v`：最后理解设计额外施加的顺序约束。
7. `axi_default_slave.v` 和 `axi_interconnect_tb.v`：确认异常地址行为和已有测试场景。

## 7. 静态结构中值得注意的限制

- 虽然 `axi_crossbar` 声明了 `NUM_MASTER`、`NUM_SLAVE` 参数，端口和实例仍然按 3x3 显式展开；修改参数不会自动改变拓扑。
- `axi_interconnect` 的 generate 循环固定为 3，且多处 FIFO 数据宽度直接写成 4/8/32，而非完全使用顶层宽度参数。因此当前层次和打包方式应按默认参数理解。
- `filelist.f` 将 testbench 写为 `./sim/axi_interconnect_tb.v`，但本次扫描到的文件位于 `rtl/axi_interconnect_tb.v`；使用该 filelist 前需确认工程目录中是否另有 `sim` 副本或修正路径。
- `sid_buffer` 深度固定为 4，因此这里的顺序跟踪容量不是由 crossbar 的 master/slave 数量参数自动推导的。

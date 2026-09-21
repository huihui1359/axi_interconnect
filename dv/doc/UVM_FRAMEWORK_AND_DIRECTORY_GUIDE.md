# UVM 验证环境框架与目录规范

## 1. 文档目的

本文档从当前 `pad_buf` 项目提炼一套可复用于后续模块级验证项目的 UVM 组织规范，重点解决以下问题：

- 一个完整的 UVM 环境必须包含哪些层次和组件；
- `base_sequence` 与具体 `sequence`、`base_test` 与具体 `testcase` 的职责如何划分；
- `env` 中应该实例化哪些组件，各组件只负责什么、不负责什么；
- `common` 目录中应该放置哪些全局声明；
- transaction、激励、采样、预测、比对、覆盖率和结束控制如何解耦；
- 文件目录、命名、package 编译顺序和新增 testcase 的固定流程。

本文档包含两种视角：

1. **当前项目映射**：说明现有 `pad_buf` 代码如何组成验证环境；
2. **后续项目强制规范**：作为新项目搭建和 AI 生成代码时的约束。

若两者存在差异，以“后续项目强制规范”为准。

---

## 2. 总体分层原则

推荐把验证平台固定分为五层：

```text
testcase 层     选择场景、配置环境、控制 objection 和测试结束
    |
sequence 层     生成“做什么”的 transaction，不接触 DUT 信号
    |
agent 层        把 transaction 与接口时序互相转换
    |
env/check 层    预测、比对、覆盖率统计和跨 agent 连接
    |
tb_top/interface 层  时钟复位、DUT 实例、静态连线、启动 UVM
```

核心数据流必须是：

```text
test -> sequence -> sequencer -> driver -> interface -> DUT
                                                |
                                           input monitor
                                                |
                                                +-> reference model -> expected
                                                |
DUT -> interface -> output monitor -> actual   +-> coverage
                                      |          |
                                      +----------+-> scoreboard -> PASS/FAIL
```

必须遵守以下边界：

- sequence 决定 transaction 内容，driver 决定引脚时序；
- driver 只驱动，不承担功能预测和结果比对；
- monitor 只依据真实 `valid && ready` 等协议事件采样，不制造激励；
- reference model 只生成 expected，不读取 actual 后修改 expected；
- scoreboard 只比较 expected/actual，不重复实现 DUT 算法；
- coverage 判断“测到了什么”，scoreboard 判断“结果是否正确”；
- testcase 选择场景和配置，不直接逐周期驱动信号；
- `tb_top` 只做静态工作，不放 testcase 业务流程。

---

## 3. 标准目录要求

新项目使用如下目录骨架，其中 `<ip>` 替换为 DUT 名称，`<bus>` 替换为具体接口名：

```text
project/
├─ rtl/                              # DUT RTL 或 RTL filelist
├─ dv/
│  ├─ common/                        # 全环境共享、无场景倾向的声明
│  │  ├─ <ip>_defines.svh            # 全局宏、编译开关、常量宏
│  │  ├─ <ip>_types.sv               # typedef、enum、struct、公共常量
│  │  ├─ <ip>_env_cfg.sv             # 环境级配置对象
│  │  └─ <ip>_pkg.sv                 # 唯一主 package 与 include 顺序
│  ├─ tb/
│  │  ├─ <bus>_if.sv                 # interface、clocking block、modport、SVA
│  │  └─ <ip>_tb_top.sv              # clock/reset、DUT、interface、run_test
│  ├─ agents/
│  │  ├─ <bus_a>_agent/
│  │  │  ├─ <bus_a>_item.sv
│  │  │  ├─ <bus_a>_agent_cfg.sv
│  │  │  ├─ <bus_a>_sequencer.sv     # 无扩展需求时可用参数化 sequencer
│  │  │  ├─ <bus_a>_driver.sv
│  │  │  ├─ <bus_a>_monitor.sv
│  │  │  └─ <bus_a>_agent.sv
│  │  └─ <bus_b>_agent/
│  │     └─ ...
│  ├─ env/
│  │  ├─ <ip>_virtual_sequencer.sv   # 多 agent 协同时才需要
│  │  ├─ <ip>_ref_model.sv
│  │  ├─ <ip>_scoreboard.sv
│  │  ├─ <ip>_coverage.sv
│  │  └─ <ip>_env.sv
│  ├─ seq/
│  │  ├─ <ip>_base_sequence.sv
│  │  ├─ <ip>_smoke_sequence.sv
│  │  ├─ <ip>_directed_sequence.sv
│  │  ├─ <ip>_random_sequence.sv
│  │  └─ <ip>_virtual_sequence.sv     # 多 agent 协同时才需要
│  ├─ tc/
│  │  ├─ <ip>_base_test.sv
│  │  ├─ <ip>_smoke_test.sv
│  │  ├─ <ip>_directed_test.sv
│  │  └─ <ip>_random_test.sv
│  ├─ assertions/                     # 跨接口或不适合放 interface 的 SVA
│  ├─ testplan/
│  │  ├─ testplan.md
│  │  └─ coverage_plan.md
│  └─ filelist/
│     └─ dv.f
└─ sim/
   ├─ Makefile
   └─ scripts/
```

小型项目可以省略空目录，但以下内容不可省略：

- `common/<ip>_pkg.sv`；
- `tb/<bus>_if.sv` 和 `tb/<ip>_tb_top.sv`；
- 至少一个 transaction、agent、sequence；
- `env/<ip>_env.sv`；
- `tc/<ip>_base_test.sv` 和至少一个具体 testcase；
- 有输出需要自动检查时，必须有 monitor、reference model 和 scoreboard。

### 3.1 文件放置规则

| 内容 | 目录 | 原因 |
|---|---|---|
| 全局 typedef/enum/struct/宏/配置对象 | `common/` | 多层共享，避免循环依赖 |
| 协议 transaction | 对应 `agents/<name>_agent/` | transaction 属于协议 agent，不属于 testcase |
| DUT 级预测和跨接口检查 | `env/` | 依赖多个 agent 的数据 |
| 单接口 driver/monitor/sequencer | 对应 agent 目录 | 保证 agent 可复用 |
| 场景生成 | `seq/` | 与组件层次和引脚实现解耦 |
| 测试选择与配置 | `tc/` | 一个类对应一个可回归的 test 名称 |
| interface、clocking、modport | `tb/` | 属于静态 SystemVerilog 世界 |
| 编译/仿真脚本 | `sim/` 或 `dv/filelist/` | 不与验证类混放 |

---

## 4. `common` 目录规范

`common` 只存放**被两个及以上层次共享、与某个 testcase 无关、且不执行接口时序**的内容。

### 4.1 应放入 `common` 的内容

#### `<ip>_defines.svh`

只放确实需要预处理器完成的内容：

- include guard；
- DUT 与 TB 必须共同看到的编译期宏；
- 条件编译开关，例如 assertion、仿真加速或功能裁剪；
- 无法用 package parameter 替代的编译期常量。

示例：

```systemverilog
`ifndef MY_IP_DEFINES_SVH
`define MY_IP_DEFINES_SVH

`ifndef MY_IP_BUFFER_AW
`define MY_IP_BUFFER_AW 7
`endif

`define MY_IP_MAX_BYTES (1 << `MY_IP_BUFFER_AW)

`endif
```

优先使用 package 中的 `parameter/localparam`，只在必须跨 package、interface、module 或 RTL 预处理阶段共享时使用宏。禁止把复杂业务逻辑写成宏。

#### `<ip>_types.sv`

放置全局类型和常量：

```systemverilog
typedef enum {MODE_NORMAL, MODE_BYPASS, MODE_ERROR_INJECT} mode_e;
typedef enum {RESP_OK, RESP_ERR, RESP_TIMEOUT} response_e;

typedef struct packed {
    bit [31:0] addr;
    bit [7:0]  len;
} command_s;

localparam int unsigned DATA_WIDTH = 128;
```

适合放入其中的内容包括：

- 多个 agent/env/test 都需要使用的 `typedef`；
- enum、packed struct、公共队列元素类型；
- 地址宽度、数据宽度、最大 outstanding 等稳定常量；
- 公共函数应放在独立 utility class/package 文件中，而不是宏中。

#### `<ip>_env_cfg.sv`

环境配置对象用于传递运行策略，而不是散落大量 `config_db` 标量：

```systemverilog
class my_ip_env_cfg extends uvm_object;
    `uvm_object_utils(my_ip_env_cfg)

    bit has_scoreboard = 1;
    bit has_coverage   = 1;
    int unsigned timeout_cycles = 1_000_000;
    my_bus_agent_cfg master_cfg;
    my_bus_agent_cfg slave_cfg;
endclass
```

典型字段包括：agent active/passive、virtual interface、超时、backpressure 范围、是否启用 scoreboard/coverage、协议能力和 DUT 参数镜像。

#### `<ip>_pkg.sv`

主 package 负责：

- `import uvm_pkg::*`；
- include `uvm_macros.svh` 和项目宏；
- 按依赖顺序 include class 文件；
- 向 `tb_top` 提供统一 `import <ip>_pkg::*` 入口。

推荐依赖顺序：

```text
defines/types
-> config
-> transaction
-> sequencer/driver/monitor/agent
-> ref_model/scoreboard/coverage/virtual_sequencer/env
-> base_sequence/derived_sequence
-> base_test/derived_test
```

### 4.2 禁止放入 `common` 的内容

- 具体 testcase 或 testcase 专属参数；
- 某条 directed sequence 的地址、数据和循环流程；
- driver/monitor 的握手 task；
- scoreboard 比对逻辑或 reference model 算法；
- DUT 实例、interface 实例、时钟和复位 initial block；
- 仅被单一 class 使用的局部 typedef/常量；
- 为缩短代码而创建、隐藏对象生命周期或时序的复杂宏。

判断规则：如果更换某个 testcase 后该内容可能变化，它通常不属于 `common`；如果只有一个组件使用，应留在该组件内部。

---

## 5. 各组件职责与禁止事项

| 组件 | 必须负责 | 不应负责 |
|---|---|---|
| sequence item | transaction 字段、约束、打印/复制/比较、协议级合法性 | 引脚操作、objection、DUT 结果判断 |
| base sequence | 公共发送 API、公共随机控制、共享 pre/body/post 流程 | 固定具体 testcase 场景、scoreboard 算法、环境创建 |
| derived sequence | 一个清晰场景的 transaction 顺序和约束 | clock/reset、直接访问 DUT 层次、PASS/FAIL |
| sequencer | sequence 与 driver 的仲裁；保存少量调度配置 | 驱动信号、预测 DUT |
| driver | transaction 到 pin-level 协议的转换、backpressure/response 驱动 | 功能覆盖率、expected 预测、actual 比对 |
| monitor | 从真实握手重建 transaction，通过 analysis port 发布 | 驱动信号、改变 transaction 以迁就预期 |
| agent | 创建并连接本协议的 driver/sequencer/monitor，处理 active/passive | 跨接口参考模型和 DUT 级比对 |
| reference model | 根据已接受输入产生 expected transaction | 采集引脚、控制激励、比较 actual |
| scoreboard | expected/actual 配对、字段比较、未配对/数量/乱序检查 | 生成激励、复制完整 DUT 算法 |
| coverage | 采样 testplan 定义的功能场景、报告覆盖率 | 判定 DUT 正误、驱动信号 |
| env | 创建配置允许的组件，连接 TLM，暴露完成/状态接口 | 编写具体测试场景、逐周期驱动 |
| base test | 创建 env、下发配置、统一 objection/reset/timeout/结束流程 | 填入某个功能点的 transaction 明细 |
| testcase | 设置本测试差异，创建并启动目标 sequence | 重建 env、重复连接、直接比对引脚 |
| interface | 信号集合、clocking block、modport、协议 SVA | testcase 选择、参考模型 |
| tb_top | 时钟复位、interface/DUT 实例、config_db 入口、`run_test()` | sequence 逻辑、scoreboard、随机场景 |

---

## 6. `base_sequence` 与具体 `sequence`

### 6.1 `base_sequence` 应负责什么

`base_sequence` 是所有场景的公共事务生成基类，推荐只包含：

- 公共配置句柄；
- 类型化 sequencer 声明（确有需要时）；
- `send_item()`、`send_cmd()` 等公共发送封装；
- 共用的合法性检查；
- 所有 sequence 一致需要的启动前/结束后操作；
- 可被派生类覆盖的 knobs，例如 item 数、延迟范围。

示例：

```systemverilog
class my_ip_base_sequence extends uvm_sequence #(my_bus_item);
    `uvm_object_utils(my_ip_base_sequence)

    rand int unsigned item_count = 1;

    task send_item(bit [31:0] addr, int unsigned len);
        my_bus_item req;
        req = my_bus_item::type_id::create("req");
        start_item(req);
        if (!req.randomize() with { req.addr == local::addr;
                                    req.len  == local::len; })
            `uvm_fatal(get_type_name(), "item randomization failed")
        finish_item(req);
    endtask
endclass
```

### 6.2 `base_sequence` 不应负责什么

- 不实例化 env、agent、driver 或 scoreboard；
- 不通过层次路径访问 `uvm_test_top.env...`；
- 不直接访问 virtual interface；
- 不做 expected/actual 比对；
- 原则上不复制 reference model 算法来计算 expected 数据；
- 不包含某一个 testcase 才需要的固定地址列表。

当前 `pad_buf_base_sequence` 中的 `record_expected_result()` 和 expected 计数用于测试结束完整性检查，但它与 reference model 的 cache/拍数算法重复。新项目推荐由 reference model/scoreboard 维护 accepted、predicted、compared、outstanding 计数，并向 test 提供 `wait_for_done()`，避免两套算法发生漂移。

### 6.3 具体 sequence 应负责什么

一个具体 sequence 对应一个可描述的激励场景，例如：

- smoke：最小合法事务；
- boundary：最小值、最大值、越界值；
- random：约束随机流量；
- reset：传输中复位；
- error：非法响应或错误注入；
- stress：高 outstanding、长 backpressure、多通道交错。

具体 sequence 的 `body()` 只表达 transaction 的顺序、数量和约束。相同场景不要同时散落在 testcase、driver 和 sequence 中。

### 6.4 何时使用 virtual sequence

只有当一个场景需要协调两个及以上独立 sequencer 时，才增加：

- `virtual_sequencer`：保存各子 sequencer 句柄；
- `virtual_sequence`：在多个子 sequencer 上并行/串行启动子 sequence。

单 agent 项目不要为了形式完整而创建空 virtual sequencer。

---

## 7. `base_test` 与具体 testcase

### 7.1 `base_test` 应负责什么

所有测试共用且只需实现一次的内容放在 `base_test`：

- 创建 env config 和 env；
- 从 plusarg/配置文件读取通用选项；
- 把 virtual interface、agent 模式和超时下发给 env；
- 统一等待 reset 释放；
- 统一 raise/drop objection；
- 调用可覆盖的 `start_main_sequence()`；
- 等待 scoreboard/reference model 完成或超时；
- 打印公共拓扑和配置（按需）。

推荐流程：

```systemverilog
task run_phase(uvm_phase phase);
    phase.raise_objection(this);
    wait_reset_released();
    start_main_sequence();
    env.wait_for_done();
    phase.drop_objection(this);
endtask
```

`start_main_sequence()` 可以在 base test 中报 fatal，强制派生类实现；也可以通过 default sequence 配置，但同一项目必须统一一种方式。

### 7.2 具体 testcase 应负责什么

具体 testcase 只描述“与基类相比有什么不同”：

- 创建哪个 sequence；
- sequence 的 item 数、约束或模式；
- agent 是 active 还是 passive；
- 是否打开 coverage、error injection、特殊 backpressure；
- 本 testcase 的 timeout 或完成条件差异。

一个 testcase 应对应 testplan 中一个场景或一组紧密相关场景，并能通过：

```text
+UVM_TESTNAME=<ip>_<scenario>_test
```

独立运行。

### 7.3 testcase 禁止事项

- 不重新创建第二套 env；
- 不复制 base test 的 objection 和 reset 流程；
- 不直接调用 driver 内部 task；
- 不在 testcase 中用 `force`/层次引用驱动 DUT，除非这是明确封装的 fault-injection 机制；
- 不用固定 `#delay` 作为正常完成条件。

---

## 8. agent 设计规范

### 8.1 标准 agent 组成

标准可复用 agent 包含：

```text
agent
├─ monitor                         # active/passive 均创建
├─ sequencer                       # 仅 active 创建
└─ driver                          # 仅 active 创建
```

基本实现要求：

```systemverilog
monitor = ...::create("monitor", this);
if (cfg.is_active == UVM_ACTIVE) begin
    sequencer = ...::create("sequencer", this);
    driver    = ...::create("driver", this);
end
```

禁止在 agent 内硬编码 `is_active = UVM_ACTIVE`。模式必须来自 agent config，使同一个 agent 可作为主动 VIP 或被动监听器复用。

### 8.2 driver 与 monitor 的数据来源

reference model 的输入应优先来自 input monitor 采集到的**真实成功握手**，而不是来自 driver 的 req。原因是 driver 收到 req 不代表 DUT 已接受该事务，reset、timeout 或协议错误都可能使两者不同。

推荐：

```text
driver req -> pin
pin handshake -> monitor -> ref_model
```

不推荐作为通用模板：

```text
driver req -> ref_model
```

如果协议需要 reactive slave（先观察 DUT request，再产生 response），可以采用：

```text
request monitor -> reactive sequence/sequencer -> response driver
```

小型环境也可由 reactive driver 通过 FIFO 接收 monitor request，但必须在注释中明确它不是普通 sequence driver，并且不能把 reference model、coverage 和比对一并塞入该 driver。

### 8.3 interface 要求

新项目 interface 至少应增加：

- driver clocking block；
- monitor clocking block；
- driver/monitor modport；
- reset 极性定义；
- `valid` 等待 `ready` 时 payload 保持稳定等协议 assertion。

这样可固定采样/驱动时钟域，减少 race，并通过 modport 限制错误方向的信号访问。

---

## 9. `env` 中应有哪些组件

### 9.1 必选组件

`<ip>_env` 至少负责实例化和连接：

- DUT 每类外部接口对应的 agent；
- reference model；
- scoreboard。

只要 testplan 有功能覆盖率，还应包含 coverage collector。多个主动 agent 需要统一调度时，再加入 virtual sequencer。

标准层次：

```text
env
├─ input_agent(s)
├─ output_agent(s)
├─ virtual_sequencer       # 可选
├─ reference_model
├─ scoreboard
└─ coverage
```

### 9.2 env 的 build/connect 分工

`build_phase`：

- 获取并检查 env config；
- 按配置创建 agent/ref model/scoreboard/coverage；
- 向子组件下发各自 config；
- 不进行 transaction 处理。

`connect_phase`：

- 连接 monitor analysis port 到 reference model、scoreboard、coverage；
- 连接 reference model expected port 到 scoreboard；
- 连接 virtual sequencer 与子 sequencer 句柄；
- 不创建组件，不产生激励。

### 9.3 推荐 TLM 连接

```text
input_agent.monitor.ap  -> ref_model.input_fifo
input_agent.monitor.ap  -> coverage.input_export
output_agent.monitor.ap -> scoreboard.actual_fifo
ref_model.expected_ap   -> scoreboard.expected_fifo
```

若 coverage 需要 reference model 计算出的语义字段，例如 cache hit/miss，可由 reference model 发布一条独立的 enriched/prediction analysis port 给 coverage。coverage 仍由 env 创建和连接，不应为了复用一个计算结果而变成 ref model 的子组件。

### 9.4 完成条件

优先使用基于事务的完成机制：

```text
sequence 已结束
+ reference model 已处理全部 accepted input
+ scoreboard expected/actual 已全部配对
+ outstanding == 0
```

`env.wait_for_done()` 必须带 timeout。只看若干周期 `valid==0` 的 quiet-window 可作为兼容方案，但不能单独证明 DUT 没有少输出事务。固定等待 N 个周期只能作为最后兜底，不能作为主要完成判据。

---

## 10. reference model、scoreboard 与 coverage 的边界

### 10.1 reference model

输入：input monitor 发布的、DUT 已实际接受的事务。

输出：DUT 应产生的 expected transaction。

要求：

- 算法可独立于 DUT RTL 实现；
- 输入 transaction 如会被缓存或异步处理，应 clone 后保存；
- reset 时清空模型状态、历史缓存和 outstanding；
- 多输出流使用独立 analysis port；
- 不以 output monitor 的 actual 内容反向修正 expected。

### 10.2 scoreboard

输入：reference model 的 expected 和 output monitor 的 actual。

要求：

- 明确 in-order 或 out-of-order 匹配策略；
- 使用 `!==` 或字段级 compare 识别 X/Z（按协议需要）；
- 对 mismatch、unexpected actual、missing actual、残留 FIFO 分别报错；
- 维护 receive/compare/error/outstanding 计数；
- `check_phase` 检查残留事务，`report_phase` 汇总结果；
- 不依赖“只要没有 mismatch 就通过”，至少要检查确实比较过事务。

### 10.3 coverage

输入：monitor 的真实事务，或 reference model 发布的带语义标记事务。

要求：

- coverpoint/cross 必须可追溯到 testplan；
- 非法组合用 `illegal_bins`，设计上不可能组合用 `ignore_bins`；
- coverage 未达到目标通常由 regression 门禁处理，不在单次 sample 中报 DUT error；
- 不因方便而从 sequence 直接采样，否则“生成过”不等于“DUT 接受过”。

---

## 11. 当前 `pad_buf` 项目映射

### 11.1 当前层次

```text
pad_buf_tb_top
├─ pad_if : pad_buf_if
├─ u_dut  : vc8000e_prp_pad_buf
└─ uvm_test_top : pad_buf_directed_test / pad_buf_random_test
   └─ env : pad_buf_env
      ├─ master_agent : pad_buf_master_agent
      │  ├─ sequencer : uvm_sequencer #(pad_buf_cmd_item)
      │  ├─ driver    : pad_buf_master_driver
      │  └─ monitor   : pad_buf_master_monitor
      ├─ slave_agent : pad_buf_slave_agent
      │  ├─ driver    : pad_buf_slave_driver
      │  └─ monitor   : pad_buf_slave_monitor
      ├─ ref_model  : pad_buf_ref_model
      │  └─ coverage : pad_buf_coverage
      └─ scoreboard : pad_buf_scoreboard
```

当前 master/slave 名称表示协议角色，而不是简单的信号方向：

| 当前组件 | 当前职责 |
|---|---|
| `pad_buf_master_driver` | 驱动 `scmd`，同时驱动 `mdata_ready` |
| `pad_buf_master_monitor` | 采样 `mdata` |
| `pad_buf_slave_monitor` | 采样 DUT 发出的 `mcmd` |
| `pad_buf_slave_driver` | 驱动 `mcmd_ready`，根据 mcmd 生成并驱动 `sdata` |
| `pad_buf_ref_model` | 根据 scmd/sdata 预测 mcmd/mdata |
| `pad_buf_scoreboard` | 分别比较 expected/actual mcmd 和 mdata |
| `pad_buf_coverage` | 采样地址对齐、长度、重复、延迟和 cache hit/miss |

### 11.2 当前连接关系

```text
master_driver.scmd_ap   -> ref_model.scmd_fifo
slave_driver.sdata_ap   -> ref_model.sdata_fifo
ref_model.exp_mcmd_ap   -> scoreboard.exp_mcmd_fifo
ref_model.exp_mdata_ap  -> scoreboard.exp_mdata_fifo
slave_monitor.mcmd_ap   -> scoreboard.act_mcmd_fifo
master_monitor.mdata_ap -> scoreboard.act_mdata_fifo
slave_monitor.mcmd_ap   -> slave_driver.mcmd_fifo
```

### 11.3 当前项目中可复用的做法

- 使用 `sim_pkg.sv` 统一 class include 顺序；
- `tb_top` 通过 `uvm_config_db` 下发 virtual interface；
- directed/random sequence 从同一个 base sequence 派生；
- directed/random test 从同一个 base test 派生；
- env 集中完成跨组件 TLM 连接；
- reference model 与 scoreboard 分离；
- scoreboard 同时检查 mismatch、零比较次数和 FIFO 残留；
- sequence 结束后保留 drain/timeout，而不是立即 drop objection；
- 功能覆盖率与 PASS/FAIL 判断分离。

### 11.4 后续项目不要直接复制的实现

| 当前实现 | 新项目要求 |
|---|---|
| ref model 从 driver analysis port 接收输入 | 增加 input monitor，从真实握手向 ref model 发布 |
| coverage 由 ref model 创建并直接调用 `sample()` | coverage 由 env 创建，通过 analysis port/export 连接 |
| base sequence 重复计算 expected 数量 | 完整性/完成计数放到 ref model 和 scoreboard |
| agent 在 build 中硬编码 active | 使用 agent config 控制 active/passive |
| interface 只有裸信号 | 增加 clocking block、modport 和协议 SVA |
| slave driver 是普通 `uvm_component` + monitor FIFO | 明确建模为 reactive agent，优先采用 reactive sequence/driver |
| `wait_for_idle()` 主要依赖 valid quiet-window | 优先使用事务 outstanding 归零并保留 timeout |
| transaction 位于 `env/` 根目录 | 按所属协议放到 agent 目录；真正全局类型放 `common/` |
| 旧 `dv/tb/tb.sv` 与 UVM 环境并存 | 新项目将 legacy TB 放 `legacy/` 或删除，避免两个入口混淆 |

---

## 12. package 与 filelist 规范

SystemVerilog 编译顺序固定为：

```text
1. interface
2. UVM package（package 内按类型依赖 include 所有 class）
3. bind/assertion module（若有）
4. DUT RTL/package/filelist
5. tb_top
```

具体顺序可因 RTL package 依赖调整，但必须满足“先声明、后使用”。同一个 class 文件只能通过一种方式编译：要么由 package `include`，要么由 filelist 单独编译，禁止两者同时使用造成重复定义。

filelist 必须显式包含所有 incdir，并使用相对项目根目录的稳定路径。新增文件后需要同时检查：

- package include 是否加入；
- include 顺序是否正确；
- filelist/incdir 是否覆盖；
- 类是否注册 factory；
- testcase 是否可由 `+UVM_TESTNAME` 找到。

---

## 13. 命名与编码约束

### 13.1 命名

| 类型 | 命名格式 |
|---|---|
| package | `<ip>_pkg` |
| interface | `<bus>_if` |
| transaction | `<bus>_item` 或 `<ip>_<channel>_item` |
| config | `<component>_cfg` |
| agent/driver/monitor/sequencer | `<bus>_<role>` |
| env/ref model/scoreboard/coverage | `<ip>_<role>` |
| sequence | `<ip>_<scenario>_sequence` |
| testcase | `<ip>_<scenario>_test` |

实例名去掉项目名前缀并保持语义明确，例如类 `pad_buf_master_agent` 的实例使用 `master_agent`。

### 13.2 编码

- 所有 UVM object/component 使用 factory `type_id::create()`；
- transaction 使用 `uvm_object_utils_*`，component 使用 `uvm_component_utils*`；
- build 中检查所有必需 config，缺失时 `uvm_fatal`；
- analysis port 在 constructor 创建，子 component 在 build 创建，TLM 连接在 connect 完成；
- monitor 发布后接收者如需长期保存，应 clone，避免句柄复用污染；
- 并发永久 task 使用 `fork...join` 或 `fork...join_none` 时明确生命周期；
- 所有无限等待必须有系统级 timeout 兜底；
- reset 行为必须在 driver、monitor、model、scoreboard 的设计中明确；
- 日志至少包含组件名、transaction 关键字段和仿真时间；
- 不用 `$display` 代替 UVM report 宏；
- 不在多个组件重复实现同一功能规则。

---

## 14. 新项目搭建顺序

按以下顺序实现，可以避免先写 testcase、后补 env 的结构性问题：

1. 从规格提取接口、握手、复位、事务字段和 testplan；
2. 创建目录、defines/types/config 和主 package；
3. 编写 interface、clocking block、modport 和基础 assertion；
4. 定义 transaction 及其合法约束；
5. 为每个协议接口实现 monitor；
6. 为主动接口实现 sequencer/driver，并组合成可配置 agent；
7. 实现 reference model 和 expected 输出；
8. 实现 scoreboard 的配对、比较、计数和残留检查；
9. 实现 coverage，并把 coverpoint 对应到 testplan；
10. 在 env 中实例化并连接所有组件，提供 `wait_for_done()`；
11. 实现 base sequence 和最小 smoke sequence；
12. 实现 base test 和 smoke test；
13. 编写 tb_top、filelist 和运行脚本，先跑通 smoke；
14. 再增加 directed、random、boundary、error、reset 和 stress 场景；
15. 最后建立 regression、seed 保存、coverage merge 和门禁。

在第 10 步之前不要大量生成 testcase；没有 env、monitor、reference model 和 scoreboard 的 testcase 只能“发激励”，不能形成可维护的自检环境。

---

## 15. AI 生成 UVM 代码时的强制提示词约束

后续让 AI 搭建环境时，可直接附加以下要求：

```text
请严格按本项目 UVM 目录和职责规范生成代码：
1. 必须先给出完整目录树、UVM topology、transaction 数据流和 TLM 连接表，再生成代码。
2. 必须包含 env；test 只能创建 env，禁止直接创建 driver/monitor/scoreboard。
3. base_sequence 只提供公共 transaction 发送能力；具体 sequence 只描述场景。
4. base_test 统一配置、reset、objection、timeout 和完成等待；具体 test 只选择 sequence 和差异配置。
5. driver 只驱动，monitor 只采样，reference model 只预测，scoreboard 只比较，coverage 只统计。
6. reference model 的输入来自 monitor 观察到的真实协议握手，不得直接使用 sequence 的意图作为已接受输入。
7. common 只放全局 defines、typedef/enum/struct、配置对象和主 package；不得放 testcase 业务逻辑。
8. agent 必须由 config 控制 active/passive；interface 必须有 clocking block 和 modport。
9. env 必须集中实例化组件和连接 TLM，并提供带 timeout 的事务级 wait_for_done()。
10. 每个文件生成前说明该文件职责、输入、输出、依赖以及明确不负责的内容。
11. 不得在多个组件中重复实现参考模型或 expected-count 算法。
12. 生成完成后给出 package include 顺序、filelist 顺序、新增 testcase 步骤和自检清单。
```

---

## 16. 评审检查清单

### 目录与依赖

- [ ] 存在明确的 `common/tb/agents/env/seq/tc` 分层；
- [ ] 全局 typedef、enum、struct、define 已集中到 `common`；
- [ ] 每个 transaction 归属于明确协议 agent；
- [ ] package include 和 filelist 没有重复编译；
- [ ] legacy TB 不会与 UVM top 同时作为入口。

### 职责边界

- [ ] env 实例化并连接所有 agent、model、scoreboard、coverage；
- [ ] test 不直接驱动 interface；
- [ ] sequence 不访问 DUT 层次和 virtual interface；
- [ ] driver 不做预测和比对；
- [ ] monitor 数据来自真实握手；
- [ ] reference model 输入来自 monitor；
- [ ] scoreboard 不重复 DUT 算法；
- [ ] coverage 不负责 PASS/FAIL。

### 配置与复用

- [ ] agent active/passive 由 config 控制；
- [ ] virtual interface 通过 config 对象或 `config_db` 下发；
- [ ] timeout、backpressure、feature enable 等无散乱硬编码；
- [ ] base class 只包含派生类真正共享的逻辑；
- [ ] 多 sequencer 时才创建 virtual sequencer/sequence。

### 正确性与结束

- [ ] scoreboard 检查 mismatch、unexpected、missing 和残留；
- [ ] 至少确认实际比较过一个或预期数量的事务；
- [ ] reset 会清理 driver/model/scoreboard 的挂起状态；
- [ ] 完成条件基于事务状态或 outstanding，而非单纯固定延时；
- [ ] 所有等待均有 timeout；
- [ ] testcase 可独立通过 `+UVM_TESTNAME` 运行；
- [ ] coverage point 能追溯到 testplan。

---

## 17. 一句话职责总结

```text
common 定义共同语言；
item 描述传什么；
sequence 决定传哪些；
sequencer 负责仲裁；
driver 决定怎么在引脚上传；
monitor 记录引脚上实际传了什么；
reference model 计算应该得到什么；
scoreboard 判断实际与预期是否一致；
coverage 判断计划中的场景是否被触达；
env 负责把组件组织和连接起来；
base_test 负责所有测试共有的生命周期；
testcase 只表达本测试与其他测试的差异；
tb_top 只负责静态硬件世界和启动 UVM。
```

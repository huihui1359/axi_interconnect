# 验证环境代码风格约定

本文约定适用于`dv`目录下新增和修改的SystemVerilog/UVM代码，以当前Stage 1实现形成的风格为基准。

## 1. 总体原则

- 优先保证逻辑直接、职责明确和容易阅读。
- 不增加当前功能不需要的状态、分支和防御性检查。
- 必要的配置、复位、对象和响应关联检查必须保留，并放在职责正确的组件中。
- 不在Driver中重复检查sequence已经确定的普通request字段；不要恢复`valid_stage1_request()`一类集中边界检查。
- 注释只说明设计意图、所有权或关键原因，不逐行复述代码。

## 2. 类、类型和方法组织

- 参数化类的默认宽度使用`axi_types_pkg`中的公共参数。
- 较长的参数化类型使用`typedef`定义本地简称，如`req_t`、`event_t`、`cfg_t`和`vif_t`。
- 类内依次放置类型定义、成员句柄/状态、UVM注册宏和方法原型。
- 非简单方法使用`extern`声明，实现放在同一文件的`endclass`之后。
- 内部task不使用`local`修饰，UVM phase方法保留`virtual`。
- 简短构造函数或简单build/connect方法允许直接写在类内；同一文件应保持统一，不在两种风格之间频繁切换。

```systemverilog
class axi_m_driver extends uvm_driver;
  typedef axi_req_item #(ADDR_WIDTH, DATA_WIDTH, ID_WIDTH, LEN_WIDTH) req_t;

  extern virtual task run_phase(uvm_phase phase);
  extern task drive_aw();
endclass

task axi_m_driver::drive_aw();
  // implementation
endtask
```

## 3. 接口访问和信号驱动

- 一个`axi_if`实例表示一个单端口AXI物理连接。
- 使用`m_drv_mp`、`s_drv_mp`和`mon_mp`直接约束访问方向，不使用带`input #1step`或`output #0`偏斜的clocking block。
- 组件通过`vif.signal`直接访问信号，时序操作统一使用`@(posedge vif.ACLK)`。
- Driver驱动接口信号使用非阻塞赋值。
- 一个信号只能由一个长期task负责驱动，Monitor只能采样，不能驱动接口。

```systemverilog
@(posedge vif.ACLK);
vif.awvalid <= 1'b1;
```

## 4. Item所有权和`item_done()`

- 在reset释放后再调用`get_next_item()`获取新item。
- Driver取得item后立即`clone()`为自己的快照，后续队列和接口驱动不得依赖sequence持有的原始对象。
- 快照必须在`item_done()`之前放入所有需要的mailbox；写request应同时放入AW和W队列。
- `get_next_item()`与`item_done()`必须一一对应，每个item只能完成一次。
- `item_done()`表示Driver已接收并保存事务，不表示AXI接口握手已经完成。
- Slave Driver对response item遵循同样规则：clone、入B/R队列、再`item_done()`。

## 5. Driver并发和握手

- AW、W、AR、B、R通道使用独立长期task，保持AXI通道独立推进。
- Master Driver的`write_busy/read_busy`表示是否存在等待B/R响应的请求，不表示正在向mailbox写数据。
- 长期线程只保留一个外层`forever`；允许用`while`等待reset释放或资源，用`do/while`等待当前VALID/READY握手，不嵌套第二个永久循环。
- VALID不得依赖READY才拉高；VALID拉高后保持VALID和payload稳定，直到握手或reset取消。
- READY的reset值和正常值在明确的`if/else`分支中分别赋值，不用复位比较表达式直接生成READY。
- 重复的输出清零操作提取为简短的`clear_*()` task。

## 6. Reset处理

- reset期间撤销Testbench主动驱动的VALID/READY并清零相应payload。
- 各通道task负责清理自己驱动的接口信号；`watch_reset()`只清理共享busy/ID状态和mailbox。
- reset发生时丢弃未完成快照，reset释放后不得自动重放旧事务。
- Monitor在reset期间不发布event；Slave Monitor同时清除未完成的AW/W请求重建状态。
- 不在同一路径重复检查reset。等待reset、握手退出和共享状态清理各自只保留一处清晰判断。

```systemverilog
forever begin
  @(posedge vif.ACLK);
  if (vif.ARESETn !== 1'b1)
    vif.bready <= 1'b0;
  else begin
    vif.bready <= 1'b1;
    // normal operation
  end
end
```

## 7. Monitor、event和TLM职责

- `axi_channel_event`表示接口上某个通道一次真实握手，是按beat发布的4-state观察对象，不代替完整request/response item。
- 每次握手创建新的event对象，只填写该通道有效字段；不得复用对象后修改已发布内容。
- Monitor只在`VALID===1'b1 && READY===1'b1`时发布event，同周期不同通道握手应分别发布。
- Master/Slave Monitor通过`channel_ap`发布event；Slave Monitor另通过`req_ap`发布由AW/W或AR重建的完整单拍request。
- Slave响应链保持为`monitor.req_ap → sequencer.request_fifo → reactive sequence → slave driver`，Monitor不直接调用Driver。
- analysis端接收对象后如果需要排队或延迟处理，必须clone后保存。

## 8. 检查职责

- Driver只保留运行必需的cfg/vif检查、Stage当前支持模式检查和B/R响应关联检查。
- Monitor负责真实握手观察和当前单拍请求重建检查，不承担端到端预期值生成。
- `axi_basic_event_comparator`只比较参数完全相同的event类型。
- `stage1_e2e_checker`负责当前M0到S0的转发、4/8-bit ID变换、响应返回和pending检查。
- 接口stall稳定性、X/Z协议检查和完整AXI规则应由专门assertion或组件测试支架承担，不在多个组件中重复实现。
- Stage限定检查只在确有运行需要时保留，能力扩展后及时删除或更新。

## 9. Agent、Test和文件组织

- active Agent创建Monitor、Sequencer和Driver；passive Agent只创建Monitor。
- 可复用组件放在`dv/env`，sequence放在`dv/seq`，测试与测试专用Checker放在`dv/tc`，interface和唯一顶层放在`dv/tb`。
- `axi_base_test`只完成cfg获取、env创建、reset等待和公共结果汇总。
- 每个具体testcase单独一个文件，只配置本用例数据、启动sequence并等待本用例检查完成。
- package文件作为统一编译、include、typedef和factory注册入口，不把所有testcase实现堆在一个文件中。
- 当前代码的详细结构、连接和能力边界以`dv/doc/stage1.md`为准。

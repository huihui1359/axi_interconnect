# 验证环境代码风格约定

本文约定适用于`dv`目录下新增和修改的SystemVerilog/UVM代码。

## 1. 总体原则

- 代码以逻辑直接、职责明确、容易阅读为优先。
- 不增加当前功能不需要的状态、分支和防御性检查。
- 避免重复代码和多层`forever/while/if`嵌套。
- 必要的协议、复位和对象有效性检查必须保留，但应放在职责正确的组件中。
- 注释说明设计意图或关键原因，不逐行复述代码。

## 2. 类和方法组织

- 类内保留成员、类型定义和方法原型。
- 方法使用`extern`声明，实现放在`endclass`之后，仍保留在同一个源码文件中。
- 内部task不使用`local`修饰。
- UVM phase方法保留`virtual`。

```systemverilog
class axi_m_driver extends uvm_driver;
  extern virtual task run_phase(uvm_phase phase);
  extern task drive_aw();
endclass

task axi_m_driver::drive_aw();
  // implementation
endtask
```

## 3. 接口访问

- `axi_if`使用modport直接封装信号方向，不使用带采样或驱动偏斜的clocking block。
- 组件通过`vif.signal`直接访问信号。
- 时序操作统一使用`@(posedge vif.ACLK)`。
- Driver驱动接口信号使用非阻塞赋值。

```systemverilog
@(posedge vif.ACLK);
vif.awvalid <= 1'b1;
```

## 4. Driver实现

- Driver负责接收item、保存必要快照并驱动接口，不承担过多事务能力边界检查。
- 请求字段错误由sequence/test约束、测试结果和对应检查组件定位。
- AW、W、AR、B、R通道保持独立线程，通道逻辑保持简单。
- VALID拉高后保持VALID和payload不变，直到READY握手或reset取消。
- 重复的信号清零操作提取为简短辅助task。
- `get_next_item()`与`item_done()`必须一一对应。

## 5. Reset处理

- 在获取新事务前等待reset释放。
- reset发生时撤销当前通道输出，并丢弃未完成事务，不在reset释放后重放。
- `watch_reset()`只负责清理共享状态和mailbox；各通道task负责自己的局部事务和输出信号。
- 永久运行线程优先使用一个`forever`，在每个时钟沿用`if/else`区分reset和正常逻辑。
- 避免在同一路径上重复确认reset。
- 协议控制信号的reset值和正常值必须在明确的`if/else`分支中分别赋值，不使用复位比较表达式直接赋值。

```systemverilog
forever begin
  @(posedge vif.ACLK);
  if (vif.ARESETn !== 1'b1)
    vif.bready <= 1'b0;
  else begin
    // normal operation
    vif.bready <= 1'b1;
  end
end
```

## 6. 检查职责

- Driver保留运行所必需的`cfg`、`vif`和响应关联检查。
- 接口时序与握手规范由assertion和Monitor检查。
- 端到端数据正确性由checker/scoreboard检查。
- 不在多个组件中重复实现同一项检查。
- Stage限定检查只在确有运行需求时实现，Stage扩展后及时删除或更新。

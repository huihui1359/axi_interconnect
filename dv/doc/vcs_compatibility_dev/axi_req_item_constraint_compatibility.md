# VCS 2018 约束函数兼容性调整说明

## 1. 调整范围

本次只调整了以下 SystemVerilog 文件：

```text
dv/env/axi_req_item.sv
```

调整对象是 `axi_req_item` 中写数据 strobe 合法性约束 `c_wstrb` 及其调用的 `calc_legal_wstrb_mask()` 函数。

## 2. 问题现象

使用 VCS `O-2018.09-SP2` 编译时，约束求解器报告：

```text
Error-[CSTR-UMC] Constraint: unsupported method call
Method calc_legal_wstrb_mask contains a construct not supported in
constraint functions: reference to a rand variable
```

原来的 `calc_legal_wstrb_mask()` 直接读取类中的以下 `rand` 成员：

- `size`
- `len`
- `addr`
- `burst`

较新的仿真器能够处理这种约束函数写法，但 VCS 2018 不支持约束函数通过对象成员间接读取这些随机变量。

## 3. 调整方法

修改前，约束只传入 beat 序号：

```systemverilog
calc_legal_wstrb_mask(i)
```

函数内部直接访问 `size`、`len`、`addr` 和 `burst`。

修改后，将这些约束输入显式传入函数：

```systemverilog
calc_legal_wstrb_mask(i, size, len, addr, burst)
```

函数形参对应为：

```systemverilog
int unsigned          beat_index,
bit [2:0]             size_value,
bit [LEN_WIDTH-1:0]   len_value,
bit [ADDR_WIDTH-1:0]  addr_value,
axi_burst_e           burst_value
```

函数内部使用这些形参完成原有的合法 WSTRB mask 计算。

## 4. 对设计语义的影响

该修改不改变约束逻辑和计算结果：

- 传入的实参仍是当前 `axi_req_item` 对象的同一组 `size/len/addr/burst` 字段。
- FIXED、INCR、WRAP 三类 burst 的地址计算公式没有改变。
- `wstrb` 允许置位的 byte lane 范围没有改变。
- 没有修改 DUT、driver、monitor、sequence 或 testcase 行为。

本质上，这只是把“函数隐式读取类成员”改为“函数通过参数显式读取相同的值”，用于适配旧版 VCS 约束求解器。

## 5. 验证结果

调整后已使用 VCS `O-2018.09-SP2` 完成以下验证：

```text
编译和 elaboration：通过
Testcase：axi_stage1_single_read_test
结果：AXI_TC_PASS
UVM_ERROR：0
UVM_FATAL：0
FSDB 波形生成：通过
```

对应的 VCS 编译与运行环境位于：

```text
sim_vcs/
```


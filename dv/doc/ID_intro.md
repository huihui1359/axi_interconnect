# AXI Interconnect ID映射说明

本文说明当前项目Master侧4-bit ID与Slave侧8-bit ID在五个AXI通道中的位段定义和映射关系。

## 1. 编号约定

Master和Slave均使用以下2-bit编号：

| 端口 | 编号 |
|---|---|
| M0 / S0 | `2'd1`（`2'b01`） |
| M1 / S1 | `2'd2`（`2'b10`） |
| M2 / S2 | `2'd3`（`2'b11`） |

`2'b00`不表示正常的M0～M2或S0～S2端口。

## 2. Master侧4-bit ID

Master侧AWID、WID、BID、ARID和RID均为4-bit：

```text
[3:2] 目标Slave编号
[1:0] 事务ID-tag
```

| 通道ID | 位段说明 |
|---|---|
| `M_AWID[3:2]` | AWADDR对应的目标Slave编号 |
| `M_AWID[1:0]` | 写事务ID-tag，可取`00`、`01`、`10`、`11` |
| `M_WID[3:2]` | 写数据对应的目标Slave编号 |
| `M_WID[1:0]` | 写事务ID-tag；同一写事务必须满足`M_WID == M_AWID` |
| `M_BID[3:0]` | 响应对应的原始Master写事务ID |
| `M_ARID[3:2]` | ARADDR对应的目标Slave编号 |
| `M_ARID[1:0]` | 读事务ID-tag，可取`00`、`01`、`10`、`11` |
| `M_RID[3:0]` | 响应对应的原始Master读事务ID |

各目标Slave对应的合法Master请求ID为：

| 目标Slave | 合法4-bit ID |
|---|---|
| S0 | `4'h4`～`4'h7`（`01_00`～`01_11`） |
| S1 | `4'h8`～`4'hB`（`10_00`～`10_11`） |
| S2 | `4'hC`～`4'hF`（`11_00`～`11_11`） |

## 3. Slave侧8-bit ID

Slave侧AWID、WID、BID、ARID和RID均为8-bit：

```text
[7:6] 实际目标Slave编号
[5:4] 请求来源Master编号
[3:0] 原始Master侧4-bit ID
        ├── [3:2] 目标Slave编号
        └── [1:0] 事务ID-tag
```

| 通道ID | 位段说明 |
|---|---|
| `S_AWID[7:6]` | 根据AWADDR地址映射得到的实际目标Slave编号 |
| `S_AWID[5:4]` | 请求来源Master编号 |
| `S_AWID[3:0]` | 原始`M_AWID` |
| `S_WID[7:6]` | 原始`M_WID[3:2]`携带的目标Slave编号 |
| `S_WID[5:4]` | 请求来源Master编号 |
| `S_WID[3:0]` | 原始`M_WID` |
| `S_BID[7:0]` | 对应写事务的完整Slave侧ID，应与该事务的AWID/WID一致 |
| `S_ARID[7:6]` | 根据ARADDR地址映射得到的实际目标Slave编号 |
| `S_ARID[5:4]` | 请求来源Master编号 |
| `S_ARID[3:0]` | 原始`M_ARID` |
| `S_RID[7:0]` | 对应读事务的完整Slave侧ID，应与该事务的ARID一致 |

正常请求必须满足：

```text
S_ID[7:6] == S_ID[3:2]
```

## 4. ID映射公式

```text
S_AWID = {address_slave_id, source_master_id, M_AWID}
S_WID  = {M_WID[3:2],      source_master_id, M_WID }
S_ARID = {address_slave_id, source_master_id, M_ARID}

M_BID  = S_BID[3:0]
M_RID  = S_RID[3:0]
```

响应返回时，RTL使用`S_BID/S_RID[5:4]`选择目标Master，并将`[3:0]`恢复为Master侧BID/RID。

## 5. 合法8-bit ID示例

下表列出不同Master访问不同Slave时的合法ID范围：

| 来源Master | 目标Slave | Master侧ID | Slave侧扩展ID |
|---|---|---|---|
| M0 | S0 | `4'h4`～`4'h7` | `8'h54`～`8'h57` |
| M1 | S0 | `4'h4`～`4'h7` | `8'h64`～`8'h67` |
| M2 | S0 | `4'h4`～`4'h7` | `8'h74`～`8'h77` |
| M0 | S1 | `4'h8`～`4'hB` | `8'h98`～`8'h9B` |
| M1 | S1 | `4'h8`～`4'hB` | `8'hA8`～`8'hAB` |
| M2 | S1 | `4'h8`～`4'hB` | `8'hB8`～`8'hBB` |
| M0 | S2 | `4'hC`～`4'hF` | `8'hDC`～`8'hDF` |
| M1 | S2 | `4'hC`～`4'hF` | `8'hEC`～`8'hEF` |
| M2 | S2 | `4'hC`～`4'hF` | `8'hFC`～`8'hFF` |

例如，M0使用ID-tag `2'b01`访问S0时：

```text
M_AWID/M_WID = 4'b01_01 = 4'h5
S_AWID/S_WID = 8'b01_01_0101 = 8'h55
S_BID         = 8'h55
M_BID         = 4'h5
```

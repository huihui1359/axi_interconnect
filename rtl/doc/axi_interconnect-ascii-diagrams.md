# AXI Interconnect 字符结构图与数据流说明

**Author**: Wang Jianghao, Codex, GPT-5.6-Solar
**Created**: 2026-10-04 20:10
**Current Version**: v1.1

**Version Changelog**:
- **v1.1** (2026-10-07 00:19): 澄清仲裁RUN/WAIT图仅为行为示意，实际保持状态已集中到round-robin的pending寄存器。
- **v1.0** (2026-10-04 20:10): 初版字符结构图与数据流说明，展示全局矩阵、读写路径、SID 布局、SID 表、反压、仲裁、FIFO 和 default slave 时序。

---

本文是学习辅助材料；完整契约和实现细节分别见架构、微架构文档。

## 1. 全局结构

```text
  Upstream initiators                    Interconnect                         Downstream targets

  M0 --+                       +----------------------------------+                   +-- S0
       |  M-side FIFOs         |             AXI CROSSBAR         |  S-side FIFOs     |
  M1 --+--> [AW/W/AR] -------->|  4 x request routers (M -> S)   |--> [AW/W/AR] -----+-- S1
       |<-- [ B/R  ] <---------|  3 x response routers (S -> M)  |<-- [ B/R  ] <-----+-- S2
  M2 --+                       |                                  |                   |
                               |  unmatched address -> DEFAULT    |<------------------+
                               +----------------+-----------------+
                                                |
                                  +-------------+-------------+
                                  |                           |
                             [AR SID x4]                  [AW SID x4]
                                  |                           |
                         R eligibility filter        W eligibility filter
```

## 2. 展开的路由矩阵

```text
 Request plane (each box arbitrates M0/M1/M2 independently)

 M0 AW/W/AR ----+----> [route S0] ----> S0 AW/W/AR
 M1 AW/W/AR ----+----> [route S1] ----> S1 AW/W/AR
 M2 AW/W/AR ----+----> [route S2] ----> S2 AW/W/AR
                +----> [route SD] ----> default slave

 Response plane (each box arbitrates S0/S1/S2/SD independently)

 S0 B/R ----+----> [route M0] ----> M0 B/R
 S1 B/R ----+----> [route M1] ----> M1 B/R
 S2 B/R ----+----> [route M2] ----> M2 B/R
 SD B/R ----+
```

这里“全连接”由并行观察和本地 mux 实现，不是一块集中式 3×3 数据 RAM。

## 3. 读事务数据流

```text
 AR request
 ==========

 Mx.AR
   |
   v
 [AR input FIFO, depth 4]
   |
   v
 address decode ---> target S0/S1/S2/default
   |
   v
 per-target 3-way round-robin
   |
   +---- create SID = {target_code, master_code, original_ARID}
   |
   +---- register SID in [AR outstanding table, 4 entries]
   |
   v
 [AR output FIFO, depth 4] ---> Sx.AR


 R response
 ==========

 Sx.R ---> [R input FIFO, depth 4]
   |
   +---- SID matches any AR-table entry? --no--> stall
   |                         |
   |                        yes (registered result)
   v                         v
 per-master 4-way round-robin and SID.MID route
   |
   +---- candidate RVALID & RLAST --> remove matching AR-table entry
   |     (current RTL does not include final FIFO ready)
   |
   v
 [R output FIFO, depth 4] ---> Mx.R (ID truncated to original ID)
```

## 4. 写事务数据流

```text
 AW path
 Mx.AW -> input FIFO -> address decode/arb -> extend SID
       -> add SID to AW-table -> output FIFO -> Sx.AW

 W path
 Mx.W  -> input FIFO -> build SID from {WID target bits, MID, WID}
       -> SID exists anywhere in AW-table?
              | no: stall
              | yes
              v
       target decode/arb -> output FIFO -> Sx.W
                                      |
                         candidate WVALID & WLAST removes SID
                         (even if final output FIFO is not ready)

 B path
 Sx.B  -> input FIFO -> decode SID.MID / 4-way arb
       -> output FIFO -> Mx.B (original ID only)
```

注意：AW 表没有把 W 限制为“只匹配最老一项”；任何槽命中都可通过。

## 5. 扩展 ID 布局（默认 8 位）

```text
 bit:       7       6 | 5       4 | 3                 0
          +-----------+-----------+---------------------+
 SID      | target ID | master ID | original AXI ID     |
          +-----------+-----------+---------------------+
              2 bits      2 bits          4 bits

 target ID: S0=01, S1=10, S2=11 (derived from base[14:13]+1)
 master ID: M0=01, M1=10, M2=11 (top-level constants)

 request routing uses target ID/address
 response routing uses master ID
 external response exposes original AXI ID
```

## 6. 4 项 SID 表

```text
 after pushes:       [ SID-A ][ SID-B ][ SID-C ][  0   ]

 clear SID-B:        compare all four entries in parallel
                              |
                              v
 after compaction:   [ SID-A ][ SID-C ][  0   ][  0   ]

 eligibility test:  candidate SID == slot0 OR slot1 OR slot2 OR slot3
                     (not candidate SID == slot0 only)
```

零值是空槽哨兵。push 和 clear 各自每拍最多选一路，优先级为端口 0、1、2。

## 7. 反压传播

```text
 Normal request backpressure:

 Sx not ready
   -> S-side FIFO cannot pop
   -> S-side FIFO eventually full
   -> crossbar target ready drops
   -> selected M-side FIFO cannot pop
   -> M-side FIFO eventually full
   -> M_AXI_*READY drops

 ID-resource backpressure:

 SID table full / clear conflict
   -> s_push_*id_rdy drops
   -> crossbar S_ARREADY/S_AWREADY is masked
   -> address path stalls upstream

 Invalid response/data ID:

 candidate SID not in outstanding table
   -> registered order_grant remains 0
   -> R or W route is ineligible
   -> corresponding FIFO eventually backpressures endpoint
```

## 8. 仲裁器状态

```text
                   grant exists AND downstream not ready
              +-------------------------------------------+
              |                                           v
          +-------+                                  +---------+
          |  RUN  |                                  |  WAIT   |
          | use   |                                  | hold    |
          | live  |                                  | saved   |
          | RR sel|                                  | grant   |
          +-------+                                  +---------+
              ^                                           |
              +-------------------------------------------+
                    saved grant valid && ready handshake
```

图中的RUN/WAIT是行为示意，不再对应wrapper中的显式FSM。AW、AR、W、B、R各自通过round-robin内部`pending_valid/pending_winner`实现同等保持；W/R在每个beat握手后释放pending，不保持到LAST。

## 9. FIFO 时序示意

```text
 cycle edge       N                 N+1                N+2
                  |                  |                  |
 wr_vld/rdy       1/1                x                  x
 action           write Mem[tail]    item now visible   possible pop
 rd_vld           0 before edge      1                  depends on pop
 rd_dout          invalid            first stored word  next word

 empty FIFO does not combinationally bypass wr_din to rd_dout.
 full FIFO does not accept a replacement push on the same edge as a pop.
```

## 10. Default slave

```text
 unmapped AW -> capture address/ID -> drain W beats -> B: DECERR
 unmapped AR -> capture address/ID -> emit ARLEN+1 R beats: DECERR, data=all-ones

 read and write FSMs are independent, so one default read and one default write
 may be active concurrently.
```

## 11. 建议学习顺序

```text
 top-level FIFOs
      |
      v
 axi_crossbar topology
      |
      +--> axi_mtos_m3: address/W target routing
      +--> axi_stom_s3: B/R return routing
      |
      v
 arbiter wrappers + round-robin primitives
      |
      v
 sid_buffer + reorder (outstanding eligibility, not strict reordering)
      |
      v
 default slave error path
```

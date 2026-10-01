# CODEBUDDY.md This file provides guidance to CodeBuddy when working with code in this repository.

> Scope: This analysis covers ONLY the digital front-end RTL design under `./rtl`. It is
> intended as foundational guidance for any future analysis, modification, or generation
> of RTL in this directory. Paths outside `./rtl` (e.g. `dv/`, `uvm_tb/`, `sim/`) are
> intentionally NOT covered here.

## 1. What this design is

A 3-master × 3-slave **AXI3** crossbar interconnect (plus a default slave). It decouples
timing with FIFOs, arbitrates between contending masters per slave, routes responses back
per master, and enforces transaction ordering for outstanding transfers using a small
reorder buffer (ROB). Fixed topology: 3 masters (M0/M1/M2, MIDs `01/10/11`), 3 slaves
(S0/S1/S2, 4 KB windows at `0x0000_0000`, `0x0000_2000`, `0x0000_4000`), AXI3 (4-bit
LEN → up to 16-beat bursts), 32-bit address/data, ID width 4, SID width 8.

## 2. Top-level data flow (`axi_interconnect.v`)

The top module is a thin wrapper that instantiates three logical layers and wires them:

```
 Masters ──► [FIFO layer] ──► [axi_crossbar] ──► [FIFO layer] ──► Slaves
 Slaves  ──◄ [FIFO layer] ──◄ [axi_crossbar] ──◄ [FIFO layer] ──◄ Masters
                                   │
                          [sid_buffer + reorder]  (read & write reordering)
```

Channel convention (each AXI channel gets a pair of FIFOs, one on the master-facing side
`*_mx`, one on the slave-facing side `*_sx`):
- `AR`: `fifo_ar_mx` (ID=4b) → crossbar → `fifo_ar_sx` (SID=8b)
- `AW`: `fifo_aw_mx` (4b) → crossbar → `fifo_aw_sx` (8b)
- `W` : `fifo_w_mx`  (4b) → crossbar → `fifo_w_sx`  (8b)
- `R` : slave→ `fifo_r_sx` (8b) → crossbar → `fifo_r_mx` (ID truncated to 4b via `M_RSID[3:0]`)
- `B` : slave→ `fifo_b_sx` (8b) → crossbar → `fifo_b_mx` (4b)

All FIFOs are `axi_fifo_sync` with `FAW=2` (4 entries), ready/valid handshake, FWFT
(first-word fall-through) style. The master-side FIFOs take the raw master ID (4b); the
slave-side FIFOs carry the widened SID (8b). The write into a slave-side FIFO is **gated**
by reorder-ready signals (see §5), so a transaction only enters the crossbar after it has
been accepted into the reorder buffer.

## 3. `axi_crossbar.v` — the routing/arbitration core

Instantiates:
- 3× `axi_mtos_m3` (slave targets S0/S1/S2, `SLAVE_DEFAULT=0`) — one per real slave.
- 1× `axi_mtos_m3` (default target SD, `SLAVE_DEFAULT=1`) — catches unmapped addresses.
- 1× `axi_default_slave` — generates DECERR responses for the SD target.
- 3× `axi_stom_s3` (master targets M0/M1/M2) — one per master, gathers all 4 slave replies.

Decode / select aggregation:
- Each non-default `axi_mtos_m3` emits `AWSELECT_OUT[i]` / `ARSELECT_OUT[i]` (3-bit, one
  bit per master) indicating which masters target that slave.
- These are OR-reduced across slaves into `AWSELECT` / `ARSELECT` (3-bit), which is fed
  **back** into the default-slave `axi_mtos_m3` as `AWSELECT_IN` / `ARSELECT_IN`. The
  default slave then selects only requests NOT claimed by any real slave
  (`AWSELECT = ~AWSELECT_IN & valid`).
- `M*_AWREADY/ARREADY/WREADY` are the OR of the per-slave ready bits
  (`M0_AWREADY = M0_AWREADY_S0|M0_AWREADY_S1|M0_AWREADY_S2|M0_AWREADY_SD`).
- `S*_BREADY/RREADY` are the OR of the per-master ready bits.

## 4. `axi_mtos_m3` (master→slave, "m-to-s") and `axi_stom_s3` (slave→master, "s-to-m")

**axi_mtos_m3** routes the 3 masters' AW/AR/W channels onto ONE slave.
- Decode (non-default): `AWSELECT[i] = (M{i}_AWADDR[WIDTH_AD-1:ADDR_LENGTH] == ADDR_BASE[...])`;
  `WSELECT[i]  = (M{i}_WID[3:2] == ADDR_BASE[14:13]+1)` (W channel has no address, so the
  slave is implied by `WID[3:2]`); `ARSELECT[i]` by ARADDR. For the default variant,
  decode is `~AWSELECT_IN & valid`.
- Builds a per-master bus: `bus_aw[i] = {ADDR_BASE[14:13]+1, M{i}_MID, M{i}_AWID, ...}`
  (so `S_AWID` = 8-bit SID). Write bus: `bus_w[i] = {M{i}_WID[3:2], M{i}_MID, M{i}_WID, ...}`.
  Read bus: `bus_ar[i] = {ADDR_BASE[14:13]+1, M{i}_MID, M{i}_ARID, ...}`.
- Arbitrates AW/W/AR among the 3 masters via `axi_arbiter_mtos_m3`; the granted bus drives
  the `S_*` outputs; `M{i}_*READY = GRANT[i] & S_*READY`.
- `w_order_grant` (from write reorder) gates `WSELECT` so write-data is only forwarded in
  an allowed order.

**axi_stom_s3** routes the 4 slave replies (S0/S1/S2/SD) of B and R back to ONE master.
- Decode: `BSELECT[i] = (S{i}_BID[WIDTH_ID+1:WIDTH_ID] == M_MID)` — i.e. compares the
  2-bit master-ID field inside the SID. `RSELECT` analogous. `RSELECT_in = RSELECT &
  {1'b1, r_order_grant}` (read ordering gate).
- Builds per-source `bus_b`/`bus_r`, arbitrates via `axi_arbiter_stom_s3`, drives `M_*`;
  `S{i}_*READY = GRANT[i] & M_*READY`. `M_RSID` passes the full 8-bit SID through so the
  master can match the response; `M_BID` is truncated to 4 bits.

## 5. Ordering / reorder mechanism (`sid_buffer.v` + `reorder.v`)

This is the trickiest part and the most error-prone to modify. It guarantees that:
(a) a slave response is only delivered to a master for an AR/AW that was actually accepted
(Outstanding-ID matching), and (b) the 4-deep ROB (defined by `ar_sid_buffer`/`aw_sid_buffer`,
each `[0:3]` of 8-bit SID) never overflows.

Read path:
- `u_ar_sid_buffer` captures the SID (`S_ARID`) of every accepted AR into the ROB when
  `S_ARVALID & S_ARREADY` and buffer has room (`s_push_srid_rdy`). It is cleared when the
  master acks the last read beat (`M_RLAST & M_RVALID` with `M_RSID`).
- `u_ar_reorder` compares incoming slave R IDs (`S_RID`) against the ROB and asserts
  `r_order_grant[2:0]` for the matching masters.
- Gating in top: `S_ARREADY_in = S_ARREADY & s_push_srid_rdy`;
  `fifo_ar_sx_vld = S_ARVALID & s_push_srid_rdy`;
  `M_RREADY_in = M_RREADY & m*_rsid_clr_rdy`; `fifo_r_mx_vld = M_RVALID & m*_rsid_clr_rdy`.

Write path:
- `u_aw_sid_buffer` captures `S_AWID` at AW accept, cleared by `S_WLAST & S_WVALID` with
  `S_WID`. `u_aw_reorder` reconstructs the expected SID as
  `{M_WID[i][3:2], M{i}_MID, M_WID[i]}` and asserts `w_order_grant[2:0]`.
- Gating: `S_AWREADY_in = S_AWREADY & s_push_swid_rdy`; `fifo_aw_sx_vld = S_AWVALID & s_push_swid_rdy`;
  `S_WREADY_in = S_WREADY & s*_wsid_clr_rdy`; `fifo_w_sx_vld = S_WVALID & s*_wsid_clr_rdy`.

`reorder.v` is a pure combinational matcher (SID ∈ ROB → grant). `sid_buffer.v` holds a
4-entry ROB with a `priority_sel` (fixed priority 0>1>2) for push and clear arbitration,
and a shift-delete on clear. `full = (sid_buffer[3] != 0)`.

## 6. Arbiters and round-robin

- `axi_arbiter_mtos_m3`: 3-way arbiters for AW/W/AR. Each = `round_robin_m2s` (3-bit) +
  a `RUN/WAIT` FSM. The FSM **holds** the grant (`*grant_reg`) when the handshake is not
  yet completed (`~(GRANT & *READY)`) so a higher-priority requester cannot preempt a
  transaction in progress. W arbiter input is `WSELECT_in = WSELECT & w_order_grant`.
- `axi_arbiter_stom_s3`: 4-way arbiters for B/R (`reg [NUM:0]` → 4 sources) using
  `round_robin_s2m` (4-bit) + same RUN/WAIT hold logic. R arbiter input is already gated
  by `r_order_grant` upstream in `axi_stom_s3`.
- `round_robin_m2s` / `round_robin_s2m`: rotating-priority arbiters. They remember
  `last_winner` and grant the next requester after it (wrapping), giving fairness. Pure
  combinational `curr_winner` from `last_winner`+`req`; `last_winner` updates only when a
  request is present.

## 7. `axi_default_slave.v`

Sinks requests that match no real slave. Returns `BRESP/RRESP = 2'b11` (DECERR), `RDATA=~0`.
Write FSM (`STW_IDLE/RUN/WAIT/RSP`) absorbs W beats until `WLAST` then emits one B. Read
FSM (`STR_IDLE/RUN/WAIT/END`) emits `ARLEN+1` error beats with `RLAST`. Wrapped in
`` `ifndef AXI_DEFAULT_SLAVE_V `` so it can be included once.

## 8. `axi_fifo_sync.v`

Generic synchronous FIFO: `FDW` data width, `FAW` → `1<<FAW` entries. Head/tail pointers +
`item_cnt`, `full`/`empty`, `rd_vld=~empty`, `wr_rdy=~full`. FWFT read
(`rd_dout = Mem[fifo_head]`). A `clr` port is present but commented out; reset is the only
flush path.

## 9. ID / SID encoding (critical for any edit)

8-bit SID = `{2-bit slave addr, 2-bit master ID, 4-bit txn ID}`.
- Slave addr field = `ADDR_BASE[14:13] + 1` (S0→01, S1→10, S2→11) on AR/AW; on W it is
  carried in `WID[3:2]` (set identically by `axi_mtos_m3`).
- Master ID field = `M{i}_MID` (01/10/11).
- Lower 4 bits = original master `AWID/ARID/WID`.
The 2-bit master-ID field (SID bits `[5:4]`) is what `axi_stom_s3` decodes to pick the
destination master. Keep this layout consistent whenever touching decode/routing.

## 10. Guidance for modification / generation

- Topology is **hardcoded** (3×3, `NUM_MASTER=3`, `NUM_SLAVE=3`, FIFO `FAW=2`). Making N×M
  requires parameterizing the generate loops and the `reg[...:0]`/`wire[...:0]` vectors,
  and generalizing `ADDR_BASE/LENGTH` arrays and the ROB depth.
- To add a slave: instantiate another `axi_mtos_m3` in `axi_crossbar`, wire its
  `AWSELECT_OUT/ARSELECT_OUT` into the OR-reduction, add its `S*_*` ports through the FIFO
  layer in `axi_interconnect`, and add another source to the matching `axi_stom_s3` calls.
- To change address map: edit `ADDR_BASE0/1/2` and `ADDR_LENGTH0/1/2` in `axi_crossbar`
  (these feed decode and SID slave-addr field). `ADDR_LENGTH` is the number of
  significant address bits.
- Never break the gating chain in §5 — the reorder-ready signals (`*_clr_rdy`,
  `*_push_rdy`) are what keep the ROB from overflowing and keep response/master mapping
  correct. If you add ordering rules, feed them through `w_order_grant`/`r_order_grant`.
- Arbitration fairness lives in `round_robin_*`. The RUN/WAIT hold FSM in `axi_arbiter_*`
  is what preserves in-flight handshake atomicity — do not remove it.
- AXI3 semantics: bursts ≤16 beats, separate WID per master, no AxLOCK/QoS. Validate
  `WLAST` counting and `BID`/`RID` field extraction if widths change.

## 11. Build / simulation commands

The RTL is plain Verilog-2001; compile with any SV-capable simulator. `rtl/filelist.f`
lists all modules (+ `sim/axi_interconnect_tb.v` testbench).

- **Compile + elaborate (VCS example):**
  `vcs -full64 -sverilog -timescale=1ns/1ps -f rtl/filelist.f -o simv`
  (TB uses `$fsdbDumpvars` → needs Verdi/fsdb; drop those lines for non-Synopsys sims.)
- **Run:**
  `./simv`  (simulation self-terminates via `$finish` after ~300 clock periods).
- **Icarus (open-source) alternative:**
  `iverilog -g2012 -f rtl/filelist.f -o axi_interconnect.vvp && vvp axi_interconnect.vvp`
- **Expected check:** the enabled TB section exercises write interleaving/reorder across
  M0/M1 to slave 0; watch `S_AXI_*` and `M_AXI_*` for correct B/R ordering and no ROB
  overflow. Lint: no built-in linter config in `./rtl`; rely on the simulator's
  `-lint`/`-Wall` if available.

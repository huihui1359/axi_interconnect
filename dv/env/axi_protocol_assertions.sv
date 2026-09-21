`ifndef AXI_PROTOCOL_ASSERTIONS_SV
`define AXI_PROTOCOL_ASSERTIONS_SV

import uvm_pkg::*;

module axi_protocol_assertions #(
  int unsigned ADDR_WIDTH       = 32,
  int unsigned DATA_WIDTH       = 32,
  int unsigned ID_WIDTH         = 4,
  int unsigned LEN_WIDTH        = 4,
  int unsigned MAX_OUTSTANDING  = 4,
  bit          TB_IS_MASTER     = 1'b1,
  bit          STAGE3_CHECKS    = 1'b0
) (
  input logic ACLK,
  input logic ARESETn,

  input logic [ID_WIDTH-1:0] awid,
  input logic [ADDR_WIDTH-1:0] awaddr,
  input logic [LEN_WIDTH-1:0] awlen,
  input logic [2:0] awsize,
  input logic [1:0] awburst,
  input logic awvalid,
  input logic awready,

  input logic [ID_WIDTH-1:0] wid,
  input logic [DATA_WIDTH-1:0] wdata,
  input logic [(DATA_WIDTH/8)-1:0] wstrb,
  input logic wlast,
  input logic wvalid,
  input logic wready,

  input logic [ID_WIDTH-1:0] bid,
  input logic [1:0] bresp,
  input logic bvalid,
  input logic bready,

  input logic [ID_WIDTH-1:0] arid,
  input logic [ADDR_WIDTH-1:0] araddr,
  input logic [LEN_WIDTH-1:0] arlen,
  input logic [2:0] arsize,
  input logic [1:0] arburst,
  input logic arvalid,
  input logic arready,

  input logic [ID_WIDTH-1:0] rid,
  input logic [DATA_WIDTH-1:0] rdata,
  input logic [1:0] rresp,
  input logic rlast,
  input logic rvalid,
  input logic rready
);

  localparam int unsigned ID_COUNT = 1 << ID_WIDTH;

  int unsigned aw_outstanding_by_id[ID_COUNT];
  int unsigned w_outstanding_by_id[ID_COUNT];
  int unsigned ar_outstanding_by_id[ID_COUNT];
  int unsigned aw_len_by_id[ID_COUNT][$];
  int unsigned completed_w_count_by_id[ID_COUNT][$];
  int unsigned ar_len_by_id[ID_COUNT][$];

  bit w_active;
  logic [ID_WIDTH-1:0] active_wid;
  int unsigned w_beat_count;
  bit r_active;
  logic [ID_WIDTH-1:0] active_rid;
  int unsigned active_rlen;
  int unsigned r_beat_count;
  int unsigned b_eligible_count;

  function void report_assertion_error(string report_id);
    uvm_report_error(report_id, "AXI protocol assertion failed");
  endfunction

  function automatic int unsigned write_outstanding();
    int unsigned total;
    total = 0;
    foreach (aw_outstanding_by_id[id])
      total += aw_outstanding_by_id[id];
    return total;
  endfunction

  function automatic int unsigned read_outstanding();
    int unsigned total;
    total = 0;
    foreach (ar_outstanding_by_id[id])
      total += ar_outstanding_by_id[id];
    return total;
  endfunction

  function automatic bit valid_stage3_id(logic [ID_WIDTH-1:0] id);
    longint unsigned id_value;
    if ($isunknown(id))
      return 1'b0;
    id_value = longint'(id);
    if (ID_WIDTH == 4)
      return ((id_value >> 2) & 2'b11) == 2'b01;
    if (ID_WIDTH == 8)
      return (((id_value >> 6) & 2'b11) == 2'b01) &&
             (((id_value >> 4) & 2'b11) == 2'b01) &&
             (((id_value >> 2) & 2'b11) == 2'b01);
    return 1'b1;
  endfunction

  function automatic bit valid_stage3_master_tag(
    logic [ID_WIDTH-1:0] id
  );
    longint unsigned id_value;
    if ($isunknown(id))
      return 1'b0;
    id_value = longint'(id);
    if (ID_WIDTH == 8)
      return ((id_value >> 4) & 2'b11) == 2'b01;
    return 1'b1;
  endfunction

  function automatic bit valid_stage3_slave_tag(
    logic [ID_WIDTH-1:0] id
  );
    longint unsigned id_value;
    if ($isunknown(id))
      return 1'b0;
    id_value = longint'(id);
    if (ID_WIDTH == 8)
      return (((id_value >> 6) & 2'b11) ==
              ((id_value >> 2) & 2'b11));
    return 1'b1;
  endfunction

  function automatic void pair_write_context(int unsigned id);
    int unsigned expected_count;
    int unsigned observed_count;
    if ((aw_len_by_id[id].size() == 0) ||
        (completed_w_count_by_id[id].size() == 0))
      return;

    expected_count = aw_len_by_id[id].pop_front() + 1;
    observed_count = completed_w_count_by_id[id].pop_front();
    assert (observed_count == expected_count)
      else report_assertion_error("AXI_ASSERT_W_COUNT");
  endfunction

  property p_aw_stable;
    @(posedge ACLK) disable iff (ARESETn !== 1'b1)
      awvalid && !awready |=>
        awvalid && $stable({awid, awaddr, awlen, awsize, awburst});
  endproperty

  property p_w_stable;
    @(posedge ACLK) disable iff (ARESETn !== 1'b1)
      wvalid && !wready |=>
        wvalid && $stable({wid, wdata, wstrb, wlast});
  endproperty

  property p_b_stable;
    @(posedge ACLK) disable iff (ARESETn !== 1'b1)
      bvalid && !bready |=> bvalid && $stable({bid, bresp});
  endproperty

  property p_b_causality;
    @(posedge ACLK) disable iff (ARESETn !== 1'b1)
      bvalid |-> ((b_eligible_count != 0) ||
                  (wvalid && wready && wlast));
  endproperty

  property p_ar_stable;
    @(posedge ACLK) disable iff (ARESETn !== 1'b1)
      arvalid && !arready |=>
        arvalid && $stable({arid, araddr, arlen, arsize, arburst});
  endproperty

  property p_r_stable;
    @(posedge ACLK) disable iff (ARESETn !== 1'b1)
      rvalid && !rready |=>
        rvalid && $stable({rid, rdata, rresp, rlast});
  endproperty

  assert property (p_aw_stable)
    else report_assertion_error("AXI_ASSERT_AW_STABLE");
  assert property (p_w_stable)
    else report_assertion_error("AXI_ASSERT_W_STABLE");
  assert property (p_b_stable)
    else report_assertion_error("AXI_ASSERT_B_STABLE");
  assert property (p_b_causality)
    else report_assertion_error("AXI_ASSERT_B_CAUSALITY");
  assert property (p_ar_stable)
    else report_assertion_error("AXI_ASSERT_AR_STABLE");
  assert property (p_r_stable)
    else report_assertion_error("AXI_ASSERT_R_STABLE");

  generate
    if (TB_IS_MASTER) begin : master_reset_outputs
      property p_master_outputs_reset;
        @(posedge ACLK)
          ARESETn === 1'b0 |->
            !awvalid && !wvalid && !bready && !arvalid && !rready;
      endproperty
      assert property (p_master_outputs_reset)
        else report_assertion_error("AXI_ASSERT_MASTER_RESET_OUTPUTS");
    end
    else begin : slave_reset_outputs
      property p_slave_outputs_reset;
        @(posedge ACLK)
          ARESETn === 1'b0 |->
            !awready && !wready && !bvalid && !arready && !rvalid;
      endproperty
      assert property (p_slave_outputs_reset)
        else report_assertion_error("AXI_ASSERT_SLAVE_RESET_OUTPUTS");
    end
  endgenerate

  always @(posedge ACLK) begin
    int unsigned id;
    int unsigned current_count;
    int unsigned expected_count;

    if (ARESETn !== 1'b1) begin
      foreach (aw_outstanding_by_id[index]) begin
        aw_outstanding_by_id[index] = 0;
        w_outstanding_by_id[index]  = 0;
        ar_outstanding_by_id[index] = 0;
        aw_len_by_id[index].delete();
        completed_w_count_by_id[index].delete();
        ar_len_by_id[index].delete();
      end
      w_active        = 1'b0;
      active_wid      = '0;
      w_beat_count    = 0;
      r_active        = 1'b0;
      active_rid      = '0;
      active_rlen     = 0;
      r_beat_count    = 0;
      b_eligible_count = 0;
    end
    else begin
      assert (!$isunknown({awvalid, awready, wvalid, wready,
                           bvalid, bready, arvalid, arready,
                           rvalid, rready}))
        else report_assertion_error("AXI_ASSERT_CONTROL_X");

      if (awvalid && awready) begin
        assert (!$isunknown({awid, awaddr, awlen, awsize, awburst}))
          else report_assertion_error("AXI_ASSERT_AW_PAYLOAD_X");
        if (!$isunknown(awid)) begin
          id = int'(awid);
          aw_outstanding_by_id[id]++;
          aw_len_by_id[id].push_back(int'(awlen));
          pair_write_context(id);
          if (STAGE3_CHECKS) begin
            assert (valid_stage3_id(awid))
              else report_assertion_error("AXI_ASSERT_AW_ID");
            assert (valid_stage3_master_tag(awid))
              else report_assertion_error("AXI_ASSERT_AW_MASTER_TAG");
            assert (valid_stage3_slave_tag(awid))
              else report_assertion_error("AXI_ASSERT_AW_SLAVE_TAG");
          end
        end
      end

      if (wvalid && wready) begin
        assert (!$isunknown({wid, wdata, wstrb, wlast}))
          else report_assertion_error("AXI_ASSERT_W_PAYLOAD_X");
        if (!$isunknown(wid)) begin
          id = int'(wid);
          if (!w_active) begin
            w_active     = 1'b1;
            active_wid   = wid;
            w_beat_count = 0;
          end
          else begin
            assert (wid === active_wid)
              else report_assertion_error("AXI_ASSERT_WID_STABLE");
          end

          current_count = w_beat_count + 1;
          w_beat_count  = current_count;
          if (aw_len_by_id[id].size() != 0) begin
            expected_count = aw_len_by_id[id][0] + 1;
            if (current_count < expected_count)
              assert (!wlast)
                else report_assertion_error("AXI_ASSERT_WLAST_EARLY");
            else if (current_count == expected_count)
              assert (wlast)
                else report_assertion_error("AXI_ASSERT_WLAST_MISSING");
            else
              assert (1'b0)
                else report_assertion_error("AXI_ASSERT_W_COUNT_EXCESS");
          end

          if (wlast) begin
            completed_w_count_by_id[id].push_back(current_count);
            w_outstanding_by_id[id]++;
            b_eligible_count++;
            pair_write_context(id);
            w_active     = 1'b0;
            w_beat_count = 0;
          end
          if (STAGE3_CHECKS) begin
            assert (valid_stage3_id(wid))
              else report_assertion_error("AXI_ASSERT_W_ID");
            assert (valid_stage3_master_tag(wid))
              else report_assertion_error("AXI_ASSERT_W_MASTER_TAG");
            assert (valid_stage3_slave_tag(wid))
              else report_assertion_error("AXI_ASSERT_W_SLAVE_TAG");
          end
        end
      end

      if (arvalid && arready) begin
        assert (!$isunknown({arid, araddr, arlen, arsize, arburst}))
          else report_assertion_error("AXI_ASSERT_AR_PAYLOAD_X");
        if (!$isunknown(arid)) begin
          id = int'(arid);
          ar_outstanding_by_id[id]++;
          ar_len_by_id[id].push_back(int'(arlen));
          if (STAGE3_CHECKS) begin
            assert (valid_stage3_id(arid))
              else report_assertion_error("AXI_ASSERT_AR_ID");
            assert (valid_stage3_master_tag(arid))
              else report_assertion_error("AXI_ASSERT_AR_MASTER_TAG");
            assert (valid_stage3_slave_tag(arid))
              else report_assertion_error("AXI_ASSERT_AR_SLAVE_TAG");
          end
        end
      end

      if (bvalid && bready) begin
        assert (!$isunknown({bid, bresp}))
          else report_assertion_error("AXI_ASSERT_B_PAYLOAD_X");
        if (!$isunknown(bid)) begin
          id = int'(bid);
          if (STAGE3_CHECKS) begin
            assert (valid_stage3_id(bid))
              else report_assertion_error("AXI_ASSERT_B_ID");
            assert (valid_stage3_master_tag(bid))
              else report_assertion_error("AXI_ASSERT_B_MASTER_TAG");
            assert (valid_stage3_slave_tag(bid))
              else report_assertion_error("AXI_ASSERT_B_SLAVE_TAG");
            if ((aw_outstanding_by_id[id] == 0) &&
                (w_outstanding_by_id[id] == 0)) begin
              assert (1'b0)
                else report_assertion_error("AXI_ASSERT_B_NO_PENDING");
            end
            else begin
              assert (aw_outstanding_by_id[id] != 0)
                else report_assertion_error("AXI_ASSERT_B_AW_UNDERFLOW");
              assert (w_outstanding_by_id[id] != 0)
                else report_assertion_error("AXI_ASSERT_B_SAME_ID_ORDER");
            end
          end
          if (aw_outstanding_by_id[id] != 0)
            aw_outstanding_by_id[id]--;
          if (w_outstanding_by_id[id] != 0)
            w_outstanding_by_id[id]--;
          if (b_eligible_count != 0)
            b_eligible_count--;
        end
      end

      if (rvalid && rready) begin
        assert (!$isunknown({rid, rdata, rresp, rlast}))
          else report_assertion_error("AXI_ASSERT_R_PAYLOAD_X");
        if (!$isunknown(rid)) begin
          id = int'(rid);
          if (!r_active) begin
            assert (ar_len_by_id[id].size() != 0)
              else report_assertion_error("AXI_ASSERT_R_CAUSALITY");
            if (ar_len_by_id[id].size() != 0) begin
              r_active     = 1'b1;
              active_rid   = rid;
              active_rlen  = ar_len_by_id[id][0];
              r_beat_count = 0;
            end
          end
          else begin
            assert (rid === active_rid)
              else report_assertion_error("AXI_ASSERT_RID_STABLE");
          end

          if (r_active) begin
            current_count = r_beat_count + 1;
            expected_count = active_rlen + 1;
            r_beat_count = current_count;
            if (current_count < expected_count)
              assert (!rlast)
                else report_assertion_error("AXI_ASSERT_RLAST_EARLY");
            else if (current_count == expected_count)
              assert (rlast)
                else report_assertion_error("AXI_ASSERT_RLAST_MISSING");
            else
              assert (1'b0)
                else report_assertion_error("AXI_ASSERT_R_COUNT_EXCESS");

            if (rlast) begin
              id = int'(active_rid);
              if (ar_len_by_id[id].size() != 0)
                expected_count = ar_len_by_id[id].pop_front();
              if (ar_outstanding_by_id[id] == 0)
                assert (1'b0)
                  else report_assertion_error("AXI_ASSERT_R_UNDERFLOW");
              else
                ar_outstanding_by_id[id]--;
              r_active     = 1'b0;
              r_beat_count = 0;
            end
          end
          if (STAGE3_CHECKS) begin
            assert (valid_stage3_id(rid))
              else report_assertion_error("AXI_ASSERT_R_ID");
            assert (valid_stage3_master_tag(rid))
              else report_assertion_error("AXI_ASSERT_R_MASTER_TAG");
            assert (valid_stage3_slave_tag(rid))
              else report_assertion_error("AXI_ASSERT_R_SLAVE_TAG");
          end
        end
      end

      if (STAGE3_CHECKS) begin
        assert (write_outstanding() <= MAX_OUTSTANDING)
          else report_assertion_error("AXI_ASSERT_WRITE_OUTSTANDING");
        assert (read_outstanding() <= MAX_OUTSTANDING)
          else report_assertion_error("AXI_ASSERT_READ_OUTSTANDING");
      end
    end
  end

endmodule

`endif

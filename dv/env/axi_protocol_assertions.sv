`ifndef AXI_PROTOCOL_ASSERTIONS_SV
`define AXI_PROTOCOL_ASSERTIONS_SV

import uvm_pkg::*;

module axi_protocol_assertions #(
  int unsigned ADDR_WIDTH   = 32,
  int unsigned DATA_WIDTH   = 32,
  int unsigned ID_WIDTH     = 4,
  int unsigned LEN_WIDTH    = 4,
  bit          TB_IS_MASTER = 1'b1
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

  bit aw_seen;
  bit w_active;
  bit w_complete;
  bit write_wait_b;
  logic [ID_WIDTH-1:0] observed_awid;
  logic [LEN_WIDTH-1:0] observed_awlen;
  logic [ID_WIDTH-1:0] observed_wid;
  int unsigned w_beat_count;

  bit read_active;
  logic [ID_WIDTH-1:0] observed_arid;
  logic [LEN_WIDTH-1:0] observed_arlen;
  int unsigned r_beat_count;

  function void report_assertion_error(string report_id);
    uvm_report_error(report_id, "AXI protocol assertion failed");
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
    int unsigned current_w_count;
    int unsigned expected_w_count;
    int unsigned current_r_count;
    int unsigned expected_r_count;

    if (ARESETn !== 1'b1) begin
      aw_seen       = 1'b0;
      w_active      = 1'b0;
      w_complete    = 1'b0;
      write_wait_b  = 1'b0;
      observed_awid = '0;
      observed_awlen = '0;
      observed_wid  = '0;
      w_beat_count  = 0;
      read_active   = 1'b0;
      observed_arid = '0;
      observed_arlen = '0;
      r_beat_count  = 0;
    end
    else begin
      assert (!$isunknown({awvalid, awready, wvalid, wready,
                           bvalid, bready, arvalid, arready,
                           rvalid, rready}))
        else report_assertion_error("AXI_ASSERT_CONTROL_X");

      if (awvalid && awready) begin
        assert (!$isunknown({awid, awaddr, awlen, awsize, awburst}))
          else report_assertion_error("AXI_ASSERT_AW_PAYLOAD_X");
        assert (!aw_seen && !write_wait_b)
          else report_assertion_error("AXI_ASSERT_AW_OUTSTANDING");
        aw_seen        = 1'b1;
        observed_awid  = awid;
        observed_awlen = awlen;

        if (w_complete) begin
          assert (observed_wid === awid)
            else report_assertion_error("AXI_ASSERT_WID_AWID");
          assert (w_beat_count == (int'(awlen) + 1))
            else report_assertion_error("AXI_ASSERT_W_COUNT");
          aw_seen      = 1'b0;
          w_active     = 1'b0;
          w_complete   = 1'b0;
          w_beat_count = 0;
          write_wait_b = 1'b1;
        end
        else if (w_active &&
                 (w_beat_count >= (int'(awlen) + 1))) begin
          if (w_beat_count == (int'(awlen) + 1))
            assert (1'b0)
              else report_assertion_error("AXI_ASSERT_WLAST_MISSING");
          else
            assert (1'b0)
              else report_assertion_error("AXI_ASSERT_W_COUNT_EXCESS");
        end
      end

      if (wvalid && wready) begin
        assert (!$isunknown({wid, wdata, wstrb, wlast}))
          else report_assertion_error("AXI_ASSERT_W_PAYLOAD_X");
        assert (!write_wait_b)
          else report_assertion_error("AXI_ASSERT_W_OUTSTANDING");

        if (!w_active) begin
          w_active     = 1'b1;
          observed_wid = wid;
        end
        else begin
          assert (wid === observed_wid)
            else report_assertion_error("AXI_ASSERT_WID_STABLE");
        end

        current_w_count = w_beat_count + 1;
        w_beat_count    = current_w_count;
        if (aw_seen) begin
          expected_w_count = int'(observed_awlen) + 1;
          if (current_w_count < expected_w_count)
            assert (!wlast)
              else report_assertion_error("AXI_ASSERT_WLAST_EARLY");
          else if (current_w_count == expected_w_count)
            assert (wlast)
              else report_assertion_error("AXI_ASSERT_WLAST_MISSING");
          else
            assert (1'b0)
              else report_assertion_error("AXI_ASSERT_W_COUNT_EXCESS");
        end

        if (wlast) begin
          w_complete = 1'b1;
          if (aw_seen) begin
            assert (observed_wid === observed_awid)
              else report_assertion_error("AXI_ASSERT_WID_AWID");
            assert (current_w_count == (int'(observed_awlen) + 1))
              else report_assertion_error("AXI_ASSERT_W_COUNT");
            aw_seen      = 1'b0;
            w_active     = 1'b0;
            w_complete   = 1'b0;
            w_beat_count = 0;
            write_wait_b = 1'b1;
          end
        end
      end

      if (bvalid && bready) begin
        assert (!$isunknown({bid, bresp}))
          else report_assertion_error("AXI_ASSERT_B_PAYLOAD_X");
        assert (write_wait_b)
          else report_assertion_error("AXI_ASSERT_B_CAUSALITY");
        write_wait_b = 1'b0;
      end

      if (arvalid && arready) begin
        assert (!$isunknown({arid, araddr, arlen, arsize, arburst}))
          else report_assertion_error("AXI_ASSERT_AR_PAYLOAD_X");
        assert (!read_active)
          else report_assertion_error("AXI_ASSERT_AR_OUTSTANDING");
        read_active    = 1'b1;
        observed_arid  = arid;
        observed_arlen = arlen;
        r_beat_count   = 0;
      end

      if (rvalid && rready) begin
        assert (!$isunknown({rid, rdata, rresp, rlast}))
          else report_assertion_error("AXI_ASSERT_R_PAYLOAD_X");
        assert (read_active)
          else report_assertion_error("AXI_ASSERT_R_CAUSALITY");

        if (read_active) begin
          assert (rid === observed_arid)
            else report_assertion_error("AXI_ASSERT_RID_ARID");
          current_r_count  = r_beat_count + 1;
          expected_r_count = int'(observed_arlen) + 1;
          r_beat_count     = current_r_count;

          if (current_r_count < expected_r_count)
            assert (!rlast)
              else report_assertion_error("AXI_ASSERT_RLAST_EARLY");
          else if (current_r_count == expected_r_count)
            assert (rlast)
              else report_assertion_error("AXI_ASSERT_RLAST_MISSING");
          else
            assert (1'b0)
              else report_assertion_error("AXI_ASSERT_R_COUNT_EXCESS");

          if (rlast) begin
            read_active  = 1'b0;
            r_beat_count = 0;
          end
        end
      end
    end
  end

endmodule

`endif

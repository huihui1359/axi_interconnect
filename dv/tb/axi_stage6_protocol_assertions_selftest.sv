`timescale 1ns/1ps

module axi_stage6_protocol_assertions_selftest;
  import uvm_pkg::*;

  class stage6_assertion_report_catcher extends uvm_report_catcher;
    bit illegal_master_tag_seen;
    bit physical_slave_tag_seen;
    bit route_mismatch_seen;
    int unsigned unexpected_count;
    virtual function action_e catch();
      string report_id;
      if (get_severity() != UVM_ERROR) return THROW;
      report_id = get_id();
      case (report_id)
        "AXI_ASSERT_AW_MASTER_TAG": illegal_master_tag_seen = 1'b1;
        "AXI_ASSERT_AW_ID": physical_slave_tag_seen = 1'b1;
        "AXI_ASSERT_AW_ROUTE": route_mismatch_seen = 1'b1;
        "AXI_ASSERT_AW_SLAVE_TAG": begin end
        default: unexpected_count++;
      endcase
      return CAUGHT;
    endfunction
  endclass

  logic ACLK, ARESETn;
  logic [7:0] awid, wid, bid, arid, rid;
  logic [31:0] awaddr, wdata, araddr, rdata;
  logic [3:0] awlen, arlen, wstrb;
  logic [2:0] awsize, arsize;
  logic [1:0] awburst, bresp, arburst, rresp;
  logic awvalid, awready, wlast, wvalid, wready;
  logic bvalid, bready, arvalid, arready, rlast, rvalid, rready;
  stage6_assertion_report_catcher report_catcher;

  axi_protocol_assertions #(
    .ADDR_WIDTH(32), .DATA_WIDTH(32), .ID_WIDTH(8), .LEN_WIDTH(4),
    .MAX_OUTSTANDING(4), .TB_IS_MASTER(1'b0),
    .STAGE3_CHECKS(1'b1), .STAGE6_CHECKS(1'b1), .PORT_INDEX(2)
  ) dut (.*);

  always #5ns ACLK = ~ACLK;

  task clear_signals();
    awid='0; awaddr='0; awlen='0; awsize=2; awburst=1;
    awvalid=0; awready=0; wid='0; wdata='0; wstrb='1;
    wlast=0; wvalid=0; wready=0; bid='0; bresp='0;
    bvalid=0; bready=0; arid='0; araddr='0; arlen='0;
    arsize=2; arburst=1; arvalid=0; arready=0;
    rid='0; rdata='0; rresp='0; rlast=0; rvalid=0; rready=0;
  endtask

  task reset_state();
    @(negedge ACLK); clear_signals(); ARESETn=0;
    repeat (2) @(posedge ACLK);
    @(negedge ACLK); ARESETn=1;
  endtask

  task pulse_aw(bit [7:0] id, bit [31:0] address);
    awid=id; awaddr=address; awvalid=1; awready=1;
    @(posedge ACLK); @(negedge ACLK); awvalid=0; awready=0;
  endtask

  initial begin
    ACLK=0; ARESETn=0; clear_signals();
    report_catcher = new();
    uvm_report_cb::add(null, report_catcher);

    reset_state(); pulse_aw(8'hec, 32'h0000_4100);
    reset_state(); pulse_aw(8'h9c, 32'h0000_2100);
    reset_state(); pulse_aw(8'hcc, 32'h0000_4100);
    reset_state(); pulse_aw(8'hec, 32'h0000_2100);
    repeat (2) @(posedge ACLK);

    if (!report_catcher.illegal_master_tag_seen ||
        !report_catcher.physical_slave_tag_seen ||
        !report_catcher.route_mismatch_seen ||
        (report_catcher.unexpected_count != 0))
      $fatal(1, "Stage 6 protocol assertion self-test missed a check");
    $display("AXI_STAGE6_ASSERT_SELFTEST_PASS");
    $finish;
  end
endmodule

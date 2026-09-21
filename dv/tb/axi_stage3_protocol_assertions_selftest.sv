`timescale 1ns/1ps

module axi_stage3_protocol_assertions_selftest;

  import uvm_pkg::*;

  class stage3_assertion_report_catcher extends uvm_report_catcher;
    bit b_no_pending_seen;
    bit r_no_pending_seen;
    bit same_id_order_seen;
    bit rid_change_seen;
    bit wid_change_seen;
    bit outstanding_seen;
    bit master_tag_seen;
    bit slave_tag_seen;
    int unsigned unexpected_count;

    virtual function action_e catch();
      string report_id;
      if (get_severity() != UVM_ERROR)
        return THROW;

      report_id = get_id();
      case (report_id)
        "AXI_ASSERT_B_NO_PENDING":
          b_no_pending_seen = 1'b1;
        "AXI_ASSERT_R_CAUSALITY":
          r_no_pending_seen = 1'b1;
        "AXI_ASSERT_B_SAME_ID_ORDER":
          same_id_order_seen = 1'b1;
        "AXI_ASSERT_RID_STABLE":
          rid_change_seen = 1'b1;
        "AXI_ASSERT_WID_STABLE":
          wid_change_seen = 1'b1;
        "AXI_ASSERT_READ_OUTSTANDING":
          outstanding_seen = 1'b1;
        "AXI_ASSERT_AW_MASTER_TAG":
          master_tag_seen = 1'b1;
        "AXI_ASSERT_AW_SLAVE_TAG":
          slave_tag_seen = 1'b1;
        "AXI_ASSERT_B_CAUSALITY",
        "AXI_ASSERT_AW_ID": begin
        end
        default: begin
          unexpected_count++;
          $display("UNEXPECTED_STAGE3_ASSERTION_ID %s", report_id);
        end
      endcase
      return CAUGHT;
    endfunction
  endclass

  logic ACLK;
  logic ARESETn;
  logic [7:0] awid;
  logic [31:0] awaddr;
  logic [3:0] awlen;
  logic [2:0] awsize;
  logic [1:0] awburst;
  logic awvalid;
  logic awready;
  logic [7:0] wid;
  logic [31:0] wdata;
  logic [3:0] wstrb;
  logic wlast;
  logic wvalid;
  logic wready;
  logic [7:0] bid;
  logic [1:0] bresp;
  logic bvalid;
  logic bready;
  logic [7:0] arid;
  logic [31:0] araddr;
  logic [3:0] arlen;
  logic [2:0] arsize;
  logic [1:0] arburst;
  logic arvalid;
  logic arready;
  logic [7:0] rid;
  logic [31:0] rdata;
  logic [1:0] rresp;
  logic rlast;
  logic rvalid;
  logic rready;

  stage3_assertion_report_catcher report_catcher;

  axi_protocol_assertions #(
    .ADDR_WIDTH(32),
    .DATA_WIDTH(32),
    .ID_WIDTH(8),
    .LEN_WIDTH(4),
    .MAX_OUTSTANDING(4),
    .TB_IS_MASTER(1'b0),
    .STAGE3_CHECKS(1'b1)
  ) dut (.*);

  always #5ns ACLK = ~ACLK;

  task clear_signals();
    awid = '0; awaddr = '0; awlen = '0; awsize = 3'd2;
    awburst = 2'b01; awvalid = 1'b0; awready = 1'b0;
    wid = '0; wdata = '0; wstrb = '1; wlast = 1'b0;
    wvalid = 1'b0; wready = 1'b0;
    bid = '0; bresp = '0; bvalid = 1'b0; bready = 1'b0;
    arid = '0; araddr = '0; arlen = '0; arsize = 3'd2;
    arburst = 2'b01; arvalid = 1'b0; arready = 1'b0;
    rid = '0; rdata = '0; rresp = '0; rlast = 1'b0;
    rvalid = 1'b0; rready = 1'b0;
  endtask

  task reset_state();
    @(negedge ACLK);
    clear_signals();
    ARESETn = 1'b0;
    repeat (2) @(posedge ACLK);
    @(negedge ACLK);
    ARESETn = 1'b1;
  endtask

  task test_b_without_pending();
    reset_state();
    bid = 8'h54; bvalid = 1'b1; bready = 1'b1;
    @(posedge ACLK);
  endtask

  task test_r_without_pending();
    reset_state();
    rid = 8'h54; rlast = 1'b1; rvalid = 1'b1; rready = 1'b1;
    @(posedge ACLK);
  endtask

  task test_same_id_second_b_early();
    reset_state();
    awid = 8'h54; awvalid = 1'b1; awready = 1'b1;
    repeat (2) @(posedge ACLK);
    @(negedge ACLK);
    awvalid = 1'b0; awready = 1'b0;
    wid = 8'h54; wlast = 1'b1; wvalid = 1'b1; wready = 1'b1;
    @(posedge ACLK);
    @(negedge ACLK);
    wvalid = 1'b0; wready = 1'b0; wlast = 1'b0;
    bid = 8'h54; bvalid = 1'b1; bready = 1'b1;
    repeat (2) @(posedge ACLK);
  endtask

  task test_rid_change();
    reset_state();
    arid = 8'h54; arlen = 1; arvalid = 1'b1; arready = 1'b1;
    @(posedge ACLK);
    @(negedge ACLK);
    arvalid = 1'b0; arready = 1'b0;
    rid = 8'h54; rvalid = 1'b1; rready = 1'b1;
    @(posedge ACLK);
    @(negedge ACLK);
    rid = 8'h55; rlast = 1'b1;
    @(posedge ACLK);
  endtask

  task test_wid_change();
    reset_state();
    wid = 8'h54; wvalid = 1'b1; wready = 1'b1;
    @(posedge ACLK);
    @(negedge ACLK);
    wid = 8'h55; wlast = 1'b1;
    @(posedge ACLK);
  endtask

  task test_outstanding_overflow();
    reset_state();
    arvalid = 1'b1; arready = 1'b1;
    for (int unsigned index = 0; index < 5; index++) begin
      arid = 8'h54 + (index % 4);
      @(posedge ACLK);
      @(negedge ACLK);
    end
  endtask

  task test_sid_tags();
    reset_state();
    awid = 8'h44; awvalid = 1'b1; awready = 1'b1;
    @(posedge ACLK);

    reset_state();
    awid = 8'h95; awvalid = 1'b1; awready = 1'b1;
    @(posedge ACLK);
  endtask

  initial begin
    ACLK = 1'b0;
    ARESETn = 1'b0;
    clear_signals();
    report_catcher = new();
    uvm_report_cb::add(null, report_catcher);

    test_b_without_pending();
    test_r_without_pending();
    test_same_id_second_b_early();
    test_rid_change();
    test_wid_change();
    test_outstanding_overflow();
    test_sid_tags();
    repeat (2) @(posedge ACLK);

    if (!report_catcher.b_no_pending_seen ||
        !report_catcher.r_no_pending_seen ||
        !report_catcher.same_id_order_seen ||
        !report_catcher.rid_change_seen ||
        !report_catcher.wid_change_seen ||
        !report_catcher.outstanding_seen ||
        !report_catcher.master_tag_seen ||
        !report_catcher.slave_tag_seen ||
        (report_catcher.unexpected_count != 0))
      $fatal(1, "Stage 3 assertion self-test missed an expected result");

    $display("AXI_STAGE3_ASSERT_SELFTEST_PASS");
    $finish;
  end

endmodule

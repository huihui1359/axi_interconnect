`timescale 1ns/1ps

module axi_protocol_assertions_selftest;

  import uvm_pkg::*;

  class assertion_report_catcher extends uvm_report_catcher;
    bit aw_stable_seen;
    bit b_causality_seen;
    int unsigned b_causality_count;
    bit wlast_early_seen;
    bit wlast_missing_seen;
    bit w_count_excess_seen;
    bit rlast_early_seen;
    bit rlast_missing_seen;
    bit r_count_excess_seen;
    bit payload_x_seen;
    int unsigned unexpected_count;

    virtual function action_e catch();
      string report_id;

      if (get_severity() != UVM_ERROR)
        return THROW;

      report_id = get_id();
      case (report_id)
        "AXI_ASSERT_AW_STABLE":     aw_stable_seen = 1'b1;
        "AXI_ASSERT_B_CAUSALITY": begin
          b_causality_seen = 1'b1;
          b_causality_count++;
        end
        "AXI_ASSERT_WLAST_EARLY":  wlast_early_seen = 1'b1;
        "AXI_ASSERT_WLAST_MISSING": wlast_missing_seen = 1'b1;
        "AXI_ASSERT_W_COUNT_EXCESS": w_count_excess_seen = 1'b1;
        "AXI_ASSERT_W_COUNT": begin
        end
        "AXI_ASSERT_RLAST_EARLY":  rlast_early_seen = 1'b1;
        "AXI_ASSERT_RLAST_MISSING": rlast_missing_seen = 1'b1;
        "AXI_ASSERT_R_COUNT_EXCESS": r_count_excess_seen = 1'b1;
        "AXI_ASSERT_AW_PAYLOAD_X": payload_x_seen = 1'b1;
        default: begin
          unexpected_count++;
          $display("UNEXPECTED_ASSERTION_ID %s", report_id);
        end
      endcase
      return CAUGHT;
    endfunction
  endclass

  logic ACLK;
  logic ARESETn;
  logic [3:0] awid;
  logic [31:0] awaddr;
  logic [3:0] awlen;
  logic [2:0] awsize;
  logic [1:0] awburst;
  logic awvalid;
  logic awready;
  logic [3:0] wid;
  logic [31:0] wdata;
  logic [3:0] wstrb;
  logic wlast;
  logic wvalid;
  logic wready;
  logic [3:0] bid;
  logic [1:0] bresp;
  logic bvalid;
  logic bready;
  logic [3:0] arid;
  logic [31:0] araddr;
  logic [3:0] arlen;
  logic [2:0] arsize;
  logic [1:0] arburst;
  logic arvalid;
  logic arready;
  logic [3:0] rid;
  logic [31:0] rdata;
  logic [1:0] rresp;
  logic rlast;
  logic rvalid;
  logic rready;

  assertion_report_catcher report_catcher;

  axi_protocol_assertions #(
    .ADDR_WIDTH(32),
    .DATA_WIDTH(32),
    .ID_WIDTH(4),
    .LEN_WIDTH(4),
    .TB_IS_MASTER(1'b1)
  ) dut (.*);

  always #5ns ACLK = ~ACLK;

  task clear_signals();
    awid = '0;
    awaddr = '0;
    awlen = '0;
    awsize = 3'd2;
    awburst = 2'b01;
    awvalid = 1'b0;
    awready = 1'b0;
    wid = '0;
    wdata = '0;
    wstrb = '1;
    wlast = 1'b0;
    wvalid = 1'b0;
    wready = 1'b0;
    bid = '0;
    bresp = '0;
    bvalid = 1'b0;
    bready = 1'b0;
    arid = '0;
    araddr = '0;
    arlen = '0;
    arsize = 3'd2;
    arburst = 2'b01;
    arvalid = 1'b0;
    arready = 1'b0;
    rid = '0;
    rdata = '0;
    rresp = '0;
    rlast = 1'b0;
    rvalid = 1'b0;
    rready = 1'b0;
  endtask

  task reset_state();
    @(negedge ACLK);
    clear_signals();
    ARESETn = 1'b0;
    repeat (2) @(posedge ACLK);
    @(negedge ACLK);
    ARESETn = 1'b1;
  endtask

  task test_stall_stability();
    reset_state();
    awid = 4'h1;
    awaddr = 32'h100;
    awlen = 0;
    awvalid = 1'b1;
    repeat (3) @(posedge ACLK);
    @(negedge ACLK);
    awready = 1'b1;
    @(posedge ACLK);
    @(negedge ACLK);
    awvalid = 1'b0;
    awready = 1'b0;
  endtask

  task test_stall_mutation();
    reset_state();
    awvalid = 1'b1;
    awaddr = 32'h200;
    @(posedge ACLK);
    @(negedge ACLK);
    awaddr = 32'h204;
    @(posedge ACLK);
  endtask

  task test_b_causality();
    reset_state();
    bvalid = 1'b1;
    @(posedge ACLK);

    reset_state();
    wid = 4'h5;
    wdata = 32'h55aa_0000;
    wlast = 1'b1;
    wvalid = 1'b1;
    wready = 1'b1;
    @(posedge ACLK);
    @(negedge ACLK);
    wvalid = 1'b0;
    wready = 1'b0;
    wlast = 1'b0;
    bvalid = 1'b1;
    bready = 1'b1;
    bid = 4'h5;
    @(posedge ACLK);
  endtask

  task test_wlast();
    reset_state();
    awid = 4'h2;
    awlen = 2;
    awvalid = 1'b1;
    awready = 1'b1;
    @(posedge ACLK);
    @(negedge ACLK);
    awvalid = 1'b0;
    awready = 1'b0;
    wid = 4'h2;
    wvalid = 1'b1;
    wready = 1'b1;
    wlast = 1'b1;
    @(posedge ACLK);

    reset_state();
    awid = 4'h3;
    awlen = 1;
    awvalid = 1'b1;
    awready = 1'b1;
    @(posedge ACLK);
    @(negedge ACLK);
    awvalid = 1'b0;
    awready = 1'b0;
    wid = 4'h3;
    wvalid = 1'b1;
    wready = 1'b1;
    wlast = 1'b0;
    repeat (3) @(posedge ACLK);
  endtask

  task test_rlast();
    reset_state();
    arid = 4'h4;
    arlen = 2;
    arvalid = 1'b1;
    arready = 1'b1;
    @(posedge ACLK);
    @(negedge ACLK);
    arvalid = 1'b0;
    arready = 1'b0;
    rid = 4'h4;
    rvalid = 1'b1;
    rready = 1'b1;
    rlast = 1'b1;
    @(posedge ACLK);

    reset_state();
    arid = 4'h5;
    arlen = 1;
    arvalid = 1'b1;
    arready = 1'b1;
    @(posedge ACLK);
    @(negedge ACLK);
    arvalid = 1'b0;
    arready = 1'b0;
    rid = 4'h5;
    rvalid = 1'b1;
    rready = 1'b1;
    rlast = 1'b0;
    repeat (3) @(posedge ACLK);
  endtask

  task test_payload_x();
    reset_state();
    awvalid = 1'b1;
    awready = 1'b1;
    awaddr = 'x;
    @(posedge ACLK);
    @(negedge ACLK);
    awvalid = 1'b0;
    awready = 1'b0;
  endtask

  initial begin
    ACLK = 1'b0;
    ARESETn = 1'b0;
    clear_signals();
    report_catcher = new();
    uvm_report_cb::add(null, report_catcher);

    test_stall_stability();
    test_stall_mutation();
    test_b_causality();
    test_wlast();
    test_rlast();
    test_payload_x();
    repeat (2) @(posedge ACLK);

    $display("ASSERTION_FLAGS aw_stable=%0d b_causality=%0d w_early=%0d w_missing=%0d w_excess=%0d r_early=%0d r_missing=%0d r_excess=%0d payload_x=%0d unexpected=%0d",
             report_catcher.aw_stable_seen,
             report_catcher.b_causality_seen,
             report_catcher.wlast_early_seen,
             report_catcher.wlast_missing_seen,
             report_catcher.w_count_excess_seen,
             report_catcher.rlast_early_seen,
             report_catcher.rlast_missing_seen,
             report_catcher.r_count_excess_seen,
             report_catcher.payload_x_seen,
             report_catcher.unexpected_count);

    if (!report_catcher.aw_stable_seen ||
        !report_catcher.b_causality_seen ||
        (report_catcher.b_causality_count != 1) ||
        !report_catcher.wlast_early_seen ||
        !report_catcher.wlast_missing_seen ||
        !report_catcher.w_count_excess_seen ||
        !report_catcher.rlast_early_seen ||
        !report_catcher.rlast_missing_seen ||
        !report_catcher.r_count_excess_seen ||
        !report_catcher.payload_x_seen ||
        (report_catcher.unexpected_count != 0))
      $fatal(1, "AXI assertion self-test did not observe the expected results");

    $display("AXI_ASSERT_SELFTEST_PASS");
    $finish;
  end

endmodule

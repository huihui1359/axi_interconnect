`timescale 1ns/1ps

module axi_stage6_protocol_assertions_selftest;
  import uvm_pkg::*;

  class stage6_assertion_report_catcher extends uvm_report_catcher;
    bit illegal_master_tag_seen;
    bit physical_slave_tag_seen;
    bit route_mismatch_seen;
    bit read_master_tag_seen;
    bit read_physical_tag_seen;
    bit response_master_tag_seen;
    bit response_physical_tag_seen;
    bit read_route_mismatch_seen;
    bit read_slave_tag_seen;
    bit response_slave_tag_seen;
    bit expect_legal_reads;
    int unsigned unexpected_count;
    virtual function action_e catch();
      string report_id;
      if (get_severity() != UVM_ERROR) return THROW;
      report_id = get_id();
      if (expect_legal_reads) begin
        unexpected_count++;
        $display("UNEXPECTED_LEGAL_READ_ASSERTION %s", report_id);
        return CAUGHT;
      end
      case (report_id)
        "AXI_ASSERT_AW_MASTER_TAG": illegal_master_tag_seen = 1'b1;
        "AXI_ASSERT_AW_ID": physical_slave_tag_seen = 1'b1;
        "AXI_ASSERT_AW_ROUTE": route_mismatch_seen = 1'b1;
        "AXI_ASSERT_AW_SLAVE_TAG": begin end
        "AXI_ASSERT_AR_MASTER_TAG": read_master_tag_seen = 1'b1;
        "AXI_ASSERT_AR_ID": read_physical_tag_seen = 1'b1;
        "AXI_ASSERT_R_MASTER_TAG": response_master_tag_seen = 1'b1;
        "AXI_ASSERT_R_ID": response_physical_tag_seen = 1'b1;
        "AXI_ASSERT_AR_ROUTE": read_route_mismatch_seen = 1'b1;
        "AXI_ASSERT_AR_SLAVE_TAG": read_slave_tag_seen = 1'b1;
        "AXI_ASSERT_R_SLAVE_TAG": response_slave_tag_seen = 1'b1;
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

  // Exercise address/ID target consistency at the master boundary as well
  // as the extended SID checks at the slave boundary.
  axi_protocol_assertions #(
    .ID_WIDTH(4), .TB_IS_MASTER(1'b1),
    .STAGE3_CHECKS(1'b1), .STAGE6_CHECKS(1'b1)
  ) master_dut (
    .ACLK(ACLK), .ARESETn(ARESETn),
    .awid(4'b0), .awaddr(32'b0), .awlen(4'b0), .awsize(3'd2),
    .awburst(2'b01), .awvalid(1'b0), .awready(1'b0),
    .wid(4'b0), .wdata(32'b0), .wstrb(4'b0), .wlast(1'b0),
    .wvalid(1'b0), .wready(1'b0),
    .bid(4'b0), .bresp(2'b0), .bvalid(1'b0), .bready(1'b0),
    .arid(arid[3:0]), .araddr(araddr), .arlen(arlen),
    .arsize(arsize), .arburst(arburst), .arvalid(arvalid), .arready(arready),
    .rid(rid[3:0]), .rdata(rdata), .rresp(rresp), .rlast(rlast),
    .rvalid(rvalid), .rready(rready)
  );

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

  task complete_read(bit [7:0] id, bit [31:0] address);
    arid=id; araddr=address; arvalid=1; arready=1;
    @(posedge ACLK); @(negedge ACLK); arvalid=0; arready=0;
    rid=id; rlast=1; rvalid=1; rready=1;
    @(posedge ACLK); @(negedge ACLK); rvalid=0; rready=0; rlast=0;
  endtask

  initial begin
    ACLK=0; ARESETn=0; clear_signals();
    report_catcher = new();
    uvm_report_cb::add(null, report_catcher);

    reset_state(); pulse_aw(8'hec, 32'h0000_4100);
    reset_state(); pulse_aw(8'h9c, 32'h0000_2100);
    reset_state(); pulse_aw(8'hcc, 32'h0000_4100);
    reset_state(); pulse_aw(8'hec, 32'h0000_2100);

    reset_state();
    report_catcher.expect_legal_reads = 1'b1;
    for (int unsigned master_tag = 1; master_tag <= 3; master_tag++)
      for (int unsigned local_tag = 0; local_tag < 4; local_tag++)
        complete_read(8'hcc | (master_tag << 4) | local_tag,
                      32'h0000_4100);
    report_catcher.expect_legal_reads = 1'b0;

    // Reject bad physical/master tags and an address/SID route mismatch.
    reset_state(); complete_read(8'h9c, 32'h0000_4100);
    if (!report_catcher.read_physical_tag_seen ||
        !report_catcher.response_physical_tag_seen)
      $fatal(1, "Read self-test missed a physical slave tag violation");
    reset_state(); complete_read(8'hcc, 32'h0000_4100);
    if (!report_catcher.read_master_tag_seen ||
        !report_catcher.response_master_tag_seen)
      $fatal(1, "Read self-test missed an illegal master tag");

    // SID target and address both select S2, but original ID selects S1.
    // Only the master-side AR route check can detect the address/ID mismatch;
    // slave-side tag checks must also reject the inconsistent original ID.
    report_catcher.read_route_mismatch_seen = 1'b0;
    report_catcher.read_slave_tag_seen = 1'b0;
    report_catcher.response_slave_tag_seen = 1'b0;
    reset_state(); complete_read(8'he8, 32'h0000_4100);
    if (!report_catcher.read_route_mismatch_seen ||
        !report_catcher.read_slave_tag_seen ||
        !report_catcher.response_slave_tag_seen)
      $fatal(1, "Read self-test missed an original ID/address target mismatch");
    repeat (2) @(posedge ACLK);

    if (!report_catcher.illegal_master_tag_seen ||
        !report_catcher.physical_slave_tag_seen ||
        !report_catcher.route_mismatch_seen ||
        !report_catcher.read_master_tag_seen ||
        !report_catcher.read_physical_tag_seen ||
        !report_catcher.response_master_tag_seen ||
        !report_catcher.response_physical_tag_seen ||
        !report_catcher.read_route_mismatch_seen ||
        (report_catcher.unexpected_count != 0))
      $fatal(1, "Stage 6 protocol assertion self-test missed a check");
    $display("AXI_STAGE6_ASSERT_SELFTEST_PASS");
    $finish;
  end
endmodule

`timescale 1ns/1ps

module axi_stage6_arbiter_assertions_selftest;
  import uvm_pkg::*;

  class arbiter_report_catcher extends uvm_report_catcher;
    bit pointer_violation_seen;
    virtual function action_e catch();
      if ((get_severity() == UVM_ERROR) &&
          (get_id() == "AXI_STAGE6_ARB_SELF_POINTER_CHANGED_WITHOUT_HANDSHAKE")) begin
        pointer_violation_seen = 1'b1;
        return CAUGHT;
      end
      return THROW;
    endfunction
  endclass

  logic clk, rst_n, locked;
  logic [2:0] request, grant, ready, last_winner;
  arbiter_report_catcher report_catcher;

  axi_stage6_rr_pointer_checker #(
    .WIDTH(3), .CHECK_NAME("SELF"), .ENABLE_ALWAYS(1'b1)
  ) dut (.*);

  always #5ns clk = ~clk;

  initial begin
    clk=0; rst_n=0; locked=0; request=0; grant=0; ready=0;
    last_winner=0;
    report_catcher = new();
    uvm_report_cb::add(null, report_catcher);
    repeat (2) @(posedge clk);
    @(negedge clk); rst_n=1;
    repeat (2) @(posedge clk);
    @(negedge clk); last_winner=3'b001;
    repeat (2) @(posedge clk);
    if (!report_catcher.pointer_violation_seen)
      $fatal(1, "Bound pointer checker did not detect an illegal update");
    $display("AXI_STAGE6_ARBITER_SELFTEST_PASS");
    $finish;
  end
endmodule

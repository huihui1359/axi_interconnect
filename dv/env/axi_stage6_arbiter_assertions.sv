`timescale 1ns/1ps

module axi_stage6_rr_pointer_checker #(
  parameter int unsigned WIDTH = 3,
  parameter string CHECK_NAME = "RR",
  parameter bit ENABLE_ALWAYS = 1'b0
) (
  input logic clk,
  input logic rst_n,
  input logic [WIDTH-1:0] request,
  input logic [WIDTH-1:0] grant,
  input logic [WIDTH-1:0] last_winner,
  input logic locked,
  input logic accept
);

  import uvm_pkg::*;

  bit enabled;

  function automatic logic [WIDTH-1:0] expected_grant(
    logic [WIDTH-1:0] req,
    logic [WIDTH-1:0] pointer
  );
    logic [WIDTH-1:0] result;
    int signed last_index;
    int unsigned candidate;
    result = '0;
    last_index = -1;
    for (int unsigned index = 0; index < WIDTH; index++)
      if (pointer[index]) last_index = index;
    for (int unsigned offset = 1; offset <= WIDTH; offset++) begin
      candidate = (last_index + offset) % WIDTH;
      if ((result == '0) && req[candidate]) result[candidate] = 1'b1;
    end
    return result;
  endfunction

  task automatic report_error(string suffix);
    uvm_report_error({"AXI_STAGE6_ARB_", CHECK_NAME, "_", suffix},
                     "Stage 6 bound arbitration assertion failed");
  endtask

  initial begin
    enabled = ENABLE_ALWAYS || $test$plusargs("UVM_TESTNAME=axi_stage6");
  end

  // ARB-SVA-001: grant在任意有效检查周期最多只能选择一个请求端。
  property p_grant_onehot;
    @(posedge clk) disable iff ((rst_n !== 1'b1) || !enabled)
      $onehot0(grant);
  endproperty

  // ARB-SVA-002: 非锁定状态下，grant只能授予当前正在请求的端口。
  property p_grant_has_request;
    @(posedge clk) disable iff ((rst_n !== 1'b1) || !enabled)
      !locked |-> ((grant & ~request) == '0);
  endproperty

  // ARB-SVA-003: 非锁定状态下，grant必须符合last_winner定义的round-robin顺序。
  property p_round_robin_order;
    @(posedge clk) disable iff ((rst_n !== 1'b1) || !enabled)
      !locked |-> (grant == expected_grant(request, last_winner));
  endproperty

  // ARB-SVA-004: 本周期accept后，下一采样周期的last_winner必须记录本次grant。
  property p_pointer_updated_on_accept;
    @(posedge clk) disable iff ((rst_n !== 1'b1) || !enabled)
      accept |=> (last_winner == $past(grant));
  endproperty

  // ARB-SVA-005: 本周期没有accept时，下一采样周期的last_winner必须保持不变。
  property p_pointer_stable_without_accept;
    @(posedge clk) disable iff ((rst_n !== 1'b1) || !enabled)
      !accept |=> $stable(last_winner);
  endproperty

  // ARB-SVA-006: grant尚未被accept时，下一采样周期必须继续保持同一个grant。
  property p_grant_stable_while_stalled;
    @(posedge clk) disable iff ((rst_n !== 1'b1) || !enabled)
      ((|grant) && !accept) |=> $stable(grant);
  endproperty

  a_grant_onehot: assert property (p_grant_onehot)
    else report_error("GRANT_ONEHOT");

  a_grant_has_request: assert property (p_grant_has_request)
    else report_error("GRANT_WITHOUT_REQUEST");

  a_round_robin_order: assert property (p_round_robin_order)
    else report_error("ROUND_ROBIN_ORDER");

  a_pointer_updated_on_accept: assert property (p_pointer_updated_on_accept)
    else report_error("POINTER_NOT_UPDATED_ON_HANDSHAKE");

  a_pointer_stable_without_accept: assert property (p_pointer_stable_without_accept)
    else report_error("POINTER_CHANGED_WITHOUT_HANDSHAKE");

  a_grant_stable_while_stalled: assert property (p_grant_stable_while_stalled)
    else report_error("GRANT_CHANGED_WHILE_STALLED");

endmodule

module axi_stage6_arbiter_bindings;

bind axi_arbiter_mtos_m3 axi_stage6_rr_pointer_checker #(
  .WIDTH(3), .CHECK_NAME("AW")
) stage6_aw_checker (
  .clk(ACLK), .rst_n(ARESETn), .request(AWREQ), .grant(AWGRANT),
  .last_winner(u_arbiter_aw.last_winner),
  .locked(u_arbiter_aw.pending_valid), .accept(AWACCEPT)
);

bind axi_arbiter_mtos_m3 axi_stage6_rr_pointer_checker #(
  .WIDTH(3), .CHECK_NAME("W")
) stage6_w_checker (
  .clk(ACLK), .rst_n(ARESETn), .request(WREQ), .grant(WGRANT),
  .last_winner(u_arbiter_w.last_winner),
  .locked(u_arbiter_w.pending_valid), .accept(WACCEPT)
);

bind axi_arbiter_mtos_m3 axi_stage6_rr_pointer_checker #(
  .WIDTH(3), .CHECK_NAME("AR")
) stage6_ar_checker (
  .clk(ACLK), .rst_n(ARESETn), .request(ARREQ), .grant(ARGRANT),
  .last_winner(u_arbiter_ar.last_winner),
  .locked(u_arbiter_ar.pending_valid), .accept(ARACCEPT)
);

bind axi_arbiter_stom_s3 axi_stage6_rr_pointer_checker #(
  .WIDTH(4), .CHECK_NAME("B")
) stage6_b_checker (
  .clk(ACLK), .rst_n(ARESETn), .request(BREQ), .grant(BGRANT),
  .last_winner(u_arbiter_b.last_winner),
  .locked(u_arbiter_b.pending_valid), .accept(BACCEPT)
);

bind axi_arbiter_stom_s3 axi_stage6_rr_pointer_checker #(
  .WIDTH(4), .CHECK_NAME("R")
) stage6_r_checker (
  .clk(ACLK), .rst_n(ARESETn), .request(RREQ), .grant(RGRANT),
  .last_winner(u_arbiter_r.last_winner),
  .locked(u_arbiter_r.pending_valid), .accept(RACCEPT)
);

endmodule

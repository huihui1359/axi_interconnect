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

  logic [WIDTH-1:0] previous_pointer;
  logic [WIDTH-1:0] previous_grant;
  logic [WIDTH-1:0] stalled_grant;
  bit previous_handshake;
  bit previous_valid;
  bit stall_active;
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
    previous_valid = 1'b0;
    previous_handshake = 1'b0;
    stall_active = 1'b0;
    previous_pointer = '0;
    previous_grant = '0;
    stalled_grant = '0;
  end

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      previous_valid <= 1'b0;
      previous_handshake <= 1'b0;
      stall_active <= 1'b0;
      previous_pointer <= '0;
      previous_grant <= '0;
      stalled_grant <= '0;
    end
    else if (enabled) begin
      if (!$onehot0(grant)) report_error("GRANT_ONEHOT");
      if (|(grant & ~request) && !locked) report_error("GRANT_WITHOUT_REQUEST");
      if (!locked && (grant !== expected_grant(request, last_winner)))
        report_error("ROUND_ROBIN_ORDER");

      if (previous_valid) begin
        if (previous_handshake) begin
          if (last_winner !== previous_grant)
            report_error("POINTER_NOT_UPDATED_ON_HANDSHAKE");
        end
        else if (last_winner !== previous_pointer) begin
          report_error("POINTER_CHANGED_WITHOUT_HANDSHAKE");
        end
      end

      if ((|grant) && !accept) begin
        if (stall_active && (grant !== stalled_grant))
          report_error("GRANT_CHANGED_WHILE_STALLED");
        stall_active <= 1'b1;
        stalled_grant <= grant;
      end
      else begin
        stall_active <= 1'b0;
      end

      previous_valid <= 1'b1;
      previous_handshake <= accept;
      previous_pointer <= last_winner;
      previous_grant <= grant;
    end
  end

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

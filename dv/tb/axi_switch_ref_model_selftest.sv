`timescale 1ns/1ps

module axi_switch_ref_model_selftest;

  import uvm_pkg::*;
  import axi_types_pkg::*;
  import axi_env_pkg::*;

  typedef axi_switch_ref_model #(
    AXI_ADDR_WIDTH, AXI_M_ID_WIDTH, AXI_S_ID_WIDTH
  ) model_t;

  initial begin
    model_t model;
    model = model_t::type_id::create("unit_model");

    assert ((model.decode_address(32'h0000_0000) == AXI_ROUTE_S0) &&
            (model.decode_address(32'h0000_0fff) == AXI_ROUTE_S0) &&
            (model.decode_address(32'h0000_2000) == AXI_ROUTE_S1) &&
            (model.decode_address(32'h0000_2fff) == AXI_ROUTE_S1) &&
            (model.decode_address(32'h0000_4000) == AXI_ROUTE_S2) &&
            (model.decode_address(32'h0000_4fff) == AXI_ROUTE_S2) &&
            (model.decode_address(32'h0000_1000) == AXI_ROUTE_DEFAULT))
      else $fatal(1, "Switch model address decode check failed");

    assert ((model.master_to_tag(0) == 2'b01) &&
            (model.master_to_tag(1) == 2'b10) &&
            (model.master_to_tag(2) == 2'b11) &&
            (model.slave_to_tag(AXI_ROUTE_S0) == 2'b01) &&
            (model.slave_to_tag(AXI_ROUTE_S1) == 2'b10) &&
            (model.slave_to_tag(AXI_ROUTE_S2) == 2'b11))
      else $fatal(1, "Switch model port tag check failed");

    for (int unsigned tag = 0; tag < 4; tag++) begin
      assert (model.build_master_id(AXI_ROUTE_S0, tag[1:0]) ==
              (4'h4 + tag))
        else $fatal(1, "Switch model Master ID build check failed");
      assert (model.encode_sid(0, AXI_ROUTE_S0, 4'h4 + tag) ==
              (8'h54 + tag))
        else $fatal(1, "Switch model Slave ID encode check failed");
      assert (model.decode_master(8'h54 + tag) == 0)
        else $fatal(1, "Switch model Master decode check failed");
      assert (model.restore_id(8'h54 + tag) == (4'h4 + tag))
        else $fatal(1, "Switch model original ID restore check failed");
    end

    assert ((model.decode_w_target(4'h4) == AXI_ROUTE_S0) &&
            (model.decode_w_target(4'h8) == AXI_ROUTE_S1) &&
            (model.decode_w_target(4'hc) == AXI_ROUTE_S2) &&
            (model.decode_w_target(4'h0) == AXI_ROUTE_INVALID))
      else $fatal(1, "Switch model W target decode check failed");

    $display("AXI_SWITCH_MODEL_SELFTEST_PASS");
    $finish;
  end

endmodule

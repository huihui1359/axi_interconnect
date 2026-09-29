`timescale 1ns/1ps

module axi_stage6_ref_model_selftest;
  import uvm_pkg::*;
  import axi_types_pkg::*;
  import axi_env_pkg::*;

  initial begin
    axi_switch_ref_model #() model;
    axi_route_e route;
    bit [3:0] mid;
    bit [7:0] sid;
    model = axi_switch_ref_model #()::type_id::create("stage6_unit_model");

    for (int unsigned master = 0; master < 3; master++) begin
      for (int unsigned slave = 0; slave < 3; slave++) begin
        case (slave)
          0: route = AXI_ROUTE_S0;
          1: route = AXI_ROUTE_S1;
          default: route = AXI_ROUTE_S2;
        endcase
        for (int unsigned tag = 0; tag < 4; tag++) begin
          mid = model.build_master_id(route, tag[1:0]);
          sid = model.encode_sid(master, route, mid);
          assert (model.decode_master(sid) == int'(master))
            else $fatal(1, "Stage 6 master decode matrix failed");
          assert (model.restore_id(sid) == mid)
            else $fatal(1, "Stage 6 original ID restore matrix failed");
          assert (sid[7:6] == (slave + 1))
            else $fatal(1, "Stage 6 slave tag encode matrix failed");
          assert (sid[5:4] == (master + 1))
            else $fatal(1, "Stage 6 master tag encode matrix failed");
        end
      end
    end

    assert (model.decode_master(8'hc0) == -1)
      else $fatal(1, "Illegal 00 master tag was accepted");
    assert (model.decode_address(32'h0000_8000) == AXI_ROUTE_DEFAULT)
      else $fatal(1, "Default route decode failed");
    assert (model.decode_w_target(4'h0) == AXI_ROUTE_INVALID)
      else $fatal(1, "Illegal write target was accepted");

    $display("AXI_STAGE6_REF_MODEL_SELFTEST_PASS");
    $finish;
  end
endmodule

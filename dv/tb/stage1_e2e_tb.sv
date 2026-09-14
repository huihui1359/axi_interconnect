`timescale 1ns/1ps

module stage1_e2e_tb;

  import uvm_pkg::*;
  import axi_types_pkg::*;
  import axi_env_pkg::*;
  import axi_seq_pkg::*;
  import stage1_e2e_test_pkg::*;

  bit aclk;
  stage1_reset_if reset_if(.aclk(aclk));

  axi_if #(
    .ADDR_WIDTH(AXI_ADDR_WIDTH),
    .DATA_WIDTH(AXI_DATA_WIDTH),
    .ID_WIDTH  (AXI_M_ID_WIDTH),
    .LEN_WIDTH (AXI_LEN_WIDTH)
  ) m_if (
    .ACLK   (aclk),
    .ARESETn(reset_if.aresetn)
  );

  axi_if #(
    .ADDR_WIDTH(AXI_ADDR_WIDTH),
    .DATA_WIDTH(AXI_DATA_WIDTH),
    .ID_WIDTH  (AXI_S_ID_WIDTH),
    .LEN_WIDTH (AXI_LEN_WIDTH)
  ) s_if (
    .ACLK   (aclk),
    .ARESETn(reset_if.aresetn)
  );

  stage1_dut_bridge dut_bridge(.m_if(m_if), .s_if(s_if));
  axi_protocol_assertions m_protocol_assertions(.bus(m_if));
  axi_protocol_assertions s_protocol_assertions(.bus(s_if));

  initial begin
    aclk = 1'b0;
    forever #5ns aclk = ~aclk;
  end

  initial begin
    reset_if.apply_initial_reset(2);
  end

  initial begin
    uvm_config_db#(m_drv_vif_t)::set(
      null, "uvm_test_top", "m_drv_vif", m_if
    );
    uvm_config_db#(m_mon_vif_t)::set(
      null, "uvm_test_top", "m_mon_vif", m_if
    );
    uvm_config_db#(s_drv_vif_t)::set(
      null, "uvm_test_top", "s_drv_vif", s_if
    );
    uvm_config_db#(s_mon_vif_t)::set(
      null, "uvm_test_top", "s_mon_vif", s_if
    );
    uvm_config_db#(reset_vif_t)::set(
      null, "uvm_test_top", "reset_vif", reset_if
    );
    uvm_root::get().set_timeout(5_000_000, 1'b1);
    run_test();
  end

endmodule

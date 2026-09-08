`timescale 1ns/1ps

module stage0_tb;

  import uvm_pkg::*;
  import axi_types_pkg::*;
  import axi_env_pkg::*;
  import stage0_test_pkg::*;

  bit aclk;
  bit aresetn;

  axi_if #(
    .ADDR_WIDTH(AXI_ADDR_WIDTH),
    .DATA_WIDTH(AXI_DATA_WIDTH),
    .ID_WIDTH  (AXI_M_ID_WIDTH),
    .LEN_WIDTH (AXI_LEN_WIDTH)
  ) m_if (
    .ACLK   (aclk),
    .ARESETn(aresetn)
  );

  axi_if #(
    .ADDR_WIDTH(AXI_ADDR_WIDTH),
    .DATA_WIDTH(AXI_DATA_WIDTH),
    .ID_WIDTH  (AXI_S_ID_WIDTH),
    .LEN_WIDTH (AXI_LEN_WIDTH)
  ) s_if (
    .ACLK   (aclk),
    .ARESETn(aresetn)
  );

  typedef virtual axi_if #(
    AXI_ADDR_WIDTH, AXI_DATA_WIDTH, AXI_M_ID_WIDTH, AXI_LEN_WIDTH
  ).m_drv_mp m_drv_vif_t;

  typedef virtual axi_if #(
    AXI_ADDR_WIDTH, AXI_DATA_WIDTH, AXI_M_ID_WIDTH, AXI_LEN_WIDTH
  ).mon_mp m_mon_vif_t;

  typedef virtual axi_if #(
    AXI_ADDR_WIDTH, AXI_DATA_WIDTH, AXI_S_ID_WIDTH, AXI_LEN_WIDTH
  ).s_drv_mp s_drv_vif_t;

  typedef virtual axi_if #(
    AXI_ADDR_WIDTH, AXI_DATA_WIDTH, AXI_S_ID_WIDTH, AXI_LEN_WIDTH
  ).mon_mp s_mon_vif_t;

  initial begin
    aclk = 1'b0;
    forever #5ns aclk = ~aclk;
  end

  initial begin
    aresetn = 1'b0;
    #20ns;
    aresetn = 1'b1;
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
    run_test("stage0_smoke_test");
  end

endmodule

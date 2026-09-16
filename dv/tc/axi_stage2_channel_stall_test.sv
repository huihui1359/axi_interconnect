`ifndef AXI_STAGE2_CHANNEL_STALL_TEST_SV
`define AXI_STAGE2_CHANNEL_STALL_TEST_SV

class axi_stage2_channel_stall_test extends axi_stage2_base_test;

  typedef virtual axi_if #(
    AXI_ADDR_WIDTH, AXI_DATA_WIDTH, AXI_M_ID_WIDTH, AXI_LEN_WIDTH
  ).mon_mp m_vif_t;
  typedef virtual axi_if #(
    AXI_ADDR_WIDTH, AXI_DATA_WIDTH, AXI_S_ID_WIDTH, AXI_LEN_WIDTH
  ).mon_mp s_vif_t;

  `uvm_component_utils(axi_stage2_channel_stall_test)

  function new(string name = "axi_stage2_channel_stall_test",
               uvm_component parent = null);
    super.new(name, parent);
  endfunction

  extern task check_channel_stalls(m_vif_t m_vif, s_vif_t s_vif);
  extern virtual task run_phase(uvm_phase phase);

endclass

task axi_stage2_channel_stall_test::check_channel_stalls(
  m_vif_t m_vif,
  s_vif_t s_vif
);
  bit aw_stalled;
  bit w_stalled;
  bit b_stalled;
  bit ar_stalled;
  bit r_stalled;
  bit b_complete;
  bit r_complete;

  while (!b_complete || !r_complete) begin
    @(posedge m_vif.ACLK);
    aw_stalled |= s_vif.awvalid && !s_vif.awready;
    w_stalled  |= s_vif.wvalid && !s_vif.wready;
    b_stalled  |= m_vif.bvalid && !m_vif.bready;
    ar_stalled |= s_vif.arvalid && !s_vif.arready;
    r_stalled  |= m_vif.rvalid && !m_vif.rready;
    b_complete |= m_vif.bvalid && m_vif.bready;
    r_complete |= m_vif.rvalid && m_vif.rready && m_vif.rlast;
  end

  if (!aw_stalled || !w_stalled || !b_stalled ||
      !ar_stalled || !r_stalled)
    `uvm_error("AXI_STAGE2_CHANNEL_STALL", $sformatf(
      "Missing stall coverage AW/W/B/AR/R=%0d/%0d/%0d/%0d/%0d",
      aw_stalled, w_stalled, b_stalled, ar_stalled, r_stalled))
endtask

task axi_stage2_channel_stall_test::run_phase(uvm_phase phase);
  axi_stage2_channel_stall_sequence scenario;

  phase.raise_objection(this);
  configure_ready_fixed(25, 35, 45, 1000, 1000);
  scenario = axi_stage2_channel_stall_sequence::type_id::create("scenario");
  wait_for_reset_release();
  fork
    check_channel_stalls(env_cfg.m_cfg[0].mon_vif,
                         env_cfg.s_cfg[0].mon_vif);
    run_stage2_scenario(scenario, 1, 1,
                        "axi_stage2_channel_stall_test");
  join
  phase.drop_objection(this);
endtask

`endif

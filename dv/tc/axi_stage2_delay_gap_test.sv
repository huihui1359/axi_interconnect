`ifndef AXI_STAGE2_DELAY_GAP_TEST_SV
`define AXI_STAGE2_DELAY_GAP_TEST_SV

class axi_stage2_delay_gap_test extends axi_stage2_base_test;

  typedef virtual axi_if #(
    AXI_ADDR_WIDTH, AXI_DATA_WIDTH, AXI_M_ID_WIDTH, AXI_LEN_WIDTH
  ).mon_mp m_vif_t;
  typedef virtual axi_if #(
    AXI_ADDR_WIDTH, AXI_DATA_WIDTH, AXI_S_ID_WIDTH, AXI_LEN_WIDTH
  ).mon_mp s_vif_t;

  `uvm_component_utils(axi_stage2_delay_gap_test)

  function new(string name = "axi_stage2_delay_gap_test",
               uvm_component parent = null);
    super.new(name, parent);
  endfunction

  extern task check_beat_gaps(m_vif_t m_vif, s_vif_t s_vif);
  extern virtual task run_phase(uvm_phase phase);

endclass

task axi_stage2_delay_gap_test::check_beat_gaps(
  m_vif_t m_vif,
  s_vif_t s_vif
);
  int unsigned expected_w_gap[3] = '{1, 3, 2};
  int unsigned expected_r_gap[3] = '{3, 1, 2};
  longint unsigned cycle_count;
  longint unsigned prior_w_cycle;
  longint unsigned prior_r_cycle;
  int unsigned w_index;
  int unsigned r_index;

  cycle_count   = 0;
  prior_w_cycle = 0;
  prior_r_cycle = 0;
  w_index       = 0;
  r_index       = 0;
  while ((w_index < 4) || (r_index < 4)) begin
    @(posedge m_vif.ACLK);
    cycle_count++;
    if (m_vif.wvalid && m_vif.wready) begin
      if ((w_index != 0) &&
          ((cycle_count - prior_w_cycle) != (expected_w_gap[w_index-1] + 1)))
        `uvm_error("AXI_STAGE2_W_GAP", $sformatf(
          "W gap[%0d] expected %0d idle cycles, observed %0d",
          w_index, expected_w_gap[w_index-1],
          cycle_count - prior_w_cycle - 1))
      prior_w_cycle = cycle_count;
      w_index++;
    end
    if (s_vif.rvalid && s_vif.rready) begin
      if ((r_index != 0) &&
          ((cycle_count - prior_r_cycle) != (expected_r_gap[r_index-1] + 1)))
        `uvm_error("AXI_STAGE2_R_GAP", $sformatf(
          "R gap[%0d] expected %0d idle cycles, observed %0d",
          r_index, expected_r_gap[r_index-1],
          cycle_count - prior_r_cycle - 1))
      prior_r_cycle = cycle_count;
      r_index++;
    end
  end
endtask

task axi_stage2_delay_gap_test::run_phase(uvm_phase phase);
  axi_stage2_delay_gap_sequence scenario;

  phase.raise_objection(this);
  configure_ready_fixed(0, 0, 0, 0, 0);
  scenario = axi_stage2_delay_gap_sequence::type_id::create("scenario");
  wait_for_reset_release();
  fork
    check_beat_gaps(env_cfg.m_cfg[0].mon_vif,
                    env_cfg.s_cfg[0].mon_vif);
    run_stage2_scenario(scenario, 1, 1,
                        "axi_stage2_delay_gap_test");
  join
  phase.drop_objection(this);
endtask

`endif

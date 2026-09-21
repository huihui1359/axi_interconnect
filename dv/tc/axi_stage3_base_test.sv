`ifndef AXI_STAGE3_BASE_TEST_SV
`define AXI_STAGE3_BASE_TEST_SV

class axi_stage3_base_test extends axi_base_test;

  `uvm_component_utils(axi_stage3_base_test)

  extern function new(string name = "axi_stage3_base_test",
                      uvm_component parent = null);
  extern virtual function void build_phase(uvm_phase phase);
  extern function void configure_ready_fixed(
    int unsigned aw_delay,
    int unsigned w_delay,
    int unsigned ar_delay,
    int unsigned b_delay,
    int unsigned r_delay
  );
  extern function void configure_ready_random(
    int unsigned minimum,
    int unsigned maximum
  );
  extern task start_stage3_scenario(axi_stage3_scenario_sequence scenario);
  extern task wait_for_stage3_counts(
    int unsigned write_count,
    int unsigned read_count
  );
  extern task finish_stage3_test(
    string test_name,
    int unsigned write_count,
    int unsigned read_count,
    int unsigned write_depth = 0,
    int unsigned read_depth = 0,
    bit require_reorder = 1'b0,
    bit require_same_id = 1'b0
  );

endclass

function axi_stage3_base_test::new(
  string name = "axi_stage3_base_test",
  uvm_component parent = null
);
  super.new(name, parent);
endfunction

function void axi_stage3_base_test::build_phase(uvm_phase phase);
  if (uvm_config_db#(axi_env_cfg)::get(this, "", "env_cfg", env_cfg)) begin
    env_cfg.checker_mode = AXI_CHECKER_STAGE3;
    env_cfg.m_cfg[0].max_write_outstanding = 4;
    env_cfg.m_cfg[0].max_read_outstanding  = 4;
    env_cfg.m_cfg[0].request_prefetch_enabled = 1'b1;
  end
  super.build_phase(phase);
endfunction

function void axi_stage3_base_test::configure_ready_fixed(
  int unsigned aw_delay,
  int unsigned w_delay,
  int unsigned ar_delay,
  int unsigned b_delay,
  int unsigned r_delay
);
  env.s_agents[0].driver.awready_latency.configure_fixed(aw_delay);
  env.s_agents[0].driver.wready_latency.configure_fixed(w_delay);
  env.s_agents[0].driver.arready_latency.configure_fixed(ar_delay);
  env.m_agents[0].driver.bready_latency.configure_fixed(b_delay);
  env.m_agents[0].driver.rready_latency.configure_fixed(r_delay);
endfunction

function void axi_stage3_base_test::configure_ready_random(
  int unsigned minimum,
  int unsigned maximum
);
  env.s_agents[0].driver.awready_latency.configure_random(minimum, maximum);
  env.s_agents[0].driver.wready_latency.configure_random(minimum, maximum);
  env.s_agents[0].driver.arready_latency.configure_random(minimum, maximum);
  env.m_agents[0].driver.bready_latency.configure_random(minimum, maximum);
  env.m_agents[0].driver.rready_latency.configure_random(minimum, maximum);
endfunction

task axi_stage3_base_test::start_stage3_scenario(
  axi_stage3_scenario_sequence scenario
);
  scenario.m_sequencer = env.m_agents[0].sequencer;
  scenario.s_sequencer = env.s_agents[0].sequencer;
  scenario.start(null);
endtask

task axi_stage3_base_test::wait_for_stage3_counts(
  int unsigned write_count,
  int unsigned read_count
);
  int unsigned elapsed_cycles;

  elapsed_cycles = 0;
  while ((env.stage3_checker.write_rsp_match_count < write_count) ||
         (env.stage3_checker.read_rsp_match_count < read_count)) begin
    @(posedge env_cfg.m_cfg[0].mon_vif.ACLK);
    elapsed_cycles++;
    if (elapsed_cycles >= 5_000)
      `uvm_fatal("AXI_STAGE3_TIMEOUT", $sformatf(
        "Timed out waiting for writes=%0d reads=%0d; observed writes=%0d reads=%0d; downstream R id=0x%0h valid=%0b ready=%0b",
        write_count, read_count,
        env.stage3_checker.write_rsp_match_count,
        env.stage3_checker.read_rsp_match_count,
        env_cfg.s_cfg[0].mon_vif.rid,
        env_cfg.s_cfg[0].mon_vif.rvalid,
        env_cfg.s_cfg[0].mon_vif.rready))
  end
endtask

task axi_stage3_base_test::finish_stage3_test(
  string test_name,
  int unsigned write_count,
  int unsigned read_count,
  int unsigned write_depth = 0,
  int unsigned read_depth = 0,
  bit require_reorder = 1'b0,
  bit require_same_id = 1'b0
);
  int unsigned w_pending;
  int error_count;

  repeat (3) @(posedge env_cfg.m_cfg[0].mon_vif.ACLK);

  if ((env.stage3_checker.write_rsp_match_count != write_count) ||
      (env.stage3_checker.read_rsp_match_count != read_count))
    `uvm_error("AXI_STAGE3_COUNT", "Stage 3 response counts do not match")
  if (env.stage3_checker.mismatch_count != 0)
    `uvm_error("AXI_STAGE3_CHECK", "Stage 3 checker reported a mismatch")
  if (env.stage3_checker.pending_count() != 0)
    `uvm_error("AXI_STAGE3_CHECK", "Stage 3 checker has pending activity")

  if ((write_depth != 0) &&
      ((env.stage3_checker.max_write_outstanding != write_depth) ||
       (env.m_agents[0].driver.max_write_outstanding != write_depth) ||
       (env.upstream_tracker.max_write_outstanding != write_depth) ||
       (env.downstream_tracker.max_write_outstanding != write_depth)))
    `uvm_error("AXI_STAGE3_WRITE_DEPTH", $sformatf(
      "Expected write depth %0d, observed checker/driver/upstream/downstream %0d/%0d/%0d/%0d",
      write_depth, env.stage3_checker.max_write_outstanding,
      env.m_agents[0].driver.max_write_outstanding,
      env.upstream_tracker.max_write_outstanding,
      env.downstream_tracker.max_write_outstanding))
  if ((read_depth != 0) &&
      ((env.stage3_checker.max_read_outstanding != read_depth) ||
       (env.m_agents[0].driver.max_read_outstanding != read_depth) ||
       (env.upstream_tracker.max_read_outstanding != read_depth) ||
       (env.downstream_tracker.max_read_outstanding != read_depth)))
    `uvm_error("AXI_STAGE3_READ_DEPTH", $sformatf(
      "Expected read depth %0d, observed checker/driver/upstream/downstream %0d/%0d/%0d/%0d",
      read_depth, env.stage3_checker.max_read_outstanding,
      env.m_agents[0].driver.max_read_outstanding,
      env.upstream_tracker.max_read_outstanding,
      env.downstream_tracker.max_read_outstanding))
  if (require_reorder &&
      (env.stage3_checker.different_id_reorder_count == 0))
    `uvm_error("AXI_STAGE3_REORDER", "No different-ID reorder was observed")
  if (require_same_id && (env.stage3_checker.same_id_multiple_count == 0))
    `uvm_error("AXI_STAGE3_SAME_ID", "No same-ID overlap was observed")

  if ((env.upstream_tracker.error_count != 0) ||
      (env.downstream_tracker.error_count != 0) ||
      (env.upstream_tracker.pending_count() != 0) ||
      (env.downstream_tracker.pending_count() != 0))
    `uvm_error("AXI_STAGE3_TRACKER", "Outstanding Tracker is not clean")

  w_pending = 0;
  foreach (env.m_agents[0].driver.w_outstanding_by_id[id])
    w_pending += env.m_agents[0].driver.w_outstanding_by_id[id];
  if ((env.m_agents[0].driver.write_outstanding() != 0) ||
      (env.m_agents[0].driver.read_outstanding() != 0) ||
      (w_pending != 0) ||
      (env.m_agents[0].driver.pending_context_count() != 0) ||
      (env.m_agents[0].driver.aw_queue.num() != 0) ||
      (env.m_agents[0].driver.w_queue.num() != 0) ||
      (env.m_agents[0].driver.ar_queue.num() != 0))
    `uvm_error("AXI_STAGE3_DRIVER", "Master Driver has pending state")
  if ((env.m_agents[0].monitor.pending_count() != 0) ||
      (env.s_agents[0].monitor.pending_count() != 0))
    `uvm_error("AXI_STAGE3_MONITOR", "Monitor has pending state")
  if (env.s_agents[0].sequencer.request_fifo.used() != 0)
    `uvm_error("AXI_STAGE3_FIFO", "Slave request FIFO is not empty")

  error_count = uvm_report_server::get_server().get_severity_count(UVM_ERROR);
  if (error_count != 0)
    `uvm_fatal("AXI_TC_FAIL", $sformatf(
      "%s failed: uvm_errors=%0d", test_name, error_count))
  `uvm_info("AXI_TC_PASS", {test_name, " passed"}, UVM_NONE)
endtask

`endif

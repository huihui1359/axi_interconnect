`ifndef AXI_STAGE2_READ_WRITE_PARALLEL_TEST_SV
`define AXI_STAGE2_READ_WRITE_PARALLEL_TEST_SV

class axi_stage2_read_write_parallel_test extends axi_stage2_base_test;

  typedef virtual axi_if #(
    AXI_ADDR_WIDTH, AXI_DATA_WIDTH, AXI_M_ID_WIDTH, AXI_LEN_WIDTH
  ).mon_mp vif_t;

  `uvm_component_utils(axi_stage2_read_write_parallel_test)

  function new(string name = "axi_stage2_read_write_parallel_test",
               uvm_component parent = null);
    super.new(name, parent);
  endfunction

  extern task check_parallel_progress(vif_t vif);
  extern virtual task run_phase(uvm_phase phase);

endclass

task axi_stage2_read_write_parallel_test::check_parallel_progress(vif_t vif);
  bit write_wait_b;
  bit read_wait_last;
  bit read_progress_while_write_waits;
  bit write_completed_while_read_waits;

  while (!read_progress_while_write_waits ||
         !write_completed_while_read_waits) begin
    @(posedge vif.ACLK);
    if (vif.wvalid && vif.wready && vif.wlast)
      write_wait_b = 1'b1;
    if (vif.arvalid && vif.arready)
      read_wait_last = 1'b1;
    if (write_wait_b && vif.rvalid && vif.rready)
      read_progress_while_write_waits = 1'b1;
    if (read_wait_last && vif.bvalid && vif.bready)
      write_completed_while_read_waits = 1'b1;
    if (vif.bvalid && vif.bready)
      write_wait_b = 1'b0;
    if (vif.rvalid && vif.rready && vif.rlast)
      read_wait_last = 1'b0;
  end
endtask

task axi_stage2_read_write_parallel_test::run_phase(uvm_phase phase);
  axi_stage2_read_write_parallel_sequence scenario;

  phase.raise_objection(this);
  configure_ready_fixed(0, 0, 0, 0, 0);
  scenario = axi_stage2_read_write_parallel_sequence::type_id::create(
    "scenario"
  );
  wait_for_reset_release();
  fork
    check_parallel_progress(env_cfg.m_cfg[0].mon_vif);
    run_stage2_scenario(scenario, 1, 1,
                        "axi_stage2_read_write_parallel_test");
  join
  phase.drop_objection(this);
endtask

`endif

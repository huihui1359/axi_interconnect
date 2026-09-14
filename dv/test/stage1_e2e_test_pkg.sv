package stage1_e2e_test_pkg;

  import uvm_pkg::*;
  `include "uvm_macros.svh"

  import axi_types_pkg::*;
  import axi_env_pkg::*;
  import axi_seq_pkg::*;

  `uvm_analysis_imp_decl(_upstream)
  `uvm_analysis_imp_decl(_downstream)
  `include "support/stage1_e2e_checker.sv"

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
  typedef virtual stage1_reset_if reset_vif_t;

  typedef axi_m_agent_cfg #(
    AXI_ADDR_WIDTH, AXI_DATA_WIDTH, AXI_M_ID_WIDTH, AXI_LEN_WIDTH
  ) m_cfg_t;
  typedef axi_s_agent_cfg #(
    AXI_ADDR_WIDTH, AXI_DATA_WIDTH, AXI_S_ID_WIDTH, AXI_LEN_WIDTH
  ) s_cfg_t;
  typedef axi_m_agent #(
    AXI_ADDR_WIDTH, AXI_DATA_WIDTH, AXI_M_ID_WIDTH, AXI_LEN_WIDTH
  ) m_agent_t;
  typedef axi_s_agent #(
    AXI_ADDR_WIDTH, AXI_DATA_WIDTH, AXI_S_ID_WIDTH, AXI_LEN_WIDTH
  ) s_agent_t;
  typedef axi_m_single_write_seq #(
    AXI_ADDR_WIDTH, AXI_DATA_WIDTH, AXI_M_ID_WIDTH, AXI_LEN_WIDTH
  ) m_write_seq_t;
  typedef axi_m_single_read_seq #(
    AXI_ADDR_WIDTH, AXI_DATA_WIDTH, AXI_M_ID_WIDTH, AXI_LEN_WIDTH
  ) m_read_seq_t;
  typedef axi_s_single_reactive_seq #(
    AXI_ADDR_WIDTH, AXI_DATA_WIDTH, AXI_S_ID_WIDTH, AXI_LEN_WIDTH
  ) s_reactive_seq_t;
  typedef stage1_e2e_checker #(
    AXI_ADDR_WIDTH, AXI_DATA_WIDTH,
    AXI_M_ID_WIDTH, AXI_S_ID_WIDTH, AXI_LEN_WIDTH
  ) e2e_checker_t;

  class stage1_e2e_base_test extends uvm_test;
    m_drv_vif_t m_drv_vif;
    m_mon_vif_t m_mon_vif;
    s_drv_vif_t s_drv_vif;
    s_mon_vif_t s_mon_vif;
    reset_vif_t reset_vif;

    m_cfg_t m_cfg;
    s_cfg_t s_cfg;
    m_agent_t m_agent;
    s_agent_t s_agent;
    e2e_checker_t e2e_checker;
    int unsigned failure_count;

    `uvm_component_utils(stage1_e2e_base_test)

    extern function new(string name = "stage1_e2e_base_test",
                        uvm_component parent = null);
    extern virtual function void build_phase(uvm_phase phase);
    extern virtual function void connect_phase(uvm_phase phase);
    extern task wait_for_reset_release();
    extern task wait_for_counts(
      int unsigned aw_count,
      int unsigned w_count,
      int unsigned b_count,
      int unsigned ar_count,
      int unsigned r_count
    );
    extern function void check_condition(bit condition, string message);
    extern task finish_with_status(
      string test_name,
      int unsigned aw_count,
      int unsigned w_count,
      int unsigned b_count,
      int unsigned ar_count,
      int unsigned r_count
    );

  endclass

  function stage1_e2e_base_test::new(
    string name = "stage1_e2e_base_test",
    uvm_component parent = null
  );
    super.new(name, parent);
    failure_count = 0;
  endfunction

  function void stage1_e2e_base_test::build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(m_drv_vif_t)::get(this, "", "m_drv_vif", m_drv_vif))
      `uvm_fatal("STAGE1_E2E_VIF", "m_drv_vif was not provided")
    if (!uvm_config_db#(m_mon_vif_t)::get(this, "", "m_mon_vif", m_mon_vif))
      `uvm_fatal("STAGE1_E2E_VIF", "m_mon_vif was not provided")
    if (!uvm_config_db#(s_drv_vif_t)::get(this, "", "s_drv_vif", s_drv_vif))
      `uvm_fatal("STAGE1_E2E_VIF", "s_drv_vif was not provided")
    if (!uvm_config_db#(s_mon_vif_t)::get(this, "", "s_mon_vif", s_mon_vif))
      `uvm_fatal("STAGE1_E2E_VIF", "s_mon_vif was not provided")
    if (!uvm_config_db#(reset_vif_t)::get(this, "", "reset_vif", reset_vif))
      `uvm_fatal("STAGE1_E2E_VIF", "reset_vif was not provided")

    m_cfg = m_cfg_t::type_id::create("m_cfg");
    m_cfg.is_active  = UVM_ACTIVE;
    m_cfg.port_index = 0;
    m_cfg.drv_vif    = m_drv_vif;
    m_cfg.mon_vif    = m_mon_vif;

    s_cfg = s_cfg_t::type_id::create("s_cfg");
    s_cfg.is_active  = UVM_ACTIVE;
    s_cfg.port_index = 0;
    s_cfg.drv_vif    = s_drv_vif;
    s_cfg.mon_vif    = s_mon_vif;

    uvm_config_db#(m_cfg_t)::set(this, "m_agent", "cfg", m_cfg);
    uvm_config_db#(s_cfg_t)::set(this, "s_agent", "cfg", s_cfg);
    uvm_config_db#(reset_vif_t)::set(
      this, "e2e_checker", "reset_vif", reset_vif
    );

    m_agent = m_agent_t::type_id::create("m_agent", this);
    s_agent = s_agent_t::type_id::create("s_agent", this);
    e2e_checker = e2e_checker_t::type_id::create("e2e_checker", this);
  endfunction

  function void stage1_e2e_base_test::connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    m_agent.monitor.channel_ap.connect(e2e_checker.upstream_export);
    s_agent.monitor.channel_ap.connect(e2e_checker.downstream_export);
  endfunction

  task stage1_e2e_base_test::wait_for_reset_release();
    while (reset_vif.aresetn !== 1'b1)
      @(posedge reset_vif.aclk);
    @(posedge reset_vif.aclk);
  endtask

  task stage1_e2e_base_test::wait_for_counts(
    int unsigned aw_count,
    int unsigned w_count,
    int unsigned b_count,
    int unsigned ar_count,
    int unsigned r_count
  );
    for (int unsigned cycle = 0; cycle < 200; cycle++) begin
      @(posedge reset_vif.aclk);
      if ((e2e_checker.aw_match_count == aw_count) &&
          (e2e_checker.w_match_count  == w_count) &&
          (e2e_checker.b_match_count  == b_count) &&
          (e2e_checker.ar_match_count == ar_count) &&
          (e2e_checker.r_match_count  == r_count))
        return;
    end
    check_condition(1'b0, "Timed out waiting for end-to-end channel matches");
  endtask

  function void stage1_e2e_base_test::check_condition(
    bit condition,
    string message
  );
    if (!condition) begin
      failure_count++;
      `uvm_error("STAGE1_E2E_CHECK", message)
    end
  endfunction

  task stage1_e2e_base_test::finish_with_status(
    string test_name,
    int unsigned aw_count,
    int unsigned w_count,
    int unsigned b_count,
    int unsigned ar_count,
    int unsigned r_count
  );
    int error_count;
    wait_for_counts(aw_count, w_count, b_count, ar_count, r_count);
    repeat (2) @(posedge reset_vif.aclk);
    check_condition((e2e_checker.aw_match_count == aw_count) &&
                    (e2e_checker.w_match_count  == w_count) &&
                    (e2e_checker.b_match_count  == b_count) &&
                    (e2e_checker.ar_match_count == ar_count) &&
                    (e2e_checker.r_match_count  == r_count),
                    "End-to-end channel match count changed unexpectedly");
    check_condition(e2e_checker.mismatch_count == 0,
                    "End-to-end checker reported a mismatch");
    check_condition(e2e_checker.pending_count() == 0,
                    "End-to-end checker has pending events or contexts");
    check_condition(s_agent.sequencer.request_fifo.used() == 0,
                    "Slave reactive request FIFO is not empty");
    error_count = uvm_report_server::get_server().get_severity_count(UVM_ERROR);
    if ((failure_count != 0) || (error_count != 0))
      `uvm_fatal("STAGE1_E2E_FAIL", $sformatf(
        "%s failed: local=%0d uvm_errors=%0d",
        test_name, failure_count, error_count))
    `uvm_info("STAGE1_E2E_PASS", {test_name, " passed"}, UVM_NONE)
  endtask

  class stage1_e2e_write_test extends stage1_e2e_base_test;
    `uvm_component_utils(stage1_e2e_write_test)

    extern function new(string name = "stage1_e2e_write_test",
                        uvm_component parent = null);
    extern virtual task run_phase(uvm_phase phase);
  endclass

  function stage1_e2e_write_test::new(
    string name = "stage1_e2e_write_test",
    uvm_component parent = null
  );
    super.new(name, parent);
  endfunction

  task stage1_e2e_write_test::run_phase(uvm_phase phase);
    m_write_seq_t write_seq;
    s_reactive_seq_t reactive_seq;
    phase.raise_objection(this);
    wait_for_reset_release();

    write_seq = m_write_seq_t::type_id::create("write_seq");
    write_seq.id   = 4'h5;
    write_seq.addr = 32'h0000_0080;
    write_seq.data = 32'hDEAD_BEEF;
    write_seq.strb = 4'hF;

    reactive_seq = s_reactive_seq_t::type_id::create("reactive_seq");
    reactive_seq.response_count = 1;
    reactive_seq.response_code  = AXI_RESP_OKAY;

    fork
      reactive_seq.start(s_agent.sequencer);
      write_seq.start(m_agent.sequencer);
    join

    finish_with_status("stage1_e2e_write_test", 1, 1, 1, 0, 0);
    phase.drop_objection(this);
  endtask

  class stage1_e2e_read_test extends stage1_e2e_base_test;
    `uvm_component_utils(stage1_e2e_read_test)

    extern function new(string name = "stage1_e2e_read_test",
                        uvm_component parent = null);
    extern virtual task run_phase(uvm_phase phase);
  endclass

  function stage1_e2e_read_test::new(
    string name = "stage1_e2e_read_test",
    uvm_component parent = null
  );
    super.new(name, parent);
  endfunction

  task stage1_e2e_read_test::run_phase(uvm_phase phase);
    m_read_seq_t read_seq;
    s_reactive_seq_t reactive_seq;
    phase.raise_objection(this);
    wait_for_reset_release();

    read_seq = m_read_seq_t::type_id::create("read_seq");
    read_seq.id   = 4'h5;
    read_seq.addr = 32'h0000_0100;

    reactive_seq = s_reactive_seq_t::type_id::create("reactive_seq");
    reactive_seq.response_count = 1;
    reactive_seq.read_data      = 32'hCAFE_BABE;
    reactive_seq.response_code  = AXI_RESP_OKAY;

    fork
      reactive_seq.start(s_agent.sequencer);
      read_seq.start(m_agent.sequencer);
    join

    finish_with_status("stage1_e2e_read_test", 0, 0, 0, 1, 1);
    phase.drop_objection(this);
  endtask

  class stage1_e2e_reset_test extends stage1_e2e_base_test;
    `uvm_component_utils(stage1_e2e_reset_test)

    extern function new(string name = "stage1_e2e_reset_test",
                        uvm_component parent = null);
    extern virtual task run_phase(uvm_phase phase);
  endclass

  function stage1_e2e_reset_test::new(
    string name = "stage1_e2e_reset_test",
    uvm_component parent = null
  );
    super.new(name, parent);
  endfunction

  task stage1_e2e_reset_test::run_phase(uvm_phase phase);
    m_read_seq_t read_seq;
    s_reactive_seq_t reactive_seq;
    phase.raise_objection(this);
    wait_for_reset_release();
    reset_vif.pulse_reset(2);
    wait_for_reset_release();

    read_seq = m_read_seq_t::type_id::create("read_seq");
    read_seq.id   = 4'h5;
    read_seq.addr = 32'h0000_0180;

    reactive_seq = s_reactive_seq_t::type_id::create("reactive_seq");
    reactive_seq.response_count = 1;
    reactive_seq.read_data      = 32'h1234_5678;

    fork
      reactive_seq.start(s_agent.sequencer);
      read_seq.start(m_agent.sequencer);
    join

    finish_with_status("stage1_e2e_reset_test", 0, 0, 0, 1, 1);
    phase.drop_objection(this);
  endtask

endpackage

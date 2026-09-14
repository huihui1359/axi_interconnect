package stage0_test_pkg;

  import uvm_pkg::*;
  `include "uvm_macros.svh"

  import axi_types_pkg::*;
  import axi_env_pkg::*;

  class stage0_smoke_test extends uvm_test;

    typedef axi_req_item #(
      AXI_ADDR_WIDTH, AXI_DATA_WIDTH, AXI_M_ID_WIDTH, AXI_LEN_WIDTH
    ) m_req_t;

    typedef axi_rsp_item #(
      AXI_DATA_WIDTH, AXI_S_ID_WIDTH, AXI_LEN_WIDTH
    ) s_rsp_t;

    typedef axi_m_agent_cfg #(
      AXI_ADDR_WIDTH, AXI_DATA_WIDTH, AXI_M_ID_WIDTH, AXI_LEN_WIDTH
    ) m_cfg_t;

    typedef axi_s_agent_cfg #(
      AXI_ADDR_WIDTH, AXI_DATA_WIDTH, AXI_S_ID_WIDTH, AXI_LEN_WIDTH
    ) s_cfg_t;

    typedef axi_env_cfg #(
      AXI_ADDR_WIDTH, AXI_DATA_WIDTH,
      AXI_M_ID_WIDTH, AXI_S_ID_WIDTH, AXI_LEN_WIDTH,
      AXI_NUM_MASTERS, AXI_NUM_SLAVES
    ) env_cfg_t;

    typedef axi_m_sequencer #(
      AXI_ADDR_WIDTH, AXI_DATA_WIDTH, AXI_M_ID_WIDTH, AXI_LEN_WIDTH
    ) m_seqr_t;

    typedef axi_s_sequencer #(
      AXI_ADDR_WIDTH, AXI_DATA_WIDTH, AXI_S_ID_WIDTH, AXI_LEN_WIDTH
    ) s_seqr_t;

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

    m_seqr_t m_seqr;
    s_seqr_t s_seqr;

    int unsigned failure_count;

    `uvm_component_utils(stage0_smoke_test)

    function new(string name = "stage0_smoke_test", uvm_component parent = null);
      super.new(name, parent);
      failure_count = 0;
    endfunction

    function void check_condition(bit condition, string message);
      if (!condition) begin
        failure_count++;
        `uvm_error("STAGE0_CHECK", message)
      end
    endfunction

    virtual function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      m_seqr = m_seqr_t::type_id::create("m_seqr", this);
      s_seqr = s_seqr_t::type_id::create("s_seqr", this);
    endfunction

    virtual task run_phase(uvm_phase phase);
      m_req_t       read_req;
      m_req_t       write_req;
      m_req_t       write_req_clone;
      s_rsp_t       read_rsp;
      s_rsp_t       write_rsp;
      s_rsp_t       read_rsp_clone;
      m_cfg_t       m_cfg;
      s_cfg_t       s_cfg;
      env_cfg_t     env_cfg;
      m_drv_vif_t   m_drv_vif;
      m_mon_vif_t   m_mon_vif;
      s_drv_vif_t   s_drv_vif;
      s_mon_vif_t   s_mon_vif;
      bit [AXI_DATA_WIDTH-1:0] original_req_data;
      bit [AXI_DATA_WIDTH-1:0] original_rsp_data;

      phase.raise_objection(this);

      read_req  = m_req_t::type_id::create("read_req");
      write_req = m_req_t::type_id::create("write_req");
      read_rsp  = s_rsp_t::type_id::create("read_rsp");
      write_rsp = s_rsp_t::type_id::create("write_rsp");
      m_cfg     = m_cfg_t::type_id::create("m_cfg");
      s_cfg     = s_cfg_t::type_id::create("s_cfg");
      env_cfg   = env_cfg_t::type_id::create("env_cfg");

      check_condition(read_req != null, "Master read request factory creation failed");
      check_condition(write_req != null, "Master write request factory creation failed");
      check_condition(read_rsp != null, "Slave read response factory creation failed");
      check_condition(write_rsp != null, "Slave write response factory creation failed");
      check_condition(m_cfg != null, "Master agent config factory creation failed");
      check_condition(s_cfg != null, "Slave agent config factory creation failed");
      check_condition(env_cfg != null, "Environment config factory creation failed");
      check_condition(m_seqr != null, "Master sequencer factory creation failed");
      check_condition(s_seqr != null, "Slave sequencer factory creation failed");

      if (!read_req.randomize() with {
        dir == AXI_READ;
        len == 0;
      }) begin
        check_condition(0, "Master read request randomization failed");
      end
      check_condition(read_req.wdata.size() == 0, "Read request wdata must be empty");
      check_condition(read_req.wstrb.size() == 0, "Read request wstrb must be empty");
      check_condition(read_req.wbeat_gap.size() == 0,
                      "Read request wbeat_gap must be empty");

      if (!write_req.randomize() with {
        dir == AXI_WRITE;
        burst == AXI_BURST_INCR;
        len == 1;
        size == 2;
      }) begin
        check_condition(0, "Master write request randomization failed");
      end
      check_condition(write_req.wdata.size() == 2,
                      "Two-beat write request must contain two data beats");
      check_condition(write_req.wstrb.size() == 2,
                      "Two-beat write request must contain two strobes");
      check_condition(write_req.wbeat_gap.size() == 2,
                      "Two-beat write request must contain two gap entries");

      if (!$cast(write_req_clone, write_req.clone())) begin
        check_condition(0, "Master write request clone cast failed");
      end
      else begin
        check_condition(write_req.compare(write_req_clone),
                        "Master write request clone compare failed");
        original_req_data = write_req.wdata[0];
        write_req_clone.wdata[0] = ~write_req_clone.wdata[0];
        check_condition(write_req.wdata[0] == original_req_data,
                        "Master request clone shares dynamic-array storage");
      end

      read_rsp.dir = AXI_READ;
      read_rsp.id  = 8'hA5;
      read_rsp.len = 1;
      if (!read_rsp.randomize())
        check_condition(0, "Slave read response randomization failed");
      check_condition(read_rsp.rdata.size() == 2,
                      "Two-beat read response must contain two data beats");
      check_condition(read_rsp.rresp.size() == 2,
                      "Two-beat read response must contain two response entries");
      check_condition(read_rsp.rbeat_gap.size() == 1,
                      "Two-beat read response must contain one inter-beat gap");

      if (!$cast(read_rsp_clone, read_rsp.clone())) begin
        check_condition(0, "Slave read response clone cast failed");
      end
      else begin
        check_condition(read_rsp.compare(read_rsp_clone),
                        "Slave read response clone compare failed");
        original_rsp_data = read_rsp.rdata[0];
        read_rsp_clone.rdata[0] = ~read_rsp_clone.rdata[0];
        check_condition(read_rsp.rdata[0] == original_rsp_data,
                        "Slave response clone shares dynamic-array storage");
      end

      write_rsp.dir = AXI_WRITE;
      write_rsp.id  = 8'h5A;
      write_rsp.len = 0;
      if (!write_rsp.randomize())
        check_condition(0, "Slave write response randomization failed");
      check_condition(write_rsp.rdata.size() == 0,
                      "Write response rdata must be empty");
      check_condition(write_rsp.rresp.size() == 0,
                      "Write response rresp must be empty");
      check_condition(write_rsp.rbeat_gap.size() == 0,
                      "Write response rbeat_gap must be empty");

      check_condition($bits(read_req.id) == AXI_M_ID_WIDTH,
                      "Master request ID width is not four bits");
      check_condition($bits(read_rsp.id) == AXI_S_ID_WIDTH,
                      "Slave response ID width is not eight bits");

      check_condition(m_cfg.is_active == UVM_ACTIVE,
                      "Master config must default to UVM_ACTIVE");
      check_condition(m_cfg.bready_mode == ALWAYS_READY,
                      "Master BREADY mode must default to ALWAYS_READY");
      check_condition(m_cfg.rready_mode == ALWAYS_READY,
                      "Master RREADY mode must default to ALWAYS_READY");
      check_condition(m_cfg.max_read_outstanding == 1,
                      "Master read outstanding default must be one");
      check_condition(m_cfg.max_write_outstanding == 1,
                      "Master write outstanding default must be one");

      check_condition(s_cfg.is_active == UVM_ACTIVE,
                      "Slave config must default to UVM_ACTIVE");
      check_condition(s_cfg.awready_mode == ALWAYS_READY,
                      "Slave AWREADY mode must default to ALWAYS_READY");
      check_condition(s_cfg.wready_mode == ALWAYS_READY,
                      "Slave WREADY mode must default to ALWAYS_READY");
      check_condition(s_cfg.arready_mode == ALWAYS_READY,
                      "Slave ARREADY mode must default to ALWAYS_READY");

      check_condition($size(env_cfg.m_cfg) == AXI_NUM_MASTERS,
                      "Environment config Master count is incorrect");
      check_condition($size(env_cfg.s_cfg) == AXI_NUM_SLAVES,
                      "Environment config Slave count is incorrect");
      foreach (env_cfg.m_cfg[i]) begin
        check_condition(env_cfg.m_cfg[i] != null,
                        $sformatf("Environment Master config %0d is null", i));
        if (env_cfg.m_cfg[i] != null)
          check_condition(env_cfg.m_cfg[i].port_index == i,
                          $sformatf("Environment Master port_index %0d is incorrect", i));
      end
      foreach (env_cfg.s_cfg[i]) begin
        check_condition(env_cfg.s_cfg[i] != null,
                        $sformatf("Environment Slave config %0d is null", i));
        if (env_cfg.s_cfg[i] != null)
          check_condition(env_cfg.s_cfg[i].port_index == i,
                          $sformatf("Environment Slave port_index %0d is incorrect", i));
      end

      check_condition(uvm_config_db#(m_drv_vif_t)::get(
                        this, "", "m_drv_vif", m_drv_vif
                      ), "Master Driver virtual interface was not provided");
      check_condition(uvm_config_db#(m_mon_vif_t)::get(
                        this, "", "m_mon_vif", m_mon_vif
                      ), "Master Monitor virtual interface was not provided");
      check_condition(uvm_config_db#(s_drv_vif_t)::get(
                        this, "", "s_drv_vif", s_drv_vif
                      ), "Slave Driver virtual interface was not provided");
      check_condition(uvm_config_db#(s_mon_vif_t)::get(
                        this, "", "s_mon_vif", s_mon_vif
                      ), "Slave Monitor virtual interface was not provided");

      m_cfg.drv_vif = m_drv_vif;
      m_cfg.mon_vif = m_mon_vif;
      s_cfg.drv_vif = s_drv_vif;
      s_cfg.mon_vif = s_mon_vif;
      check_condition(m_cfg.drv_vif != null, "Master Driver vif assignment failed");
      check_condition(m_cfg.mon_vif != null, "Master Monitor vif assignment failed");
      check_condition(s_cfg.drv_vif != null, "Slave Driver vif assignment failed");
      check_condition(s_cfg.mon_vif != null, "Slave Monitor vif assignment failed");

      if (failure_count == 0)
        `uvm_info("STAGE0_PASS", "Stage 0 smoke test passed", UVM_NONE)
      else
        `uvm_fatal("STAGE0_FAIL",
                   $sformatf("Stage 0 smoke test failed with %0d checks",
                             failure_count))

      phase.drop_objection(this);
    endtask

  endclass

endpackage

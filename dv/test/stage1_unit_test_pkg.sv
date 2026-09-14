package stage1_unit_test_pkg;

  import uvm_pkg::*;
  `include "uvm_macros.svh"

  import axi_types_pkg::*;
  import axi_env_pkg::*;
  import axi_seq_pkg::*;

  `include "support/pin_peer_checker.sv"

  typedef virtual axi_if #(
    AXI_ADDR_WIDTH, AXI_DATA_WIDTH, AXI_M_ID_WIDTH, AXI_LEN_WIDTH
  ).m_drv_mp m_master_vif_t;
  typedef virtual axi_if #(
    AXI_ADDR_WIDTH, AXI_DATA_WIDTH, AXI_M_ID_WIDTH, AXI_LEN_WIDTH
  ).s_drv_mp m_slave_vif_t;
  typedef virtual axi_if #(
    AXI_ADDR_WIDTH, AXI_DATA_WIDTH, AXI_M_ID_WIDTH, AXI_LEN_WIDTH
  ).mon_mp m_mon_vif_t;

  typedef virtual axi_if #(
    AXI_ADDR_WIDTH, AXI_DATA_WIDTH, AXI_S_ID_WIDTH, AXI_LEN_WIDTH
  ).m_drv_mp s_master_vif_t;
  typedef virtual axi_if #(
    AXI_ADDR_WIDTH, AXI_DATA_WIDTH, AXI_S_ID_WIDTH, AXI_LEN_WIDTH
  ).s_drv_mp s_slave_vif_t;
  typedef virtual axi_if #(
    AXI_ADDR_WIDTH, AXI_DATA_WIDTH, AXI_S_ID_WIDTH, AXI_LEN_WIDTH
  ).mon_mp s_mon_vif_t;
  typedef virtual stage1_reset_if reset_vif_t;

  typedef axi_req_item #(
    AXI_ADDR_WIDTH, AXI_DATA_WIDTH, AXI_M_ID_WIDTH, AXI_LEN_WIDTH
  ) m_req_t;
  typedef axi_req_item #(
    AXI_ADDR_WIDTH, AXI_DATA_WIDTH, AXI_S_ID_WIDTH, AXI_LEN_WIDTH
  ) s_req_t;
  typedef axi_rsp_item #(
    AXI_DATA_WIDTH, AXI_S_ID_WIDTH, AXI_LEN_WIDTH
  ) s_rsp_t;
  typedef axi_channel_event #(
    AXI_ADDR_WIDTH, AXI_DATA_WIDTH, AXI_M_ID_WIDTH, AXI_LEN_WIDTH
  ) m_event_t;
  typedef axi_channel_event #(
    AXI_ADDR_WIDTH, AXI_DATA_WIDTH, AXI_S_ID_WIDTH, AXI_LEN_WIDTH
  ) s_event_t;

  typedef axi_m_agent_cfg #(
    AXI_ADDR_WIDTH, AXI_DATA_WIDTH, AXI_M_ID_WIDTH, AXI_LEN_WIDTH
  ) m_cfg_t;
  typedef axi_s_agent_cfg #(
    AXI_ADDR_WIDTH, AXI_DATA_WIDTH, AXI_S_ID_WIDTH, AXI_LEN_WIDTH
  ) s_cfg_t;
  typedef axi_m_sequencer #(
    AXI_ADDR_WIDTH, AXI_DATA_WIDTH, AXI_M_ID_WIDTH, AXI_LEN_WIDTH
  ) m_seqr_t;
  typedef axi_s_sequencer #(
    AXI_ADDR_WIDTH, AXI_DATA_WIDTH, AXI_S_ID_WIDTH, AXI_LEN_WIDTH
  ) s_seqr_t;
  typedef axi_m_driver #(
    AXI_ADDR_WIDTH, AXI_DATA_WIDTH, AXI_M_ID_WIDTH, AXI_LEN_WIDTH
  ) m_driver_t;
  typedef axi_s_driver #(
    AXI_ADDR_WIDTH, AXI_DATA_WIDTH, AXI_S_ID_WIDTH, AXI_LEN_WIDTH
  ) s_driver_t;
  typedef axi_m_monitor #(
    AXI_ADDR_WIDTH, AXI_DATA_WIDTH, AXI_M_ID_WIDTH, AXI_LEN_WIDTH
  ) m_monitor_t;
  typedef axi_s_monitor #(
    AXI_ADDR_WIDTH, AXI_DATA_WIDTH, AXI_S_ID_WIDTH, AXI_LEN_WIDTH
  ) s_monitor_t;
  typedef axi_m_agent #(
    AXI_ADDR_WIDTH, AXI_DATA_WIDTH, AXI_M_ID_WIDTH, AXI_LEN_WIDTH
  ) m_agent_t;
  typedef axi_s_agent #(
    AXI_ADDR_WIDTH, AXI_DATA_WIDTH, AXI_S_ID_WIDTH, AXI_LEN_WIDTH
  ) s_agent_t;
  typedef axi_basic_event_comparator #(
    AXI_ADDR_WIDTH, AXI_DATA_WIDTH, AXI_M_ID_WIDTH, AXI_LEN_WIDTH
  ) m_comparator_t;
  typedef axi_basic_event_comparator #(
    AXI_ADDR_WIDTH, AXI_DATA_WIDTH, AXI_S_ID_WIDTH, AXI_LEN_WIDTH
  ) s_comparator_t;
  typedef axi_m_single_write_seq #(
    AXI_ADDR_WIDTH, AXI_DATA_WIDTH, AXI_M_ID_WIDTH, AXI_LEN_WIDTH
  ) m_write_seq_t;
  typedef axi_m_single_read_seq #(
    AXI_ADDR_WIDTH, AXI_DATA_WIDTH, AXI_M_ID_WIDTH, AXI_LEN_WIDTH
  ) m_read_seq_t;
  typedef axi_s_single_reactive_seq #(
    AXI_ADDR_WIDTH, AXI_DATA_WIDTH, AXI_S_ID_WIDTH, AXI_LEN_WIDTH
  ) s_reactive_seq_t;

  class stage1_unit_base_test extends uvm_test;
    m_master_vif_t m_master_vif;
    m_slave_vif_t  m_slave_vif;
    m_mon_vif_t    m_mon_vif;
    s_master_vif_t s_master_vif;
    s_slave_vif_t  s_slave_vif;
    s_mon_vif_t    s_mon_vif;
    reset_vif_t    reset_vif;
    int unsigned failure_count;

    `uvm_component_utils(stage1_unit_base_test)

    function new(string name = "stage1_unit_base_test",
                 uvm_component parent = null);
      super.new(name, parent);
      failure_count = 0;
    endfunction

    virtual function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      if (!uvm_config_db#(m_master_vif_t)::get(this, "", "m_master_vif", m_master_vif))
        `uvm_fatal("STAGE1_VIF", "m_master_vif was not provided")
      if (!uvm_config_db#(m_slave_vif_t)::get(this, "", "m_slave_vif", m_slave_vif))
        `uvm_fatal("STAGE1_VIF", "m_slave_vif was not provided")
      if (!uvm_config_db#(m_mon_vif_t)::get(this, "", "m_mon_vif", m_mon_vif))
        `uvm_fatal("STAGE1_VIF", "m_mon_vif was not provided")
      if (!uvm_config_db#(s_master_vif_t)::get(this, "", "s_master_vif", s_master_vif))
        `uvm_fatal("STAGE1_VIF", "s_master_vif was not provided")
      if (!uvm_config_db#(s_slave_vif_t)::get(this, "", "s_slave_vif", s_slave_vif))
        `uvm_fatal("STAGE1_VIF", "s_slave_vif was not provided")
      if (!uvm_config_db#(s_mon_vif_t)::get(this, "", "s_mon_vif", s_mon_vif))
        `uvm_fatal("STAGE1_VIF", "s_mon_vif was not provided")
      if (!uvm_config_db#(reset_vif_t)::get(this, "", "reset_vif", reset_vif))
        `uvm_fatal("STAGE1_VIF", "reset_vif was not provided")
    endfunction

    function void check_condition(bit condition, string message);
      if (!condition) begin
        failure_count++;
        `uvm_error("STAGE1_CHECK", message)
      end
    endfunction

    task wait_for_reset_release();
      while (m_mon_vif.ARESETn !== 1'b1)
        @(posedge m_mon_vif.ACLK);
      @(posedge m_mon_vif.ACLK);
    endtask

    task finish_with_status(string test_name);
      int error_count;
      error_count = uvm_report_server::get_server().get_severity_count(UVM_ERROR);
      if ((failure_count != 0) || (error_count != 0))
        `uvm_fatal("STAGE1_UNIT_FAIL",
                   $sformatf("%s failed: local=%0d uvm_errors=%0d",
                             test_name, failure_count, error_count))
      `uvm_info("STAGE1_UNIT_PASS", {test_name, " passed"}, UVM_NONE)
    endtask

  endclass

  class stage1_direct_rsp_seq extends uvm_sequence #(s_rsp_t);
    axi_dir_e dir;
    bit [AXI_S_ID_WIDTH-1:0] id;
    bit [AXI_DATA_WIDTH-1:0] data;
    axi_resp_e response_code;
    s_rsp_t rsp;

    `uvm_object_utils(stage1_direct_rsp_seq)

    function new(string name = "stage1_direct_rsp_seq");
      super.new(name);
      dir           = AXI_WRITE;
      id            = '0;
      data          = '0;
      response_code = AXI_RESP_OKAY;
    endfunction

    virtual task body();
      rsp = s_rsp_t::type_id::create("rsp");
      start_item(rsp);
      rsp.dir       = dir;
      rsp.id        = id;
      rsp.len       = '0;
      rsp.rsp_delay = 0;
      if (dir == AXI_WRITE) begin
        rsp.bresp     = response_code;
        rsp.rdata     = new[0];
        rsp.rresp     = new[0];
        rsp.rbeat_gap = new[0];
      end
      else begin
        rsp.bresp      = AXI_RESP_OKAY;
        rsp.rdata      = new[1];
        rsp.rresp      = new[1];
        rsp.rbeat_gap  = new[0];
        rsp.rdata[0]   = data;
        rsp.rresp[0]   = response_code;
      end
      finish_item(rsp);
    endtask
  endclass

  class stage1_mutable_m_req_seq extends uvm_sequence #(
    m_req_t,
    axi_rsp_item #(AXI_DATA_WIDTH, AXI_M_ID_WIDTH, AXI_LEN_WIDTH)
  );
    m_req_t req;
    bit [AXI_M_ID_WIDTH-1:0] id;
    bit [AXI_ADDR_WIDTH-1:0] addr;
    bit [AXI_DATA_WIDTH-1:0] data;

    `uvm_object_utils(stage1_mutable_m_req_seq)

    function new(string name = "stage1_mutable_m_req_seq");
      super.new(name);
      id   = '0;
      addr = '0;
      data = '0;
    endfunction

    virtual task body();
      req = m_req_t::type_id::create("req");
      start_item(req);
      req.dir           = AXI_WRITE;
      req.id            = id;
      req.addr          = addr;
      req.len           = 0;
      req.size          = 3'd2;
      req.burst         = AXI_BURST_INCR;
      req.addr_delay    = 0;
      req.w_start_delay = 0;
      req.wdata         = new[1];
      req.wstrb         = new[1];
      req.wbeat_gap     = new[1];
      req.wdata[0]      = data;
      req.wstrb[0]      = 4'hF;
      req.wbeat_gap[0]  = 0;
      finish_item(req);
    endtask
  endclass

  class stage1_m_driver_unit_test extends stage1_unit_base_test;
    m_cfg_t cfg;
    m_seqr_t sequencer;
    m_driver_t driver;
    pin_peer_checker pin_checker;

    `uvm_component_utils(stage1_m_driver_unit_test)

    function new(string name = "stage1_m_driver_unit_test",
                 uvm_component parent = null);
      super.new(name, parent);
    endfunction

    virtual function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      cfg = m_cfg_t::type_id::create("cfg");
      cfg.drv_vif = m_master_vif;
      cfg.mon_vif = m_mon_vif;
      uvm_config_db#(m_cfg_t)::set(this, "driver", "cfg", cfg);
      sequencer = m_seqr_t::type_id::create("sequencer", this);
      driver    = m_driver_t::type_id::create("driver", this);
      pin_checker = pin_peer_checker::type_id::create("pin_checker", this);
    endfunction

    virtual function void connect_phase(uvm_phase phase);
      super.connect_phase(phase);
      driver.seq_item_port.connect(sequencer.seq_item_export);
    endfunction

    virtual task run_phase(uvm_phase phase);
      m_write_seq_t write_seq;
      m_read_seq_t read_seq;
      stage1_mutable_m_req_seq mutable_seq;
      logic [AXI_M_ID_WIDTH-1:0] held_awid;
      logic [AXI_ADDR_WIDTH-1:0] held_awaddr;
      logic [AXI_DATA_WIDTH-1:0] held_wdata;
      logic [AXI_M_ID_WIDTH-1:0] held_arid;
      logic [AXI_ADDR_WIDTH-1:0] held_araddr;

      phase.raise_objection(this);
      m_slave_vif.awready <= 1'b0;
      m_slave_vif.wready  <= 1'b1;
      m_slave_vif.arready <= 1'b0;
      m_slave_vif.bvalid  <= 1'b0;
      m_slave_vif.bid     <= '0;
      m_slave_vif.bresp   <= '0;
      m_slave_vif.rvalid  <= 1'b0;
      m_slave_vif.rid     <= '0;
      m_slave_vif.rdata   <= '0;
      m_slave_vif.rresp   <= '0;
      m_slave_vif.rlast   <= 1'b0;
      wait_for_reset_release();

      write_seq       = m_write_seq_t::type_id::create("write_seq");
      write_seq.id    = 4'h5;
      write_seq.addr  = 32'h0000_1020;
      write_seq.size  = 3'd2;
      write_seq.data  = 32'hA5A5_5A5A;
      write_seq.strb  = 4'hF;
      write_seq.start(sequencer);
      pin_checker.check_condition(m_mon_vif.awready === 1'b0,
                                  "write sequence did not return while AWREADY was low");

      do @(posedge m_slave_vif.ACLK);
      while (m_slave_vif.wvalid !== 1'b1);
      pin_checker.check_condition(m_slave_vif.wid === 4'h5, "WID mismatch");
      pin_checker.check_condition(m_slave_vif.wdata === 32'hA5A5_5A5A,
                              "WDATA mismatch");
      pin_checker.check_condition(m_slave_vif.wstrb === 4'hF, "WSTRB mismatch");
      pin_checker.check_condition(m_slave_vif.wlast === 1'b1, "WLAST mismatch");
      m_slave_vif.wready <= 1'b0;

      do @(posedge m_slave_vif.ACLK);
      while (m_slave_vif.awvalid !== 1'b1);
      held_awid   = m_slave_vif.awid;
      held_awaddr = m_slave_vif.awaddr;
      repeat (2) begin
        @(posedge m_slave_vif.ACLK);
        pin_checker.check_condition(m_slave_vif.awvalid === 1'b1,
                                "AWVALID dropped during stall");
        pin_checker.check_condition((m_slave_vif.awid === held_awid) &&
                                (m_slave_vif.awaddr === held_awaddr),
                                "AW payload changed during stall");
      end
      pin_checker.check_condition((held_awid === 4'h5) &&
                              (held_awaddr === 32'h0000_1020),
                              "AW payload mismatch");
      m_slave_vif.awready <= 1'b1;
      m_slave_vif.wready  <= 1'b1;
      @(posedge m_slave_vif.ACLK);
      m_slave_vif.awready <= 1'b0;
      m_slave_vif.wready  <= 1'b0;

      while (m_slave_vif.bready !== 1'b1)
        @(posedge m_slave_vif.ACLK);
      m_slave_vif.bid    <= 4'h5;
      m_slave_vif.bresp  <= AXI_RESP_OKAY;
      m_slave_vif.bvalid <= 1'b1;
      @(posedge m_slave_vif.ACLK);
      pin_checker.check_condition(m_slave_vif.bready === 1'b1,
                              "BREADY is not ALWAYS_READY");
      m_slave_vif.bvalid <= 1'b0;

      read_seq      = m_read_seq_t::type_id::create("read_seq");
      read_seq.id   = 4'h9;
      read_seq.addr = 32'h0000_2040;
      read_seq.size = 3'd2;
      read_seq.start(sequencer);
      do @(posedge m_slave_vif.ACLK);
      while (m_slave_vif.arvalid !== 1'b1);
      held_arid   = m_slave_vif.arid;
      held_araddr = m_slave_vif.araddr;
      repeat (2) begin
        @(posedge m_slave_vif.ACLK);
        pin_checker.check_condition(m_slave_vif.arvalid === 1'b1,
                                "ARVALID dropped during stall");
        pin_checker.check_condition((m_slave_vif.arid === held_arid) &&
                                (m_slave_vif.araddr === held_araddr),
                                "AR payload changed during stall");
      end
      pin_checker.check_condition((held_arid === 4'h9) &&
                              (held_araddr === 32'h0000_2040),
                              "AR payload mismatch");
      m_slave_vif.arready <= 1'b1;
      @(posedge m_slave_vif.ACLK);
      m_slave_vif.arready <= 1'b0;

      while (m_slave_vif.rready !== 1'b1)
        @(posedge m_slave_vif.ACLK);
      m_slave_vif.rid    <= 4'h9;
      m_slave_vif.rdata  <= 32'hCAFE_BABE;
      m_slave_vif.rresp  <= AXI_RESP_OKAY;
      m_slave_vif.rlast  <= 1'b1;
      m_slave_vif.rvalid <= 1'b1;
      @(posedge m_slave_vif.ACLK);
      pin_checker.check_condition(m_slave_vif.rready === 1'b1,
                              "RREADY is not ALWAYS_READY");
      m_slave_vif.rvalid <= 1'b0;
      m_slave_vif.rlast  <= 1'b0;
      repeat (2) @(posedge m_slave_vif.ACLK);

      // Reset must cancel an in-flight request and must not replay it.
      mutable_seq      = stage1_mutable_m_req_seq::type_id::create("mutable_seq");
      mutable_seq.id   = 4'h2;
      mutable_seq.addr = 32'h0000_1080;
      mutable_seq.data = 32'hDEAD_0002;
      mutable_seq.start(sequencer);
      mutable_seq.req.addr     = 32'hFFFF_FFFF;
      mutable_seq.req.wdata[0] = 32'hFFFF_FFFF;
      do @(posedge m_mon_vif.ACLK);
      while ((m_mon_vif.awvalid !== 1'b1) ||
             (m_mon_vif.wvalid !== 1'b1));
      pin_checker.check_condition((m_mon_vif.awaddr === 32'h0000_1080) &&
                                  (m_mon_vif.wdata === 32'hDEAD_0002),
                                  "Driver did not isolate its request snapshot");
      reset_vif.pulse_reset(2);
      @(posedge m_mon_vif.ACLK);
      pin_checker.check_condition((m_mon_vif.awvalid === 1'b0) &&
                                  (m_mon_vif.wvalid === 1'b0),
                                  "Reset did not cancel Master request VALIDs");
      repeat (2) @(posedge m_mon_vif.ACLK);
      pin_checker.check_condition((m_mon_vif.awvalid === 1'b0) &&
                                  (m_mon_vif.wvalid === 1'b0),
                                  "Canceled Master request replayed after reset");

      check_condition(pin_checker.mismatch_count == 0,
                      "Master pin_peer_checker reported mismatches");
      finish_with_status("stage1_m_driver_unit_test");
      phase.drop_objection(this);
    endtask
  endclass

  class stage1_s_driver_unit_test extends stage1_unit_base_test;
    s_cfg_t cfg;
    s_seqr_t sequencer;
    s_driver_t driver;
    pin_peer_checker pin_checker;

    `uvm_component_utils(stage1_s_driver_unit_test)

    function new(string name = "stage1_s_driver_unit_test",
                 uvm_component parent = null);
      super.new(name, parent);
    endfunction

    virtual function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      cfg = s_cfg_t::type_id::create("cfg");
      cfg.drv_vif = s_slave_vif;
      cfg.mon_vif = s_mon_vif;
      uvm_config_db#(s_cfg_t)::set(this, "driver", "cfg", cfg);
      sequencer = s_seqr_t::type_id::create("sequencer", this);
      driver    = s_driver_t::type_id::create("driver", this);
      pin_checker = pin_peer_checker::type_id::create("pin_checker", this);
    endfunction

    virtual function void connect_phase(uvm_phase phase);
      super.connect_phase(phase);
      driver.seq_item_port.connect(sequencer.seq_item_export);
    endfunction

    virtual task run_phase(uvm_phase phase);
      stage1_direct_rsp_seq rsp_seq;
      logic [AXI_S_ID_WIDTH-1:0] held_id;
      logic [AXI_DATA_WIDTH-1:0] held_data;

      phase.raise_objection(this);
      s_master_vif.awvalid <= 1'b0;
      s_master_vif.wvalid  <= 1'b0;
      s_master_vif.arvalid <= 1'b0;
      s_master_vif.bready  <= 1'b0;
      s_master_vif.rready  <= 1'b0;
      wait_for_reset_release();
      repeat (2) @(posedge s_master_vif.ACLK);
      pin_checker.check_condition(s_master_vif.awready === 1'b1,
                              "AWREADY is not ALWAYS_READY");
      pin_checker.check_condition(s_master_vif.wready === 1'b1,
                              "WREADY is not independent/ALWAYS_READY");
      pin_checker.check_condition(s_master_vif.arready === 1'b1,
                              "ARREADY is not ALWAYS_READY");

      rsp_seq               = stage1_direct_rsp_seq::type_id::create("write_rsp_seq");
      rsp_seq.dir           = AXI_WRITE;
      rsp_seq.id            = 8'h55;
      rsp_seq.response_code = AXI_RESP_SLVERR;
      rsp_seq.start(sequencer);
      rsp_seq.rsp.id    = 8'hFF;
      rsp_seq.rsp.bresp = AXI_RESP_DECERR;
      do @(posedge s_master_vif.ACLK);
      while (s_master_vif.bvalid !== 1'b1);
      held_id = s_master_vif.bid;
      repeat (2) begin
        @(posedge s_master_vif.ACLK);
        pin_checker.check_condition(s_master_vif.bvalid === 1'b1,
                                "BVALID dropped during BREADY stall");
        pin_checker.check_condition((s_master_vif.bid === held_id) &&
                                (s_master_vif.bresp === AXI_RESP_SLVERR),
                                "B payload changed during stall");
      end
      pin_checker.check_condition(held_id === 8'h55, "BID mismatch");
      s_master_vif.bready <= 1'b1;
      @(posedge s_master_vif.ACLK);
      s_master_vif.bready <= 1'b0;

      rsp_seq               = stage1_direct_rsp_seq::type_id::create("read_rsp_seq");
      rsp_seq.dir           = AXI_READ;
      rsp_seq.id            = 8'hA9;
      rsp_seq.data          = 32'h1234_5678;
      rsp_seq.response_code = AXI_RESP_OKAY;
      rsp_seq.start(sequencer);
      rsp_seq.rsp.id       = 8'hFF;
      rsp_seq.rsp.rdata[0] = 32'hFFFF_FFFF;
      do @(posedge s_master_vif.ACLK);
      while (s_master_vif.rvalid !== 1'b1);
      held_id   = s_master_vif.rid;
      held_data = s_master_vif.rdata;
      repeat (2) begin
        @(posedge s_master_vif.ACLK);
        pin_checker.check_condition(s_master_vif.rvalid === 1'b1,
                                "RVALID dropped during RREADY stall");
        pin_checker.check_condition((s_master_vif.rid === held_id) &&
                                (s_master_vif.rdata === held_data) &&
                                (s_master_vif.rlast === 1'b1),
                                "R payload changed during stall");
      end
      pin_checker.check_condition((held_id === 8'hA9) &&
                              (held_data === 32'h1234_5678),
                              "R payload mismatch");
      s_master_vif.rready <= 1'b1;
      @(posedge s_master_vif.ACLK);
      s_master_vif.rready <= 1'b0;
      repeat (2) @(posedge s_master_vif.ACLK);

      // Reset must cancel a stalled response and must not replay it.
      rsp_seq               = stage1_direct_rsp_seq::type_id::create("reset_rsp_seq");
      rsp_seq.dir           = AXI_WRITE;
      rsp_seq.id            = 8'h77;
      rsp_seq.response_code = AXI_RESP_OKAY;
      rsp_seq.start(sequencer);
      do @(posedge s_mon_vif.ACLK);
      while (s_mon_vif.bvalid !== 1'b1);
      fork
        reset_vif.pulse_reset(2);
        begin
          wait (reset_vif.aresetn === 1'b0);
          repeat (2) @(posedge s_mon_vif.ACLK);
          pin_checker.check_condition((s_mon_vif.awready === 1'b0) &&
                                      (s_mon_vif.wready === 1'b0) &&
                                      (s_mon_vif.arready === 1'b0) &&
                                      (s_mon_vif.bvalid === 1'b0),
                                      "Slave Driver outputs were active during reset");
        end
      join
      repeat (3) @(posedge s_mon_vif.ACLK);
      pin_checker.check_condition(s_mon_vif.bvalid === 1'b0,
                                  "Canceled Slave response replayed after reset");

      check_condition(pin_checker.mismatch_count == 0,
                      "Slave pin_peer_checker reported mismatches");
      finish_with_status("stage1_s_driver_unit_test");
      phase.drop_objection(this);
    endtask
  endclass

  class stage1_m_monitor_unit_test extends stage1_unit_base_test;
    m_cfg_t cfg;
    m_monitor_t monitor;
    m_comparator_t comparator;
    uvm_analysis_port #(m_event_t) expected_ap;

    `uvm_component_utils(stage1_m_monitor_unit_test)

    function new(string name = "stage1_m_monitor_unit_test",
                 uvm_component parent = null);
      super.new(name, parent);
    endfunction

    virtual function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      cfg = m_cfg_t::type_id::create("cfg");
      cfg.is_active  = UVM_PASSIVE;
      cfg.port_index = 0;
      cfg.mon_vif    = m_mon_vif;
      uvm_config_db#(m_cfg_t)::set(this, "monitor", "cfg", cfg);
      monitor    = m_monitor_t::type_id::create("monitor", this);
      comparator = m_comparator_t::type_id::create("comparator", this);
      expected_ap = new("expected_ap", this);
    endfunction

    virtual function void connect_phase(uvm_phase phase);
      super.connect_phase(phase);
      expected_ap.connect(comparator.expected_export);
      monitor.channel_ap.connect(comparator.actual_export);
    endfunction

    function m_event_t make_event(axi_channel_e channel);
      m_event_t event_out;
      event_out = m_event_t::type_id::create($sformatf("expected_%s", channel.name()));
      event_out.channel    = channel;
      event_out.side       = AXI_UPSTREAM;
      event_out.port_index = 0;
      event_out.clear_payload();
      return event_out;
    endfunction

    virtual task run_phase(uvm_phase phase);
      m_event_t event_out;
      phase.raise_objection(this);

      m_master_vif.awvalid <= 1'b0;
      m_master_vif.wvalid  <= 1'b0;
      m_master_vif.arvalid <= 1'b0;
      m_master_vif.bready  <= 1'b0;
      m_master_vif.rready  <= 1'b0;
      m_slave_vif.awready  <= 1'b0;
      m_slave_vif.wready   <= 1'b0;
      m_slave_vif.arready  <= 1'b0;
      m_slave_vif.bvalid   <= 1'b0;
      m_slave_vif.rvalid   <= 1'b0;
      wait_for_reset_release();

      // VALID without READY must not publish an event.
      m_master_vif.awid    <= 4'h3;
      m_master_vif.awaddr  <= 32'h1000;
      m_master_vif.awlen   <= '0;
      m_master_vif.awsize  <= 3'd2;
      m_master_vif.awburst <= AXI_BURST_INCR;
      m_master_vif.awvalid <= 1'b1;
      repeat (2) @(posedge m_mon_vif.ACLK);
      check_condition(comparator.match_count == 0,
                      "Monitor published AW without READY");
      event_out           = make_event(AXI_CHANNEL_AW);
      event_out.id        = 4'h3;
      event_out.addr      = 32'h1000;
      event_out.len       = '0;
      event_out.size      = 3'd2;
      event_out.burst_raw = AXI_BURST_INCR;
      expected_ap.write(event_out);
      m_slave_vif.awready <= 1'b1;
      @(posedge m_mon_vif.ACLK);
      m_master_vif.awvalid <= 1'b0;
      m_slave_vif.awready  <= 1'b0;

      event_out      = make_event(AXI_CHANNEL_W);
      event_out.id   = 4'h3;
      event_out.data = 32'h1122_3344;
      event_out.strb = 4'hF;
      event_out.last = 1'b1;
      expected_ap.write(event_out);
      m_master_vif.wid    <= 4'h3;
      m_master_vif.wdata  <= 32'h1122_3344;
      m_master_vif.wstrb  <= 4'hF;
      m_master_vif.wlast  <= 1'b1;
      m_master_vif.wvalid <= 1'b1;
      m_slave_vif.wready  <= 1'b1;
      @(posedge m_mon_vif.ACLK);
      m_master_vif.wvalid <= 1'b0;
      m_slave_vif.wready  <= 1'b0;

      event_out          = make_event(AXI_CHANNEL_B);
      event_out.id       = 4'h3;
      event_out.resp_raw = AXI_RESP_OKAY;
      expected_ap.write(event_out);
      m_slave_vif.bid    <= 4'h3;
      m_slave_vif.bresp  <= AXI_RESP_OKAY;
      m_slave_vif.bvalid <= 1'b1;
      m_master_vif.bready <= 1'b1;
      @(posedge m_mon_vif.ACLK);
      m_slave_vif.bvalid <= 1'b0;
      m_master_vif.bready <= 1'b0;

      event_out           = make_event(AXI_CHANNEL_AR);
      event_out.id        = 4'h7;
      event_out.addr      = 32'h2000;
      event_out.len       = '0;
      event_out.size      = 3'd2;
      event_out.burst_raw = AXI_BURST_FIXED;
      expected_ap.write(event_out);
      m_master_vif.arid    <= 4'h7;
      m_master_vif.araddr  <= 32'h2000;
      m_master_vif.arlen   <= '0;
      m_master_vif.arsize  <= 3'd2;
      m_master_vif.arburst <= AXI_BURST_FIXED;
      m_master_vif.arvalid <= 1'b1;
      m_slave_vif.arready  <= 1'b1;
      @(posedge m_mon_vif.ACLK);
      m_master_vif.arvalid <= 1'b0;
      m_slave_vif.arready  <= 1'b0;

      event_out          = make_event(AXI_CHANNEL_R);
      event_out.id       = 4'h7;
      event_out.data     = 32'h5566_7788;
      event_out.resp_raw = AXI_RESP_SLVERR;
      event_out.last     = 1'b1;
      expected_ap.write(event_out);
      m_slave_vif.rid    <= 4'h7;
      m_slave_vif.rdata  <= 32'h5566_7788;
      m_slave_vif.rresp  <= AXI_RESP_SLVERR;
      m_slave_vif.rlast  <= 1'b1;
      m_slave_vif.rvalid <= 1'b1;
      m_master_vif.rready <= 1'b1;
      @(posedge m_mon_vif.ACLK);
      m_slave_vif.rvalid <= 1'b0;
      m_master_vif.rready <= 1'b0;
      repeat (2) @(posedge m_mon_vif.ACLK);

      // A real pin handshake during reset must not become an event.
      fork
        reset_vif.pulse_reset(2);
        begin
          wait (reset_vif.aresetn === 1'b0);
          m_master_vif.awid    <= 4'hE;
          m_master_vif.awaddr  <= 32'h3000;
          m_master_vif.awlen   <= 0;
          m_master_vif.awsize  <= 3'd2;
          m_master_vif.awburst <= AXI_BURST_INCR;
          m_master_vif.awvalid <= 1'b1;
          m_slave_vif.awready  <= 1'b1;
          @(posedge m_mon_vif.ACLK);
          m_master_vif.awvalid <= 1'b0;
          m_slave_vif.awready  <= 1'b0;
        end
      join
      repeat (2) @(posedge m_mon_vif.ACLK);

      check_condition(comparator.match_count == 5,
                      $sformatf("Expected 5 monitor matches, got %0d",
                                comparator.match_count));
      check_condition(comparator.mismatch_count == 0,
                      "Master Monitor comparator found a mismatch");
      check_condition((comparator.pending_expected() == 0) &&
                      (comparator.pending_actual() == 0),
                      "Master Monitor comparator has pending events");
      finish_with_status("stage1_m_monitor_unit_test");
      phase.drop_objection(this);
    endtask
  endclass

  class stage1_s_monitor_unit_test extends stage1_unit_base_test;
    s_cfg_t cfg;
    s_monitor_t monitor;
    s_comparator_t comparator;
    uvm_analysis_port #(s_event_t) expected_ap;
    uvm_tlm_analysis_fifo #(s_req_t) req_fifo;

    `uvm_component_utils(stage1_s_monitor_unit_test)

    function new(string name = "stage1_s_monitor_unit_test",
                 uvm_component parent = null);
      super.new(name, parent);
    endfunction

    virtual function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      cfg = s_cfg_t::type_id::create("cfg");
      cfg.is_active  = UVM_PASSIVE;
      cfg.port_index = 0;
      cfg.mon_vif    = s_mon_vif;
      uvm_config_db#(s_cfg_t)::set(this, "monitor", "cfg", cfg);
      monitor     = s_monitor_t::type_id::create("monitor", this);
      comparator  = s_comparator_t::type_id::create("comparator", this);
      expected_ap = new("expected_ap", this);
      req_fifo    = new("req_fifo", this);
    endfunction

    virtual function void connect_phase(uvm_phase phase);
      super.connect_phase(phase);
      expected_ap.connect(comparator.expected_export);
      monitor.channel_ap.connect(comparator.actual_export);
      monitor.req_ap.connect(req_fifo.analysis_export);
    endfunction

    function s_event_t make_event(axi_channel_e channel);
      s_event_t event_out;
      event_out = s_event_t::type_id::create($sformatf("expected_%s", channel.name()));
      event_out.channel    = channel;
      event_out.side       = AXI_DOWNSTREAM;
      event_out.port_index = 0;
      event_out.clear_payload();
      return event_out;
    endfunction

    task drive_aw(bit [7:0] id, bit [31:0] addr);
      s_event_t event_out;
      event_out           = make_event(AXI_CHANNEL_AW);
      event_out.id        = id;
      event_out.addr      = addr;
      event_out.len       = 0;
      event_out.size      = 3'd2;
      event_out.burst_raw = AXI_BURST_INCR;
      expected_ap.write(event_out);
      s_master_vif.awid    <= id;
      s_master_vif.awaddr  <= addr;
      s_master_vif.awlen   <= 0;
      s_master_vif.awsize  <= 3'd2;
      s_master_vif.awburst <= AXI_BURST_INCR;
      s_master_vif.awvalid <= 1'b1;
      s_slave_vif.awready  <= 1'b1;
      @(posedge s_mon_vif.ACLK);
      s_master_vif.awvalid <= 1'b0;
      s_slave_vif.awready  <= 1'b0;
    endtask

    task drive_w(bit [7:0] id, bit [31:0] data);
      s_event_t event_out;
      event_out      = make_event(AXI_CHANNEL_W);
      event_out.id   = id;
      event_out.data = data;
      event_out.strb = 4'hF;
      event_out.last = 1'b1;
      expected_ap.write(event_out);
      s_master_vif.wid    <= id;
      s_master_vif.wdata  <= data;
      s_master_vif.wstrb  <= 4'hF;
      s_master_vif.wlast  <= 1'b1;
      s_master_vif.wvalid <= 1'b1;
      s_slave_vif.wready  <= 1'b1;
      @(posedge s_mon_vif.ACLK);
      s_master_vif.wvalid <= 1'b0;
      s_slave_vif.wready  <= 1'b0;
    endtask

    task check_write_req(bit [7:0] id, bit [31:0] addr, bit [31:0] data);
      s_req_t req;
      req_fifo.get(req);
      check_condition((req.dir == AXI_WRITE) && (req.id == id) &&
                      (req.addr == addr) && (req.len == 0),
                      "Reconstructed write request header mismatch");
      check_condition((req.wdata.size() == 1) &&
                      (req.wstrb.size() == 1) &&
                      (req.wdata[0] == data) && (req.wstrb[0] == 4'hF),
                      "Reconstructed write request payload mismatch");
    endtask

    virtual task run_phase(uvm_phase phase);
      s_event_t event_out;
      s_req_t req;
      phase.raise_objection(this);

      s_master_vif.awvalid <= 1'b0;
      s_master_vif.wvalid  <= 1'b0;
      s_master_vif.arvalid <= 1'b0;
      s_master_vif.bready  <= 1'b0;
      s_master_vif.rready  <= 1'b0;
      s_slave_vif.awready  <= 1'b0;
      s_slave_vif.wready   <= 1'b0;
      s_slave_vif.arready  <= 1'b0;
      s_slave_vif.bvalid   <= 1'b0;
      s_slave_vif.rvalid   <= 1'b0;
      wait_for_reset_release();

      // AW before W.
      drive_aw(8'h51, 32'h1000);
      repeat (2) @(posedge s_mon_vif.ACLK);
      check_condition(req_fifo.used() == 0, "Write request published before W");
      drive_w(8'h51, 32'hAAAA_0001);
      check_write_req(8'h51, 32'h1000, 32'hAAAA_0001);

      // W before AW.
      drive_w(8'h52, 32'hAAAA_0002);
      repeat (2) @(posedge s_mon_vif.ACLK);
      check_condition(req_fifo.used() == 0, "Write request published before AW");
      drive_aw(8'h52, 32'h1020);
      check_write_req(8'h52, 32'h1020, 32'hAAAA_0002);

      // AW and W in the same sampled cycle.
      event_out           = make_event(AXI_CHANNEL_AW);
      event_out.id        = 8'h53;
      event_out.addr      = 32'h1040;
      event_out.len       = 0;
      event_out.size      = 3'd2;
      event_out.burst_raw = AXI_BURST_INCR;
      expected_ap.write(event_out);
      event_out      = make_event(AXI_CHANNEL_W);
      event_out.id   = 8'h53;
      event_out.data = 32'hAAAA_0003;
      event_out.strb = 4'hF;
      event_out.last = 1'b1;
      expected_ap.write(event_out);
      s_master_vif.awid    <= 8'h53;
      s_master_vif.awaddr  <= 32'h1040;
      s_master_vif.awlen   <= 0;
      s_master_vif.awsize  <= 3'd2;
      s_master_vif.awburst <= AXI_BURST_INCR;
      s_master_vif.awvalid <= 1'b1;
      s_master_vif.wid     <= 8'h53;
      s_master_vif.wdata   <= 32'hAAAA_0003;
      s_master_vif.wstrb   <= 4'hF;
      s_master_vif.wlast   <= 1'b1;
      s_master_vif.wvalid  <= 1'b1;
      s_slave_vif.awready  <= 1'b1;
      s_slave_vif.wready   <= 1'b1;
      @(posedge s_mon_vif.ACLK);
      s_master_vif.awvalid <= 1'b0;
      s_master_vif.wvalid  <= 1'b0;
      s_slave_vif.awready  <= 1'b0;
      s_slave_vif.wready   <= 1'b0;
      check_write_req(8'h53, 32'h1040, 32'hAAAA_0003);

      event_out           = make_event(AXI_CHANNEL_AR);
      event_out.id        = 8'h61;
      event_out.addr      = 32'h2000;
      event_out.len       = 0;
      event_out.size      = 3'd2;
      event_out.burst_raw = AXI_BURST_FIXED;
      expected_ap.write(event_out);
      s_master_vif.arid    <= 8'h61;
      s_master_vif.araddr  <= 32'h2000;
      s_master_vif.arlen   <= 0;
      s_master_vif.arsize  <= 3'd2;
      s_master_vif.arburst <= AXI_BURST_FIXED;
      s_master_vif.arvalid <= 1'b1;
      s_slave_vif.arready  <= 1'b1;
      @(posedge s_mon_vif.ACLK);
      s_master_vif.arvalid <= 1'b0;
      s_slave_vif.arready  <= 1'b0;
      req_fifo.get(req);
      check_condition((req.dir == AXI_READ) && (req.id == 8'h61) &&
                      (req.addr == 32'h2000) && (req.wdata.size() == 0),
                      "Reconstructed read request mismatch");

      event_out          = make_event(AXI_CHANNEL_B);
      event_out.id       = 8'h53;
      event_out.resp_raw = AXI_RESP_OKAY;
      expected_ap.write(event_out);
      s_slave_vif.bid    <= 8'h53;
      s_slave_vif.bresp  <= AXI_RESP_OKAY;
      s_slave_vif.bvalid <= 1'b1;
      s_master_vif.bready <= 1'b1;
      @(posedge s_mon_vif.ACLK);
      s_slave_vif.bvalid <= 1'b0;
      s_master_vif.bready <= 1'b0;

      event_out          = make_event(AXI_CHANNEL_R);
      event_out.id       = 8'h61;
      event_out.data     = 32'hDEAD_BEEF;
      event_out.resp_raw = AXI_RESP_OKAY;
      event_out.last     = 1'b1;
      expected_ap.write(event_out);
      s_slave_vif.rid    <= 8'h61;
      s_slave_vif.rdata  <= 32'hDEAD_BEEF;
      s_slave_vif.rresp  <= AXI_RESP_OKAY;
      s_slave_vif.rlast  <= 1'b1;
      s_slave_vif.rvalid <= 1'b1;
      s_master_vif.rready <= 1'b1;
      @(posedge s_mon_vif.ACLK);
      s_slave_vif.rvalid <= 1'b0;
      s_master_vif.rready <= 1'b0;
      repeat (2) @(posedge s_mon_vif.ACLK);

      // Reset clears an incomplete AW/W reconstruction.
      drive_aw(8'h71, 32'h3000);
      reset_vif.pulse_reset(2);
      @(posedge s_mon_vif.ACLK);
      drive_w(8'h72, 32'hBBBB_0002);
      repeat (2) @(posedge s_mon_vif.ACLK);
      check_condition(req_fifo.used() == 0,
                      "Pre-reset AW survived into a post-reset write request");
      drive_aw(8'h72, 32'h3020);
      check_write_req(8'h72, 32'h3020, 32'hBBBB_0002);
      repeat (2) @(posedge s_mon_vif.ACLK);

      check_condition(comparator.match_count == 12,
                      $sformatf("Expected 12 Slave Monitor matches, got %0d",
                                comparator.match_count));
      check_condition(comparator.mismatch_count == 0,
                      "Slave Monitor comparator found a mismatch");
      check_condition((comparator.pending_expected() == 0) &&
                      (comparator.pending_actual() == 0) &&
                      (req_fifo.used() == 0),
                      "Slave Monitor test left pending objects");
      finish_with_status("stage1_s_monitor_unit_test");
      phase.drop_objection(this);
    endtask
  endclass

  class stage1_expected_mismatch_catcher extends uvm_report_catcher;
    int unsigned caught_count;
    `uvm_object_utils(stage1_expected_mismatch_catcher)

    function new(string name = "stage1_expected_mismatch_catcher");
      super.new(name);
      caught_count = 0;
    endfunction

    virtual function action_e catch();
      if (get_id() == "AXI_EVENT_MISMATCH") begin
        caught_count++;
        return CAUGHT;
      end
      return THROW;
    endfunction
  endclass

  class stage1_event_comparator_unit_test extends stage1_unit_base_test;
    m_comparator_t comparator;
    uvm_analysis_port #(m_event_t) expected_ap;
    uvm_analysis_port #(m_event_t) actual_ap;

    `uvm_component_utils(stage1_event_comparator_unit_test)

    function new(string name = "stage1_event_comparator_unit_test",
                 uvm_component parent = null);
      super.new(name, parent);
    endfunction

    virtual function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      comparator = m_comparator_t::type_id::create("comparator", this);
      expected_ap = new("expected_ap", this);
      actual_ap   = new("actual_ap", this);
    endfunction

    virtual function void connect_phase(uvm_phase phase);
      super.connect_phase(phase);
      expected_ap.connect(comparator.expected_export);
      actual_ap.connect(comparator.actual_export);
    endfunction

    function m_event_t make_event(axi_channel_e channel, bit [3:0] id);
      m_event_t event_out;
      event_out = m_event_t::type_id::create($sformatf("%s_event", channel.name()));
      event_out.channel      = channel;
      event_out.side         = AXI_UPSTREAM;
      event_out.port_index   = 0;
      event_out.sample_cycle = 10;
      event_out.clear_payload();
      event_out.id        = id;
      event_out.addr      = 32'h1234_5000;
      event_out.len       = 0;
      event_out.size      = 3'd2;
      event_out.burst_raw = AXI_BURST_INCR;
      event_out.data      = 32'h89AB_CDEF;
      event_out.strb      = 4'hF;
      event_out.resp_raw  = AXI_RESP_OKAY;
      event_out.last      = 1'b1;
      return event_out;
    endfunction

    virtual task run_phase(uvm_phase phase);
      m_event_t expected_event;
      m_event_t actual_event;
      stage1_expected_mismatch_catcher catcher;
      phase.raise_objection(this);

      expected_event = make_event(AXI_CHANNEL_AW, 4'hF);
      expected_ap.write(expected_event);
      check_condition(comparator.pending_expected() == 1,
                      "Comparator did not queue unmatched expected event");
      comparator.clear();
      check_condition((comparator.pending_expected() == 0) &&
                      (comparator.pending_actual() == 0) &&
                      (comparator.match_count == 0) &&
                      (comparator.mismatch_count == 0),
                      "Comparator clear did not reset pending state");

      for (int channel_index = 0; channel_index < 5; channel_index++) begin
        expected_event = make_event(axi_channel_e'(channel_index), channel_index[3:0]);
        if (!$cast(actual_event, expected_event.clone()))
          `uvm_fatal("STAGE1_CMP_CLONE", "Comparator test clone failed")
        actual_event.sample_cycle = 100 + channel_index;
        expected_ap.write(expected_event);
        actual_ap.write(actual_event);
      end
      check_condition(comparator.match_count == 5,
                      "Comparator did not match all five channels");

      catcher = stage1_expected_mismatch_catcher::type_id::create("catcher");
      uvm_report_cb::add(comparator, catcher);
      expected_event = make_event(AXI_CHANNEL_W, 4'hA);
      if (!$cast(actual_event, expected_event.clone()))
        `uvm_fatal("STAGE1_CMP_CLONE", "Mismatch test clone failed")
      actual_event.data = ~actual_event.data;
      expected_ap.write(expected_event);
      actual_ap.write(actual_event);

      expected_event = make_event(AXI_CHANNEL_R, 4'hB);
      if (!$cast(actual_event, expected_event.clone()))
        `uvm_fatal("STAGE1_CMP_CLONE", "4-state mismatch test clone failed")
      expected_event.data = 'x;
      actual_event.data   = '0;
      expected_ap.write(expected_event);
      actual_ap.write(actual_event);
      uvm_report_cb::delete(comparator, catcher);

      check_condition(comparator.mismatch_count == 2,
                      "Comparator did not count payload mismatch");
      check_condition(catcher.caught_count == 2,
                      "Expected mismatch report was not observed");
      check_condition((comparator.pending_expected() == 0) &&
                      (comparator.pending_actual() == 0),
                      "Comparator left unmatched objects");
      finish_with_status("stage1_event_comparator_unit_test");
      phase.drop_objection(this);
    endtask
  endclass

  class stage1_agent_unit_test extends stage1_unit_base_test;
    m_cfg_t active_m_cfg;
    m_cfg_t passive_m_cfg;
    s_cfg_t active_s_cfg;
    s_cfg_t passive_s_cfg;
    m_agent_t active_m_agent;
    m_agent_t passive_m_agent;
    s_agent_t active_s_agent;
    s_agent_t passive_s_agent;

    `uvm_component_utils(stage1_agent_unit_test)

    function new(string name = "stage1_agent_unit_test",
                 uvm_component parent = null);
      super.new(name, parent);
    endfunction

    virtual function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      active_m_cfg = m_cfg_t::type_id::create("active_m_cfg");
      active_m_cfg.is_active = UVM_ACTIVE;
      active_m_cfg.drv_vif   = m_master_vif;
      active_m_cfg.mon_vif   = m_mon_vif;
      passive_m_cfg = m_cfg_t::type_id::create("passive_m_cfg");
      passive_m_cfg.is_active = UVM_PASSIVE;
      passive_m_cfg.mon_vif   = m_mon_vif;

      active_s_cfg = s_cfg_t::type_id::create("active_s_cfg");
      active_s_cfg.is_active = UVM_ACTIVE;
      active_s_cfg.drv_vif   = s_slave_vif;
      active_s_cfg.mon_vif   = s_mon_vif;
      passive_s_cfg = s_cfg_t::type_id::create("passive_s_cfg");
      passive_s_cfg.is_active = UVM_PASSIVE;
      passive_s_cfg.mon_vif   = s_mon_vif;

      uvm_config_db#(m_cfg_t)::set(this, "active_m_agent", "cfg", active_m_cfg);
      uvm_config_db#(m_cfg_t)::set(this, "passive_m_agent", "cfg", passive_m_cfg);
      uvm_config_db#(s_cfg_t)::set(this, "active_s_agent", "cfg", active_s_cfg);
      uvm_config_db#(s_cfg_t)::set(this, "passive_s_agent", "cfg", passive_s_cfg);
      active_m_agent  = m_agent_t::type_id::create("active_m_agent", this);
      passive_m_agent = m_agent_t::type_id::create("passive_m_agent", this);
      active_s_agent  = s_agent_t::type_id::create("active_s_agent", this);
      passive_s_agent = s_agent_t::type_id::create("passive_s_agent", this);
    endfunction

    virtual task run_phase(uvm_phase phase);
      phase.raise_objection(this);
      wait_for_reset_release();
      check_condition((active_m_agent.driver != null) &&
                      (active_m_agent.sequencer != null) &&
                      (active_m_agent.monitor != null),
                      "Active Master Agent composition is incomplete");
      check_condition((passive_m_agent.driver == null) &&
                      (passive_m_agent.sequencer == null) &&
                      (passive_m_agent.monitor != null),
                      "Passive Master Agent composition is incorrect");
      check_condition((active_s_agent.driver != null) &&
                      (active_s_agent.sequencer != null) &&
                      (active_s_agent.monitor != null),
                      "Active Slave Agent composition is incomplete");
      check_condition((passive_s_agent.driver == null) &&
                      (passive_s_agent.sequencer == null) &&
                      (passive_s_agent.monitor != null),
                      "Passive Slave Agent composition is incorrect");
      check_condition(active_m_agent.driver.seq_item_port.size() == 1,
                      "Master Agent sequence connection is missing");
      check_condition(active_s_agent.driver.seq_item_port.size() == 1,
                      "Slave Agent response sequence connection is missing");
      check_condition(active_s_agent.monitor.req_ap.size() == 1,
                      "Slave Agent request FIFO connection is missing");
      finish_with_status("stage1_agent_unit_test");
      phase.drop_objection(this);
    endtask
  endclass

  class stage1_reactive_chain_unit_test extends stage1_unit_base_test;
    s_cfg_t cfg;
    s_agent_t agent;

    `uvm_component_utils(stage1_reactive_chain_unit_test)

    function new(string name = "stage1_reactive_chain_unit_test",
                 uvm_component parent = null);
      super.new(name, parent);
    endfunction

    virtual function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      cfg = s_cfg_t::type_id::create("cfg");
      cfg.is_active = UVM_ACTIVE;
      cfg.drv_vif   = s_slave_vif;
      cfg.mon_vif   = s_mon_vif;
      uvm_config_db#(s_cfg_t)::set(this, "agent", "cfg", cfg);
      agent = s_agent_t::type_id::create("agent", this);
    endfunction

    virtual task run_phase(uvm_phase phase);
      s_reactive_seq_t reactive_seq;
      phase.raise_objection(this);
      s_master_vif.awvalid <= 1'b0;
      s_master_vif.wvalid  <= 1'b0;
      s_master_vif.arvalid <= 1'b0;
      s_master_vif.bready  <= 1'b1;
      s_master_vif.rready  <= 1'b1;
      wait_for_reset_release();
      while ((s_master_vif.awready !== 1'b1) ||
             (s_master_vif.wready !== 1'b1) ||
             (s_master_vif.arready !== 1'b1))
        @(posedge s_master_vif.ACLK);

      reactive_seq = s_reactive_seq_t::type_id::create("reactive_seq");
      reactive_seq.response_count = 2;
      reactive_seq.read_data      = 32'h0BAD_F00D;
      fork
        reactive_seq.start(agent.sequencer);
      join_none

      s_master_vif.arid    <= 8'h91;
      s_master_vif.araddr  <= 32'h2000;
      s_master_vif.arlen   <= 0;
      s_master_vif.arsize  <= 3'd2;
      s_master_vif.arburst <= AXI_BURST_INCR;
      s_master_vif.arvalid <= 1'b1;
      @(posedge s_master_vif.ACLK);
      s_master_vif.arvalid <= 1'b0;
      do @(posedge s_master_vif.ACLK);
      while (s_master_vif.rvalid !== 1'b1);
      check_condition((s_master_vif.rid === 8'h91) &&
                      (s_master_vif.rdata === 32'h0BAD_F00D) &&
                      (s_master_vif.rresp === AXI_RESP_OKAY) &&
                      (s_master_vif.rlast === 1'b1),
                      "Reactive read response mismatch");

      s_master_vif.awid    <= 8'h92;
      s_master_vif.awaddr  <= 32'h1000;
      s_master_vif.awlen   <= 0;
      s_master_vif.awsize  <= 3'd2;
      s_master_vif.awburst <= AXI_BURST_INCR;
      s_master_vif.awvalid <= 1'b1;
      s_master_vif.wid     <= 8'h92;
      s_master_vif.wdata   <= 32'hFACE_CAFE;
      s_master_vif.wstrb   <= 4'hF;
      s_master_vif.wlast   <= 1'b1;
      s_master_vif.wvalid  <= 1'b1;
      @(posedge s_master_vif.ACLK);
      s_master_vif.awvalid <= 1'b0;
      s_master_vif.wvalid  <= 1'b0;
      do @(posedge s_master_vif.ACLK);
      while (s_master_vif.bvalid !== 1'b1);
      check_condition((s_master_vif.bid === 8'h92) &&
                      (s_master_vif.bresp === AXI_RESP_OKAY),
                      "Reactive write response mismatch");
      wait fork;
      repeat (2) @(posedge s_master_vif.ACLK);
      check_condition(agent.sequencer.request_fifo.used() == 0,
                      "Reactive request FIFO is not empty");
      finish_with_status("stage1_reactive_chain_unit_test");
      phase.drop_objection(this);
    endtask
  endclass

endpackage

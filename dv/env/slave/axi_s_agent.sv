`ifndef AXI_S_AGENT_SV
`define AXI_S_AGENT_SV

class axi_s_agent #(
  int unsigned ADDR_WIDTH = AXI_ADDR_WIDTH,
  int unsigned DATA_WIDTH = AXI_DATA_WIDTH,
  int unsigned ID_WIDTH   = AXI_S_ID_WIDTH,
  int unsigned LEN_WIDTH  = AXI_LEN_WIDTH
) extends uvm_agent;

  typedef axi_s_agent_cfg #(
    ADDR_WIDTH, DATA_WIDTH, ID_WIDTH, LEN_WIDTH
  ) cfg_t;
  typedef axi_s_driver #(
    ADDR_WIDTH, DATA_WIDTH, ID_WIDTH, LEN_WIDTH
  ) driver_t;
  typedef axi_s_monitor #(
    ADDR_WIDTH, DATA_WIDTH, ID_WIDTH, LEN_WIDTH
  ) monitor_t;
  typedef axi_s_sequencer #(
    ADDR_WIDTH, DATA_WIDTH, ID_WIDTH, LEN_WIDTH
  ) sequencer_t;

  cfg_t cfg;
  driver_t driver;
  monitor_t monitor;
  sequencer_t sequencer;

  `uvm_component_param_utils(
    axi_s_agent #(ADDR_WIDTH, DATA_WIDTH, ID_WIDTH, LEN_WIDTH)
  )

  function new(string name = "axi_s_agent", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(cfg_t)::get(this, "", "cfg", cfg) || (cfg == null))
      `uvm_fatal("AXI_S_AGENT_CFG", "Slave Agent requires a non-null cfg")

    uvm_config_db#(cfg_t)::set(this, "monitor", "cfg", cfg);
    monitor = monitor_t::type_id::create("monitor", this);

    if (cfg.is_active == UVM_ACTIVE) begin
      uvm_config_db#(cfg_t)::set(this, "driver", "cfg", cfg);
      sequencer = sequencer_t::type_id::create("sequencer", this);
      driver    = driver_t::type_id::create("driver", this);
    end
  endfunction

  virtual function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    if (cfg.is_active == UVM_ACTIVE) begin
      driver.seq_item_port.connect(sequencer.seq_item_export);
      monitor.req_ap.connect(sequencer.request_fifo.analysis_export);
    end
  endfunction

endclass

`endif

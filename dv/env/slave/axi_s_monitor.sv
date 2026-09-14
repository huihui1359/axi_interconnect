`ifndef AXI_S_MONITOR_SV
`define AXI_S_MONITOR_SV

class axi_s_monitor #(
  int unsigned ADDR_WIDTH = AXI_ADDR_WIDTH,
  int unsigned DATA_WIDTH = AXI_DATA_WIDTH,
  int unsigned ID_WIDTH   = AXI_S_ID_WIDTH,
  int unsigned LEN_WIDTH  = AXI_LEN_WIDTH
) extends uvm_monitor;

  localparam int unsigned DATA_BYTES = DATA_WIDTH / 8;

  typedef axi_channel_event #(
    ADDR_WIDTH, DATA_WIDTH, ID_WIDTH, LEN_WIDTH
  ) event_t;
  typedef axi_req_item #(
    ADDR_WIDTH, DATA_WIDTH, ID_WIDTH, LEN_WIDTH
  ) req_t;
  typedef axi_s_agent_cfg #(
    ADDR_WIDTH, DATA_WIDTH, ID_WIDTH, LEN_WIDTH
  ) cfg_t;
  typedef virtual axi_if #(
    ADDR_WIDTH, DATA_WIDTH, ID_WIDTH, LEN_WIDTH
  ).mon_mp vif_t;

  cfg_t cfg;
  vif_t vif;
  uvm_analysis_port #(event_t) channel_ap;
  uvm_analysis_port #(req_t) req_ap;
  longint unsigned sample_cycle;

  bit aw_pending;
  bit w_pending;
  logic [ID_WIDTH-1:0] aw_id;
  logic [ADDR_WIDTH-1:0] aw_addr;
  logic [LEN_WIDTH-1:0] aw_len;
  logic [2:0] aw_size;
  logic [1:0] aw_burst;
  logic [ID_WIDTH-1:0] w_id;
  logic [DATA_WIDTH-1:0] w_data;
  logic [DATA_BYTES-1:0] w_strb;
  logic w_last;

  `uvm_component_param_utils(
    axi_s_monitor #(ADDR_WIDTH, DATA_WIDTH, ID_WIDTH, LEN_WIDTH)
  )

  extern function new(string name = "axi_s_monitor", uvm_component parent = null);
  extern virtual function void build_phase(uvm_phase phase);
  extern function void clear_request_state();
  extern function event_t create_event(axi_channel_e channel);
  extern function void publish_write_if_complete();
  extern function void publish_read_request();
  extern virtual task run_phase(uvm_phase phase);

endclass

function axi_s_monitor::new(
  string name = "axi_s_monitor",
  uvm_component parent = null
);
  super.new(name, parent);
  sample_cycle = 0;
  clear_request_state();
endfunction

function void axi_s_monitor::build_phase(uvm_phase phase);
  super.build_phase(phase);
  channel_ap = new("channel_ap", this);
  req_ap     = new("req_ap", this);
  if (!uvm_config_db#(cfg_t)::get(this, "", "cfg", cfg) || (cfg == null))
    `uvm_fatal("AXI_S_MON_CFG", "Slave Monitor requires a non-null cfg")
  vif = cfg.mon_vif;
  if (vif == null)
    `uvm_fatal("AXI_S_MON_VIF", "Slave Monitor requires cfg.mon_vif")
endfunction

function void axi_s_monitor::clear_request_state();
  aw_pending = 1'b0;
  w_pending  = 1'b0;
  aw_id      = '0;
  aw_addr    = '0;
  aw_len     = '0;
  aw_size    = '0;
  aw_burst   = '0;
  w_id       = '0;
  w_data     = '0;
  w_strb     = '0;
  w_last     = 1'b0;
endfunction

function axi_s_monitor::event_t axi_s_monitor::create_event(
  axi_channel_e channel
);
  event_t event_out;
  event_out = event_t::type_id::create($sformatf("%s_event", channel.name()));
  event_out.channel      = channel;
  event_out.side         = AXI_DOWNSTREAM;
  event_out.port_index   = cfg.port_index;
  event_out.sample_cycle = sample_cycle;
  return event_out;
endfunction

function void axi_s_monitor::publish_write_if_complete();
  req_t req;
  if (!aw_pending || !w_pending)
    return;

  if (aw_id !== w_id)
    `uvm_error("AXI_S_MON_WID", "Stage 1 AWID and WID do not match")
  if (aw_len !== '0)
    `uvm_error("AXI_S_MON_AWLEN", "Stage 1 supports only AWLEN=0")
  if (w_last !== 1'b1)
    `uvm_error("AXI_S_MON_WLAST", "Stage 1 single-beat write requires WLAST")

  req = req_t::type_id::create("reconstructed_write_req");
  req.dir           = AXI_WRITE;
  req.id            = aw_id;
  req.addr          = aw_addr;
  req.len           = aw_len;
  req.size          = aw_size;
  req.burst         = axi_burst_e'(aw_burst);
  req.addr_delay    = 0;
  req.w_start_delay = 0;
  req.wdata         = new[1];
  req.wstrb         = new[1];
  req.wbeat_gap     = new[1];
  req.wdata[0]      = w_data;
  req.wstrb[0]      = w_strb;
  req.wbeat_gap[0]  = 0;
  req_ap.write(req);
  clear_request_state();
endfunction

function void axi_s_monitor::publish_read_request();
  req_t req;
  req = req_t::type_id::create("reconstructed_read_req");
  req.dir           = AXI_READ;
  req.id            = vif.arid;
  req.addr          = vif.araddr;
  req.len           = vif.arlen;
  req.size          = vif.arsize;
  req.burst         = axi_burst_e'(vif.arburst);
  req.addr_delay    = 0;
  req.w_start_delay = 0;
  req.wdata         = new[0];
  req.wstrb         = new[0];
  req.wbeat_gap     = new[0];
  if (req.len != '0)
    `uvm_error("AXI_S_MON_ARLEN", "Stage 1 supports only ARLEN=0")
  req_ap.write(req);
endfunction

task axi_s_monitor::run_phase(uvm_phase phase);
  event_t event_out;
  forever begin
    @(posedge vif.ACLK);
    if (vif.ARESETn !== 1'b1) begin
      sample_cycle = 0;
      clear_request_state();
    end
    else begin
      sample_cycle++;

      if ((vif.awvalid === 1'b1) && (vif.awready === 1'b1)) begin
        event_out           = create_event(AXI_CHANNEL_AW);
        event_out.id        = vif.awid;
        event_out.addr      = vif.awaddr;
        event_out.len       = vif.awlen;
        event_out.size      = vif.awsize;
        event_out.burst_raw = vif.awburst;
        channel_ap.write(event_out);

        if (aw_pending)
          `uvm_error("AXI_S_MON_AW", "Second AW arrived before write reconstruction")
        aw_pending = 1'b1;
        aw_id      = vif.awid;
        aw_addr    = vif.awaddr;
        aw_len     = vif.awlen;
        aw_size    = vif.awsize;
        aw_burst   = vif.awburst;
        publish_write_if_complete();
      end

      if ((vif.wvalid === 1'b1) && (vif.wready === 1'b1)) begin
        event_out      = create_event(AXI_CHANNEL_W);
        event_out.id   = vif.wid;
        event_out.data = vif.wdata;
        event_out.strb = vif.wstrb;
        event_out.last = vif.wlast;
        channel_ap.write(event_out);

        if (w_pending)
          `uvm_error("AXI_S_MON_W", "Second W arrived before write reconstruction")
        w_pending = 1'b1;
        w_id      = vif.wid;
        w_data    = vif.wdata;
        w_strb    = vif.wstrb;
        w_last    = vif.wlast;
        publish_write_if_complete();
      end

      if ((vif.bvalid === 1'b1) && (vif.bready === 1'b1)) begin
        event_out          = create_event(AXI_CHANNEL_B);
        event_out.id       = vif.bid;
        event_out.resp_raw = vif.bresp;
        channel_ap.write(event_out);
      end

      if ((vif.arvalid === 1'b1) && (vif.arready === 1'b1)) begin
        event_out           = create_event(AXI_CHANNEL_AR);
        event_out.id        = vif.arid;
        event_out.addr      = vif.araddr;
        event_out.len       = vif.arlen;
        event_out.size      = vif.arsize;
        event_out.burst_raw = vif.arburst;
        channel_ap.write(event_out);
        publish_read_request();
      end

      if ((vif.rvalid === 1'b1) && (vif.rready === 1'b1)) begin
        event_out          = create_event(AXI_CHANNEL_R);
        event_out.id       = vif.rid;
        event_out.data     = vif.rdata;
        event_out.resp_raw = vif.rresp;
        event_out.last     = vif.rlast;
        channel_ap.write(event_out);
      end
    end
  end
endtask

`endif

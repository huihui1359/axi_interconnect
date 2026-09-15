`ifndef AXI_M_MONITOR_SV
`define AXI_M_MONITOR_SV

class axi_m_monitor #(
  int unsigned ADDR_WIDTH = AXI_ADDR_WIDTH,
  int unsigned DATA_WIDTH = AXI_DATA_WIDTH,
  int unsigned ID_WIDTH   = AXI_M_ID_WIDTH,
  int unsigned LEN_WIDTH  = AXI_LEN_WIDTH
) extends uvm_monitor;

  localparam int unsigned DATA_BYTES = DATA_WIDTH / 8;

  typedef axi_channel_event #(
    ADDR_WIDTH, DATA_WIDTH, ID_WIDTH, LEN_WIDTH
  ) event_t;
  typedef axi_req_item #(
    ADDR_WIDTH, DATA_WIDTH, ID_WIDTH, LEN_WIDTH
  ) req_t;
  typedef axi_rsp_item #(DATA_WIDTH, ID_WIDTH, LEN_WIDTH) rsp_t;
  typedef axi_m_agent_cfg #(
    ADDR_WIDTH, DATA_WIDTH, ID_WIDTH, LEN_WIDTH
  ) cfg_t;
  typedef virtual axi_if #(
    ADDR_WIDTH, DATA_WIDTH, ID_WIDTH, LEN_WIDTH
  ).mon_mp vif_t;

  cfg_t cfg;
  vif_t vif;
  uvm_analysis_port #(event_t) channel_ap;
  uvm_analysis_port #(req_t) req_ap;
  uvm_analysis_port #(rsp_t) rsp_ap;
  longint unsigned sample_cycle;

  bit aw_pending;
  logic [ID_WIDTH-1:0] aw_id;
  logic [ADDR_WIDTH-1:0] aw_addr;
  logic [LEN_WIDTH-1:0] aw_len;
  logic [2:0] aw_size;
  logic [1:0] aw_burst;

  bit w_active;
  bit w_complete;
  logic [ID_WIDTH-1:0] w_id;
  logic [DATA_WIDTH-1:0] w_data_q[$];
  logic [DATA_BYTES-1:0] w_strb_q[$];

  bit read_pending;
  logic [ID_WIDTH-1:0] read_id;
  logic [LEN_WIDTH-1:0] read_len;
  bit r_active;
  logic [ID_WIDTH-1:0] r_id;
  logic [DATA_WIDTH-1:0] r_data_q[$];
  logic [1:0] r_resp_q[$];

  `uvm_component_param_utils(
    axi_m_monitor #(ADDR_WIDTH, DATA_WIDTH, ID_WIDTH, LEN_WIDTH)
  )

  extern function new(string name = "axi_m_monitor",
                      uvm_component parent = null);
  extern virtual function void build_phase(uvm_phase phase);
  extern function void clear_write_state();
  extern function void clear_read_state();
  extern function event_t create_event(axi_channel_e channel);
  extern function void publish_write_if_complete();
  extern function void publish_read_request();
  extern function void publish_b_response();
  extern function void capture_r_beat();
  extern virtual task run_phase(uvm_phase phase);

endclass

function axi_m_monitor::new(
  string name = "axi_m_monitor",
  uvm_component parent = null
);
  super.new(name, parent);
  sample_cycle = 0;
  clear_write_state();
  clear_read_state();
endfunction

function void axi_m_monitor::build_phase(uvm_phase phase);
  super.build_phase(phase);
  channel_ap = new("channel_ap", this);
  req_ap     = new("req_ap", this);
  rsp_ap     = new("rsp_ap", this);
  if (!uvm_config_db#(cfg_t)::get(this, "", "cfg", cfg) || (cfg == null))
    `uvm_fatal("AXI_M_MON_CFG", "Master Monitor requires a non-null cfg")
  vif = cfg.mon_vif;
  if (vif == null)
    `uvm_fatal("AXI_M_MON_VIF", "Master Monitor requires cfg.mon_vif")
endfunction

function void axi_m_monitor::clear_write_state();
  aw_pending = 1'b0;
  aw_id      = '0;
  aw_addr    = '0;
  aw_len     = '0;
  aw_size    = '0;
  aw_burst   = '0;
  w_active   = 1'b0;
  w_complete = 1'b0;
  w_id       = '0;
  w_data_q.delete();
  w_strb_q.delete();
endfunction

function void axi_m_monitor::clear_read_state();
  read_pending = 1'b0;
  read_id      = '0;
  read_len     = '0;
  r_active     = 1'b0;
  r_id         = '0;
  r_data_q.delete();
  r_resp_q.delete();
endfunction

function axi_m_monitor::event_t axi_m_monitor::create_event(
  axi_channel_e channel
);
  event_t event_out;
  event_out = event_t::type_id::create($sformatf("%s_event", channel.name()));
  event_out.channel      = channel;
  event_out.side         = AXI_UPSTREAM;
  event_out.port_index   = cfg.port_index;
  event_out.sample_cycle = sample_cycle;
  return event_out;
endfunction

function void axi_m_monitor::publish_write_if_complete();
  req_t req;

  if (!aw_pending || !w_complete)
    return;

  if (aw_id !== w_id)
    `uvm_error("AXI_M_MON_WID", "AWID and WID do not match")
  if (w_data_q.size() != (int'(aw_len) + 1))
    `uvm_error("AXI_M_MON_WCOUNT", $sformatf(
      "Observed %0d W beats, expected %0d",
      w_data_q.size(), int'(aw_len) + 1))

  req = req_t::type_id::create("reconstructed_write_req");
  req.dir           = AXI_WRITE;
  req.id            = aw_id;
  req.addr          = aw_addr;
  req.len           = aw_len;
  req.size          = aw_size;
  req.burst         = axi_burst_e'(aw_burst);
  req.addr_delay    = 0;
  req.w_start_delay = 0;
  req.wdata         = new[w_data_q.size()];
  req.wstrb         = new[w_strb_q.size()];
  req.wbeat_gap     = new[w_data_q.size()];
  foreach (req.wdata[index]) begin
    req.wdata[index]     = w_data_q[index];
    req.wstrb[index]     = w_strb_q[index];
    req.wbeat_gap[index] = 0;
  end
  req_ap.write(req);
  clear_write_state();
endfunction

function void axi_m_monitor::publish_read_request();
  req_t req;

  if (read_pending)
    `uvm_error("AXI_M_MON_AR", "Second AR arrived before RLAST")

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
  req_ap.write(req);

  read_pending = 1'b1;
  read_id      = vif.arid;
  read_len     = vif.arlen;
endfunction

function void axi_m_monitor::publish_b_response();
  rsp_t rsp;
  rsp = rsp_t::type_id::create("reconstructed_write_rsp");
  rsp.dir        = AXI_WRITE;
  rsp.id         = vif.bid;
  rsp.len        = '0;
  rsp.bresp      = axi_resp_e'(vif.bresp);
  rsp.rdata      = new[0];
  rsp.rresp      = new[0];
  rsp.rsp_delay  = 0;
  rsp.rbeat_gap  = new[0];
  rsp_ap.write(rsp);
endfunction

function void axi_m_monitor::capture_r_beat();
  rsp_t rsp;

  if (!r_active) begin
    r_active = 1'b1;
    r_id     = vif.rid;
  end
  else if (vif.rid !== r_id) begin
    `uvm_error("AXI_M_MON_RID", "RID changed within an R burst")
  end

  r_data_q.push_back(vif.rdata);
  r_resp_q.push_back(vif.rresp);

  if (vif.rlast !== 1'b1)
    return;

  if (!read_pending)
    `uvm_error("AXI_M_MON_R", "RLAST arrived without a pending read request")
  else begin
    if (r_id !== read_id)
      `uvm_error("AXI_M_MON_RID", "R burst ID does not match ARID")
    if (r_data_q.size() != (int'(read_len) + 1))
      `uvm_error("AXI_M_MON_RCOUNT", $sformatf(
        "Observed %0d R beats, expected %0d",
        r_data_q.size(), int'(read_len) + 1))
  end

  rsp = rsp_t::type_id::create("reconstructed_read_rsp");
  rsp.dir        = AXI_READ;
  rsp.id         = r_id;
  rsp.len        = read_len;
  rsp.bresp      = AXI_RESP_OKAY;
  rsp.rdata      = new[r_data_q.size()];
  rsp.rresp      = new[r_resp_q.size()];
  rsp.rsp_delay  = 0;
  rsp.rbeat_gap  = new[(r_data_q.size() == 0) ? 0 : r_data_q.size() - 1];
  foreach (rsp.rdata[index]) begin
    rsp.rdata[index] = r_data_q[index];
    rsp.rresp[index] = axi_resp_e'(r_resp_q[index]);
  end
  foreach (rsp.rbeat_gap[index])
    rsp.rbeat_gap[index] = 0;
  rsp_ap.write(rsp);
  clear_read_state();
endfunction

task axi_m_monitor::run_phase(uvm_phase phase);
  event_t event_out;

  forever begin
    @(posedge vif.ACLK);
    if (vif.ARESETn !== 1'b1) begin
      sample_cycle = 0;
      clear_write_state();
      clear_read_state();
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
          `uvm_error("AXI_M_MON_AW", "Second AW arrived before reconstruction")
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

        if (w_complete)
          `uvm_error("AXI_M_MON_W", "W beat arrived after WLAST")
        if (!w_active) begin
          w_active = 1'b1;
          w_id     = vif.wid;
        end
        else if (vif.wid !== w_id) begin
          `uvm_error("AXI_M_MON_WID", "WID changed within a W burst")
        end
        w_data_q.push_back(vif.wdata);
        w_strb_q.push_back(vif.wstrb);
        if (vif.wlast === 1'b1)
          w_complete = 1'b1;
        publish_write_if_complete();
      end

      if ((vif.bvalid === 1'b1) && (vif.bready === 1'b1)) begin
        event_out          = create_event(AXI_CHANNEL_B);
        event_out.id       = vif.bid;
        event_out.resp_raw = vif.bresp;
        channel_ap.write(event_out);
        publish_b_response();
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
        capture_r_beat();
      end
    end
  end
endtask

`endif

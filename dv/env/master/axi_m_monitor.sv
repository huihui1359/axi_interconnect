`ifndef AXI_M_MONITOR_SV
`define AXI_M_MONITOR_SV

class axi_m_monitor #(
  int unsigned ADDR_WIDTH = AXI_ADDR_WIDTH,
  int unsigned DATA_WIDTH = AXI_DATA_WIDTH,
  int unsigned ID_WIDTH   = AXI_M_ID_WIDTH,
  int unsigned LEN_WIDTH  = AXI_LEN_WIDTH
) extends uvm_monitor;

  localparam int unsigned DATA_BYTES = DATA_WIDTH / 8;
  localparam int unsigned ID_COUNT   = 1 << ID_WIDTH;

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

  req_t aw_context_by_id[ID_COUNT][$];
  req_t completed_w_by_id[ID_COUNT][$];
  req_t write_response_by_id[ID_COUNT][$];
  req_t read_context_by_id[ID_COUNT][$];
  req_t active_w_burst;
  req_t active_r_context;
  logic [DATA_WIDTH-1:0] active_w_data[$];
  logic [DATA_BYTES-1:0] active_w_strb[$];
  logic [DATA_WIDTH-1:0] active_r_data[$];
  logic [1:0] active_r_resp[$];

  `uvm_component_param_utils(
    axi_m_monitor #(ADDR_WIDTH, DATA_WIDTH, ID_WIDTH, LEN_WIDTH)
  )

  extern function new(string name = "axi_m_monitor",
                      uvm_component parent = null);
  extern virtual function void build_phase(uvm_phase phase);
  extern function void clear_write_state();
  extern function void clear_read_state();
  extern function event_t create_event(axi_channel_e channel);
  extern function req_t create_address_request(axi_dir_e dir);
  extern function void publish_write_if_complete(int unsigned id);
  extern function void capture_w_beat();
  extern function void publish_read_request();
  extern function void publish_b_response();
  extern function void capture_r_beat();
  extern function int unsigned pending_count();
  extern virtual task run_phase(uvm_phase phase);
  extern virtual function void check_phase(uvm_phase phase);

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
  foreach (aw_context_by_id[id]) begin
    aw_context_by_id[id].delete();
    completed_w_by_id[id].delete();
    write_response_by_id[id].delete();
  end
  active_w_burst = null;
  active_w_data.delete();
  active_w_strb.delete();
endfunction

function void axi_m_monitor::clear_read_state();
  foreach (read_context_by_id[id])
    read_context_by_id[id].delete();
  active_r_context = null;
  active_r_data.delete();
  active_r_resp.delete();
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

function axi_m_monitor::req_t axi_m_monitor::create_address_request(
  axi_dir_e dir
);
  req_t req;
  req = req_t::type_id::create("address_context");
  req.dir           = dir;
  req.id            = (dir == AXI_WRITE) ? vif.awid : vif.arid;
  req.addr          = (dir == AXI_WRITE) ? vif.awaddr : vif.araddr;
  req.len           = (dir == AXI_WRITE) ? vif.awlen : vif.arlen;
  req.size          = (dir == AXI_WRITE) ? vif.awsize : vif.arsize;
  req.burst         = axi_burst_e'((dir == AXI_WRITE) ?
                                   vif.awburst : vif.arburst);
  req.addr_delay    = 0;
  req.w_start_delay = 0;
  req.wdata         = new[0];
  req.wstrb         = new[0];
  req.wbeat_gap     = new[0];
  return req;
endfunction

function void axi_m_monitor::publish_write_if_complete(int unsigned id);
  req_t address_context;
  req_t data_context;
  req_t response_context;

  while ((aw_context_by_id[id].size() != 0) &&
         (completed_w_by_id[id].size() != 0)) begin
    address_context = aw_context_by_id[id].pop_front();
    data_context    = completed_w_by_id[id].pop_front();

    if (data_context.wdata.size() != (int'(address_context.len) + 1))
      `uvm_error("AXI_M_MON_WCOUNT", $sformatf(
        "Observed %0d W beats, expected %0d for ID 0x%0h",
        data_context.wdata.size(), int'(address_context.len) + 1, id))

    address_context.wdata     = new[data_context.wdata.size()];
    address_context.wstrb     = new[data_context.wstrb.size()];
    address_context.wbeat_gap = new[data_context.wdata.size()];
    foreach (address_context.wdata[index]) begin
      address_context.wdata[index]     = data_context.wdata[index];
      address_context.wstrb[index]     = data_context.wstrb[index];
      address_context.wbeat_gap[index] = 0;
    end
    req_ap.write(address_context);

    if (!$cast(response_context, address_context.clone()))
      `uvm_fatal("AXI_M_MON_CLONE", "Failed to clone write ctx")
    write_response_by_id[id].push_back(response_context);
  end
endfunction

function void axi_m_monitor::capture_w_beat();
  req_t completed;
  int unsigned id;

  if (active_w_burst == null) begin
    active_w_burst = req_t::type_id::create("active_w_burst");
    active_w_burst.dir = AXI_WRITE;
    active_w_burst.id  = vif.wid;
  end
  else if (vif.wid !== active_w_burst.id) begin
    `uvm_error("AXI_M_MON_WID", "WID changed within a W burst")
  end

  active_w_data.push_back(vif.wdata);
  active_w_strb.push_back(vif.wstrb);
  if (vif.wlast !== 1'b1)
    return;

  active_w_burst.wdata     = new[active_w_data.size()];
  active_w_burst.wstrb     = new[active_w_strb.size()];
  active_w_burst.wbeat_gap = new[active_w_data.size()];
  foreach (active_w_burst.wdata[index]) begin
    active_w_burst.wdata[index]     = active_w_data[index];
    active_w_burst.wstrb[index]     = active_w_strb[index];
    active_w_burst.wbeat_gap[index] = 0;
  end
  if (!$cast(completed, active_w_burst.clone()))
    `uvm_fatal("AXI_M_MON_CLONE", "Failed to clone completed W burst")
  id = int'(active_w_burst.id);
  completed_w_by_id[id].push_back(completed);
  active_w_burst = null;
  active_w_data.delete();
  active_w_strb.delete();
  publish_write_if_complete(id);
endfunction

function void axi_m_monitor::publish_read_request();
  req_t req;
  req_t ctx;
  int unsigned id;

  req = create_address_request(AXI_READ);
  req_ap.write(req);
  if (!$cast(ctx, req.clone()))
    `uvm_fatal("AXI_M_MON_CLONE", "Failed to clone read ctx")
  id = int'(req.id);
  read_context_by_id[id].push_back(ctx);
endfunction

function void axi_m_monitor::publish_b_response();
  rsp_t rsp;
  req_t completed;
  int unsigned id;

  id = int'(vif.bid);
  if (write_response_by_id[id].size() == 0) begin
    `uvm_error("AXI_M_MON_B", "B response has no complete write request")
  end
  else begin
    completed = write_response_by_id[id].pop_front();
  end

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
  req_t completed;
  int unsigned id;

  id = int'(vif.rid);
  if (active_r_context == null) begin
    if (read_context_by_id[id].size() == 0) begin
      `uvm_error("AXI_M_MON_R", "R burst has no pending AR ctx")
      return;
    end
    active_r_context = read_context_by_id[id][0];
  end
  else if (vif.rid !== active_r_context.id) begin
    `uvm_error("AXI_M_MON_RID", "RID changed within an R burst")
  end

  active_r_data.push_back(vif.rdata);
  active_r_resp.push_back(vif.rresp);
  if (vif.rlast !== 1'b1)
    return;

  if (active_r_data.size() != (int'(active_r_context.len) + 1))
    `uvm_error("AXI_M_MON_RCOUNT", $sformatf(
      "Observed %0d R beats, expected %0d",
      active_r_data.size(), int'(active_r_context.len) + 1))

  rsp = rsp_t::type_id::create("reconstructed_read_rsp");
  rsp.dir        = AXI_READ;
  rsp.id         = active_r_context.id;
  rsp.len        = active_r_context.len;
  rsp.bresp      = AXI_RESP_OKAY;
  rsp.rdata      = new[active_r_data.size()];
  rsp.rresp      = new[active_r_resp.size()];
  rsp.rsp_delay  = 0;
  rsp.rbeat_gap  = new[(active_r_data.size() == 0) ?
                       0 : active_r_data.size() - 1];
  foreach (rsp.rdata[index]) begin
    rsp.rdata[index] = active_r_data[index];
    rsp.rresp[index] = axi_resp_e'(active_r_resp[index]);
  end
  foreach (rsp.rbeat_gap[index])
    rsp.rbeat_gap[index] = 0;
  rsp_ap.write(rsp);

  id = int'(active_r_context.id);
  completed = read_context_by_id[id].pop_front();
  active_r_context = null;
  active_r_data.delete();
  active_r_resp.delete();
endfunction

function int unsigned axi_m_monitor::pending_count();
  int unsigned total;
  total = (active_w_burst == null) ? 0 : 1;
  total += (active_r_context == null) ? 0 : 1;
  foreach (aw_context_by_id[id]) begin
    total += aw_context_by_id[id].size();
    total += completed_w_by_id[id].size();
    total += write_response_by_id[id].size();
    total += read_context_by_id[id].size();
  end
  return total;
endfunction

task axi_m_monitor::run_phase(uvm_phase phase);
  event_t event_out;
  req_t address_context;
  int unsigned id;

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

        address_context = create_address_request(AXI_WRITE);
        id = int'(address_context.id);
        aw_context_by_id[id].push_back(address_context);
        publish_write_if_complete(id);
      end

      if ((vif.wvalid === 1'b1) && (vif.wready === 1'b1)) begin
        event_out      = create_event(AXI_CHANNEL_W);
        event_out.id   = vif.wid;
        event_out.data = vif.wdata;
        event_out.strb = vif.wstrb;
        event_out.last = vif.wlast;
        channel_ap.write(event_out);
        capture_w_beat();
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

function void axi_m_monitor::check_phase(uvm_phase phase);
  super.check_phase(phase);
  if (pending_count() != 0)
    `uvm_error("AXI_M_MON_PENDING", $sformatf(
      "Master Monitor ended with %0d pending contexts", pending_count()))
endfunction

`endif

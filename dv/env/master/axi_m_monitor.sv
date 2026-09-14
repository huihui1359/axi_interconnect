`ifndef AXI_M_MONITOR_SV
`define AXI_M_MONITOR_SV

class axi_m_monitor #(
  int unsigned ADDR_WIDTH = AXI_ADDR_WIDTH,
  int unsigned DATA_WIDTH = AXI_DATA_WIDTH,
  int unsigned ID_WIDTH   = AXI_M_ID_WIDTH,
  int unsigned LEN_WIDTH  = AXI_LEN_WIDTH
) extends uvm_monitor;
  `uvm_component_param_utils(
    axi_m_monitor #(ADDR_WIDTH, DATA_WIDTH, ID_WIDTH, LEN_WIDTH)
  )

//定义类型简称
  typedef axi_channel_event #(
    ADDR_WIDTH, DATA_WIDTH, ID_WIDTH, LEN_WIDTH
  ) event_t;
  typedef axi_m_agent_cfg #(
    ADDR_WIDTH, DATA_WIDTH, ID_WIDTH, LEN_WIDTH
  ) cfg_t;
  typedef virtual axi_if #(
    ADDR_WIDTH, DATA_WIDTH, ID_WIDTH, LEN_WIDTH
  ).mon_mp vif_t;

  cfg_t cfg;
  vif_t vif;
  uvm_analysis_port #(event_t) channel_ap; //通信端口
  longint unsigned sample_cycle;



  extern function new(string name = "axi_m_monitor",
                      uvm_component parent = null);
  extern virtual function void build_phase(uvm_phase phase);
  extern function event_t create_event(axi_channel_e channel);
  extern virtual task run_phase(uvm_phase phase);

endclass

function axi_m_monitor::new(
  string name = "axi_m_monitor", uvm_component parent = null
);
  super.new(name, parent);
  sample_cycle = 0;
endfunction

function void axi_m_monitor::build_phase(uvm_phase phase);
  super.build_phase(phase);
  channel_ap = new("channel_ap", this);
  if (!uvm_config_db#(cfg_t)::get(this, "", "cfg", cfg) || (cfg == null))
    `uvm_fatal("AXI_M_MON_CFG", "Master Monitor requires a non-null cfg")
  vif = cfg.mon_vif;
  if (vif == null)
    `uvm_fatal("AXI_M_MON_VIF", "Master Monitor requires cfg.mon_vif")
endfunction

function axi_m_monitor::event_t axi_m_monitor::create_event(axi_channel_e channel);
  //创建event对象，并填写通用的信息
  event_t event_out;
  event_out = event_t::type_id::create($sformatf("%s_event", channel.name()));
  event_out.channel      = channel; //来自哪个通道
  event_out.side         = AXI_UPSTREAM; //来自接口哪一侧
  event_out.port_index   = cfg.port_index; //标记端口编号，区分多个master端口
  event_out.sample_cycle = sample_cycle; //记录采样周期
  return event_out;
endfunction

task axi_m_monitor::run_phase(uvm_phase phase);
  event_t event_out;
  forever begin
    @(posedge vif.ACLK);
    if (vif.ARESETn !== 1'b1)
      sample_cycle = 0;
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
      end

      if ((vif.wvalid === 1'b1) && (vif.wready === 1'b1)) begin
        event_out      = create_event(AXI_CHANNEL_W);
        event_out.id   = vif.wid;
        event_out.data = vif.wdata;
        event_out.strb = vif.wstrb;
        event_out.last = vif.wlast;
        channel_ap.write(event_out);
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

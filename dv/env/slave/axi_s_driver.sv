`ifndef AXI_S_DRIVER_SV
`define AXI_S_DRIVER_SV

class axi_s_driver #(
  int unsigned ADDR_WIDTH = AXI_ADDR_WIDTH,
  int unsigned DATA_WIDTH = AXI_DATA_WIDTH,
  int unsigned ID_WIDTH   = AXI_S_ID_WIDTH,
  int unsigned LEN_WIDTH  = AXI_LEN_WIDTH
) extends uvm_driver #(
  axi_rsp_item #(DATA_WIDTH, ID_WIDTH, LEN_WIDTH)
);

  typedef axi_rsp_item #(DATA_WIDTH, ID_WIDTH, LEN_WIDTH) rsp_t;
  typedef axi_s_agent_cfg #(
    ADDR_WIDTH, DATA_WIDTH, ID_WIDTH, LEN_WIDTH
  ) cfg_t;
  typedef virtual axi_if #(
    ADDR_WIDTH, DATA_WIDTH, ID_WIDTH, LEN_WIDTH
  ).s_drv_mp vif_t;

  cfg_t cfg;
  vif_t vif;

  mailbox #(rsp_t) b_queue;
  mailbox #(rsp_t) r_queue;

  latency_gen awready_latency;
  latency_gen wready_latency;
  latency_gen arready_latency;

  `uvm_component_param_utils(
    axi_s_driver #(ADDR_WIDTH, DATA_WIDTH, ID_WIDTH, LEN_WIDTH)
  )

  extern function new(string name = "axi_s_driver",
                      uvm_component parent = null);
  extern virtual function void build_phase(uvm_phase phase);
  extern virtual task run_phase(uvm_phase phase);
  extern task accept_items();
  extern task drive_awready();
  extern task drive_wready();
  extern task drive_arready();
  extern task clear_b();
  extern task clear_r();
  extern task drive_b();
  extern task drive_r();
  extern task watch_reset();

endclass

function axi_s_driver::new(
  string name = "axi_s_driver",
  uvm_component parent = null
);
  super.new(name, parent);
  b_queue         = new();
  r_queue         = new();
  awready_latency = latency_gen::type_id::create("awready_latency");
  wready_latency  = latency_gen::type_id::create("wready_latency");
  arready_latency = latency_gen::type_id::create("arready_latency");
endfunction

function void axi_s_driver::build_phase(uvm_phase phase);
  super.build_phase(phase);
  if (!uvm_config_db#(cfg_t)::get(this, "", "cfg", cfg) || (cfg == null))
    `uvm_fatal("AXI_S_DRV_CFG", "Slave Driver requires a non-null cfg")

  vif = cfg.drv_vif;
  if (vif == null)
    `uvm_fatal("AXI_S_DRV_VIF", "Slave Driver requires cfg.drv_vif")
endfunction

task axi_s_driver::run_phase(uvm_phase phase);
  fork
    accept_items();
    drive_awready();
    drive_wready();
    drive_arready();
    drive_b();
    drive_r();
    watch_reset();
  join
endtask

task axi_s_driver::accept_items();
  rsp_t rsp;
  rsp_t snapshot;

  forever begin
    while (vif.ARESETn !== 1'b1)
      @(posedge vif.ACLK);

    seq_item_port.get_next_item(rsp);
    if ((rsp == null) || !$cast(snapshot, rsp.clone()))
      `uvm_fatal("AXI_S_DRV_CLONE", "Failed to clone response item")

    if (snapshot.dir == AXI_WRITE)
      b_queue.put(snapshot);
    else
      r_queue.put(snapshot);

    seq_item_port.item_done();
  end
endtask

task axi_s_driver::drive_awready();
  int unsigned delay_cycles;
  vif.awready <= 1'b0;

  forever begin
    vif.awready <= 1'b0;
    while (vif.ARESETn !== 1'b1)
      @(posedge vif.ACLK);

    if (!awready_latency.randomize())
      `uvm_fatal("AXI_S_AWREADY_LATENCY",
                 "Failed to randomize AWREADY latency")
    delay_cycles = awready_latency.get_delay();
    repeat (delay_cycles)
      @(posedge vif.ACLK);

    if (vif.ARESETn !== 1'b1)
      continue;

    vif.awready <= 1'b1;
    do begin
      @(posedge vif.ACLK);
    end
    while ((vif.ARESETn === 1'b1) && (vif.awvalid !== 1'b1));
  end
endtask

task axi_s_driver::drive_wready();
  int unsigned delay_cycles;
  vif.wready <= 1'b0;

  forever begin
    vif.wready <= 1'b0;
    while (vif.ARESETn !== 1'b1)
      @(posedge vif.ACLK);

    if (!wready_latency.randomize())
      `uvm_fatal("AXI_S_WREADY_LATENCY",
                 "Failed to randomize WREADY latency")
    delay_cycles = wready_latency.get_delay();
    repeat (delay_cycles)
      @(posedge vif.ACLK);

    if (vif.ARESETn !== 1'b1)
      continue;

    vif.wready <= 1'b1;
    do begin
      @(posedge vif.ACLK);
    end
    while ((vif.ARESETn === 1'b1) && (vif.wvalid !== 1'b1));
  end
endtask

task axi_s_driver::drive_arready();
  int unsigned delay_cycles;
  vif.arready <= 1'b0;

  forever begin
    vif.arready <= 1'b0;
    while (vif.ARESETn !== 1'b1)
      @(posedge vif.ACLK);

    if (!arready_latency.randomize())
      `uvm_fatal("AXI_S_ARREADY_LATENCY",
                 "Failed to randomize ARREADY latency")
    delay_cycles = arready_latency.get_delay();
    repeat (delay_cycles)
      @(posedge vif.ACLK);

    if (vif.ARESETn !== 1'b1)
      continue;

    vif.arready <= 1'b1;
    do begin
      @(posedge vif.ACLK);
    end
    while ((vif.ARESETn === 1'b1) && (vif.arvalid !== 1'b1));
  end
endtask

task axi_s_driver::clear_b();
  vif.bvalid <= 1'b0;
  vif.bid    <= '0;
  vif.bresp  <= '0;
endtask

task axi_s_driver::clear_r();
  vif.rvalid <= 1'b0;
  vif.rid    <= '0;
  vif.rdata  <= '0;
  vif.rresp  <= '0;
  vif.rlast  <= 1'b0;
endtask

task axi_s_driver::drive_b();
  rsp_t rsp;
  clear_b();

  forever begin
    while (vif.ARESETn !== 1'b1)
      @(posedge vif.ACLK);
    b_queue.get(rsp);

    @(posedge vif.ACLK);
    repeat (rsp.rsp_delay)
      @(posedge vif.ACLK);

    if (vif.ARESETn !== 1'b1) begin
      clear_b();
      continue;
    end

    vif.bid    <= rsp.id;
    vif.bresp  <= rsp.bresp;
    vif.bvalid <= 1'b1;

    do begin
      @(posedge vif.ACLK);
    end
    while ((vif.ARESETn === 1'b1) && (vif.bready !== 1'b1));
    clear_b();
  end
endtask

task axi_s_driver::drive_r();
  rsp_t rsp;
  int unsigned beat_index;
  clear_r();

  forever begin
    while (vif.ARESETn !== 1'b1)
      @(posedge vif.ACLK);
    r_queue.get(rsp);
    beat_index = 0;

    @(posedge vif.ACLK);
    repeat (rsp.rsp_delay)
      @(posedge vif.ACLK);

    if (vif.ARESETn !== 1'b1) begin
      clear_r();
      continue;
    end

    vif.rid    <= rsp.id;
    vif.rdata  <= rsp.rdata[beat_index];
    vif.rresp  <= rsp.rresp[beat_index];
    vif.rlast  <= (beat_index == int'(rsp.len));
    vif.rvalid <= 1'b1;

    while (vif.ARESETn === 1'b1) begin
      do begin
        @(posedge vif.ACLK);
      end
      while ((vif.ARESETn === 1'b1) && (vif.rready !== 1'b1));

      if ((vif.ARESETn !== 1'b1) ||
          (beat_index == int'(rsp.len)))
        break;

      clear_r();
      repeat (rsp.rbeat_gap[beat_index])
        @(posedge vif.ACLK);
      beat_index++;

      if (vif.ARESETn !== 1'b1)
        break;

      vif.rid    <= rsp.id;
      vif.rdata  <= rsp.rdata[beat_index];
      vif.rresp  <= rsp.rresp[beat_index];
      vif.rlast  <= (beat_index == int'(rsp.len));
      vif.rvalid <= 1'b1;
    end
    clear_r();
  end
endtask

task axi_s_driver::watch_reset();
  rsp_t discarded;
  forever begin
    @(posedge vif.ACLK);
    if (vif.ARESETn !== 1'b1) begin
      while (b_queue.try_get(discarded));
      while (r_queue.try_get(discarded));
    end
  end
endtask

`endif

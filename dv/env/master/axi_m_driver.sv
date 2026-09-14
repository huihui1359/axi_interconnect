`ifndef AXI_M_DRIVER_SV
`define AXI_M_DRIVER_SV

class axi_m_driver #(
  int unsigned ADDR_WIDTH = AXI_ADDR_WIDTH,
  int unsigned DATA_WIDTH = AXI_DATA_WIDTH,
  int unsigned ID_WIDTH   = AXI_M_ID_WIDTH,
  int unsigned LEN_WIDTH  = AXI_LEN_WIDTH
) extends uvm_driver #(
  axi_req_item #(ADDR_WIDTH, DATA_WIDTH, ID_WIDTH, LEN_WIDTH),
  axi_rsp_item #(DATA_WIDTH, ID_WIDTH, LEN_WIDTH)
);
  `uvm_component_param_utils(
    axi_m_driver #(ADDR_WIDTH, DATA_WIDTH, ID_WIDTH, LEN_WIDTH)
  )

//定义类型简称
  typedef axi_req_item #(
    ADDR_WIDTH, DATA_WIDTH, ID_WIDTH, LEN_WIDTH
  ) req_t;

  typedef axi_m_agent_cfg #(
    ADDR_WIDTH, DATA_WIDTH, ID_WIDTH, LEN_WIDTH
  ) cfg_t;

  typedef virtual axi_if #(
    ADDR_WIDTH, DATA_WIDTH, ID_WIDTH, LEN_WIDTH
  ).m_drv_mp vif_t;

//声明句柄
  cfg_t cfg;
  vif_t vif;

  mailbox #(req_t) aw_queue; //只能存取 req_t 类型的对象
  mailbox #(req_t) w_queue;
  mailbox #(req_t) ar_queue;

  bit write_busy; //限制outstanding数量
  bit read_busy; //限制outstanding数量
  logic [ID_WIDTH-1:0] write_id;
  logic [ID_WIDTH-1:0] read_id;

  extern function new(string name = "axi_m_driver",
                      uvm_component parent = null);
  extern virtual function void build_phase(uvm_phase phase);
  extern virtual task run_phase(uvm_phase phase);
  extern task accept_items();
  extern task clear_aw();
  extern task clear_w();
  extern task clear_ar();
  extern task drive_aw();
  extern task drive_w();
  extern task drive_ar();
  extern task receive_b();
  extern task receive_r();
  extern task watch_reset();

endclass

function axi_m_driver::new(
  string name = "axi_m_driver", uvm_component parent = null
);
  super.new(name, parent);
  aw_queue   = new();
  w_queue    = new();
  ar_queue   = new();
  write_busy = 1'b0;
  read_busy  = 1'b0;
endfunction

function void axi_m_driver::build_phase(uvm_phase phase);
  super.build_phase(phase);
  if (!uvm_config_db#(cfg_t)::get(this, "", "cfg", cfg) || (cfg == null))
    `uvm_fatal("AXI_M_DRV_CFG", "Master Driver requires a non-null cfg")

  vif = cfg.drv_vif;
  if (vif == null)
    `uvm_fatal("AXI_M_DRV_VIF", "Master Driver requires cfg.drv_vif")

  if ((cfg.bready_mode != ALWAYS_READY) ||
      (cfg.rready_mode != ALWAYS_READY))
    `uvm_fatal("AXI_M_DRV_MODE", "Stage 1 supports only ALWAYS_READY")

  if ((cfg.max_read_outstanding != 1) ||
      (cfg.max_write_outstanding != 1))
    `uvm_fatal("AXI_M_DRV_DEPTH", "Stage 1 outstanding limits must be one")
endfunction

task axi_m_driver::run_phase(uvm_phase phase);
  fork
    accept_items();
    drive_aw();
    drive_w();
    drive_ar();
    receive_b();
    receive_r();
    watch_reset();
  join
endtask

task axi_m_driver::accept_items();
  req_t req;
  req_t snapshot;

  forever begin
    while (vif.ARESETn !== 1'b1)
      @(posedge vif.ACLK);

    seq_item_port.get_next_item(req); //1.取得原始item

    $cast(snapshot, req.clone()); //2.创建独立快照。$cast将uvm_object类型转换为req_t类型的snapshot

    if (snapshot.dir == AXI_WRITE) begin
      wait (!write_busy || (vif.ARESETn !== 1'b1));
      if (vif.ARESETn !== 1'b1) begin
        seq_item_port.item_done();
        continue;
      end
      write_busy = 1'b1;
      write_id   = snapshot.id;
      aw_queue.put(snapshot);// 3.快照放入AW队列
      w_queue.put(snapshot);// 4.快照放入W队列
    end
    else begin
      wait (!read_busy || (vif.ARESETn !== 1'b1));
      if (vif.ARESETn !== 1'b1) begin
        seq_item_port.item_done();
        continue;
      end
      read_busy = 1'b1;
      read_id   = snapshot.id;
      ar_queue.put(snapshot);//3.快照放入ar队列
    end

    seq_item_port.item_done(); //5.通知sequencer可以继续发送事务
  end
endtask

task axi_m_driver::clear_aw();
  vif.awvalid <= 1'b0;
  vif.awid    <= '0;
  vif.awaddr  <= '0;
  vif.awlen   <= '0;
  vif.awsize  <= '0;
  vif.awburst <= '0;
endtask

task axi_m_driver::clear_w();
  vif.wvalid <= 1'b0;
  vif.wid    <= '0;
  vif.wdata  <= '0;
  vif.wstrb  <= '0;
  vif.wlast  <= 1'b0;
endtask

task axi_m_driver::clear_ar();
  vif.arvalid <= 1'b0;
  vif.arid    <= '0;
  vif.araddr  <= '0;
  vif.arlen   <= '0;
  vif.arsize  <= '0;
  vif.arburst <= '0;
endtask

task axi_m_driver::drive_aw();
  req_t req;
  clear_aw();

  forever begin
    while (vif.ARESETn !== 1'b1)
      @(posedge vif.ACLK);
    aw_queue.get(req);

    vif.awid    <= req.id;
    vif.awaddr  <= req.addr;
    vif.awlen   <= req.len;
    vif.awsize  <= req.size;
    vif.awburst <= req.burst;
    vif.awvalid <= 1'b1;

    do @(posedge vif.ACLK);
    while ((vif.ARESETn === 1'b1) && (vif.awready !== 1'b1));
    clear_aw();
  end
endtask

task axi_m_driver::drive_w();
  req_t req;
  clear_w();

  forever begin
    while (vif.ARESETn !== 1'b1)
      @(posedge vif.ACLK);
    w_queue.get(req);

    vif.wid    <= req.id;
    vif.wdata  <= req.wdata[0];
    vif.wstrb  <= req.wstrb[0];
    vif.wlast  <= 1'b1;
    vif.wvalid <= 1'b1;

    do @(posedge vif.ACLK);
    while ((vif.ARESETn === 1'b1) && (vif.wready !== 1'b1));
    clear_w();
  end
endtask

task axi_m_driver::drive_ar();
  req_t req;
  clear_ar();

  forever begin
    while (vif.ARESETn !== 1'b1)
      @(posedge vif.ACLK);
    ar_queue.get(req);

    vif.arid    <= req.id;
    vif.araddr  <= req.addr;
    vif.arlen   <= req.len;
    vif.arsize  <= req.size;
    vif.arburst <= req.burst;
    vif.arvalid <= 1'b1;

    do @(posedge vif.ACLK);
    while ((vif.ARESETn === 1'b1) && (vif.arready !== 1'b1));
    clear_ar();
  end
endtask

task axi_m_driver::receive_b();
  vif.bready <= 1'b0;

  forever begin
    @(posedge vif.ACLK);
    if (vif.ARESETn !== 1'b1) begin
      vif.bready <= 1'b0;
    end
    else begin
      vif.bready <= 1'b1;
      if ((vif.bready === 1'b1) && (vif.bvalid === 1'b1)) begin
        if (!write_busy)
          `uvm_error("AXI_M_DRV_B", "B response without pending write")
        else if (vif.bid !== write_id)
          `uvm_error("AXI_M_DRV_BID", "BID does not match pending write ID")
        write_busy = 1'b0;
      end
    end
  end
endtask

task axi_m_driver::receive_r();
  vif.rready <= 1'b0;

  forever begin
    @(posedge vif.ACLK);
    if (vif.ARESETn !== 1'b1) begin
      vif.rready <= 1'b0;
    end
    else begin
      if ((vif.rready === 1'b1) && (vif.rvalid === 1'b1)) begin
        if (!read_busy)
          `uvm_error("AXI_M_DRV_R", "R response without pending read")
        else begin
          if (vif.rid !== read_id)
            `uvm_error("AXI_M_DRV_RID", "RID does not match pending read ID")
          if (vif.rlast !== 1'b1)
            `uvm_error("AXI_M_DRV_RLAST", "Stage 1 read response must assert RLAST")
        end
        if (vif.rlast === 1'b1)
          read_busy = 1'b0;
      end
      vif.rready <= 1'b1;
    end
  end
endtask

task axi_m_driver::watch_reset();
  req_t discarded;
  forever begin
    @(posedge vif.ACLK);
    if (vif.ARESETn !== 1'b1) begin
      write_busy = 1'b0;
      read_busy  = 1'b0;
      write_id   = '0;
      read_id    = '0;
      //清空 mailbox 中的残留事务
      while (aw_queue.try_get(discarded));
      while (w_queue.try_get(discarded));
      while (ar_queue.try_get(discarded));
    end
  end
endtask

`endif

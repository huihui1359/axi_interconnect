`ifndef AXI_M_DRIVER_SV
`define AXI_M_DRIVER_SV

class axi_m_request_context #(
  int unsigned ADDR_WIDTH = AXI_ADDR_WIDTH,
  int unsigned DATA_WIDTH = AXI_DATA_WIDTH,
  int unsigned ID_WIDTH   = AXI_M_ID_WIDTH,
  int unsigned LEN_WIDTH  = AXI_LEN_WIDTH
);

  typedef axi_req_item #(
    ADDR_WIDTH, DATA_WIDTH, ID_WIDTH, LEN_WIDTH
  ) req_t;

  req_t req;
  int unsigned issue_order;
  bit aw_complete;
  bit w_complete;

  function new(req_t req, int unsigned issue_order);
    this.req         = req;
    this.issue_order = issue_order;
    aw_complete      = 1'b0;
    w_complete       = 1'b0;
  endfunction

endclass

class axi_m_driver #(
  int unsigned ADDR_WIDTH = AXI_ADDR_WIDTH,
  int unsigned DATA_WIDTH = AXI_DATA_WIDTH,
  int unsigned ID_WIDTH   = AXI_M_ID_WIDTH,
  int unsigned LEN_WIDTH  = AXI_LEN_WIDTH
) extends uvm_driver #(
  axi_req_item #(ADDR_WIDTH, DATA_WIDTH, ID_WIDTH, LEN_WIDTH),
  axi_rsp_item #(DATA_WIDTH, ID_WIDTH, LEN_WIDTH)
);

  localparam int unsigned ID_COUNT = 1 << ID_WIDTH;

  typedef axi_req_item #(
    ADDR_WIDTH, DATA_WIDTH, ID_WIDTH, LEN_WIDTH
  ) req_t;
  typedef axi_m_request_context #(
    ADDR_WIDTH, DATA_WIDTH, ID_WIDTH, LEN_WIDTH
  ) context_t;
  typedef axi_m_agent_cfg #(
    ADDR_WIDTH, DATA_WIDTH, ID_WIDTH, LEN_WIDTH
  ) cfg_t;
  typedef virtual axi_if #(
    ADDR_WIDTH, DATA_WIDTH, ID_WIDTH, LEN_WIDTH
  ).m_drv_mp vif_t;

  cfg_t cfg;
  vif_t vif;

  mailbox #(context_t) aw_queue;
  mailbox #(context_t) w_queue;
  mailbox #(context_t) ar_queue;

  latency_gen bready_latency;
  latency_gen rready_latency;
  semaphore write_request_gate;
  semaphore read_request_gate;

  int unsigned aw_outstanding_by_id[ID_COUNT];
  int unsigned w_outstanding_by_id[ID_COUNT];
  int unsigned ar_outstanding_by_id[ID_COUNT];
  int unsigned max_write_outstanding;
  int unsigned max_read_outstanding;

  context_t write_context_by_id[ID_COUNT][$];
  context_t read_context_by_id[ID_COUNT][$];
  context_t active_aw_context;
  context_t active_w_context;
  context_t active_ar_context;
  context_t active_r_context;
  int unsigned active_r_beat_index;
  int unsigned next_issue_order;

  `uvm_component_param_utils(
    axi_m_driver #(ADDR_WIDTH, DATA_WIDTH, ID_WIDTH, LEN_WIDTH)
  )

  extern function new(string name = "axi_m_driver",
                      uvm_component parent = null);
  extern virtual function void build_phase(uvm_phase phase);
  extern function int unsigned write_outstanding();
  extern function int unsigned read_outstanding();
  extern function int unsigned pending_context_count();
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
  extern task track_outstanding();
  extern virtual function void check_phase(uvm_phase phase);

endclass

function axi_m_driver::new(
  string name = "axi_m_driver",
  uvm_component parent = null
);
  super.new(name, parent);
  aw_queue           = new();
  w_queue            = new();
  ar_queue           = new();
  bready_latency     = latency_gen::type_id::create("bready_latency");
  rready_latency     = latency_gen::type_id::create("rready_latency");
  write_request_gate = new(1);
  read_request_gate  = new(1);
  active_aw_context  = null;
  active_w_context   = null;
  active_ar_context  = null;
  active_r_context   = null;
  active_r_beat_index = 0;
  next_issue_order   = 0;
  foreach (aw_outstanding_by_id[id]) begin
    aw_outstanding_by_id[id] = 0;
    w_outstanding_by_id[id]  = 0;
    ar_outstanding_by_id[id] = 0;
  end
  max_write_outstanding = 0;
  max_read_outstanding  = 0;
endfunction

function void axi_m_driver::build_phase(uvm_phase phase);
  super.build_phase(phase);
  if (!uvm_config_db#(cfg_t)::get(this, "", "cfg", cfg) || (cfg == null))
    `uvm_fatal("AXI_M_DRV_CFG", "Master Driver requires a non-null cfg")

  vif = cfg.drv_vif;
  if (vif == null)
    `uvm_fatal("AXI_M_DRV_VIF", "Master Driver requires cfg.drv_vif")

  if (!(cfg.max_read_outstanding inside {[1:4]}) ||
      !(cfg.max_write_outstanding inside {[1:4]}))
    `uvm_fatal("AXI_M_DRV_DEPTH",
               "Stage 3 outstanding limits must be in the range 1 to 4")
endfunction

function int unsigned axi_m_driver::write_outstanding();
  int unsigned total;
  total = 0;
  foreach (aw_outstanding_by_id[id])
    total += aw_outstanding_by_id[id];
  return total;
endfunction

function int unsigned axi_m_driver::read_outstanding();
  int unsigned total;
  total = 0;
  foreach (ar_outstanding_by_id[id])
    total += ar_outstanding_by_id[id];
  return total;
endfunction

function int unsigned axi_m_driver::pending_context_count();
  int unsigned total;
  total = (active_r_context == null) ? 0 : 1;
  foreach (write_context_by_id[id])
    total += write_context_by_id[id].size();
  foreach (read_context_by_id[id])
    total += read_context_by_id[id].size();
  return total;
endfunction

task axi_m_driver::run_phase(uvm_phase phase);
  fork
    accept_items();
    drive_aw();
    drive_w();
    drive_ar();
    receive_b();
    receive_r();
    track_outstanding();
  join
endtask

task axi_m_driver::accept_items();
  req_t req;
  req_t snapshot;
  context_t ctx;

  forever begin
    while (vif.ARESETn !== 1'b1)
      @(posedge vif.ACLK);

    seq_item_port.get_next_item(req);
    if ((req == null) || !$cast(snapshot, req.clone()))
      `uvm_fatal("AXI_M_DRV_CLONE", "Failed to clone request item")

    ctx = new(snapshot, next_issue_order++);
    if (snapshot.dir == AXI_WRITE) begin
      if (!cfg.request_prefetch_enabled)
        write_request_gate.get();
      aw_queue.put(ctx);
      w_queue.put(ctx);
    end
    else begin
      if (!cfg.request_prefetch_enabled)
        read_request_gate.get();
      ar_queue.put(ctx);
    end
    seq_item_port.item_done();
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
  context_t ctx;
  clear_aw();

  forever begin
    while (vif.ARESETn !== 1'b1)
      @(posedge vif.ACLK);
    aw_queue.get(ctx);

    do begin
      @(posedge vif.ACLK);
    end
    while ((vif.ARESETn === 1'b1) &&
           (write_outstanding() >= cfg.max_write_outstanding));
    if (vif.ARESETn !== 1'b1)
      continue;

    repeat (ctx.req.addr_delay)
      @(posedge vif.ACLK);
    if (vif.ARESETn !== 1'b1)
      continue;

    active_aw_context = ctx;
    vif.awid    <= ctx.req.id;
    vif.awaddr  <= ctx.req.addr;
    vif.awlen   <= ctx.req.len;
    vif.awsize  <= ctx.req.size;
    vif.awburst <= ctx.req.burst;
    vif.awvalid <= 1'b1;

    do begin
      @(posedge vif.ACLK);
    end
    while ((vif.ARESETn === 1'b1) && (vif.awready !== 1'b1));
    clear_aw();
  end
endtask

task axi_m_driver::drive_w();
  context_t ctx;
  int unsigned beat_index;
  clear_w();

  forever begin
    while (vif.ARESETn !== 1'b1)
      @(posedge vif.ACLK);
    w_queue.get(ctx);
    beat_index = 0;

    @(posedge vif.ACLK);
    repeat (ctx.req.w_start_delay + ctx.req.wbeat_gap[0])
      @(posedge vif.ACLK);
    if (vif.ARESETn !== 1'b1)
      continue;

    active_w_context = ctx;
    vif.wid    <= ctx.req.id;
    vif.wdata  <= ctx.req.wdata[beat_index];
    vif.wstrb  <= ctx.req.wstrb[beat_index];
    vif.wlast  <= (beat_index == int'(ctx.req.len));
    vif.wvalid <= 1'b1;

    while (vif.ARESETn === 1'b1) begin
      do begin
        @(posedge vif.ACLK);
      end
      while ((vif.ARESETn === 1'b1) && (vif.wready !== 1'b1));

      if ((vif.ARESETn !== 1'b1) ||
          (beat_index == int'(ctx.req.len)))
        break;

      beat_index++;
      clear_w();
      repeat (ctx.req.wbeat_gap[beat_index])
        @(posedge vif.ACLK);
      if (vif.ARESETn !== 1'b1)
        break;

      vif.wid    <= ctx.req.id;
      vif.wdata  <= ctx.req.wdata[beat_index];
      vif.wstrb  <= ctx.req.wstrb[beat_index];
      vif.wlast  <= (beat_index == int'(ctx.req.len));
      vif.wvalid <= 1'b1;
    end
    clear_w();
  end
endtask

task axi_m_driver::drive_ar();
  context_t ctx;
  clear_ar();

  forever begin
    while (vif.ARESETn !== 1'b1)
      @(posedge vif.ACLK);
    ar_queue.get(ctx);

    do begin
      @(posedge vif.ACLK);
    end
    while ((vif.ARESETn === 1'b1) &&
           (read_outstanding() >= cfg.max_read_outstanding));
    if (vif.ARESETn !== 1'b1)
      continue;

    repeat (ctx.req.addr_delay)
      @(posedge vif.ACLK);
    if (vif.ARESETn !== 1'b1)
      continue;

    active_ar_context = ctx;
    vif.arid    <= ctx.req.id;
    vif.araddr  <= ctx.req.addr;
    vif.arlen   <= ctx.req.len;
    vif.arsize  <= ctx.req.size;
    vif.arburst <= ctx.req.burst;
    vif.arvalid <= 1'b1;

    do begin
      @(posedge vif.ACLK);
    end
    while ((vif.ARESETn === 1'b1) && (vif.arready !== 1'b1));
    clear_ar();
  end
endtask

task axi_m_driver::receive_b();
  int unsigned delay_cycles;
  vif.bready <= 1'b0;

  forever begin
    vif.bready <= 1'b0;
    while (vif.ARESETn !== 1'b1)
      @(posedge vif.ACLK);

    if (!bready_latency.randomize())
      `uvm_fatal("AXI_M_BREADY_LATENCY",
                 "Failed to randomize BREADY latency")
    delay_cycles = bready_latency.get_delay();
    repeat (delay_cycles)
      @(posedge vif.ACLK);
    if (vif.ARESETn !== 1'b1)
      continue;

    vif.bready <= 1'b1;
    do begin
      @(posedge vif.ACLK);
    end
    while ((vif.ARESETn === 1'b1) && (vif.bvalid !== 1'b1));
  end
endtask

task axi_m_driver::receive_r();
  int unsigned delay_cycles;
  vif.rready <= 1'b0;

  forever begin
    vif.rready <= 1'b0;
    while (vif.ARESETn !== 1'b1)
      @(posedge vif.ACLK);

    if (!rready_latency.randomize())
      `uvm_fatal("AXI_M_RREADY_LATENCY",
                 "Failed to randomize RREADY latency")
    delay_cycles = rready_latency.get_delay();
    repeat (delay_cycles)
      @(posedge vif.ACLK);
    if (vif.ARESETn !== 1'b1)
      continue;

    vif.rready <= 1'b1;
    do begin
      @(posedge vif.ACLK);
    end
    while ((vif.ARESETn === 1'b1) && (vif.rvalid !== 1'b1));
  end
endtask

task axi_m_driver::track_outstanding();
  context_t discarded;
  context_t completed;
  int unsigned id;
  bit expected_last;

  forever begin
    @(posedge vif.ACLK);
    if (vif.ARESETn !== 1'b1) begin
      foreach (aw_outstanding_by_id[index]) begin
        aw_outstanding_by_id[index] = 0;
        w_outstanding_by_id[index]  = 0;
        ar_outstanding_by_id[index] = 0;
        write_context_by_id[index].delete();
        read_context_by_id[index].delete();
      end
      max_write_outstanding = 0;
      max_read_outstanding  = 0;
      active_aw_context   = null;
      active_w_context    = null;
      active_ar_context   = null;
      active_r_context    = null;
      active_r_beat_index = 0;
      while (aw_queue.try_get(discarded));
      while (w_queue.try_get(discarded));
      while (ar_queue.try_get(discarded));
    end
    else begin
      if ((vif.awvalid === 1'b1) && (vif.awready === 1'b1)) begin
        if ($isunknown(vif.awid) || (active_aw_context == null)) begin
          `uvm_error("AXI_M_DRV_AW_CONTEXT",
                     "AW handshake has no valid Driver ctx")
        end
        else begin
          id = int'(vif.awid);
          active_aw_context.aw_complete = 1'b1;
          write_context_by_id[id].push_back(active_aw_context);
          aw_outstanding_by_id[id]++;
        end
      end

      if ((vif.wvalid === 1'b1) && (vif.wready === 1'b1) &&
          (vif.wlast === 1'b1)) begin
        if ($isunknown(vif.wid) || (active_w_context == null)) begin
          `uvm_error("AXI_M_DRV_W_CONTEXT",
                     "WLAST handshake has no valid Driver ctx")
        end
        else begin
          id = int'(vif.wid);
          active_w_context.w_complete = 1'b1;
          w_outstanding_by_id[id]++;
        end
      end

      if ((vif.arvalid === 1'b1) && (vif.arready === 1'b1)) begin
        if ($isunknown(vif.arid) || (active_ar_context == null)) begin
          `uvm_error("AXI_M_DRV_AR_CONTEXT",
                     "AR handshake has no valid Driver ctx")
        end
        else begin
          id = int'(vif.arid);
          read_context_by_id[id].push_back(active_ar_context);
          ar_outstanding_by_id[id]++;
        end
      end

      if ((vif.bvalid === 1'b1) && (vif.bready === 1'b1)) begin
        if ($isunknown(vif.bid)) begin
          `uvm_error("AXI_M_DRV_BID", "BID contains X/Z")
        end
        else begin
          id = int'(vif.bid);
          if ((aw_outstanding_by_id[id] == 0) ||
              (w_outstanding_by_id[id] == 0)) begin
            `uvm_error("AXI_M_DRV_B",
                       "B response has no complete pending write")
          end
          else begin
            aw_outstanding_by_id[id]--;
            w_outstanding_by_id[id]--;
          end

          if (write_context_by_id[id].size() == 0) begin
            `uvm_error("AXI_M_DRV_B_CONTEXT",
                       "B response has no matching write ctx")
          end
          else begin
            completed = write_context_by_id[id].pop_front();
            if (!completed.aw_complete || !completed.w_complete)
              `uvm_error("AXI_M_DRV_B_CONTEXT",
                         "B response arrived before AW and W completed")
          end
          if (!cfg.request_prefetch_enabled)
            write_request_gate.put();
        end
        if (!(vif.bresp inside {2'b00, 2'b10, 2'b11}))
          `uvm_error("AXI_M_DRV_BRESP", "Observed unsupported BRESP")
      end

      if ((vif.rvalid === 1'b1) && (vif.rready === 1'b1)) begin
        if ($isunknown(vif.rid)) begin
          `uvm_error("AXI_M_DRV_RID", "RID contains X/Z")
        end
        else begin
          id = int'(vif.rid);
          if (active_r_context == null) begin
            if (read_context_by_id[id].size() == 0) begin
              `uvm_error("AXI_M_DRV_R_CONTEXT",
                         "R response has no matching read ctx")
            end
            else begin
              active_r_context    = read_context_by_id[id][0];
              active_r_beat_index = 0;
            end
          end
          else if (vif.rid !== active_r_context.req.id) begin
            `uvm_error("AXI_M_DRV_RID", "RID changed within an R burst")
          end

          if (active_r_context != null) begin
            expected_last =
              (active_r_beat_index == int'(active_r_context.req.len));
            if (vif.rlast !== expected_last)
              `uvm_error("AXI_M_DRV_RLAST", $sformatf(
                "Unexpected RLAST at beat %0d of %0d",
                active_r_beat_index,
                int'(active_r_context.req.len) + 1))

            if (vif.rlast === 1'b1) begin
              id = int'(active_r_context.req.id);
              if (ar_outstanding_by_id[id] == 0)
                `uvm_error("AXI_M_DRV_R", "RLAST underflow")
              else
                ar_outstanding_by_id[id]--;
              if (read_context_by_id[id].size() != 0)
                completed = read_context_by_id[id].pop_front();
              active_r_context    = null;
              active_r_beat_index = 0;
              if (!cfg.request_prefetch_enabled)
                read_request_gate.put();
            end
            else begin
              active_r_beat_index++;
            end
          end
        end
        if (!(vif.rresp inside {2'b00, 2'b10, 2'b11}))
          `uvm_error("AXI_M_DRV_RRESP", "Observed unsupported RRESP")
      end

      if (write_outstanding() > cfg.max_write_outstanding)
        `uvm_error("AXI_M_DRV_WRITE_DEPTH", "Write outstanding overflow")
      if (read_outstanding() > cfg.max_read_outstanding)
        `uvm_error("AXI_M_DRV_READ_DEPTH", "Read outstanding overflow")
      if (write_outstanding() > max_write_outstanding)
        max_write_outstanding = write_outstanding();
      if (read_outstanding() > max_read_outstanding)
        max_read_outstanding = read_outstanding();
    end
  end
endtask

function void axi_m_driver::check_phase(uvm_phase phase);
  int unsigned w_pending;
  super.check_phase(phase);
  w_pending = 0;
  foreach (w_outstanding_by_id[id])
    w_pending += w_outstanding_by_id[id];

  if ((write_outstanding() != 0) || (read_outstanding() != 0) ||
      (w_pending != 0) || (pending_context_count() != 0) ||
      (aw_queue.num() != 0) || (w_queue.num() != 0) ||
      (ar_queue.num() != 0))
    `uvm_error("AXI_M_DRV_PENDING", "Master Driver ended with pending state")
endfunction

`endif

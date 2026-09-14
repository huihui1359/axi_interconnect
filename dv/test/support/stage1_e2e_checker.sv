`ifndef STAGE1_E2E_CHECKER_SV
`define STAGE1_E2E_CHECKER_SV

class stage1_e2e_checker #(
  int unsigned ADDR_WIDTH = AXI_ADDR_WIDTH,
  int unsigned DATA_WIDTH = AXI_DATA_WIDTH,
  int unsigned M_ID_WIDTH = AXI_M_ID_WIDTH,
  int unsigned S_ID_WIDTH = AXI_S_ID_WIDTH,
  int unsigned LEN_WIDTH  = AXI_LEN_WIDTH
) extends uvm_component;

  typedef axi_channel_event #(
    ADDR_WIDTH, DATA_WIDTH, M_ID_WIDTH, LEN_WIDTH
  ) m_event_t;
  typedef axi_channel_event #(
    ADDR_WIDTH, DATA_WIDTH, S_ID_WIDTH, LEN_WIDTH
  ) s_event_t;
  typedef logic [S_ID_WIDTH-1:0] sid_t;
  typedef virtual stage1_reset_if reset_vif_t;

  uvm_analysis_imp_upstream #(m_event_t,
    stage1_e2e_checker #(
      ADDR_WIDTH, DATA_WIDTH, M_ID_WIDTH, S_ID_WIDTH, LEN_WIDTH
    )
  ) upstream_export;
  uvm_analysis_imp_downstream #(s_event_t,
    stage1_e2e_checker #(
      ADDR_WIDTH, DATA_WIDTH, M_ID_WIDTH, S_ID_WIDTH, LEN_WIDTH
    )
  ) downstream_export;

  reset_vif_t reset_vif;

  m_event_t upstream_aw_q[$];
  m_event_t upstream_w_q[$];
  m_event_t upstream_b_q[$];
  m_event_t upstream_ar_q[$];
  m_event_t upstream_r_q[$];
  s_event_t downstream_aw_q[$];
  s_event_t downstream_w_q[$];
  s_event_t downstream_b_q[$];
  s_event_t downstream_ar_q[$];
  s_event_t downstream_r_q[$];

  logic [M_ID_WIDTH-1:0] aw_id_q[$];
  logic [M_ID_WIDTH-1:0] w_id_q[$];
  logic [M_ID_WIDTH-1:0] write_id_q[$];
  logic [M_ID_WIDTH-1:0] read_id_q[$];

  int unsigned aw_match_count;
  int unsigned w_match_count;
  int unsigned b_match_count;
  int unsigned ar_match_count;
  int unsigned r_match_count;
  int unsigned mismatch_count;

  `uvm_component_param_utils(
    stage1_e2e_checker #(
      ADDR_WIDTH, DATA_WIDTH, M_ID_WIDTH, S_ID_WIDTH, LEN_WIDTH
    )
  )

  extern function new(string name = "stage1_e2e_checker",
                      uvm_component parent = null);
  extern virtual function void build_phase(uvm_phase phase);
  extern virtual task run_phase(uvm_phase phase);
  extern virtual function void write_upstream(m_event_t event_in);
  extern virtual function void write_downstream(s_event_t event_in);
  extern function logic [S_ID_WIDTH-1:0] expand_id(
    logic [M_ID_WIDTH-1:0] original_id
  );
  extern function void compare_available();
  extern function void compare_aw();
  extern function void compare_w();
  extern function void compare_ar();
  extern function void build_write_context();
  extern function void compare_b();
  extern function void compare_r();
  extern function int unsigned pending_count();
  extern function void clear();
  extern virtual function void check_phase(uvm_phase phase);

endclass

function stage1_e2e_checker::new(
  string name = "stage1_e2e_checker",
  uvm_component parent = null
);
  super.new(name, parent);
  clear();
endfunction

function void stage1_e2e_checker::build_phase(uvm_phase phase);
  super.build_phase(phase);
  upstream_export   = new("upstream_export", this);
  downstream_export = new("downstream_export", this);
  if (!uvm_config_db#(reset_vif_t)::get(this, "", "reset_vif", reset_vif))
    `uvm_fatal("STAGE1_E2E_VIF", "stage1_e2e_checker requires reset_vif")
endfunction

task stage1_e2e_checker::run_phase(uvm_phase phase);
  forever begin
    @(posedge reset_vif.aclk);
    if (reset_vif.aresetn !== 1'b1)
      clear();
  end
endtask

function void stage1_e2e_checker::write_upstream(m_event_t event_in);
  m_event_t snapshot;
  if ((event_in == null) || !$cast(snapshot, event_in.clone())) begin
    mismatch_count++;
    `uvm_error("STAGE1_E2E", "Failed to clone upstream event")
    return;
  end

  case (snapshot.channel)
    AXI_CHANNEL_AW: upstream_aw_q.push_back(snapshot);
    AXI_CHANNEL_W:  upstream_w_q.push_back(snapshot);
    AXI_CHANNEL_B:  upstream_b_q.push_back(snapshot);
    AXI_CHANNEL_AR: upstream_ar_q.push_back(snapshot);
    AXI_CHANNEL_R:  upstream_r_q.push_back(snapshot);
  endcase
  compare_available();
endfunction

function void stage1_e2e_checker::write_downstream(s_event_t event_in);
  s_event_t snapshot;
  if ((event_in == null) || !$cast(snapshot, event_in.clone())) begin
    mismatch_count++;
    `uvm_error("STAGE1_E2E", "Failed to clone downstream event")
    return;
  end

  case (snapshot.channel)
    AXI_CHANNEL_AW: downstream_aw_q.push_back(snapshot);
    AXI_CHANNEL_W:  downstream_w_q.push_back(snapshot);
    AXI_CHANNEL_B: begin
      if (write_id_q.size() == 0) begin
        mismatch_count++;
        `uvm_error("STAGE1_E2E_B_ORDER",
                   "Downstream B arrived before a complete write request")
      end
      downstream_b_q.push_back(snapshot);
    end
    AXI_CHANNEL_AR: downstream_ar_q.push_back(snapshot);
    AXI_CHANNEL_R: begin
      if (read_id_q.size() == 0) begin
        mismatch_count++;
        `uvm_error("STAGE1_E2E_R_ORDER",
                   "Downstream R arrived before a read request")
      end
      downstream_r_q.push_back(snapshot);
    end
  endcase
  compare_available();
endfunction

function stage1_e2e_checker::sid_t stage1_e2e_checker::expand_id(
  logic [M_ID_WIDTH-1:0] original_id
);
  return {2'b01, 2'b01, original_id};
endfunction

function void stage1_e2e_checker::compare_available();
  compare_aw();
  compare_w();
  compare_ar();
  build_write_context();
  compare_b();
  compare_r();
endfunction

function void stage1_e2e_checker::compare_aw();
  m_event_t upstream;
  s_event_t downstream;
  while ((upstream_aw_q.size() != 0) &&
         (downstream_aw_q.size() != 0)) begin
    upstream   = upstream_aw_q.pop_front();
    downstream = downstream_aw_q.pop_front();
    if ((upstream.side          === AXI_UPSTREAM) &&
        (downstream.side        === AXI_DOWNSTREAM) &&
        (upstream.port_index    == 0) &&
        (downstream.port_index  == 0) &&
        (downstream.id          === expand_id(upstream.id)) &&
        (downstream.addr        === upstream.addr) &&
        (downstream.len         === upstream.len) &&
        (downstream.size        === upstream.size) &&
        (downstream.burst_raw   === upstream.burst_raw)) begin
      aw_match_count++;
    end
    else begin
      mismatch_count++;
      `uvm_error("STAGE1_E2E_AW", $sformatf(
        "AW mismatch: upstream {%s}, downstream {%s}",
        upstream.convert2string(), downstream.convert2string()))
    end
    aw_id_q.push_back(upstream.id);
  end
endfunction

function void stage1_e2e_checker::compare_w();
  m_event_t upstream;
  s_event_t downstream;
  while ((upstream_w_q.size() != 0) &&
         (downstream_w_q.size() != 0)) begin
    upstream   = upstream_w_q.pop_front();
    downstream = downstream_w_q.pop_front();
    if ((upstream.side          === AXI_UPSTREAM) &&
        (downstream.side        === AXI_DOWNSTREAM) &&
        (upstream.port_index    == 0) &&
        (downstream.port_index  == 0) &&
        (downstream.id          === expand_id(upstream.id)) &&
        (downstream.data        === upstream.data) &&
        (downstream.strb        === upstream.strb) &&
        (downstream.last        === upstream.last)) begin
      w_match_count++;
    end
    else begin
      mismatch_count++;
      `uvm_error("STAGE1_E2E_W", $sformatf(
        "W mismatch: upstream {%s}, downstream {%s}",
        upstream.convert2string(), downstream.convert2string()))
    end
    w_id_q.push_back(upstream.id);
  end
endfunction

function void stage1_e2e_checker::compare_ar();
  m_event_t upstream;
  s_event_t downstream;
  while ((upstream_ar_q.size() != 0) &&
         (downstream_ar_q.size() != 0)) begin
    upstream   = upstream_ar_q.pop_front();
    downstream = downstream_ar_q.pop_front();
    if ((upstream.side          === AXI_UPSTREAM) &&
        (downstream.side        === AXI_DOWNSTREAM) &&
        (upstream.port_index    == 0) &&
        (downstream.port_index  == 0) &&
        (downstream.id          === expand_id(upstream.id)) &&
        (downstream.addr        === upstream.addr) &&
        (downstream.len         === upstream.len) &&
        (downstream.size        === upstream.size) &&
        (downstream.burst_raw   === upstream.burst_raw)) begin
      ar_match_count++;
    end
    else begin
      mismatch_count++;
      `uvm_error("STAGE1_E2E_AR", $sformatf(
        "AR mismatch: upstream {%s}, downstream {%s}",
        upstream.convert2string(), downstream.convert2string()))
    end
    read_id_q.push_back(upstream.id);
  end
endfunction

function void stage1_e2e_checker::build_write_context();
  logic [M_ID_WIDTH-1:0] aw_id;
  logic [M_ID_WIDTH-1:0] w_id;
  while ((aw_id_q.size() != 0) && (w_id_q.size() != 0)) begin
    aw_id = aw_id_q.pop_front();
    w_id  = w_id_q.pop_front();
    if (aw_id !== w_id) begin
      mismatch_count++;
      `uvm_error("STAGE1_E2E_WID", "Upstream AWID and WID do not match")
    end
    write_id_q.push_back(aw_id);
  end
endfunction

function void stage1_e2e_checker::compare_b();
  m_event_t upstream;
  s_event_t downstream;
  logic [M_ID_WIDTH-1:0] original_id;
  while ((downstream_b_q.size() != 0) &&
         (upstream_b_q.size() != 0) &&
         (write_id_q.size() != 0)) begin
    downstream = downstream_b_q.pop_front();
    upstream   = upstream_b_q.pop_front();
    original_id = write_id_q.pop_front();
    if ((downstream.side       === AXI_DOWNSTREAM) &&
        (upstream.side         === AXI_UPSTREAM) &&
        (downstream.port_index == 0) &&
        (upstream.port_index   == 0) &&
        (downstream.id         === expand_id(original_id)) &&
        (upstream.id           === original_id) &&
        (upstream.resp_raw     === downstream.resp_raw)) begin
      b_match_count++;
    end
    else begin
      mismatch_count++;
      `uvm_error("STAGE1_E2E_B", $sformatf(
        "B mismatch: downstream {%s}, upstream {%s}",
        downstream.convert2string(), upstream.convert2string()))
    end
  end
endfunction

function void stage1_e2e_checker::compare_r();
  m_event_t upstream;
  s_event_t downstream;
  logic [M_ID_WIDTH-1:0] original_id;
  while ((downstream_r_q.size() != 0) &&
         (upstream_r_q.size() != 0) &&
         (read_id_q.size() != 0)) begin
    downstream = downstream_r_q.pop_front();
    upstream   = upstream_r_q.pop_front();
    original_id = read_id_q.pop_front();
    if ((downstream.side       === AXI_DOWNSTREAM) &&
        (upstream.side         === AXI_UPSTREAM) &&
        (downstream.port_index == 0) &&
        (upstream.port_index   == 0) &&
        (downstream.id         === expand_id(original_id)) &&
        (upstream.id           === original_id) &&
        (upstream.data         === downstream.data) &&
        (upstream.resp_raw     === downstream.resp_raw) &&
        (upstream.last         === downstream.last)) begin
      r_match_count++;
    end
    else begin
      mismatch_count++;
      `uvm_error("STAGE1_E2E_R", $sformatf(
        "R mismatch: downstream {%s}, upstream {%s}",
        downstream.convert2string(), upstream.convert2string()))
    end
  end
endfunction

function int unsigned stage1_e2e_checker::pending_count();
  return upstream_aw_q.size() + upstream_w_q.size() +
         upstream_b_q.size() + upstream_ar_q.size() +
         upstream_r_q.size() + downstream_aw_q.size() +
         downstream_w_q.size() + downstream_b_q.size() +
         downstream_ar_q.size() + downstream_r_q.size() +
         aw_id_q.size() + w_id_q.size() +
         write_id_q.size() + read_id_q.size();
endfunction

function void stage1_e2e_checker::clear();
  upstream_aw_q.delete();
  upstream_w_q.delete();
  upstream_b_q.delete();
  upstream_ar_q.delete();
  upstream_r_q.delete();
  downstream_aw_q.delete();
  downstream_w_q.delete();
  downstream_b_q.delete();
  downstream_ar_q.delete();
  downstream_r_q.delete();
  aw_id_q.delete();
  w_id_q.delete();
  write_id_q.delete();
  read_id_q.delete();
  aw_match_count = 0;
  w_match_count  = 0;
  b_match_count  = 0;
  ar_match_count = 0;
  r_match_count  = 0;
  mismatch_count = 0;
endfunction

function void stage1_e2e_checker::check_phase(uvm_phase phase);
  super.check_phase(phase);
  compare_available();
  if (pending_count() != 0)
    `uvm_error("STAGE1_E2E_PENDING", $sformatf(
      "Unmatched events or request contexts: %0d", pending_count()))
endfunction

`endif

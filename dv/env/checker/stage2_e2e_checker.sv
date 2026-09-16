`ifndef STAGE2_E2E_CHECKER_SV
`define STAGE2_E2E_CHECKER_SV

class stage2_e2e_checker #(
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
  typedef axi_req_item #(
    ADDR_WIDTH, DATA_WIDTH, M_ID_WIDTH, LEN_WIDTH
  ) m_req_t;
  typedef axi_req_item #(
    ADDR_WIDTH, DATA_WIDTH, S_ID_WIDTH, LEN_WIDTH
  ) s_req_t;
  typedef axi_rsp_item #(DATA_WIDTH, M_ID_WIDTH, LEN_WIDTH) m_rsp_t;
  typedef axi_rsp_item #(DATA_WIDTH, S_ID_WIDTH, LEN_WIDTH) s_rsp_t;
  typedef logic [S_ID_WIDTH-1:0] sid_t;

  uvm_analysis_imp_upstream_channel #(m_event_t,
    stage2_e2e_checker #(
      ADDR_WIDTH, DATA_WIDTH, M_ID_WIDTH, S_ID_WIDTH, LEN_WIDTH
    )
  ) upstream_channel_export;
  uvm_analysis_imp_downstream_channel #(s_event_t,
    stage2_e2e_checker #(
      ADDR_WIDTH, DATA_WIDTH, M_ID_WIDTH, S_ID_WIDTH, LEN_WIDTH
    )
  ) downstream_channel_export;
  uvm_analysis_imp_upstream_req #(m_req_t,
    stage2_e2e_checker #(
      ADDR_WIDTH, DATA_WIDTH, M_ID_WIDTH, S_ID_WIDTH, LEN_WIDTH
    )
  ) upstream_req_export;
  uvm_analysis_imp_downstream_req #(s_req_t,
    stage2_e2e_checker #(
      ADDR_WIDTH, DATA_WIDTH, M_ID_WIDTH, S_ID_WIDTH, LEN_WIDTH
    )
  ) downstream_req_export;
  uvm_analysis_imp_upstream_rsp #(m_rsp_t,
    stage2_e2e_checker #(
      ADDR_WIDTH, DATA_WIDTH, M_ID_WIDTH, S_ID_WIDTH, LEN_WIDTH
    )
  ) upstream_rsp_export;
  uvm_analysis_imp_downstream_rsp #(s_rsp_t,
    stage2_e2e_checker #(
      ADDR_WIDTH, DATA_WIDTH, M_ID_WIDTH, S_ID_WIDTH, LEN_WIDTH
    )
  ) downstream_rsp_export;

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
  m_req_t upstream_write_req_q[$];
  m_req_t upstream_read_req_q[$];
  s_req_t downstream_write_req_q[$];
  s_req_t downstream_read_req_q[$];
  m_rsp_t upstream_write_rsp_q[$];
  m_rsp_t upstream_read_rsp_q[$];
  s_rsp_t downstream_write_rsp_q[$];
  s_rsp_t downstream_read_rsp_q[$];

  bit write_event_context;
  bit write_item_context;
  bit read_event_context;
  bit read_item_context;
  logic [M_ID_WIDTH-1:0] write_original_id;
  logic [M_ID_WIDTH-1:0] read_original_id;
  logic [S_ID_WIDTH-1:0] write_expanded_id;
  logic [S_ID_WIDTH-1:0] read_expanded_id;

  bit check_expected_counts;
  int unsigned expected_write_count;
  int unsigned expected_read_count;
  int unsigned aw_match_count;
  int unsigned w_match_count;
  int unsigned b_match_count;
  int unsigned ar_match_count;
  int unsigned r_match_count;
  int unsigned write_req_match_count;
  int unsigned read_req_match_count;
  int unsigned write_rsp_match_count;
  int unsigned read_rsp_match_count;
  int unsigned expected_w_beat_count;
  int unsigned expected_r_beat_count;
  int unsigned mismatch_count;

  `uvm_component_param_utils(
    stage2_e2e_checker #(
      ADDR_WIDTH, DATA_WIDTH, M_ID_WIDTH, S_ID_WIDTH, LEN_WIDTH
    )
  )

  extern function new(string name = "stage2_e2e_checker",
                      uvm_component parent = null);
  extern virtual function void build_phase(uvm_phase phase);
  extern virtual function void write_upstream_channel(m_event_t item);
  extern virtual function void write_downstream_channel(s_event_t item);
  extern virtual function void write_upstream_req(m_req_t item);
  extern virtual function void write_downstream_req(s_req_t item);
  extern virtual function void write_upstream_rsp(m_rsp_t item);
  extern virtual function void write_downstream_rsp(s_rsp_t item);
  extern function sid_t expand_id(logic [M_ID_WIDTH-1:0] original_id);
  extern function void set_expected_counts(int unsigned write_count,
                                           int unsigned read_count);
  extern function void compare_available();
  extern function void compare_aw();
  extern function void compare_w();
  extern function void compare_ar();
  extern function void compare_b();
  extern function void compare_r();
  extern function void compare_requests();
  extern function void compare_responses();
  extern function bit compare_write_request(m_req_t upstream,
                                             s_req_t downstream);
  extern function bit compare_read_request(m_req_t upstream,
                                            s_req_t downstream);
  extern function bit compare_write_response(s_rsp_t downstream,
                                              m_rsp_t upstream);
  extern function bit compare_read_response(s_rsp_t downstream,
                                             m_rsp_t upstream);
  extern function int unsigned pending_count();
  extern function void clear();
  extern virtual function void check_phase(uvm_phase phase);

endclass

function stage2_e2e_checker::new(
  string name = "stage2_e2e_checker",
  uvm_component parent = null
);
  super.new(name, parent);
  clear();
endfunction

function void stage2_e2e_checker::build_phase(uvm_phase phase);
  super.build_phase(phase);
  upstream_channel_export   = new("upstream_channel_export", this);
  downstream_channel_export = new("downstream_channel_export", this);
  upstream_req_export       = new("upstream_req_export", this);
  downstream_req_export     = new("downstream_req_export", this);
  upstream_rsp_export       = new("upstream_rsp_export", this);
  downstream_rsp_export     = new("downstream_rsp_export", this);
endfunction

function void stage2_e2e_checker::write_upstream_channel(m_event_t item);
  m_event_t snapshot;
  if ((item == null) || !$cast(snapshot, item.clone())) begin
    mismatch_count++;
    `uvm_error("STAGE2_E2E", "Failed to clone upstream channel event")
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

function void stage2_e2e_checker::write_downstream_channel(s_event_t item);
  s_event_t snapshot;
  if ((item == null) || !$cast(snapshot, item.clone())) begin
    mismatch_count++;
    `uvm_error("STAGE2_E2E", "Failed to clone downstream channel event")
    return;
  end
  case (snapshot.channel)
    AXI_CHANNEL_AW: downstream_aw_q.push_back(snapshot);
    AXI_CHANNEL_W:  downstream_w_q.push_back(snapshot);
    AXI_CHANNEL_B: begin
      if (!write_event_context) begin
        mismatch_count++;
        `uvm_error("STAGE2_E2E_B_ORDER",
                   "Downstream B arrived before a complete write request")
      end
      downstream_b_q.push_back(snapshot);
    end
    AXI_CHANNEL_AR: downstream_ar_q.push_back(snapshot);
    AXI_CHANNEL_R: begin
      if (!read_event_context) begin
        mismatch_count++;
        `uvm_error("STAGE2_E2E_R_ORDER",
                   "Downstream R arrived before a complete read request")
      end
      downstream_r_q.push_back(snapshot);
    end
  endcase
  compare_available();
endfunction

function void stage2_e2e_checker::write_upstream_req(m_req_t item);
  m_req_t snapshot;
  if ((item == null) || !$cast(snapshot, item.clone())) begin
    mismatch_count++;
    `uvm_error("STAGE2_E2E", "Failed to clone upstream request")
    return;
  end
  if (snapshot.dir == AXI_WRITE)
    upstream_write_req_q.push_back(snapshot);
  else
    upstream_read_req_q.push_back(snapshot);
  compare_available();
endfunction

function void stage2_e2e_checker::write_downstream_req(s_req_t item);
  s_req_t snapshot;
  if ((item == null) || !$cast(snapshot, item.clone())) begin
    mismatch_count++;
    `uvm_error("STAGE2_E2E", "Failed to clone downstream request")
    return;
  end
  if (snapshot.dir == AXI_WRITE)
    downstream_write_req_q.push_back(snapshot);
  else
    downstream_read_req_q.push_back(snapshot);
  compare_available();
endfunction

function void stage2_e2e_checker::write_upstream_rsp(m_rsp_t item);
  m_rsp_t snapshot;
  if ((item == null) || !$cast(snapshot, item.clone())) begin
    mismatch_count++;
    `uvm_error("STAGE2_E2E", "Failed to clone upstream response")
    return;
  end
  if (snapshot.dir == AXI_WRITE)
    upstream_write_rsp_q.push_back(snapshot);
  else
    upstream_read_rsp_q.push_back(snapshot);
  compare_available();
endfunction

function void stage2_e2e_checker::write_downstream_rsp(s_rsp_t item);
  s_rsp_t snapshot;
  if ((item == null) || !$cast(snapshot, item.clone())) begin
    mismatch_count++;
    `uvm_error("STAGE2_E2E", "Failed to clone downstream response")
    return;
  end
  if (snapshot.dir == AXI_WRITE)
    downstream_write_rsp_q.push_back(snapshot);
  else
    downstream_read_rsp_q.push_back(snapshot);
  compare_available();
endfunction

function stage2_e2e_checker::sid_t stage2_e2e_checker::expand_id(
  logic [M_ID_WIDTH-1:0] original_id
);
  return sid_t'({2'b01, 2'b01, original_id});
endfunction

function void stage2_e2e_checker::set_expected_counts(
  int unsigned write_count,
  int unsigned read_count
);
  check_expected_counts = 1'b1;
  expected_write_count  = write_count;
  expected_read_count   = read_count;
endfunction

function void stage2_e2e_checker::compare_available();
  compare_aw();
  compare_w();
  compare_ar();
  compare_requests();
  compare_b();
  compare_r();
  compare_responses();
endfunction

function void stage2_e2e_checker::compare_aw();
  m_event_t upstream;
  s_event_t downstream;
  while ((upstream_aw_q.size() != 0) &&
         (downstream_aw_q.size() != 0)) begin
    upstream   = upstream_aw_q.pop_front();
    downstream = downstream_aw_q.pop_front();
    if ((upstream.side         === AXI_UPSTREAM) &&
        (downstream.side       === AXI_DOWNSTREAM) &&
        (upstream.port_index   == 0) &&
        (downstream.port_index == 0) &&
        (downstream.id         === expand_id(upstream.id)) &&
        (downstream.addr       === upstream.addr) &&
        (downstream.len        === upstream.len) &&
        (downstream.size       === upstream.size) &&
        (downstream.burst_raw  === upstream.burst_raw)) begin
      aw_match_count++;
    end
    else begin
      mismatch_count++;
      `uvm_error("STAGE2_E2E_AW", $sformatf(
        "AW mismatch: upstream {%s}, downstream {%s}",
        upstream.convert2string(), downstream.convert2string()))
    end
  end
endfunction

function void stage2_e2e_checker::compare_w();
  m_event_t upstream;
  s_event_t downstream;
  while ((upstream_w_q.size() != 0) &&
         (downstream_w_q.size() != 0)) begin
    upstream   = upstream_w_q.pop_front();
    downstream = downstream_w_q.pop_front();
    if ((upstream.side         === AXI_UPSTREAM) &&
        (downstream.side       === AXI_DOWNSTREAM) &&
        (upstream.port_index   == 0) &&
        (downstream.port_index == 0) &&
        (downstream.id         === expand_id(upstream.id)) &&
        (downstream.data       === upstream.data) &&
        (downstream.strb       === upstream.strb) &&
        (downstream.last       === upstream.last)) begin
      w_match_count++;
    end
    else begin
      mismatch_count++;
      `uvm_error("STAGE2_E2E_W", $sformatf(
        "W mismatch: upstream {%s}, downstream {%s}",
        upstream.convert2string(), downstream.convert2string()))
    end
  end
endfunction

function void stage2_e2e_checker::compare_ar();
  m_event_t upstream;
  s_event_t downstream;
  while ((upstream_ar_q.size() != 0) &&
         (downstream_ar_q.size() != 0)) begin
    upstream   = upstream_ar_q.pop_front();
    downstream = downstream_ar_q.pop_front();
    if ((upstream.side         === AXI_UPSTREAM) &&
        (downstream.side       === AXI_DOWNSTREAM) &&
        (upstream.port_index   == 0) &&
        (downstream.port_index == 0) &&
        (downstream.id         === expand_id(upstream.id)) &&
        (downstream.addr       === upstream.addr) &&
        (downstream.len        === upstream.len) &&
        (downstream.size       === upstream.size) &&
        (downstream.burst_raw  === upstream.burst_raw)) begin
      ar_match_count++;
    end
    else begin
      mismatch_count++;
      `uvm_error("STAGE2_E2E_AR", $sformatf(
        "AR mismatch: upstream {%s}, downstream {%s}",
        upstream.convert2string(), downstream.convert2string()))
    end
  end
endfunction

function bit stage2_e2e_checker::compare_write_request(
  m_req_t upstream,
  s_req_t downstream
);
  if ((upstream.dir != AXI_WRITE) ||
      (downstream.dir != AXI_WRITE) ||
      (downstream.id != expand_id(upstream.id)) ||
      (downstream.addr != upstream.addr) ||
      (downstream.len != upstream.len) ||
      (downstream.size != upstream.size) ||
      (downstream.burst != upstream.burst) ||
      (downstream.wdata.size() != upstream.wdata.size()) ||
      (downstream.wstrb.size() != upstream.wstrb.size()))
    return 1'b0;

  foreach (upstream.wdata[index]) begin
    if ((downstream.wdata[index] != upstream.wdata[index]) ||
        (downstream.wstrb[index] != upstream.wstrb[index]))
      return 1'b0;
  end
  return 1'b1;
endfunction

function bit stage2_e2e_checker::compare_read_request(
  m_req_t upstream,
  s_req_t downstream
);
  return (upstream.dir == AXI_READ) &&
         (downstream.dir == AXI_READ) &&
         (downstream.id == expand_id(upstream.id)) &&
         (downstream.addr == upstream.addr) &&
         (downstream.len == upstream.len) &&
         (downstream.size == upstream.size) &&
         (downstream.burst == upstream.burst) &&
         (upstream.wdata.size() == 0) &&
         (upstream.wstrb.size() == 0) &&
         (downstream.wdata.size() == 0) &&
         (downstream.wstrb.size() == 0);
endfunction

function void stage2_e2e_checker::compare_requests();
  m_req_t upstream;
  s_req_t downstream;
  bit match;

  while ((upstream_write_req_q.size() != 0) &&
         (downstream_write_req_q.size() != 0)) begin
    upstream   = upstream_write_req_q.pop_front();
    downstream = downstream_write_req_q.pop_front();
    match = compare_write_request(upstream, downstream);
    if (write_event_context || write_item_context) begin
      mismatch_count++;
      `uvm_error("STAGE2_E2E_WRITE_CONTEXT",
                 "Second write request before prior B response")
    end
    write_original_id   = upstream.id;
    write_expanded_id   = downstream.id;
    write_event_context = 1'b1;
    write_item_context  = 1'b1;
    if (match)
      write_req_match_count++;
    else begin
      mismatch_count++;
      `uvm_error("STAGE2_E2E_REQ", $sformatf(
        "Write request mismatch: upstream {%s}, downstream {%s}",
        upstream.convert2string(), downstream.convert2string()))
    end
    expected_w_beat_count += int'(upstream.len) + 1;
  end

  while ((upstream_read_req_q.size() != 0) &&
         (downstream_read_req_q.size() != 0)) begin
    upstream   = upstream_read_req_q.pop_front();
    downstream = downstream_read_req_q.pop_front();
    match = compare_read_request(upstream, downstream);
    if (read_event_context || read_item_context) begin
      mismatch_count++;
      `uvm_error("STAGE2_E2E_READ_CONTEXT",
                 "Second read request before prior R response")
    end
    read_original_id   = upstream.id;
    read_expanded_id   = downstream.id;
    read_event_context = 1'b1;
    read_item_context  = 1'b1;
    if (match)
      read_req_match_count++;
    else begin
      mismatch_count++;
      `uvm_error("STAGE2_E2E_REQ", $sformatf(
        "Read request mismatch: upstream {%s}, downstream {%s}",
        upstream.convert2string(), downstream.convert2string()))
    end
    expected_r_beat_count += int'(upstream.len) + 1;
  end
endfunction

function void stage2_e2e_checker::compare_b();
  m_event_t upstream;
  s_event_t downstream;
  while ((upstream_b_q.size() != 0) &&
         (downstream_b_q.size() != 0)) begin
    upstream   = upstream_b_q.pop_front();
    downstream = downstream_b_q.pop_front();
    if (write_event_context &&
        (downstream.side   === AXI_DOWNSTREAM) &&
        (upstream.side     === AXI_UPSTREAM) &&
        (downstream.port_index == 0) &&
        (upstream.port_index == 0) &&
        (downstream.id     === write_expanded_id) &&
        (upstream.id       === write_original_id) &&
        (upstream.resp_raw === downstream.resp_raw)) begin
      b_match_count++;
    end
    else begin
      mismatch_count++;
      `uvm_error("STAGE2_E2E_B", $sformatf(
        "B mismatch: downstream {%s}, upstream {%s}",
        downstream.convert2string(), upstream.convert2string()))
    end
    write_event_context = 1'b0;
  end
endfunction

function void stage2_e2e_checker::compare_r();
  m_event_t upstream;
  s_event_t downstream;
  while ((upstream_r_q.size() != 0) &&
         (downstream_r_q.size() != 0)) begin
    upstream   = upstream_r_q.pop_front();
    downstream = downstream_r_q.pop_front();
    if (read_event_context &&
        (downstream.side   === AXI_DOWNSTREAM) &&
        (upstream.side     === AXI_UPSTREAM) &&
        (downstream.port_index == 0) &&
        (upstream.port_index == 0) &&
        (downstream.id     === read_expanded_id) &&
        (upstream.id       === read_original_id) &&
        (upstream.data     === downstream.data) &&
        (upstream.resp_raw === downstream.resp_raw) &&
        (upstream.last     === downstream.last)) begin
      r_match_count++;
    end
    else begin
      mismatch_count++;
      `uvm_error("STAGE2_E2E_R", $sformatf(
        "R mismatch: downstream {%s}, upstream {%s}",
        downstream.convert2string(), upstream.convert2string()))
    end
    if (upstream.last === 1'b1)
      read_event_context = 1'b0;
  end
endfunction

function bit stage2_e2e_checker::compare_write_response(
  s_rsp_t downstream,
  m_rsp_t upstream
);
  return (downstream.dir == AXI_WRITE) &&
         (upstream.dir == AXI_WRITE) &&
         (downstream.id == write_expanded_id) &&
         (upstream.id == write_original_id) &&
         (upstream.bresp == downstream.bresp);
endfunction

function bit stage2_e2e_checker::compare_read_response(
  s_rsp_t downstream,
  m_rsp_t upstream
);
  if ((downstream.dir != AXI_READ) ||
      (upstream.dir != AXI_READ) ||
      (downstream.id != read_expanded_id) ||
      (upstream.id != read_original_id) ||
      (downstream.len != upstream.len) ||
      (downstream.rdata.size() != upstream.rdata.size()) ||
      (downstream.rresp.size() != upstream.rresp.size()))
    return 1'b0;

  foreach (downstream.rdata[index]) begin
    if ((downstream.rdata[index] != upstream.rdata[index]) ||
        (downstream.rresp[index] != upstream.rresp[index]))
      return 1'b0;
  end
  return 1'b1;
endfunction

function void stage2_e2e_checker::compare_responses();
  m_rsp_t upstream;
  s_rsp_t downstream;
  bit match;

  while ((upstream_write_rsp_q.size() != 0) &&
         (downstream_write_rsp_q.size() != 0)) begin
    upstream   = upstream_write_rsp_q.pop_front();
    downstream = downstream_write_rsp_q.pop_front();
    match = write_item_context &&
            compare_write_response(downstream, upstream);
    write_item_context = 1'b0;
    if (match)
      write_rsp_match_count++;
    else begin
      mismatch_count++;
      `uvm_error("STAGE2_E2E_RSP", $sformatf(
        "Write response mismatch: downstream {%s}, upstream {%s}",
        downstream.convert2string(), upstream.convert2string()))
    end
  end

  while ((upstream_read_rsp_q.size() != 0) &&
         (downstream_read_rsp_q.size() != 0)) begin
    upstream   = upstream_read_rsp_q.pop_front();
    downstream = downstream_read_rsp_q.pop_front();
    match = read_item_context &&
            compare_read_response(downstream, upstream);
    read_item_context = 1'b0;
    if (match)
      read_rsp_match_count++;
    else begin
      mismatch_count++;
      `uvm_error("STAGE2_E2E_RSP", $sformatf(
        "Read response mismatch: downstream {%s}, upstream {%s}",
        downstream.convert2string(), upstream.convert2string()))
    end
  end
endfunction

function int unsigned stage2_e2e_checker::pending_count();
  return upstream_aw_q.size() + upstream_w_q.size() +
         upstream_b_q.size() + upstream_ar_q.size() +
         upstream_r_q.size() + downstream_aw_q.size() +
         downstream_w_q.size() + downstream_b_q.size() +
         downstream_ar_q.size() + downstream_r_q.size() +
         upstream_write_req_q.size() + upstream_read_req_q.size() +
         downstream_write_req_q.size() + downstream_read_req_q.size() +
         upstream_write_rsp_q.size() + upstream_read_rsp_q.size() +
         downstream_write_rsp_q.size() + downstream_read_rsp_q.size() +
         write_event_context + write_item_context +
         read_event_context + read_item_context;
endfunction

function void stage2_e2e_checker::clear();
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
  upstream_write_req_q.delete();
  upstream_read_req_q.delete();
  downstream_write_req_q.delete();
  downstream_read_req_q.delete();
  upstream_write_rsp_q.delete();
  upstream_read_rsp_q.delete();
  downstream_write_rsp_q.delete();
  downstream_read_rsp_q.delete();
  write_event_context  = 1'b0;
  write_item_context   = 1'b0;
  read_event_context   = 1'b0;
  read_item_context    = 1'b0;
  check_expected_counts = 1'b0;
  expected_write_count = 0;
  expected_read_count  = 0;
  aw_match_count        = 0;
  w_match_count         = 0;
  b_match_count         = 0;
  ar_match_count        = 0;
  r_match_count         = 0;
  write_req_match_count = 0;
  read_req_match_count  = 0;
  write_rsp_match_count = 0;
  read_rsp_match_count  = 0;
  expected_w_beat_count = 0;
  expected_r_beat_count = 0;
  mismatch_count        = 0;
endfunction

function void stage2_e2e_checker::check_phase(uvm_phase phase);
  super.check_phase(phase);
  compare_available();

  if (pending_count() != 0)
    `uvm_error("STAGE2_E2E_PENDING", $sformatf(
      "Unmatched events, items, or contexts: %0d", pending_count()))

  if ((aw_match_count != write_req_match_count) ||
      (w_match_count != expected_w_beat_count) ||
      (b_match_count != write_rsp_match_count) ||
      (ar_match_count != read_req_match_count) ||
      (r_match_count != expected_r_beat_count) ||
      (write_rsp_match_count != write_req_match_count) ||
      (read_rsp_match_count != read_req_match_count))
    `uvm_error("STAGE2_E2E_INTERNAL_COUNT", $sformatf({
      "Channel/item counts AW/W/B=%0d/%0d/%0d AR/R=%0d/%0d ",
      "REQ(W/R)=%0d/%0d RSP(W/R)=%0d/%0d expected W/R beats=%0d/%0d"},
      aw_match_count, w_match_count, b_match_count,
      ar_match_count, r_match_count,
      write_req_match_count, read_req_match_count,
      write_rsp_match_count, read_rsp_match_count,
      expected_w_beat_count, expected_r_beat_count))

  if (check_expected_counts &&
      ((write_req_match_count != expected_write_count) ||
       (write_rsp_match_count != expected_write_count) ||
       (read_req_match_count != expected_read_count) ||
       (read_rsp_match_count != expected_read_count)))
    `uvm_error("STAGE2_E2E_COUNT", $sformatf(
      "Expected write/read=%0d/%0d, matched req=%0d/%0d rsp=%0d/%0d",
      expected_write_count, expected_read_count,
      write_req_match_count, read_req_match_count,
      write_rsp_match_count, read_rsp_match_count))
endfunction

`endif

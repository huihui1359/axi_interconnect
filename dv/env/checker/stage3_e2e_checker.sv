`ifndef STAGE3_E2E_CHECKER_SV
`define STAGE3_E2E_CHECKER_SV

class stage3_e2e_checker #(
  int unsigned ADDR_WIDTH = AXI_ADDR_WIDTH,
  int unsigned DATA_WIDTH = AXI_DATA_WIDTH,
  int unsigned M_ID_WIDTH = AXI_M_ID_WIDTH,
  int unsigned S_ID_WIDTH = AXI_S_ID_WIDTH,
  int unsigned LEN_WIDTH  = AXI_LEN_WIDTH
) extends uvm_component;

  localparam int unsigned M_ID_COUNT = 1 << M_ID_WIDTH;

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
  typedef axi_switch_ref_model #(
    ADDR_WIDTH, M_ID_WIDTH, S_ID_WIDTH
  ) model_t;
  typedef bit [M_ID_WIDTH-1:0] mid_t;
  typedef bit [S_ID_WIDTH-1:0] sid_t;

  uvm_analysis_imp_upstream_channel #(m_event_t,
    stage3_e2e_checker #(
      ADDR_WIDTH, DATA_WIDTH, M_ID_WIDTH, S_ID_WIDTH, LEN_WIDTH
    )
  ) upstream_channel_export;
  uvm_analysis_imp_downstream_channel #(s_event_t,
    stage3_e2e_checker #(
      ADDR_WIDTH, DATA_WIDTH, M_ID_WIDTH, S_ID_WIDTH, LEN_WIDTH
    )
  ) downstream_channel_export;
  uvm_analysis_imp_upstream_req #(m_req_t,
    stage3_e2e_checker #(
      ADDR_WIDTH, DATA_WIDTH, M_ID_WIDTH, S_ID_WIDTH, LEN_WIDTH
    )
  ) upstream_req_export;
  uvm_analysis_imp_downstream_req #(s_req_t,
    stage3_e2e_checker #(
      ADDR_WIDTH, DATA_WIDTH, M_ID_WIDTH, S_ID_WIDTH, LEN_WIDTH
    )
  ) downstream_req_export;
  uvm_analysis_imp_upstream_rsp #(m_rsp_t,
    stage3_e2e_checker #(
      ADDR_WIDTH, DATA_WIDTH, M_ID_WIDTH, S_ID_WIDTH, LEN_WIDTH
    )
  ) upstream_rsp_export;
  uvm_analysis_imp_downstream_rsp #(s_rsp_t,
    stage3_e2e_checker #(
      ADDR_WIDTH, DATA_WIDTH, M_ID_WIDTH, S_ID_WIDTH, LEN_WIDTH
    )
  ) downstream_rsp_export;

  model_t switch_model;
  bit enabled;

  m_event_t upstream_aw_by_id[M_ID_COUNT][$];
  m_event_t upstream_w_by_id[M_ID_COUNT][$];
  m_event_t upstream_b_by_id[M_ID_COUNT][$];
  m_event_t upstream_ar_by_id[M_ID_COUNT][$];
  m_event_t upstream_r_by_id[M_ID_COUNT][$];
  s_event_t downstream_aw_by_id[M_ID_COUNT][$];
  s_event_t downstream_w_by_id[M_ID_COUNT][$];
  s_event_t downstream_b_by_id[M_ID_COUNT][$];
  s_event_t downstream_ar_by_id[M_ID_COUNT][$];
  s_event_t downstream_r_by_id[M_ID_COUNT][$];

  m_req_t upstream_write_req_by_id[M_ID_COUNT][$];
  m_req_t upstream_read_req_by_id[M_ID_COUNT][$];
  s_req_t downstream_write_req_by_id[M_ID_COUNT][$];
  s_req_t downstream_read_req_by_id[M_ID_COUNT][$];
  s_req_t pending_write_response_by_id[M_ID_COUNT][$];
  s_req_t pending_read_response_by_id[M_ID_COUNT][$];
  m_rsp_t upstream_write_rsp_by_id[M_ID_COUNT][$];
  m_rsp_t upstream_read_rsp_by_id[M_ID_COUNT][$];
  s_rsp_t downstream_write_rsp_by_id[M_ID_COUNT][$];
  s_rsp_t downstream_read_rsp_by_id[M_ID_COUNT][$];

  int unsigned write_accept_order[$];
  int unsigned read_accept_order[$];
  int unsigned write_depth_by_id[M_ID_COUNT];
  int unsigned read_depth_by_id[M_ID_COUNT];
  int unsigned write_req_count_by_id[M_ID_COUNT];
  int unsigned read_req_count_by_id[M_ID_COUNT];
  int unsigned write_rsp_count_by_id[M_ID_COUNT];
  int unsigned read_rsp_count_by_id[M_ID_COUNT];

  int unsigned aw_event_count;
  int unsigned w_event_count;
  int unsigned b_event_count;
  int unsigned ar_event_count;
  int unsigned r_event_count;
  int unsigned write_req_match_count;
  int unsigned read_req_match_count;
  int unsigned write_rsp_match_count;
  int unsigned read_rsp_match_count;
  int unsigned expected_w_beat_count;
  int unsigned expected_r_beat_count;
  int unsigned max_write_outstanding;
  int unsigned max_read_outstanding;
  int unsigned different_id_reorder_count;
  int unsigned same_id_multiple_count;
  int unsigned mismatch_count;
  bit check_expected_counts;
  int unsigned expected_write_count;
  int unsigned expected_read_count;

  `uvm_component_param_utils(
    stage3_e2e_checker #(
      ADDR_WIDTH, DATA_WIDTH, M_ID_WIDTH, S_ID_WIDTH, LEN_WIDTH
    )
  )

  extern function new(string name = "stage3_e2e_checker",
                      uvm_component parent = null);
  extern virtual function void build_phase(uvm_phase phase);
  extern virtual function void write_upstream_channel(m_event_t item);
  extern virtual function void write_downstream_channel(s_event_t item);
  extern virtual function void write_upstream_req(m_req_t item);
  extern virtual function void write_downstream_req(s_req_t item);
  extern virtual function void write_upstream_rsp(m_rsp_t item);
  extern virtual function void write_downstream_rsp(s_rsp_t item);
  extern function void set_expected_counts(int unsigned write_count,
                                           int unsigned read_count);
  extern function sid_t expected_sid(mid_t id, bit [ADDR_WIDTH-1:0] addr);
  extern function int unsigned restore_index(sid_t sid);
  extern function int unsigned write_outstanding();
  extern function int unsigned read_outstanding();
  extern function void compare_available();
  extern function void compare_aw(int unsigned id);
  extern function void compare_w(int unsigned id);
  extern function void compare_b(int unsigned id);
  extern function void compare_ar(int unsigned id);
  extern function void compare_r(int unsigned id);
  extern function void compare_requests(int unsigned id);
  extern function void compare_responses(int unsigned id);
  extern function bit compare_write_request(m_req_t upstream,
                                             s_req_t downstream);
  extern function bit compare_read_request(m_req_t upstream,
                                            s_req_t downstream);
  extern function bit compare_write_response(s_rsp_t downstream,
                                              m_rsp_t upstream);
  extern function bit compare_read_response(s_rsp_t downstream,
                                             m_rsp_t upstream);
  extern function void record_write_completion(int unsigned id);
  extern function void record_read_completion(int unsigned id);
  extern function int unsigned pending_count();
  extern function void clear();
  extern virtual function void check_phase(uvm_phase phase);

endclass

function stage3_e2e_checker::new(
  string name = "stage3_e2e_checker",
  uvm_component parent = null
);
  super.new(name, parent);
  switch_model = model_t::type_id::create("switch_model");
  enabled = 1'b0;
  clear();
endfunction

function void stage3_e2e_checker::build_phase(uvm_phase phase);
  super.build_phase(phase);
  upstream_channel_export   = new("upstream_channel_export", this);
  downstream_channel_export = new("downstream_channel_export", this);
  upstream_req_export       = new("upstream_req_export", this);
  downstream_req_export     = new("downstream_req_export", this);
  upstream_rsp_export       = new("upstream_rsp_export", this);
  downstream_rsp_export     = new("downstream_rsp_export", this);
endfunction

function stage3_e2e_checker::sid_t stage3_e2e_checker::expected_sid(
  mid_t id,
  bit [ADDR_WIDTH-1:0] addr
);
  return switch_model.encode_sid(0, switch_model.decode_address(addr), id);
endfunction

function int unsigned stage3_e2e_checker::restore_index(sid_t sid);
  return int'(switch_model.restore_id(sid));
endfunction

function void stage3_e2e_checker::write_upstream_channel(m_event_t item);
  m_event_t snapshot;
  int unsigned id;

  if (!enabled)
    return;
  if ((item == null) || !$cast(snapshot, item.clone())) begin
    mismatch_count++;
    `uvm_error("STAGE3_E2E", "Failed to clone upstream channel event")
    return;
  end
  id = int'(snapshot.id);
  case (snapshot.channel)
    AXI_CHANNEL_AW: begin
      upstream_aw_by_id[id].push_back(snapshot);
      if (write_depth_by_id[id] != 0)
        same_id_multiple_count++;
      write_depth_by_id[id]++;
      if (write_outstanding() > max_write_outstanding)
        max_write_outstanding = write_outstanding();
    end
    AXI_CHANNEL_W:  upstream_w_by_id[id].push_back(snapshot);
    AXI_CHANNEL_B: begin
      upstream_b_by_id[id].push_back(snapshot);
      if (write_depth_by_id[id] == 0) begin
        mismatch_count++;
        `uvm_error("STAGE3_E2E_B_CAUSAL", "Upstream B underflow")
      end
      else begin
        write_depth_by_id[id]--;
      end
    end
    AXI_CHANNEL_AR: begin
      upstream_ar_by_id[id].push_back(snapshot);
      if (read_depth_by_id[id] != 0)
        same_id_multiple_count++;
      read_depth_by_id[id]++;
      if (read_outstanding() > max_read_outstanding)
        max_read_outstanding = read_outstanding();
    end
    AXI_CHANNEL_R: begin
      upstream_r_by_id[id].push_back(snapshot);
      if (snapshot.last === 1'b1) begin
        if (read_depth_by_id[id] == 0) begin
          mismatch_count++;
          `uvm_error("STAGE3_E2E_R_CAUSAL", "Upstream RLAST underflow")
        end
        else begin
          read_depth_by_id[id]--;
        end
      end
    end
  endcase
  compare_available();
endfunction

function void stage3_e2e_checker::write_downstream_channel(s_event_t item);
  s_event_t snapshot;
  int unsigned id;

  if (!enabled)
    return;
  if ((item == null) || !$cast(snapshot, item.clone())) begin
    mismatch_count++;
    `uvm_error("STAGE3_E2E", "Failed to clone downstream channel event")
    return;
  end
  id = restore_index(snapshot.id);
  case (snapshot.channel)
    AXI_CHANNEL_AW: begin
      downstream_aw_by_id[id].push_back(snapshot);
      write_accept_order.push_back(id);
    end
    AXI_CHANNEL_W:  downstream_w_by_id[id].push_back(snapshot);
    AXI_CHANNEL_B:  downstream_b_by_id[id].push_back(snapshot);
    AXI_CHANNEL_AR: begin
      downstream_ar_by_id[id].push_back(snapshot);
      read_accept_order.push_back(id);
    end
    AXI_CHANNEL_R:  downstream_r_by_id[id].push_back(snapshot);
  endcase
  compare_available();
endfunction

function void stage3_e2e_checker::write_upstream_req(m_req_t item);
  m_req_t snapshot;
  int unsigned id;

  if (!enabled)
    return;
  if ((item == null) || !$cast(snapshot, item.clone())) begin
    mismatch_count++;
    `uvm_error("STAGE3_E2E", "Failed to clone upstream request")
    return;
  end
  id = int'(snapshot.id);
  if (snapshot.dir == AXI_WRITE)
    upstream_write_req_by_id[id].push_back(snapshot);
  else
    upstream_read_req_by_id[id].push_back(snapshot);
  compare_available();
endfunction

function void stage3_e2e_checker::write_downstream_req(s_req_t item);
  s_req_t snapshot;
  s_req_t response_context;
  int unsigned id;

  if (!enabled)
    return;
  if ((item == null) || !$cast(snapshot, item.clone())) begin
    mismatch_count++;
    `uvm_error("STAGE3_E2E", "Failed to clone downstream request")
    return;
  end
  id = restore_index(snapshot.id);
  if (snapshot.id !== expected_sid(mid_t'(id), snapshot.addr)) begin
    mismatch_count++;
    `uvm_error("STAGE3_E2E_SID", $sformatf(
      "Request SID 0x%0h is inconsistent with ID 0x%0h and address 0x%0h",
      snapshot.id, id, snapshot.addr))
  end
  if (!$cast(response_context, snapshot.clone()))
    `uvm_fatal("STAGE3_E2E_CLONE", "Failed to clone response context")

  if (snapshot.dir == AXI_WRITE) begin
    downstream_write_req_by_id[id].push_back(snapshot);
    pending_write_response_by_id[id].push_back(response_context);
  end
  else begin
    downstream_read_req_by_id[id].push_back(snapshot);
    pending_read_response_by_id[id].push_back(response_context);
  end
  compare_available();
endfunction

function void stage3_e2e_checker::write_upstream_rsp(m_rsp_t item);
  m_rsp_t snapshot;
  int unsigned id;

  if (!enabled)
    return;
  if ((item == null) || !$cast(snapshot, item.clone())) begin
    mismatch_count++;
    `uvm_error("STAGE3_E2E", "Failed to clone upstream response")
    return;
  end
  id = int'(snapshot.id);
  if (snapshot.dir == AXI_WRITE)
    upstream_write_rsp_by_id[id].push_back(snapshot);
  else
    upstream_read_rsp_by_id[id].push_back(snapshot);
  compare_available();
endfunction

function void stage3_e2e_checker::write_downstream_rsp(s_rsp_t item);
  s_rsp_t snapshot;
  s_req_t completed;
  int unsigned id;

  if (!enabled)
    return;
  if ((item == null) || !$cast(snapshot, item.clone())) begin
    mismatch_count++;
    `uvm_error("STAGE3_E2E", "Failed to clone downstream response")
    return;
  end
  id = restore_index(snapshot.id);
  if (snapshot.dir == AXI_WRITE) begin
    if (pending_write_response_by_id[id].size() == 0) begin
      mismatch_count++;
      `uvm_error("STAGE3_E2E_B_CAUSAL",
                 "Downstream B has no complete write request")
    end
    else begin
      completed = pending_write_response_by_id[id].pop_front();
    end
    downstream_write_rsp_by_id[id].push_back(snapshot);
    record_write_completion(id);
  end
  else begin
    if (pending_read_response_by_id[id].size() == 0) begin
      mismatch_count++;
      `uvm_error("STAGE3_E2E_R_CAUSAL",
                 "Downstream R has no accepted read request")
    end
    else begin
      completed = pending_read_response_by_id[id].pop_front();
    end
    downstream_read_rsp_by_id[id].push_back(snapshot);
    record_read_completion(id);
  end
  compare_available();
endfunction

function void stage3_e2e_checker::set_expected_counts(
  int unsigned write_count,
  int unsigned read_count
);
  check_expected_counts = 1'b1;
  expected_write_count  = write_count;
  expected_read_count   = read_count;
endfunction

function int unsigned stage3_e2e_checker::write_outstanding();
  int unsigned total;
  total = 0;
  foreach (write_depth_by_id[id])
    total += write_depth_by_id[id];
  return total;
endfunction

function int unsigned stage3_e2e_checker::read_outstanding();
  int unsigned total;
  total = 0;
  foreach (read_depth_by_id[id])
    total += read_depth_by_id[id];
  return total;
endfunction

function void stage3_e2e_checker::compare_available();
  for (int unsigned id = 0; id < M_ID_COUNT; id++) begin
    compare_aw(id);
    compare_w(id);
    compare_b(id);
    compare_ar(id);
    compare_r(id);
    compare_requests(id);
    compare_responses(id);
  end
endfunction

function void stage3_e2e_checker::compare_aw(int unsigned id);
  m_event_t upstream;
  s_event_t downstream;
  while ((upstream_aw_by_id[id].size() != 0) &&
         (downstream_aw_by_id[id].size() != 0)) begin
    upstream   = upstream_aw_by_id[id].pop_front();
    downstream = downstream_aw_by_id[id].pop_front();
    if ((downstream.id === expected_sid(upstream.id, upstream.addr)) &&
        (downstream.addr === upstream.addr) &&
        (downstream.len === upstream.len) &&
        (downstream.size === upstream.size) &&
        (downstream.burst_raw === upstream.burst_raw)) begin
      aw_event_count++;
    end
    else begin
      mismatch_count++;
      `uvm_error("STAGE3_E2E_AW", "AW forwarding or SID mismatch")
    end
  end
endfunction

function void stage3_e2e_checker::compare_w(int unsigned id);
  m_event_t upstream;
  s_event_t downstream;
  sid_t sid;
  while ((upstream_w_by_id[id].size() != 0) &&
         (downstream_w_by_id[id].size() != 0)) begin
    upstream   = upstream_w_by_id[id].pop_front();
    downstream = downstream_w_by_id[id].pop_front();
    sid = switch_model.encode_sid(
      0, switch_model.decode_w_target(upstream.id), upstream.id
    );
    if ((downstream.id === sid) &&
        (downstream.data === upstream.data) &&
        (downstream.strb === upstream.strb) &&
        (downstream.last === upstream.last)) begin
      w_event_count++;
    end
    else begin
      mismatch_count++;
      `uvm_error("STAGE3_E2E_W", "W forwarding or SID mismatch")
    end
  end
endfunction

function void stage3_e2e_checker::compare_b(int unsigned id);
  m_event_t upstream;
  s_event_t downstream;
  while ((upstream_b_by_id[id].size() != 0) &&
         (downstream_b_by_id[id].size() != 0)) begin
    upstream   = upstream_b_by_id[id].pop_front();
    downstream = downstream_b_by_id[id].pop_front();
    if ((upstream.id === switch_model.restore_id(downstream.id)) &&
        (upstream.resp_raw === downstream.resp_raw)) begin
      b_event_count++;
    end
    else begin
      mismatch_count++;
      `uvm_error("STAGE3_E2E_B", "B forwarding or restored ID mismatch")
    end
  end
endfunction

function void stage3_e2e_checker::compare_ar(int unsigned id);
  m_event_t upstream;
  s_event_t downstream;
  while ((upstream_ar_by_id[id].size() != 0) &&
         (downstream_ar_by_id[id].size() != 0)) begin
    upstream   = upstream_ar_by_id[id].pop_front();
    downstream = downstream_ar_by_id[id].pop_front();
    if ((downstream.id === expected_sid(upstream.id, upstream.addr)) &&
        (downstream.addr === upstream.addr) &&
        (downstream.len === upstream.len) &&
        (downstream.size === upstream.size) &&
        (downstream.burst_raw === upstream.burst_raw)) begin
      ar_event_count++;
    end
    else begin
      mismatch_count++;
      `uvm_error("STAGE3_E2E_AR", "AR forwarding or SID mismatch")
    end
  end
endfunction

function void stage3_e2e_checker::compare_r(int unsigned id);
  m_event_t upstream;
  s_event_t downstream;
  while ((upstream_r_by_id[id].size() != 0) &&
         (downstream_r_by_id[id].size() != 0)) begin
    upstream   = upstream_r_by_id[id].pop_front();
    downstream = downstream_r_by_id[id].pop_front();
    if ((upstream.id === switch_model.restore_id(downstream.id)) &&
        (upstream.data === downstream.data) &&
        (upstream.resp_raw === downstream.resp_raw) &&
        (upstream.last === downstream.last)) begin
      r_event_count++;
    end
    else begin
      mismatch_count++;
      `uvm_error("STAGE3_E2E_R", "R forwarding or restored ID mismatch")
    end
  end
endfunction

function bit stage3_e2e_checker::compare_write_request(
  m_req_t upstream,
  s_req_t downstream
);
  if ((downstream.id != expected_sid(upstream.id, upstream.addr)) ||
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

function bit stage3_e2e_checker::compare_read_request(
  m_req_t upstream,
  s_req_t downstream
);
  return (downstream.id == expected_sid(upstream.id, upstream.addr)) &&
         (downstream.addr == upstream.addr) &&
         (downstream.len == upstream.len) &&
         (downstream.size == upstream.size) &&
         (downstream.burst == upstream.burst);
endfunction

function void stage3_e2e_checker::compare_requests(int unsigned id);
  m_req_t upstream;
  s_req_t downstream;
  while ((upstream_write_req_by_id[id].size() != 0) &&
         (downstream_write_req_by_id[id].size() != 0)) begin
    upstream   = upstream_write_req_by_id[id].pop_front();
    downstream = downstream_write_req_by_id[id].pop_front();
    if (compare_write_request(upstream, downstream))
      begin
        write_req_match_count++;
        write_req_count_by_id[id]++;
        expected_w_beat_count += int'(upstream.len) + 1;
      end
    else begin
      mismatch_count++;
      `uvm_error("STAGE3_E2E_WRITE_REQ", "Write request mismatch")
    end
  end

  while ((upstream_read_req_by_id[id].size() != 0) &&
         (downstream_read_req_by_id[id].size() != 0)) begin
    upstream   = upstream_read_req_by_id[id].pop_front();
    downstream = downstream_read_req_by_id[id].pop_front();
    if (compare_read_request(upstream, downstream))
      begin
        read_req_match_count++;
        read_req_count_by_id[id]++;
        expected_r_beat_count += int'(upstream.len) + 1;
      end
    else begin
      mismatch_count++;
      `uvm_error("STAGE3_E2E_READ_REQ", "Read request mismatch")
    end
  end
endfunction

function bit stage3_e2e_checker::compare_write_response(
  s_rsp_t downstream,
  m_rsp_t upstream
);
  return (upstream.id == switch_model.restore_id(downstream.id)) &&
         (upstream.bresp == downstream.bresp);
endfunction

function bit stage3_e2e_checker::compare_read_response(
  s_rsp_t downstream,
  m_rsp_t upstream
);
  if ((upstream.id != switch_model.restore_id(downstream.id)) ||
      (upstream.len != downstream.len) ||
      (upstream.rdata.size() != downstream.rdata.size()) ||
      (upstream.rresp.size() != downstream.rresp.size()))
    return 1'b0;
  foreach (downstream.rdata[index]) begin
    if ((upstream.rdata[index] != downstream.rdata[index]) ||
        (upstream.rresp[index] != downstream.rresp[index]))
      return 1'b0;
  end
  return 1'b1;
endfunction

function void stage3_e2e_checker::compare_responses(int unsigned id);
  m_rsp_t upstream;
  s_rsp_t downstream;
  while ((upstream_write_rsp_by_id[id].size() != 0) &&
         (downstream_write_rsp_by_id[id].size() != 0)) begin
    upstream   = upstream_write_rsp_by_id[id].pop_front();
    downstream = downstream_write_rsp_by_id[id].pop_front();
    if (compare_write_response(downstream, upstream))
      begin
        write_rsp_match_count++;
        write_rsp_count_by_id[id]++;
      end
    else begin
      mismatch_count++;
      `uvm_error("STAGE3_E2E_WRITE_RSP", "Write response mismatch")
    end
  end

  while ((upstream_read_rsp_by_id[id].size() != 0) &&
         (downstream_read_rsp_by_id[id].size() != 0)) begin
    upstream   = upstream_read_rsp_by_id[id].pop_front();
    downstream = downstream_read_rsp_by_id[id].pop_front();
    if (compare_read_response(downstream, upstream))
      begin
        read_rsp_match_count++;
        read_rsp_count_by_id[id]++;
      end
    else begin
      mismatch_count++;
      `uvm_error("STAGE3_E2E_READ_RSP", "Read response mismatch")
    end
  end
endfunction

function void stage3_e2e_checker::record_write_completion(int unsigned id);
  int signed found;
  `uvm_info("AXI_STAGE3_B_ACTUAL", $sformatf(
    "id=0x%0h pending_before=%0d", id, write_accept_order.size()), UVM_HIGH)
  found = -1;
  foreach (write_accept_order[index]) begin
    if ((found < 0) && (write_accept_order[index] == id))
      found = index;
  end
  if (found < 0) begin
    mismatch_count++;
    `uvm_error("STAGE3_E2E_B_ORDER", "B completed without an accepted AW")
  end
  else begin
    if ((found > 0) && (write_accept_order[0] != id))
      different_id_reorder_count++;
    write_accept_order.delete(found);
  end
endfunction

function void stage3_e2e_checker::record_read_completion(int unsigned id);
  int signed found;
  `uvm_info("AXI_STAGE3_R_ACTUAL", $sformatf(
    "id=0x%0h pending_before=%0d", id, read_accept_order.size()), UVM_HIGH)
  found = -1;
  foreach (read_accept_order[index]) begin
    if ((found < 0) && (read_accept_order[index] == id))
      found = index;
  end
  if (found < 0) begin
    mismatch_count++;
    `uvm_error("STAGE3_E2E_R_ORDER", "R completed without an accepted AR")
  end
  else begin
    if ((found > 0) && (read_accept_order[0] != id))
      different_id_reorder_count++;
    read_accept_order.delete(found);
  end
endfunction

function int unsigned stage3_e2e_checker::pending_count();
  int unsigned total;
  total = write_accept_order.size() + read_accept_order.size();
  foreach (upstream_aw_by_id[id]) begin
    total += upstream_aw_by_id[id].size();
    total += upstream_w_by_id[id].size();
    total += upstream_b_by_id[id].size();
    total += upstream_ar_by_id[id].size();
    total += upstream_r_by_id[id].size();
    total += downstream_aw_by_id[id].size();
    total += downstream_w_by_id[id].size();
    total += downstream_b_by_id[id].size();
    total += downstream_ar_by_id[id].size();
    total += downstream_r_by_id[id].size();
    total += upstream_write_req_by_id[id].size();
    total += upstream_read_req_by_id[id].size();
    total += downstream_write_req_by_id[id].size();
    total += downstream_read_req_by_id[id].size();
    total += pending_write_response_by_id[id].size();
    total += pending_read_response_by_id[id].size();
    total += upstream_write_rsp_by_id[id].size();
    total += upstream_read_rsp_by_id[id].size();
    total += downstream_write_rsp_by_id[id].size();
    total += downstream_read_rsp_by_id[id].size();
    total += write_depth_by_id[id];
    total += read_depth_by_id[id];
  end
  return total;
endfunction

function void stage3_e2e_checker::clear();
  write_accept_order.delete();
  read_accept_order.delete();
  foreach (upstream_aw_by_id[id]) begin
    upstream_aw_by_id[id].delete();
    upstream_w_by_id[id].delete();
    upstream_b_by_id[id].delete();
    upstream_ar_by_id[id].delete();
    upstream_r_by_id[id].delete();
    downstream_aw_by_id[id].delete();
    downstream_w_by_id[id].delete();
    downstream_b_by_id[id].delete();
    downstream_ar_by_id[id].delete();
    downstream_r_by_id[id].delete();
    upstream_write_req_by_id[id].delete();
    upstream_read_req_by_id[id].delete();
    downstream_write_req_by_id[id].delete();
    downstream_read_req_by_id[id].delete();
    pending_write_response_by_id[id].delete();
    pending_read_response_by_id[id].delete();
    upstream_write_rsp_by_id[id].delete();
    upstream_read_rsp_by_id[id].delete();
    downstream_write_rsp_by_id[id].delete();
    downstream_read_rsp_by_id[id].delete();
    write_depth_by_id[id] = 0;
    read_depth_by_id[id]  = 0;
    write_req_count_by_id[id] = 0;
    read_req_count_by_id[id]  = 0;
    write_rsp_count_by_id[id] = 0;
    read_rsp_count_by_id[id]  = 0;
  end
  aw_event_count              = 0;
  w_event_count               = 0;
  b_event_count               = 0;
  ar_event_count              = 0;
  r_event_count               = 0;
  write_req_match_count       = 0;
  read_req_match_count        = 0;
  write_rsp_match_count       = 0;
  read_rsp_match_count        = 0;
  expected_w_beat_count       = 0;
  expected_r_beat_count       = 0;
  max_write_outstanding       = 0;
  max_read_outstanding        = 0;
  different_id_reorder_count = 0;
  same_id_multiple_count     = 0;
  mismatch_count              = 0;
  check_expected_counts       = 1'b0;
  expected_write_count        = 0;
  expected_read_count         = 0;
endfunction

function void stage3_e2e_checker::check_phase(uvm_phase phase);
  super.check_phase(phase);
  if (!enabled)
    return;
  compare_available();
  if (pending_count() != 0)
    `uvm_error("STAGE3_E2E_PENDING", $sformatf(
      "Unmatched Stage 3 state remains: %0d", pending_count()))
  if ((aw_event_count != write_req_match_count) ||
      (w_event_count != expected_w_beat_count) ||
      (b_event_count != write_rsp_match_count) ||
      (ar_event_count != read_req_match_count) ||
      (r_event_count != expected_r_beat_count) ||
      (write_rsp_match_count != write_req_match_count) ||
      (read_rsp_match_count != read_req_match_count))
    `uvm_error("STAGE3_E2E_INTERNAL_COUNT",
               "Stage 3 channel and item counts are inconsistent")
  foreach (write_req_count_by_id[id]) begin
    if ((write_req_count_by_id[id] != write_rsp_count_by_id[id]) ||
        (read_req_count_by_id[id] != read_rsp_count_by_id[id]))
      `uvm_error("STAGE3_E2E_ID_COUNT", $sformatf(
        "Request/response count mismatch for ID 0x%0h", id))
  end
  if (check_expected_counts &&
      ((write_req_match_count != expected_write_count) ||
       (write_rsp_match_count != expected_write_count) ||
       (read_req_match_count != expected_read_count) ||
       (read_rsp_match_count != expected_read_count)))
    `uvm_error("STAGE3_E2E_COUNT", "Stage 3 expected counts were not met")
endfunction

`endif

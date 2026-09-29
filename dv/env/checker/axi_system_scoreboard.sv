`ifndef AXI_SYSTEM_SCOREBOARD_SV
`define AXI_SYSTEM_SCOREBOARD_SV

class axi_system_scoreboard #(
  int unsigned ADDR_WIDTH  = AXI_ADDR_WIDTH,
  int unsigned DATA_WIDTH  = AXI_DATA_WIDTH,
  int unsigned M_ID_WIDTH  = AXI_M_ID_WIDTH,
  int unsigned S_ID_WIDTH  = AXI_S_ID_WIDTH,
  int unsigned LEN_WIDTH   = AXI_LEN_WIDTH,
  int unsigned NUM_MASTERS = AXI_ENV_NUM_MASTERS,
  int unsigned NUM_SLAVES  = AXI_ENV_NUM_SLAVES
) extends uvm_component;

  localparam int unsigned M_ID_COUNT = 1 << M_ID_WIDTH;
  localparam int unsigned S_ID_COUNT = 1 << S_ID_WIDTH;

  uvm_tlm_analysis_fifo #(
    axi_req_item #(ADDR_WIDTH, DATA_WIDTH, S_ID_WIDTH, LEN_WIDTH)
  ) exp_s_req_fifo[NUM_SLAVES];
  uvm_tlm_analysis_fifo #(
    axi_req_item #(ADDR_WIDTH, DATA_WIDTH, S_ID_WIDTH, LEN_WIDTH)
  ) act_s_req_fifo[NUM_SLAVES];
  uvm_tlm_analysis_fifo #(
    axi_rsp_item #(DATA_WIDTH, M_ID_WIDTH, LEN_WIDTH)
  ) exp_m_rsp_fifo[NUM_MASTERS];
  uvm_tlm_analysis_fifo #(
    axi_rsp_item #(DATA_WIDTH, M_ID_WIDTH, LEN_WIDTH)
  ) act_m_rsp_fifo[NUM_MASTERS];

  axi_req_item #(
    ADDR_WIDTH, DATA_WIDTH, S_ID_WIDTH, LEN_WIDTH
  ) exp_s_req_by_id[NUM_SLAVES][2][S_ID_COUNT][$];
  axi_req_item #(
    ADDR_WIDTH, DATA_WIDTH, S_ID_WIDTH, LEN_WIDTH
  ) act_s_req_by_id[NUM_SLAVES][2][S_ID_COUNT][$];
  axi_rsp_item #(
    DATA_WIDTH, M_ID_WIDTH, LEN_WIDTH
  ) exp_m_rsp_by_id[NUM_MASTERS][2][M_ID_COUNT][$];
  axi_rsp_item #(
    DATA_WIDTH, M_ID_WIDTH, LEN_WIDTH
  ) act_m_rsp_by_id[NUM_MASTERS][2][M_ID_COUNT][$];

  bit enabled;
  int unsigned mismatch_count;
  int unsigned request_match_count;
  int unsigned response_match_count;

  `uvm_component_param_utils(
    axi_system_scoreboard #(
      ADDR_WIDTH, DATA_WIDTH, M_ID_WIDTH, S_ID_WIDTH,
      LEN_WIDTH, NUM_MASTERS, NUM_SLAVES
    )
  )

  extern function new(string name = "axi_system_scoreboard",
                      uvm_component parent = null);
  extern virtual function void build_phase(uvm_phase phase);
  extern virtual task run_phase(uvm_phase phase);
  extern task collect_exp_s_req(int unsigned port_index);
  extern task collect_act_s_req(int unsigned port_index);
  extern task collect_exp_m_rsp(int unsigned port_index);
  extern task collect_act_m_rsp(int unsigned port_index);
  extern function void match_s_req(int unsigned port_index,
                                   axi_dir_e dir,
                                   int unsigned id);
  extern function void match_m_rsp(int unsigned port_index,
                                   axi_dir_e dir,
                                   int unsigned id);
  extern function bit request_equal(
    axi_req_item #(ADDR_WIDTH, DATA_WIDTH, S_ID_WIDTH, LEN_WIDTH) expected,
    axi_req_item #(ADDR_WIDTH, DATA_WIDTH, S_ID_WIDTH, LEN_WIDTH) actual
  );
  extern function bit response_equal(
    axi_rsp_item #(DATA_WIDTH, M_ID_WIDTH, LEN_WIDTH) expected,
    axi_rsp_item #(DATA_WIDTH, M_ID_WIDTH, LEN_WIDTH) actual
  );
  extern function int unsigned pending_count();
  extern virtual function void check_phase(uvm_phase phase);

endclass

function axi_system_scoreboard::new(
  string name = "axi_system_scoreboard",
  uvm_component parent = null
);
  super.new(name, parent);
  enabled = 1'b0;
  mismatch_count = 0;
  request_match_count = 0;
  response_match_count = 0;
endfunction

function void axi_system_scoreboard::build_phase(uvm_phase phase);
  super.build_phase(phase);
  foreach (exp_s_req_fifo[index]) begin
    exp_s_req_fifo[index] = new($sformatf("exp_s_req_fifo_%0d", index), this);
    act_s_req_fifo[index] = new($sformatf("act_s_req_fifo_%0d", index), this);
  end
  foreach (exp_m_rsp_fifo[index]) begin
    exp_m_rsp_fifo[index] = new($sformatf("exp_m_rsp_fifo_%0d", index), this);
    act_m_rsp_fifo[index] = new($sformatf("act_m_rsp_fifo_%0d", index), this);
  end
endfunction

task axi_system_scoreboard::run_phase(uvm_phase phase);
  if (!enabled)
    return;
  for (int unsigned index = 0; index < NUM_SLAVES; index++) begin
    automatic int unsigned port_index = index;
    fork
      collect_exp_s_req(port_index);
      collect_act_s_req(port_index);
    join_none
  end
  for (int unsigned index = 0; index < NUM_MASTERS; index++) begin
    automatic int unsigned port_index = index;
    fork
      collect_exp_m_rsp(port_index);
      collect_act_m_rsp(port_index);
    join_none
  end
  wait fork;
endtask

task axi_system_scoreboard::collect_exp_s_req(int unsigned port_index);
  axi_req_item #(ADDR_WIDTH, DATA_WIDTH, S_ID_WIDTH, LEN_WIDTH) item;
  axi_req_item #(ADDR_WIDTH, DATA_WIDTH, S_ID_WIDTH, LEN_WIDTH) snapshot;
  forever begin
    exp_s_req_fifo[port_index].get(item);
    if ((item == null) || !$cast(snapshot, item.clone())) begin
      mismatch_count++;
      `uvm_error("AXI_SYS_SB_CLONE", "Failed to clone expected slave request")
      continue;
    end
    exp_s_req_by_id[port_index][int'(snapshot.dir)]
                   [int'(snapshot.id)].push_back(snapshot);
    match_s_req(port_index, snapshot.dir, int'(snapshot.id));
  end
endtask

task axi_system_scoreboard::collect_act_s_req(int unsigned port_index);
  axi_req_item #(ADDR_WIDTH, DATA_WIDTH, S_ID_WIDTH, LEN_WIDTH) item;
  axi_req_item #(ADDR_WIDTH, DATA_WIDTH, S_ID_WIDTH, LEN_WIDTH) snapshot;
  forever begin
    act_s_req_fifo[port_index].get(item);
    if ((item == null) || !$cast(snapshot, item.clone())) begin
      mismatch_count++;
      `uvm_error("AXI_SYS_SB_CLONE", "Failed to clone actual slave request")
      continue;
    end
    act_s_req_by_id[port_index][int'(snapshot.dir)]
                   [int'(snapshot.id)].push_back(snapshot);
    match_s_req(port_index, snapshot.dir, int'(snapshot.id));
  end
endtask

task axi_system_scoreboard::collect_exp_m_rsp(int unsigned port_index);
  axi_rsp_item #(DATA_WIDTH, M_ID_WIDTH, LEN_WIDTH) item;
  axi_rsp_item #(DATA_WIDTH, M_ID_WIDTH, LEN_WIDTH) snapshot;
  forever begin
    exp_m_rsp_fifo[port_index].get(item);
    if ((item == null) || !$cast(snapshot, item.clone())) begin
      mismatch_count++;
      `uvm_error("AXI_SYS_SB_CLONE", "Failed to clone expected master response")
      continue;
    end
    exp_m_rsp_by_id[port_index][int'(snapshot.dir)]
                   [int'(snapshot.id)].push_back(snapshot);
    match_m_rsp(port_index, snapshot.dir, int'(snapshot.id));
  end
endtask

task axi_system_scoreboard::collect_act_m_rsp(int unsigned port_index);
  axi_rsp_item #(DATA_WIDTH, M_ID_WIDTH, LEN_WIDTH) item;
  axi_rsp_item #(DATA_WIDTH, M_ID_WIDTH, LEN_WIDTH) snapshot;
  forever begin
    act_m_rsp_fifo[port_index].get(item);
    if ((item == null) || !$cast(snapshot, item.clone())) begin
      mismatch_count++;
      `uvm_error("AXI_SYS_SB_CLONE", "Failed to clone actual master response")
      continue;
    end
    act_m_rsp_by_id[port_index][int'(snapshot.dir)]
                   [int'(snapshot.id)].push_back(snapshot);
    match_m_rsp(port_index, snapshot.dir, int'(snapshot.id));
  end
endtask

function void axi_system_scoreboard::match_s_req(
  int unsigned port_index,
  axi_dir_e dir,
  int unsigned id
);
  axi_req_item #(ADDR_WIDTH, DATA_WIDTH, S_ID_WIDTH, LEN_WIDTH) expected;
  axi_req_item #(ADDR_WIDTH, DATA_WIDTH, S_ID_WIDTH, LEN_WIDTH) actual;
  while ((exp_s_req_by_id[port_index][int'(dir)][id].size() != 0) &&
         (act_s_req_by_id[port_index][int'(dir)][id].size() != 0)) begin
    expected = exp_s_req_by_id[port_index][int'(dir)][id].pop_front();
    actual = act_s_req_by_id[port_index][int'(dir)][id].pop_front();
    if (!request_equal(expected, actual)) begin
      mismatch_count++;
      `uvm_error("AXI_SYS_SB_REQ", $sformatf(
        "S%0d request mismatch expected={%s} actual={%s}",
        port_index, expected.convert2string(), actual.convert2string()))
    end
    else request_match_count++;
  end
endfunction

function void axi_system_scoreboard::match_m_rsp(
  int unsigned port_index,
  axi_dir_e dir,
  int unsigned id
);
  axi_rsp_item #(DATA_WIDTH, M_ID_WIDTH, LEN_WIDTH) expected;
  axi_rsp_item #(DATA_WIDTH, M_ID_WIDTH, LEN_WIDTH) actual;
  while ((exp_m_rsp_by_id[port_index][int'(dir)][id].size() != 0) &&
         (act_m_rsp_by_id[port_index][int'(dir)][id].size() != 0)) begin
    expected = exp_m_rsp_by_id[port_index][int'(dir)][id].pop_front();
    actual = act_m_rsp_by_id[port_index][int'(dir)][id].pop_front();
    if (!response_equal(expected, actual)) begin
      mismatch_count++;
      `uvm_error("AXI_SYS_SB_RSP", $sformatf(
        "M%0d response mismatch expected={%s} actual={%s}",
        port_index, expected.convert2string(), actual.convert2string()))
    end
    else response_match_count++;
  end
endfunction

function bit axi_system_scoreboard::request_equal(
  axi_req_item #(ADDR_WIDTH, DATA_WIDTH, S_ID_WIDTH, LEN_WIDTH) expected,
  axi_req_item #(ADDR_WIDTH, DATA_WIDTH, S_ID_WIDTH, LEN_WIDTH) actual
);
  if ((expected.dir != actual.dir) || (expected.id !== actual.id) ||
      (expected.addr !== actual.addr) || (expected.len !== actual.len) ||
      (expected.size !== actual.size) || (expected.burst != actual.burst) ||
      (expected.wdata.size() != actual.wdata.size()) ||
      (expected.wstrb.size() != actual.wstrb.size()))
    return 1'b0;
  foreach (expected.wdata[index])
    if (expected.wdata[index] !== actual.wdata[index]) return 1'b0;
  foreach (expected.wstrb[index])
    if (expected.wstrb[index] !== actual.wstrb[index]) return 1'b0;
  return 1'b1;
endfunction

function bit axi_system_scoreboard::response_equal(
  axi_rsp_item #(DATA_WIDTH, M_ID_WIDTH, LEN_WIDTH) expected,
  axi_rsp_item #(DATA_WIDTH, M_ID_WIDTH, LEN_WIDTH) actual
);
  if ((expected.dir != actual.dir) || (expected.id !== actual.id) ||
      (expected.len !== actual.len) ||
      (expected.rdata.size() != actual.rdata.size()) ||
      (expected.rresp.size() != actual.rresp.size()))
    return 1'b0;
  if ((expected.dir == AXI_WRITE) && (expected.bresp != actual.bresp))
    return 1'b0;
  foreach (expected.rdata[index])
    if (expected.rdata[index] !== actual.rdata[index]) return 1'b0;
  foreach (expected.rresp[index])
    if (expected.rresp[index] != actual.rresp[index]) return 1'b0;
  return 1'b1;
endfunction

function int unsigned axi_system_scoreboard::pending_count();
  int unsigned total;
  total = 0;
  foreach (exp_s_req_fifo[index]) begin
    total += exp_s_req_fifo[index].used();
    total += act_s_req_fifo[index].used();
  end
  foreach (exp_m_rsp_fifo[index]) begin
    total += exp_m_rsp_fifo[index].used();
    total += act_m_rsp_fifo[index].used();
  end
  foreach (exp_s_req_by_id[port, dir, id]) begin
    total += exp_s_req_by_id[port][dir][id].size();
    total += act_s_req_by_id[port][dir][id].size();
  end
  foreach (exp_m_rsp_by_id[port, dir, id]) begin
    total += exp_m_rsp_by_id[port][dir][id].size();
    total += act_m_rsp_by_id[port][dir][id].size();
  end
  return total;
endfunction

function void axi_system_scoreboard::check_phase(uvm_phase phase);
  super.check_phase(phase);
  if (enabled && (pending_count() != 0))
    `uvm_error("AXI_SYS_SB_PENDING", $sformatf(
      "System scoreboard has %0d unmatched items", pending_count()))
endfunction

`endif

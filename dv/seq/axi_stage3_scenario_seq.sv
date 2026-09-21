`ifndef AXI_STAGE3_SCENARIO_SEQ_SV
`define AXI_STAGE3_SCENARIO_SEQ_SV

class axi_stage3_scenario_sequence extends uvm_sequence;

  localparam int unsigned DATA_BYTES = AXI_DATA_WIDTH / 8;

  typedef axi_req_item #(
    AXI_ADDR_WIDTH, AXI_DATA_WIDTH, AXI_M_ID_WIDTH, AXI_LEN_WIDTH
  ) m_req_t;
  typedef axi_m_sequencer #(
    AXI_ADDR_WIDTH, AXI_DATA_WIDTH, AXI_M_ID_WIDTH, AXI_LEN_WIDTH
  ) m_sequencer_t;
  typedef axi_s_sequencer #(
    AXI_ADDR_WIDTH, AXI_DATA_WIDTH, AXI_S_ID_WIDTH, AXI_LEN_WIDTH
  ) s_sequencer_t;
  typedef axi_s_stage3_reactive_seq #(
    AXI_ADDR_WIDTH, AXI_DATA_WIDTH, AXI_S_ID_WIDTH, AXI_LEN_WIDTH
  ) reactive_t;
  typedef axi_switch_ref_model #(
    AXI_ADDR_WIDTH, AXI_M_ID_WIDTH, AXI_S_ID_WIDTH
  ) model_t;
  typedef bit [AXI_M_ID_WIDTH-1:0] mid_t;
  typedef bit [AXI_S_ID_WIDTH-1:0] sid_t;

  m_sequencer_t m_sequencer;
  s_sequencer_t s_sequencer;
  model_t switch_model;
  sid_t b_return_order[$];
  sid_t r_return_order[$];
  int unsigned b_rsp_delay;
  int unsigned r_rsp_delay;
  int unsigned r_beat_gap;
  int unsigned issue_order;
  bit [AXI_DATA_WIDTH-1:0] read_data_base;

  `uvm_object_utils(axi_stage3_scenario_sequence)

  extern function new(string name = "axi_stage3_scenario_sequence");
  extern function mid_t master_id(bit [AXI_ADDR_WIDTH-1:0] addr,
                                  bit [1:0] tag);
  extern function sid_t slave_id(bit [AXI_ADDR_WIDTH-1:0] addr,
                                 bit [1:0] tag);
  extern task send_write(bit [1:0] tag,
                         bit [AXI_ADDR_WIDTH-1:0] addr,
                         int unsigned beat_count,
                         bit [AXI_DATA_WIDTH-1:0] data_base,
                         int unsigned addr_delay = 0,
                         int unsigned w_start_delay = 0,
                         int unsigned beat_gap = 0);
  extern task send_read(bit [1:0] tag,
                        bit [AXI_ADDR_WIDTH-1:0] addr,
                        int unsigned beat_count,
                        int unsigned addr_delay = 0);
  extern task run_reactive();

endclass

function axi_stage3_scenario_sequence::new(
  string name = "axi_stage3_scenario_sequence"
);
  super.new(name);
  switch_model   = model_t::type_id::create("switch_model");
  b_rsp_delay    = 0;
  r_rsp_delay    = 0;
  r_beat_gap     = 0;
  issue_order    = 0;
  read_data_base = 32'h8000_0000;
endfunction

function axi_stage3_scenario_sequence::mid_t
axi_stage3_scenario_sequence::master_id(
  bit [AXI_ADDR_WIDTH-1:0] addr,
  bit [1:0] tag
);
  return switch_model.build_master_id(
    switch_model.decode_address(addr), tag
  );
endfunction

function axi_stage3_scenario_sequence::sid_t
axi_stage3_scenario_sequence::slave_id(
  bit [AXI_ADDR_WIDTH-1:0] addr,
  bit [1:0] tag
);
  mid_t id;
  id = master_id(addr, tag);
  return switch_model.encode_sid(
    0, switch_model.decode_address(addr), id
  );
endfunction

task axi_stage3_scenario_sequence::send_write(
  bit [1:0] tag,
  bit [AXI_ADDR_WIDTH-1:0] addr,
  int unsigned beat_count,
  bit [AXI_DATA_WIDTH-1:0] data_base,
  int unsigned addr_delay = 0,
  int unsigned w_start_delay = 0,
  int unsigned beat_gap = 0
);
  m_req_t req;

  if (!(beat_count inside {[1:16]}))
    `uvm_fatal("AXI_STAGE3_WRITE", "beat_count must be in the range 1 to 16")
  req = m_req_t::type_id::create("stage3_write_req");
  start_item(req, -1, m_sequencer);
  req.dir           = AXI_WRITE;
  req.id            = master_id(addr, tag);
  req.addr          = addr;
  req.len           = beat_count - 1;
  req.size          = $clog2(DATA_BYTES);
  req.burst         = AXI_BURST_INCR;
  req.addr_delay    = addr_delay;
  req.w_start_delay = w_start_delay;
  req.wdata         = new[beat_count];
  req.wstrb         = new[beat_count];
  req.wbeat_gap     = new[beat_count];
  foreach (req.wdata[index]) begin
    req.wdata[index]     = data_base + index;
    req.wstrb[index]     = '1;
    req.wbeat_gap[index] = beat_gap;
  end
  `uvm_info("AXI_STAGE3_ISSUE", $sformatf(
    "order=%0d write id=0x%0h addr=0x%0h beats=%0d",
    issue_order, req.id, req.addr, beat_count),
    UVM_HIGH)
  issue_order++;
  finish_item(req);
endtask

task axi_stage3_scenario_sequence::send_read(
  bit [1:0] tag,
  bit [AXI_ADDR_WIDTH-1:0] addr,
  int unsigned beat_count,
  int unsigned addr_delay = 0
);
  m_req_t req;

  if (!(beat_count inside {[1:16]}))
    `uvm_fatal("AXI_STAGE3_READ", "beat_count must be in the range 1 to 16")
  req = m_req_t::type_id::create("stage3_read_req");
  start_item(req, -1, m_sequencer);
  req.dir           = AXI_READ;
  req.id            = master_id(addr, tag);
  req.addr          = addr;
  req.len           = beat_count - 1;
  req.size          = $clog2(DATA_BYTES);
  req.burst         = AXI_BURST_INCR;
  req.addr_delay    = addr_delay;
  req.w_start_delay = 0;
  req.wdata         = new[0];
  req.wstrb         = new[0];
  req.wbeat_gap     = new[0];
  `uvm_info("AXI_STAGE3_ISSUE", $sformatf(
    "order=%0d read id=0x%0h addr=0x%0h beats=%0d",
    issue_order, req.id, req.addr, beat_count),
    UVM_HIGH)
  issue_order++;
  finish_item(req);
endtask

task axi_stage3_scenario_sequence::run_reactive();
  reactive_t reactive;
  reactive = reactive_t::type_id::create("stage3_reactive");
  reactive.b_return_order = b_return_order;
  reactive.r_return_order = r_return_order;
  reactive.b_rsp_delay    = b_rsp_delay;
  reactive.r_rsp_delay    = r_rsp_delay;
  reactive.r_beat_gap     = r_beat_gap;
  reactive.read_data_base = read_data_base;
  reactive.start(s_sequencer);
endtask

`endif

`ifndef AXI_STAGE2_SCENARIO_SEQ_SV
`define AXI_STAGE2_SCENARIO_SEQ_SV

class axi_stage2_scenario_sequence extends uvm_sequence;

  localparam int unsigned DATA_BYTES = AXI_DATA_WIDTH / 8;

  typedef axi_req_item #(
    AXI_ADDR_WIDTH, AXI_DATA_WIDTH, AXI_M_ID_WIDTH, AXI_LEN_WIDTH
  ) m_req_t;
  typedef axi_req_item #(
    AXI_ADDR_WIDTH, AXI_DATA_WIDTH, AXI_S_ID_WIDTH, AXI_LEN_WIDTH
  ) s_req_t;
  typedef axi_rsp_item #(
    AXI_DATA_WIDTH, AXI_S_ID_WIDTH, AXI_LEN_WIDTH
  ) s_rsp_t;
  typedef axi_m_sequencer #(
    AXI_ADDR_WIDTH, AXI_DATA_WIDTH, AXI_M_ID_WIDTH, AXI_LEN_WIDTH
  ) m_sequencer_t;
  typedef axi_s_sequencer #(
    AXI_ADDR_WIDTH, AXI_DATA_WIDTH, AXI_S_ID_WIDTH, AXI_LEN_WIDTH
  ) s_sequencer_t;

  m_sequencer_t m_sequencer;
  s_sequencer_t s_sequencer;

  latency_gen aw_latency;
  latency_gen w_start_latency;
  latency_gen w_gap_latency;
  latency_gen ar_latency;
  latency_gen b_latency;
  latency_gen r_latency;
  latency_gen r_gap_latency;

  int unsigned next_w_gaps[$];
  int unsigned next_r_gaps[$];

  `uvm_object_utils(axi_stage2_scenario_sequence)

  extern function new(string name = "axi_stage2_scenario_sequence");
  extern task send_write(
    bit [AXI_M_ID_WIDTH-1:0] id,
    bit [AXI_ADDR_WIDTH-1:0] addr,
    int unsigned beat_count,
    axi_burst_e burst,
    bit [AXI_DATA_WIDTH-1:0] data_base
  );
  extern task send_read(
    bit [AXI_M_ID_WIDTH-1:0] id,
    bit [AXI_ADDR_WIDTH-1:0] addr,
    int unsigned beat_count,
    axi_burst_e burst
  );
  extern task get_slave_request(output s_req_t req);
  extern task send_slave_response(
    s_req_t req,
    bit [AXI_DATA_WIDTH-1:0] data_base
  );
  extern task serve_responses(
    int unsigned response_count,
    bit [AXI_DATA_WIDTH-1:0] data_base
  );

endclass

function axi_stage2_scenario_sequence::new(
  string name = "axi_stage2_scenario_sequence"
);
  super.new(name);
  aw_latency      = latency_gen::type_id::create("aw_latency");
  w_start_latency = latency_gen::type_id::create("w_start_latency");
  w_gap_latency   = latency_gen::type_id::create("w_gap_latency");
  ar_latency      = latency_gen::type_id::create("ar_latency");
  b_latency       = latency_gen::type_id::create("b_latency");
  r_latency       = latency_gen::type_id::create("r_latency");
  r_gap_latency   = latency_gen::type_id::create("r_gap_latency");
endfunction

task axi_stage2_scenario_sequence::send_write(
  bit [AXI_M_ID_WIDTH-1:0] id,
  bit [AXI_ADDR_WIDTH-1:0] addr,
  int unsigned beat_count,
  axi_burst_e burst,
  bit [AXI_DATA_WIDTH-1:0] data_base
);
  m_req_t req;

  if (!(beat_count inside {[1:16]}))
    `uvm_fatal("AXI_STAGE2_WRITE", "beat_count must be in the range 1 to 16")

  req = m_req_t::type_id::create("write_req");
  start_item(req, -1, m_sequencer);
  if (!req.randomize() with {
    dir          == AXI_WRITE;
    id           == local::id;
    addr         == local::addr;
    len          == local::beat_count - 1;
    size         == $clog2(DATA_BYTES);
    burst        == local::burst;
  })
    `uvm_fatal("AXI_STAGE2_WRITE", "Failed to randomize write request")

  foreach (req.wdata[index]) begin
    req.wdata[index] = data_base + index;
    req.wstrb[index] = '1;
  end

  if (!aw_latency.randomize())
    `uvm_fatal("AXI_STAGE2_AW_LATENCY", "Failed to randomize AW latency")
  if (!w_start_latency.randomize())
    `uvm_fatal("AXI_STAGE2_W_START", "Failed to randomize W start latency")
  req.addr_delay    = aw_latency.get_delay();
  req.w_start_delay = w_start_latency.get_delay();

  if ((next_w_gaps.size() != 0) &&
      (next_w_gaps.size() != beat_count))
    `uvm_fatal("AXI_STAGE2_W_GAP", "Explicit W gap count must equal beat_count")

  foreach (req.wbeat_gap[index]) begin
    if (next_w_gaps.size() != 0) begin
      req.wbeat_gap[index] = next_w_gaps[index];
    end
    else begin
      if (!w_gap_latency.randomize())
        `uvm_fatal("AXI_STAGE2_W_GAP", "Failed to randomize W gap")
      req.wbeat_gap[index] = w_gap_latency.get_delay();
    end
  end
  next_w_gaps.delete();
  finish_item(req);
endtask

task axi_stage2_scenario_sequence::send_read(
  bit [AXI_M_ID_WIDTH-1:0] id,
  bit [AXI_ADDR_WIDTH-1:0] addr,
  int unsigned beat_count,
  axi_burst_e burst
);
  m_req_t req;

  if (!(beat_count inside {[1:16]}))
    `uvm_fatal("AXI_STAGE2_READ", "beat_count must be in the range 1 to 16")

  req = m_req_t::type_id::create("read_req");
  start_item(req, -1, m_sequencer);
  if (!req.randomize() with {
    dir          == AXI_READ;
    id           == local::id;
    addr         == local::addr;
    len          == local::beat_count - 1;
    size         == $clog2(DATA_BYTES);
    burst        == local::burst;
  })
    `uvm_fatal("AXI_STAGE2_READ", "Failed to randomize read request")

  if (!ar_latency.randomize())
    `uvm_fatal("AXI_STAGE2_AR_LATENCY", "Failed to randomize AR latency")
  req.addr_delay = ar_latency.get_delay();
  finish_item(req);
endtask

task axi_stage2_scenario_sequence::get_slave_request(output s_req_t req);
  s_sequencer.request_fifo.get(req);
  if (req == null)
    `uvm_fatal("AXI_STAGE2_SLAVE_REQ", "Received a null reconstructed request")
endtask

task axi_stage2_scenario_sequence::send_slave_response(
  s_req_t req,
  bit [AXI_DATA_WIDTH-1:0] data_base
);
  s_rsp_t rsp;

  rsp = s_rsp_t::type_id::create("slave_rsp");
  start_item(rsp, -1, s_sequencer);
  rsp.dir = req.dir;
  rsp.id  = req.id;
  rsp.len = req.len;
  if (!rsp.randomize())
    `uvm_fatal("AXI_STAGE2_SLAVE_RSP", "Failed to randomize response")

  rsp.bresp = AXI_RESP_OKAY;
  if (req.dir == AXI_WRITE) begin
    if (!b_latency.randomize())
      `uvm_fatal("AXI_STAGE2_B_LATENCY", "Failed to randomize B latency")
    rsp.rsp_delay = b_latency.get_delay();
  end
  else begin
    if (!r_latency.randomize())
      `uvm_fatal("AXI_STAGE2_R_LATENCY", "Failed to randomize R latency")
    rsp.rsp_delay = r_latency.get_delay();

    foreach (rsp.rdata[index]) begin
      rsp.rdata[index] = data_base + index;
      rsp.rresp[index] = AXI_RESP_OKAY;
    end

    if ((next_r_gaps.size() != 0) &&
        (next_r_gaps.size() != rsp.rbeat_gap.size()))
      `uvm_fatal("AXI_STAGE2_R_GAP",
                 "Explicit R gap count must equal beat_count-1")

    foreach (rsp.rbeat_gap[index]) begin
      if (next_r_gaps.size() != 0) begin
        rsp.rbeat_gap[index] = next_r_gaps[index];
      end
      else begin
        if (!r_gap_latency.randomize())
          `uvm_fatal("AXI_STAGE2_R_GAP", "Failed to randomize R gap")
        rsp.rbeat_gap[index] = r_gap_latency.get_delay();
      end
    end
    next_r_gaps.delete();
  end
  finish_item(rsp);
endtask

task axi_stage2_scenario_sequence::serve_responses(
  int unsigned response_count,
  bit [AXI_DATA_WIDTH-1:0] data_base
);
  s_req_t req;

  for (int unsigned index = 0; index < response_count; index++) begin
    get_slave_request(req);
    send_slave_response(req, data_base + (index * 32));
  end
endtask

`endif

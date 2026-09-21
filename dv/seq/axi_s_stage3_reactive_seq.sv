`ifndef AXI_S_STAGE3_REACTIVE_SEQ_SV
`define AXI_S_STAGE3_REACTIVE_SEQ_SV

class axi_s_stage3_reactive_seq #(
  int unsigned ADDR_WIDTH = AXI_ADDR_WIDTH,
  int unsigned DATA_WIDTH = AXI_DATA_WIDTH,
  int unsigned ID_WIDTH   = AXI_S_ID_WIDTH,
  int unsigned LEN_WIDTH  = AXI_LEN_WIDTH
) extends uvm_sequence #(
  axi_rsp_item #(DATA_WIDTH, ID_WIDTH, LEN_WIDTH)
);

  localparam int unsigned ID_COUNT = 1 << ID_WIDTH;

  typedef axi_req_item #(
    ADDR_WIDTH, DATA_WIDTH, ID_WIDTH, LEN_WIDTH
  ) req_t;
  typedef axi_rsp_item #(DATA_WIDTH, ID_WIDTH, LEN_WIDTH) rsp_t;
  typedef axi_s_sequencer #(
    ADDR_WIDTH, DATA_WIDTH, ID_WIDTH, LEN_WIDTH
  ) sequencer_t;
  typedef bit [ID_WIDTH-1:0] id_t;

  req_t pending_b_by_id[ID_COUNT][$];
  req_t pending_r_by_id[ID_COUNT][$];
  id_t b_return_order[$];
  id_t r_return_order[$];

  semaphore send_lock;
  axi_resp_e response_code;
  bit [DATA_WIDTH-1:0] read_data_base;
  int unsigned b_rsp_delay;
  int unsigned r_rsp_delay;
  int unsigned r_beat_gap;
  time response_timeout;
  int unsigned collected_count;
  int unsigned sent_b_count;
  int unsigned sent_r_count;

  `uvm_object_param_utils(
    axi_s_stage3_reactive_seq #(ADDR_WIDTH, DATA_WIDTH, ID_WIDTH, LEN_WIDTH)
  )
  `uvm_declare_p_sequencer(sequencer_t)

  extern function new(string name = "axi_s_stage3_reactive_seq");
  extern virtual task body();
  extern task collect_requests(int unsigned request_count);
  extern task schedule_b(int unsigned response_count);
  extern task schedule_r(int unsigned response_count);
  extern task wait_for_b(id_t id);
  extern task wait_for_r(id_t id);
  extern task send_response(rsp_t rsp);
  extern function int unsigned pending_count();

endclass

function axi_s_stage3_reactive_seq::new(
  string name = "axi_s_stage3_reactive_seq"
);
  super.new(name);
  send_lock       = new(1);
  response_code   = AXI_RESP_OKAY;
  read_data_base  = '0;
  b_rsp_delay     = 0;
  r_rsp_delay     = 0;
  r_beat_gap      = 0;
  response_timeout = 20us;
  collected_count = 0;
  sent_b_count    = 0;
  sent_r_count    = 0;
endfunction

task axi_s_stage3_reactive_seq::body();
  int unsigned b_count;
  int unsigned r_count;

  b_count = b_return_order.size();
  r_count = r_return_order.size();
  if ((b_count + r_count) == 0)
    `uvm_fatal("AXI_STAGE3_SCRIPT", "Response return script is empty")

  fork
    collect_requests(b_count + r_count);
    schedule_b(b_count);
    schedule_r(r_count);
  join

  if (pending_count() != 0)
    `uvm_error("AXI_STAGE3_PENDING", $sformatf(
      "Reactive response plan still has %0d pending requests",
      pending_count()))
endtask

task axi_s_stage3_reactive_seq::collect_requests(
  int unsigned request_count
);
  req_t req;
  req_t snapshot;
  int unsigned id;
  time deadline;

  repeat (request_count) begin
    deadline = $time + response_timeout;
    while (!p_sequencer.request_fifo.try_get(req)) begin
      #1ns;
      if ($time >= deadline)
        `uvm_fatal("AXI_STAGE3_REQUEST_TIMEOUT", $sformatf(
          "Collected %0d of %0d planned requests",
          collected_count, request_count))
    end
    if ((req == null) || !$cast(snapshot, req.clone()))
      `uvm_fatal("AXI_STAGE3_COLLECT", "Failed to clone slave request")

    id = int'(snapshot.id);
    if (snapshot.dir == AXI_WRITE)
      pending_b_by_id[id].push_back(snapshot);
    else
      pending_r_by_id[id].push_back(snapshot);
    collected_count++;
    `uvm_info("AXI_STAGE3_COLLECT", $sformatf(
      "accepted request=%0d dir=%s id=0x%0h",
      collected_count, snapshot.dir.name(), snapshot.id), UVM_HIGH)
  end
endtask

task axi_s_stage3_reactive_seq::wait_for_b(id_t id);
  time deadline;
  deadline = $time + response_timeout;
  while (pending_b_by_id[int'(id)].size() == 0) begin
    #1ns;
    if ($time >= deadline)
      `uvm_fatal("AXI_STAGE3_B_SCRIPT", $sformatf(
        "Timed out waiting for B response plan ID 0x%0h", id))
  end
endtask

task axi_s_stage3_reactive_seq::wait_for_r(id_t id);
  time deadline;
  deadline = $time + response_timeout;
  while (pending_r_by_id[int'(id)].size() == 0) begin
    #1ns;
    if ($time >= deadline)
      `uvm_fatal("AXI_STAGE3_R_SCRIPT", $sformatf(
        "Timed out waiting for R response plan ID 0x%0h", id))
  end
endtask

task axi_s_stage3_reactive_seq::schedule_b(int unsigned response_count);
  id_t id;
  req_t req;
  rsp_t rsp;

  repeat (response_count) begin
    id = b_return_order.pop_front();
    wait_for_b(id);
    req = pending_b_by_id[int'(id)].pop_front();
    `uvm_info("AXI_STAGE3_B_PLAN", $sformatf(
      "response=%0d id=0x%0h", sent_b_count, id), UVM_HIGH)

    rsp = rsp_t::type_id::create("stage3_b_rsp");
    rsp.dir        = AXI_WRITE;
    rsp.id         = req.id;
    rsp.len        = '0;
    rsp.bresp      = response_code;
    rsp.rdata      = new[0];
    rsp.rresp      = new[0];
    rsp.rsp_delay  = b_rsp_delay;
    rsp.rbeat_gap  = new[0];
    send_response(rsp);
    sent_b_count++;
  end
endtask

task axi_s_stage3_reactive_seq::schedule_r(int unsigned response_count);
  id_t id;
  req_t req;
  rsp_t rsp;
  bit [DATA_WIDTH-1:0] transaction_base;

  repeat (response_count) begin
    id = r_return_order.pop_front();
    wait_for_r(id);
    req = pending_r_by_id[int'(id)].pop_front();
    `uvm_info("AXI_STAGE3_R_PLAN", $sformatf(
      "response=%0d id=0x%0h", sent_r_count, id), UVM_HIGH)
    transaction_base = read_data_base + (sent_r_count << 8);

    rsp = rsp_t::type_id::create("stage3_r_rsp");
    rsp.dir        = AXI_READ;
    rsp.id         = req.id;
    rsp.len        = req.len;
    rsp.bresp      = AXI_RESP_OKAY;
    rsp.rdata      = new[int'(req.len) + 1];
    rsp.rresp      = new[int'(req.len) + 1];
    rsp.rsp_delay  = r_rsp_delay;
    rsp.rbeat_gap  = new[int'(req.len)];
    foreach (rsp.rdata[index]) begin
      rsp.rdata[index] = transaction_base + index;
      rsp.rresp[index] = response_code;
    end
    foreach (rsp.rbeat_gap[index])
      rsp.rbeat_gap[index] = r_beat_gap;
    send_response(rsp);
    sent_r_count++;
  end
endtask

task axi_s_stage3_reactive_seq::send_response(rsp_t rsp);
  send_lock.get();
  start_item(rsp);
  finish_item(rsp);
  send_lock.put();
endtask

function int unsigned axi_s_stage3_reactive_seq::pending_count();
  int unsigned total;
  total = b_return_order.size() + r_return_order.size();
  foreach (pending_b_by_id[id]) begin
    total += pending_b_by_id[id].size();
    total += pending_r_by_id[id].size();
  end
  return total;
endfunction

`endif

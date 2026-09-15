`ifndef AXI_S_REACTIVE_SEQ_SV
`define AXI_S_REACTIVE_SEQ_SV

class axi_s_reactive_seq #(
  int unsigned ADDR_WIDTH = AXI_ADDR_WIDTH,
  int unsigned DATA_WIDTH = AXI_DATA_WIDTH,
  int unsigned ID_WIDTH   = AXI_S_ID_WIDTH,
  int unsigned LEN_WIDTH  = AXI_LEN_WIDTH
) extends uvm_sequence #(
  axi_rsp_item #(DATA_WIDTH, ID_WIDTH, LEN_WIDTH)
);

  typedef axi_req_item #(
    ADDR_WIDTH, DATA_WIDTH, ID_WIDTH, LEN_WIDTH
  ) req_t;
  typedef axi_rsp_item #(DATA_WIDTH, ID_WIDTH, LEN_WIDTH) rsp_t;
  typedef axi_s_sequencer #(
    ADDR_WIDTH, DATA_WIDTH, ID_WIDTH, LEN_WIDTH
  ) sequencer_t;

  int unsigned response_count;
  bit [DATA_WIDTH-1:0] read_data_base;
  axi_resp_e response_code;
  latency_gen rsp_latency;
  latency_gen r_gap_latency;

  `uvm_object_param_utils(
    axi_s_reactive_seq #(ADDR_WIDTH, DATA_WIDTH, ID_WIDTH, LEN_WIDTH)
  )
  `uvm_declare_p_sequencer(sequencer_t)

  extern function new(string name = "axi_s_reactive_seq");
  extern virtual task body();

endclass

function axi_s_reactive_seq::new(string name = "axi_s_reactive_seq");
  super.new(name);
  response_count = 1;
  read_data_base = '0;
  response_code  = AXI_RESP_OKAY;
  rsp_latency    = latency_gen::type_id::create("rsp_latency");
  r_gap_latency  = latency_gen::type_id::create("r_gap_latency");
endfunction

task axi_s_reactive_seq::body();
  req_t req;
  rsp_t rsp;

  for (int unsigned response_index = 0;
       response_index < response_count;
       response_index++) begin
    p_sequencer.request_fifo.get(req);
    if (req == null) begin
      `uvm_error("AXI_S_REACTIVE", "Received null reconstructed request")
      continue;
    end

    rsp = rsp_t::type_id::create($sformatf("rsp_%0d", response_index));
    start_item(rsp);
    rsp.dir = req.dir;
    rsp.id  = req.id;
    rsp.len = req.len;

    if (!rsp.randomize())
      `uvm_fatal("AXI_S_REACTIVE", "Failed to randomize response payload")

    if (req.dir == AXI_WRITE) begin
      rsp.bresp = response_code;
    end
    else begin
      foreach (rsp.rdata[beat_index]) begin
        rsp.rdata[beat_index] = read_data_base + beat_index;
        rsp.rresp[beat_index] = response_code;
      end
    end

    if (!rsp_latency.randomize())
      `uvm_fatal("AXI_S_RSP_LATENCY",
                 "Failed to randomize response latency")
    rsp.rsp_delay = rsp_latency.get_delay();

    foreach (rsp.rbeat_gap[gap_index]) begin
      if (!r_gap_latency.randomize())
        `uvm_fatal("AXI_S_R_GAP_LATENCY", $sformatf(
          "Failed to randomize R gap %0d", gap_index))
      rsp.rbeat_gap[gap_index] = r_gap_latency.get_delay();
    end

    finish_item(rsp);
  end
endtask

`endif

`ifndef AXI_S_SINGLE_REACTIVE_SEQ_SV
`define AXI_S_SINGLE_REACTIVE_SEQ_SV

class axi_s_single_reactive_seq #(
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
  bit [DATA_WIDTH-1:0] read_data;
  axi_resp_e response_code;

  `uvm_object_param_utils(
    axi_s_single_reactive_seq #(ADDR_WIDTH, DATA_WIDTH, ID_WIDTH, LEN_WIDTH)
  )
  `uvm_declare_p_sequencer(sequencer_t)

  function new(string name = "axi_s_single_reactive_seq");
    super.new(name);
    response_count = 1;
    read_data      = '0;
    response_code  = AXI_RESP_OKAY;
  endfunction

  virtual task body();
    req_t req;
    rsp_t rsp;

    for (int unsigned index = 0; index < response_count; index++) begin
      p_sequencer.request_fifo.get(req);
      if (req == null) begin
        `uvm_error("AXI_S_REACTIVE", "Received null reconstructed request")
        continue;
      end

      rsp = rsp_t::type_id::create($sformatf("rsp_%0d", index));
      start_item(rsp);
      rsp.dir        = req.dir;
      rsp.id         = req.id;
      rsp.len        = '0;
      rsp.rsp_delay  = 0;
      if (req.dir == AXI_WRITE) begin
        rsp.bresp     = response_code;
        rsp.rdata     = new[0];
        rsp.rresp     = new[0];
        rsp.rbeat_gap = new[0];
      end
      else begin
        rsp.bresp      = AXI_RESP_OKAY;
        rsp.rdata      = new[1];
        rsp.rresp      = new[1];
        rsp.rbeat_gap  = new[0];
        rsp.rdata[0]   = read_data;
        rsp.rresp[0]   = response_code;
      end
      finish_item(rsp);
    end
  endtask

endclass

`endif

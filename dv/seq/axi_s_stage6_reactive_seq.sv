`ifndef AXI_S_STAGE6_REACTIVE_SEQ_SV
`define AXI_S_STAGE6_REACTIVE_SEQ_SV

class axi_s_stage6_reactive_seq #(
  int unsigned ADDR_WIDTH = AXI_ADDR_WIDTH,
  int unsigned DATA_WIDTH = AXI_DATA_WIDTH,
  int unsigned ID_WIDTH   = AXI_S_ID_WIDTH,
  int unsigned LEN_WIDTH  = AXI_LEN_WIDTH
) extends uvm_sequence #(axi_rsp_item #(DATA_WIDTH, ID_WIDTH, LEN_WIDTH));

  rand int unsigned request_count;
  rand bit [DATA_WIDTH-1:0] read_data_base;
  rand axi_resp_e response_code;
  rand int unsigned response_delay;

  `uvm_object_param_utils(
    axi_s_stage6_reactive_seq #(ADDR_WIDTH, DATA_WIDTH, ID_WIDTH, LEN_WIDTH)
  )
  `uvm_declare_p_sequencer(
    axi_s_sequencer #(ADDR_WIDTH, DATA_WIDTH, ID_WIDTH, LEN_WIDTH)
  )

  function new(string name = "axi_s_stage6_reactive_seq");
    super.new(name);
    request_count = 0;
    read_data_base = 32'h6000_0000;
    response_code = AXI_RESP_OKAY;
    response_delay = 0;
  endfunction

  virtual task body();
    axi_req_item #(ADDR_WIDTH, DATA_WIDTH, ID_WIDTH, LEN_WIDTH) req;
    axi_rsp_item #(DATA_WIDTH, ID_WIDTH, LEN_WIDTH) rsp;
    repeat (request_count) begin
      p_sequencer.request_fifo.get(req);
      rsp = axi_rsp_item #(
        DATA_WIDTH, ID_WIDTH, LEN_WIDTH
      )::type_id::create("stage6_rsp");
      rsp.dir = req.dir;
      rsp.id = req.id;
      rsp.len = (req.dir == AXI_READ) ? req.len : '0;
      rsp.bresp = (req.dir == AXI_WRITE) ? response_code : AXI_RESP_OKAY;
      rsp.rsp_delay = response_delay;
      if (req.dir == AXI_READ) begin
        rsp.rdata = new[int'(req.len) + 1];
        rsp.rresp = new[int'(req.len) + 1];
        rsp.rbeat_gap = new[int'(req.len)];
        foreach (rsp.rdata[index]) begin
          rsp.rdata[index] = read_data_base + index;
          rsp.rresp[index] = response_code;
        end
        foreach (rsp.rbeat_gap[index]) rsp.rbeat_gap[index] = 0;
      end
      else begin
        rsp.rdata = new[0];
        rsp.rresp = new[0];
        rsp.rbeat_gap = new[0];
      end
      start_item(rsp);
      finish_item(rsp);
    end
  endtask

endclass

`endif

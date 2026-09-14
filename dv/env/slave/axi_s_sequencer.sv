`ifndef AXI_S_SEQUENCER_SV
`define AXI_S_SEQUENCER_SV

class axi_s_sequencer #(
  int unsigned ADDR_WIDTH = AXI_ADDR_WIDTH,
  int unsigned DATA_WIDTH = AXI_DATA_WIDTH,
  int unsigned ID_WIDTH   = AXI_S_ID_WIDTH,
  int unsigned LEN_WIDTH  = AXI_LEN_WIDTH
) extends uvm_sequencer #(
  axi_rsp_item #(DATA_WIDTH, ID_WIDTH, LEN_WIDTH)
);

  typedef axi_req_item #(
    ADDR_WIDTH, DATA_WIDTH, ID_WIDTH, LEN_WIDTH
  ) req_t;

  uvm_tlm_analysis_fifo #(req_t) request_fifo;

  `uvm_component_param_utils(
    axi_s_sequencer #(ADDR_WIDTH, DATA_WIDTH, ID_WIDTH, LEN_WIDTH)
  )

  function new(string name = "axi_s_sequencer", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    request_fifo = new("request_fifo", this);
  endfunction

endclass

`endif

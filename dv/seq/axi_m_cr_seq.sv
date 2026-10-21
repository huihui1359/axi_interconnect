`ifndef AXI_M_CR_SEQ_SV
`define AXI_M_CR_SEQ_SV

class axi_m_cr_seq extends uvm_sequence #(axi_m_req_t, axi_m_rsp_t);

  axi_m_req_t source_req;

  `uvm_object_utils(axi_m_cr_seq)

  function new(string name = "axi_m_cr_seq");
    super.new(name);
    source_req = null;
  endfunction

  virtual task body();
    axi_m_req_t req;

    if (source_req == null)
      `uvm_fatal("AXI_M_CR_SEQ", "source_req must be assigned before start()")
    if (!$cast(req, source_req.clone()))
      `uvm_fatal("AXI_M_CR_SEQ", "Failed to clone the planned request")

    start_item(req);
    finish_item(req);
  endtask

endclass

`endif

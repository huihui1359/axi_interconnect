`ifndef AXI_STAGE6_BASE_VSEQ_SV
`define AXI_STAGE6_BASE_VSEQ_SV

class axi_stage6_base_vseq extends uvm_sequence;
  `uvm_object_utils(axi_stage6_base_vseq)
  `uvm_declare_p_sequencer(axi_virtual_sequencer)

  function new(string name = "axi_stage6_base_vseq");
    super.new(name);
  endfunction

endclass

`endif

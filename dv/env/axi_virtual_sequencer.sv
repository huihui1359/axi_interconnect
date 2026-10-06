`ifndef AXI_VIRTUAL_SEQUENCER_SV
`define AXI_VIRTUAL_SEQUENCER_SV

class axi_virtual_sequencer extends uvm_sequencer;

  axi_m_sequencer_t m_seqr[AXI_NUM_MASTERS];
  axi_s_sequencer_t s_seqr[AXI_NUM_SLAVES];

  `uvm_component_utils(axi_virtual_sequencer)

  function new(string name = "axi_virtual_sequencer",
               uvm_component parent = null);
    super.new(name, parent);
  endfunction

endclass

`endif

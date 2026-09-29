`ifndef AXI_VIRTUAL_SEQUENCER_SV
`define AXI_VIRTUAL_SEQUENCER_SV

class axi_virtual_sequencer #(
  int unsigned ADDR_WIDTH  = AXI_ADDR_WIDTH,
  int unsigned DATA_WIDTH  = AXI_DATA_WIDTH,
  int unsigned M_ID_WIDTH  = AXI_M_ID_WIDTH,
  int unsigned S_ID_WIDTH  = AXI_S_ID_WIDTH,
  int unsigned LEN_WIDTH   = AXI_LEN_WIDTH,
  int unsigned NUM_MASTERS = AXI_ENV_NUM_MASTERS,
  int unsigned NUM_SLAVES  = AXI_ENV_NUM_SLAVES
) extends uvm_sequencer;

  axi_m_sequencer #(
    ADDR_WIDTH, DATA_WIDTH, M_ID_WIDTH, LEN_WIDTH
  ) m_seqr[NUM_MASTERS];
  axi_s_sequencer #(
    ADDR_WIDTH, DATA_WIDTH, S_ID_WIDTH, LEN_WIDTH
  ) s_seqr[NUM_SLAVES];

  `uvm_component_param_utils(
    axi_virtual_sequencer #(
      ADDR_WIDTH, DATA_WIDTH, M_ID_WIDTH, S_ID_WIDTH,
      LEN_WIDTH, NUM_MASTERS, NUM_SLAVES
    )
  )

  function new(string name = "axi_virtual_sequencer",
               uvm_component parent = null);
    super.new(name, parent);
  endfunction

endclass

`endif

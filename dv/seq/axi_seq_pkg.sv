package axi_seq_pkg;

  import uvm_pkg::*;
  `include "uvm_macros.svh"

  import axi_types_pkg::*;
  import axi_env_pkg::*;

  `include "axi_m_single_write_seq.sv"
  `include "axi_m_single_read_seq.sv"
  `include "axi_s_single_reactive_seq.sv"
  `include "axi_m_burst_write_seq.sv"
  `include "axi_m_burst_read_seq.sv"
  `include "axi_s_reactive_seq.sv"

endpackage

package axi_seq_pkg;

  import uvm_pkg::*;
  `include "uvm_macros.svh"

  import axi_types_pkg::*;
  import axi_env_pkg::*;

  `include "axi_m_single_write_seq.sv"
  `include "axi_m_single_read_seq.sv"
  `include "axi_s_single_reactive_seq.sv"
  `include "axi_stage2_scenario_seq.sv"
  `include "axi_stage2_burst_write_seq.sv"
  `include "axi_stage2_burst_read_seq.sv"
  `include "axi_stage2_aw_w_order_seq.sv"
  `include "axi_stage2_delay_gap_seq.sv"
  `include "axi_stage2_channel_stall_seq.sv"
  `include "axi_stage2_read_write_parallel_seq.sv"
  `include "axi_stage2_ready_random_smoke_seq.sv"

endpackage

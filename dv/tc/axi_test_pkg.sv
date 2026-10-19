package axi_test_pkg;

  import uvm_pkg::*;
  `include "uvm_macros.svh"

  import axi_types_pkg::*;
  import axi_env_pkg::*;
  import axi_seq_pkg::*;

  `include "axi_base_test.sv"
  `include "axi_stage2_base_test.sv"
  `include "axi_stage3_base_test.sv"
  `include "axi_stage6_base_test.sv"
  `include "tp_write_end_to_end.sv"
  `include "tp_read_end_to_end.sv"
  `include "tp_burst_lengths_write.sv"
  `include "tp_burst_lengths_read.sv"
  `include "tp_write_end_to_end_aw_w_order.sv"
  `include "tp_burst_lengths_gap.sv"
  `include "tp_channel_backpressure.sv"
  `include "tp_concurrency_read_write_parallel.sv"
  `include "tp_backpressure_random.sv"
  `include "tp_sid_table_depth_write.sv"
  `include "tp_sid_table_depth_read.sv"
  `include "tp_sid_membership_write_ooo.sv"
  `include "tp_sid_membership_read_ooo.sv"
  `include "tp_sid_membership_same_id_order.sv"
  `include "tp_outstanding_mixed_rw.sv"
  `include "tp_sid_exhaustive_local.sv"
  `include "tp_backpressure_outstanding.sv"
  `include "tp_system_tests.sv"

endpackage

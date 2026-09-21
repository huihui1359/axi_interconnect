package axi_test_pkg;

  import uvm_pkg::*;
  `include "uvm_macros.svh"

  import axi_types_pkg::*;
  import axi_env_pkg::*;
  import axi_seq_pkg::*;

  `include "axi_base_test.sv"
  `include "axi_stage2_base_test.sv"
  `include "axi_stage3_base_test.sv"
  `include "axi_stage1_single_write_test.sv"
  `include "axi_stage1_single_read_test.sv"
  `include "axi_stage2_burst_write_test.sv"
  `include "axi_stage2_burst_read_test.sv"
  `include "axi_stage2_aw_w_order_test.sv"
  `include "axi_stage2_delay_gap_test.sv"
  `include "axi_stage2_channel_stall_test.sv"
  `include "axi_stage2_read_write_parallel_test.sv"
  `include "axi_stage2_ready_random_smoke_test.sv"
  `include "axi_stage3_outstanding_write_test.sv"
  `include "axi_stage3_outstanding_read_test.sv"
  `include "axi_stage3_write_ooo_test.sv"
  `include "axi_stage3_read_ooo_test.sv"
  `include "axi_stage3_same_id_order_test.sv"
  `include "axi_stage3_mixed_rw_test.sv"
  `include "axi_stage3_id_mapping_test.sv"
  `include "axi_stage3_outstanding_stall_test.sv"

endpackage

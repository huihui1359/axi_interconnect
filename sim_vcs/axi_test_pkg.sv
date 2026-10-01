// Stage-1 package manifest for the focused VCS build.
package axi_test_pkg;

  import uvm_pkg::*;
  `include "uvm_macros.svh"

  import axi_types_pkg::*;
  import axi_env_pkg::*;
  import axi_seq_pkg::*;

  `include "axi_base_test.sv"
  `include "axi_stage1_single_write_test.sv"
  `include "axi_stage1_single_read_test.sv"

endpackage

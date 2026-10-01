// Stage-1 package manifest for this focused VCS build.  Keeping only the
// sequences needed by the selected testcase avoids compiling unrelated
// stage-2/3 code while those sources depend on latency_gen APIs not present in
// the current repository revision.
package axi_seq_pkg;

  import uvm_pkg::*;
  `include "uvm_macros.svh"

  import axi_types_pkg::*;
  import axi_env_pkg::*;

  `include "axi_m_single_write_seq.sv"
  `include "axi_m_single_read_seq.sv"
  `include "axi_s_single_reactive_seq.sv"

endpackage

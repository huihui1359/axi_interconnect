package axi_types_pkg;

  localparam int unsigned AXI_ADDR_WIDTH  = 32;
  localparam int unsigned AXI_DATA_WIDTH  = 32;
  localparam int unsigned AXI_M_ID_WIDTH  = 4;
  localparam int unsigned AXI_S_ID_WIDTH  = 8;
  localparam int unsigned AXI_LEN_WIDTH   = 4;
  localparam int unsigned AXI_DUT_NUM_MASTERS = 3;
  localparam int unsigned AXI_DUT_NUM_SLAVES  = 3;
  localparam int unsigned AXI_ENV_NUM_MASTERS = 1;
  localparam int unsigned AXI_ENV_NUM_SLAVES  = 1;

  // Backward-compatible default for generic transaction/interface types.
  // Project-level Master/Slave components must use the explicit constants.
  localparam int unsigned AXI_ID_WIDTH = AXI_M_ID_WIDTH;

  `include "common_typedef.svh"

endpackage

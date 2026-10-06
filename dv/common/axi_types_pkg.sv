package axi_types_pkg;

  // Single source of truth for the elaborated DUT/testbench shape.
  localparam int unsigned AXI_ADDR_WIDTH  = 32;
  localparam int unsigned AXI_DATA_WIDTH  = 32;
  localparam int unsigned AXI_M_ID_WIDTH  = 4;
  localparam int unsigned AXI_CID_WIDTH   = 4;
  localparam int unsigned AXI_S_ID_WIDTH  =
      AXI_CID_WIDTH + AXI_M_ID_WIDTH;
  localparam int unsigned AXI_LEN_WIDTH   = 4;
  localparam int unsigned AXI_NUM_MASTERS = 3;
  localparam int unsigned AXI_NUM_SLAVES  = 3;

  localparam int unsigned AXI_DATA_BYTES = AXI_DATA_WIDTH / 8;

  // Deprecated spelling retained for source compatibility. These are aliases,
  // not independent configuration points.
  localparam int unsigned AXI_DUT_NUM_MASTERS = AXI_NUM_MASTERS;
  localparam int unsigned AXI_DUT_NUM_SLAVES  = AXI_NUM_SLAVES;
  localparam int unsigned AXI_ENV_NUM_MASTERS = AXI_NUM_MASTERS;
  localparam int unsigned AXI_ENV_NUM_SLAVES  = AXI_NUM_SLAVES;

  // Backward-compatible default for generic transaction/interface types.
  // Project-level Master/Slave components must use the explicit constants.
  localparam int unsigned AXI_ID_WIDTH = AXI_M_ID_WIDTH;

  `include "common_typedef.svh"

  typedef bit [AXI_ADDR_WIDTH-1:0] axi_addr_t;
  typedef bit [AXI_DATA_WIDTH-1:0] axi_data_t;
  typedef bit [AXI_M_ID_WIDTH-1:0] axi_mid_t;
  typedef bit [AXI_S_ID_WIDTH-1:0] axi_sid_t;
  typedef bit [AXI_LEN_WIDTH-1:0]  axi_len_t;

endpackage

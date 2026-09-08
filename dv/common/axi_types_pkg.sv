package axi_types_pkg;

  localparam int unsigned AXI_ADDR_WIDTH  = 32;
  localparam int unsigned AXI_DATA_WIDTH  = 32;
  localparam int unsigned AXI_M_ID_WIDTH  = 4;
  localparam int unsigned AXI_S_ID_WIDTH  = 8;
  localparam int unsigned AXI_LEN_WIDTH   = 4;
  localparam int unsigned AXI_NUM_MASTERS = 3;
  localparam int unsigned AXI_NUM_SLAVES  = 3;

  // Backward-compatible default for generic transaction/interface types.
  // Project-level Master/Slave components must use the explicit constants.
  localparam int unsigned AXI_ID_WIDTH = AXI_M_ID_WIDTH;

  typedef enum bit {
    AXI_READ  = 1'b0,
    AXI_WRITE = 1'b1
  } axi_dir_e;

  typedef enum bit [1:0] {
    AXI_BURST_FIXED = 2'b00,
    AXI_BURST_INCR  = 2'b01,
    AXI_BURST_WRAP  = 2'b10
  } axi_burst_e;

  typedef enum bit [1:0] {
    AXI_RESP_OKAY   = 2'b00,
    AXI_RESP_EXOKAY = 2'b01,
    AXI_RESP_SLVERR = 2'b10,
    AXI_RESP_DECERR = 2'b11
  } axi_resp_e;

  typedef enum bit [1:0] {
    AXI_REGION_S0,
    AXI_REGION_S1,
    AXI_REGION_S2,
    AXI_REGION_DEFAULT
  } axi_region_e;

  typedef enum bit [2:0] {
    AXI_DATA_RANDOM,
    AXI_DATA_ZERO,
    AXI_DATA_ONES,
    AXI_DATA_WALKING_ONE,
    AXI_DATA_ADDRESS
  } axi_data_pattern_e;

  typedef enum bit [1:0] {
    ALWAYS_READY,
    RANDOM_READY,
    SCRIPTED_READY
  } axi_ready_mode_e;

endpackage

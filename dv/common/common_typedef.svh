`ifndef AXI_COMMON_TYPEDEF_SVH
`define AXI_COMMON_TYPEDEF_SVH

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

typedef enum bit [2:0] {
  AXI_CHANNEL_AW,
  AXI_CHANNEL_W,
  AXI_CHANNEL_B,
  AXI_CHANNEL_AR,
  AXI_CHANNEL_R
} axi_channel_e;

typedef enum bit {
  AXI_UPSTREAM,
  AXI_DOWNSTREAM
} axi_side_e;

`endif

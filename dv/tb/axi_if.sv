`ifndef AXI_IF_SV
`define AXI_IF_SV

// 一个axi_if实例表示一组单端口AXI物理连接。
// Driver和Monitor通过modport直接访问接口信号，并在各自组件中按ACLK同步。
interface axi_if #(
  int unsigned ADDR_WIDTH = axi_types_pkg::AXI_ADDR_WIDTH,
  int unsigned DATA_WIDTH = axi_types_pkg::AXI_DATA_WIDTH,
  int unsigned ID_WIDTH   = axi_types_pkg::AXI_ID_WIDTH,
  int unsigned LEN_WIDTH  = axi_types_pkg::AXI_LEN_WIDTH
) (
  input logic ACLK,
  input logic ARESETn
);

  localparam int unsigned DATA_BYTES = DATA_WIDTH / 8;

  // Write address channel
  logic [ID_WIDTH-1:0]    awid;
  logic [ADDR_WIDTH-1:0]  awaddr;
  logic [LEN_WIDTH-1:0]   awlen;
  logic [2:0]             awsize;
  logic [1:0]             awburst;
  logic                   awvalid;
  logic                   awready;

  // Write data channel (AXI3 includes WID)
  logic [ID_WIDTH-1:0]    wid;
  logic [DATA_WIDTH-1:0]  wdata;
  logic [DATA_BYTES-1:0]  wstrb;
  logic                   wlast;
  logic                   wvalid;
  logic                   wready;

  // Write response channel
  logic [ID_WIDTH-1:0]    bid;
  logic [1:0]             bresp;
  logic                   bvalid;
  logic                   bready;

  // Read address channel
  logic [ID_WIDTH-1:0]    arid;
  logic [ADDR_WIDTH-1:0]  araddr;
  logic [LEN_WIDTH-1:0]   arlen;
  logic [2:0]             arsize;
  logic [1:0]             arburst;
  logic                   arvalid;
  logic                   arready;

  // Read data channel
  logic [ID_WIDTH-1:0]    rid;
  logic [DATA_WIDTH-1:0]  rdata;
  logic [1:0]             rresp;
  logic                   rlast;
  logic                   rvalid;
  logic                   rready;

  // Master Driver drives request channels and response READY signals.
  modport m_drv_mp (
    input  ACLK, ARESETn,
    output awid, awaddr, awlen, awsize, awburst, awvalid,
    input  awready,
    output wid, wdata, wstrb, wlast, wvalid,
    input  wready,
    input  bid, bresp, bvalid,
    output bready,
    output arid, araddr, arlen, arsize, arburst, arvalid,
    input  arready,
    input  rid, rdata, rresp, rlast, rvalid,
    output rready
  );

  // Slave Driver receives requests and drives READY and response channels.
  modport s_drv_mp (
    input  ACLK, ARESETn,
    input  awid, awaddr, awlen, awsize, awburst, awvalid,
    output awready,
    input  wid, wdata, wstrb, wlast, wvalid,
    output wready,
    output bid, bresp, bvalid,
    input  bready,
    input  arid, araddr, arlen, arsize, arburst, arvalid,
    output arready,
    output rid, rdata, rresp, rlast, rvalid,
    input  rready
  );

  // Monitor has read-only access to the complete interface.
  modport mon_mp (
    input ACLK, ARESETn,
    input awid, awaddr, awlen, awsize, awburst, awvalid, awready,
    input wid, wdata, wstrb, wlast, wvalid, wready,
    input bid, bresp, bvalid, bready,
    input arid, araddr, arlen, arsize, arburst, arvalid, arready,
    input rid, rdata, rresp, rlast, rvalid, rready
  );

  // DUT behaves as an AXI Slave on each upstream Master-facing port.
  modport dut_slave_mp (
    input  ACLK, ARESETn,
    input  awid, awaddr, awlen, awsize, awburst, awvalid,
    output awready,
    input  wid, wdata, wstrb, wlast, wvalid,
    output wready,
    output bid, bresp, bvalid,
    input  bready,
    input  arid, araddr, arlen, arsize, arburst, arvalid,
    output arready,
    output rid, rdata, rresp, rlast, rvalid,
    input  rready
  );

  // DUT behaves as an AXI Master on each downstream Slave-facing port.
  modport dut_master_mp (
    input  ACLK, ARESETn,
    output awid, awaddr, awlen, awsize, awburst, awvalid,
    input  awready,
    output wid, wdata, wstrb, wlast, wvalid,
    input  wready,
    input  bid, bresp, bvalid,
    output bready,
    output arid, araddr, arlen, arsize, arburst, arvalid,
    input  arready,
    input  rid, rdata, rresp, rlast, rvalid,
    output rready
  );

  initial begin
    if (ADDR_WIDTH == 0)
      $fatal(1, "AXI_IF_PARAM: ADDR_WIDTH must be non-zero");

    if ((DATA_WIDTH == 0) || ((DATA_WIDTH % 8) != 0))
      $fatal(1, "AXI_IF_PARAM: DATA_WIDTH must be a non-zero multiple of 8");

    if ((DATA_BYTES & (DATA_BYTES - 1)) != 0)
      $fatal(1, "AXI_IF_PARAM: DATA_BYTES must be a power of two");

    if ((ID_WIDTH == 0) || (LEN_WIDTH == 0))
      $fatal(1, "AXI_IF_PARAM: ID_WIDTH and LEN_WIDTH must be non-zero");
  end

endinterface

`endif

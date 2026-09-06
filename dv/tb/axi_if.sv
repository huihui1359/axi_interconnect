`ifndef AXI_IF_SV
`define AXI_IF_SV

//一个完整的、单端口AXI接口，包含所有的信号和时序约束
//一个axi_if实例只代表一个物理AXI连接
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

  // One clocking event observes the just-completed transfer and drives the
  // next-cycle outputs without testbench/DUT scheduling races.
  clocking m_drv_cb @(posedge ACLK);
    default input #1step output #0;//提前1step采样input信号，立即驱动output

    input  ARESETn;

    output awid, awaddr, awlen, awsize, awburst, awvalid;
    input  awready;

    output wid, wdata, wstrb, wlast, wvalid;
    input  wready;

    input  bid, bresp, bvalid;
    output bready;

    output arid, araddr, arlen, arsize, arburst, arvalid;
    input  arready;

    input  rid, rdata, rresp, rlast, rvalid;
    output rready;
  endclocking

  clocking s_drv_cb @(posedge ACLK);
    default input #1step output #0;

    input  ARESETn;

    input  awid, awaddr, awlen, awsize, awburst, awvalid;
    output awready;

    input  wid, wdata, wstrb, wlast, wvalid;
    output wready;

    output bid, bresp, bvalid;
    input  bready;

    input  arid, araddr, arlen, arsize, arburst, arvalid;
    output arready;

    output rid, rdata, rresp, rlast, rvalid;
    input  rready;
  endclocking

  // Monitor sees every signal but never drives the interface.
  clocking mon_cb @(posedge ACLK);
    default input #1step;

    input ARESETn;

    input awid, awaddr, awlen, awsize, awburst, awvalid, awready;
    input wid, wdata, wstrb, wlast, wvalid, wready;
    input bid, bresp, bvalid, bready;
    input arid, araddr, arlen, arsize, arburst, arvalid, arready;
    input rid, rdata, rresp, rlast, rvalid, rready;
  endclocking

  modport m_drv_mp (clocking m_drv_cb);
  modport s_drv_mp (clocking s_drv_cb);
  modport mon_mp   (clocking mon_cb);

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

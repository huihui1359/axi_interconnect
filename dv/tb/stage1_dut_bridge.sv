module stage1_dut_bridge(
  axi_if.dut_slave_mp m_if,
  axi_if.dut_master_mp s_if
);

  import axi_types_pkg::*;

  wire [AXI_M_ID_WIDTH-1:0] M_AXI_AWID[0:2];
  wire [AXI_ADDR_WIDTH-1:0] M_AXI_AWADDR[0:2];
  wire [AXI_LEN_WIDTH-1:0] M_AXI_AWLEN[0:2];
  wire [2:0] M_AXI_AWSIZE[0:2];
  wire [1:0] M_AXI_AWBURST[0:2];
  wire M_AXI_AWVALID[0:2];
  wire M_AXI_AWREADY[0:2];

  wire [AXI_M_ID_WIDTH-1:0] M_AXI_WID[0:2];
  wire [AXI_DATA_WIDTH-1:0] M_AXI_WDATA[0:2];
  wire [(AXI_DATA_WIDTH/8)-1:0] M_AXI_WSTRB[0:2];
  wire M_AXI_WLAST[0:2];
  wire M_AXI_WVALID[0:2];
  wire M_AXI_WREADY[0:2];

  wire [AXI_M_ID_WIDTH-1:0] M_AXI_BID[0:2];
  wire [1:0] M_AXI_BRESP[0:2];
  wire M_AXI_BVALID[0:2];
  wire M_AXI_BREADY[0:2];

  wire [AXI_M_ID_WIDTH-1:0] M_AXI_ARID[0:2];
  wire [AXI_ADDR_WIDTH-1:0] M_AXI_ARADDR[0:2];
  wire [AXI_LEN_WIDTH-1:0] M_AXI_ARLEN[0:2];
  wire [2:0] M_AXI_ARSIZE[0:2];
  wire [1:0] M_AXI_ARBURST[0:2];
  wire M_AXI_ARVALID[0:2];
  wire M_AXI_ARREADY[0:2];

  wire [AXI_M_ID_WIDTH-1:0] M_AXI_RID[0:2];
  wire [AXI_DATA_WIDTH-1:0] M_AXI_RDATA[0:2];
  wire [1:0] M_AXI_RRESP[0:2];
  wire M_AXI_RLAST[0:2];
  wire M_AXI_RVALID[0:2];
  wire M_AXI_RREADY[0:2];

  wire [AXI_S_ID_WIDTH-1:0] S_AXI_AWID[0:2];
  wire [AXI_ADDR_WIDTH-1:0] S_AXI_AWADDR[0:2];
  wire [AXI_LEN_WIDTH-1:0] S_AXI_AWLEN[0:2];
  wire [2:0] S_AXI_AWSIZE[0:2];
  wire [1:0] S_AXI_AWBURST[0:2];
  wire S_AXI_AWVALID[0:2];
  wire S_AXI_AWREADY[0:2];

  wire [AXI_S_ID_WIDTH-1:0] S_AXI_WID[0:2];
  wire [AXI_DATA_WIDTH-1:0] S_AXI_WDATA[0:2];
  wire [(AXI_DATA_WIDTH/8)-1:0] S_AXI_WSTRB[0:2];
  wire S_AXI_WLAST[0:2];
  wire S_AXI_WVALID[0:2];
  wire S_AXI_WREADY[0:2];

  wire [AXI_S_ID_WIDTH-1:0] S_AXI_BID[0:2];
  wire [1:0] S_AXI_BRESP[0:2];
  wire S_AXI_BVALID[0:2];
  wire S_AXI_BREADY[0:2];

  wire [AXI_S_ID_WIDTH-1:0] S_AXI_ARID[0:2];
  wire [AXI_ADDR_WIDTH-1:0] S_AXI_ARADDR[0:2];
  wire [AXI_LEN_WIDTH-1:0] S_AXI_ARLEN[0:2];
  wire [2:0] S_AXI_ARSIZE[0:2];
  wire [1:0] S_AXI_ARBURST[0:2];
  wire S_AXI_ARVALID[0:2];
  wire S_AXI_ARREADY[0:2];

  wire [AXI_S_ID_WIDTH-1:0] S_AXI_RID[0:2];
  wire [AXI_DATA_WIDTH-1:0] S_AXI_RDATA[0:2];
  wire [1:0] S_AXI_RRESP[0:2];
  wire S_AXI_RLAST[0:2];
  wire S_AXI_RVALID[0:2];
  wire S_AXI_RREADY[0:2];

  assign M_AXI_AWID[0]    = m_if.awid;
  assign M_AXI_AWADDR[0]  = m_if.awaddr;
  assign M_AXI_AWLEN[0]   = m_if.awlen;
  assign M_AXI_AWSIZE[0]  = m_if.awsize;
  assign M_AXI_AWBURST[0] = m_if.awburst;
  assign M_AXI_AWVALID[0] = m_if.awvalid;
  assign m_if.awready     = M_AXI_AWREADY[0];

  assign M_AXI_WID[0]    = m_if.wid;
  assign M_AXI_WDATA[0]  = m_if.wdata;
  assign M_AXI_WSTRB[0]  = m_if.wstrb;
  assign M_AXI_WLAST[0]  = m_if.wlast;
  assign M_AXI_WVALID[0] = m_if.wvalid;
  assign m_if.wready     = M_AXI_WREADY[0];

  assign m_if.bid       = M_AXI_BID[0];
  assign m_if.bresp     = M_AXI_BRESP[0];
  assign m_if.bvalid    = M_AXI_BVALID[0];
  assign M_AXI_BREADY[0] = m_if.bready;

  assign M_AXI_ARID[0]    = m_if.arid;
  assign M_AXI_ARADDR[0]  = m_if.araddr;
  assign M_AXI_ARLEN[0]   = m_if.arlen;
  assign M_AXI_ARSIZE[0]  = m_if.arsize;
  assign M_AXI_ARBURST[0] = m_if.arburst;
  assign M_AXI_ARVALID[0] = m_if.arvalid;
  assign m_if.arready     = M_AXI_ARREADY[0];

  assign m_if.rid       = M_AXI_RID[0];
  assign m_if.rdata     = M_AXI_RDATA[0];
  assign m_if.rresp     = M_AXI_RRESP[0];
  assign m_if.rlast     = M_AXI_RLAST[0];
  assign m_if.rvalid    = M_AXI_RVALID[0];
  assign M_AXI_RREADY[0] = m_if.rready;

  assign s_if.awid       = S_AXI_AWID[0];
  assign s_if.awaddr     = S_AXI_AWADDR[0];
  assign s_if.awlen      = S_AXI_AWLEN[0];
  assign s_if.awsize     = S_AXI_AWSIZE[0];
  assign s_if.awburst    = S_AXI_AWBURST[0];
  assign s_if.awvalid    = S_AXI_AWVALID[0];
  assign S_AXI_AWREADY[0] = s_if.awready;

  assign s_if.wid       = S_AXI_WID[0];
  assign s_if.wdata     = S_AXI_WDATA[0];
  assign s_if.wstrb     = S_AXI_WSTRB[0];
  assign s_if.wlast     = S_AXI_WLAST[0];
  assign s_if.wvalid    = S_AXI_WVALID[0];
  assign S_AXI_WREADY[0] = s_if.wready;

  assign S_AXI_BID[0]    = s_if.bid;
  assign S_AXI_BRESP[0]  = s_if.bresp;
  assign S_AXI_BVALID[0] = s_if.bvalid;
  assign s_if.bready     = S_AXI_BREADY[0];

  assign s_if.arid       = S_AXI_ARID[0];
  assign s_if.araddr     = S_AXI_ARADDR[0];
  assign s_if.arlen      = S_AXI_ARLEN[0];
  assign s_if.arsize     = S_AXI_ARSIZE[0];
  assign s_if.arburst    = S_AXI_ARBURST[0];
  assign s_if.arvalid    = S_AXI_ARVALID[0];
  assign S_AXI_ARREADY[0] = s_if.arready;

  assign S_AXI_RID[0]    = s_if.rid;
  assign S_AXI_RDATA[0]  = s_if.rdata;
  assign S_AXI_RRESP[0]  = s_if.rresp;
  assign S_AXI_RLAST[0]  = s_if.rlast;
  assign S_AXI_RVALID[0] = s_if.rvalid;
  assign s_if.rready     = S_AXI_RREADY[0];

  generate
    for (genvar index = 1; index < 3; index++) begin : inactive_ports
      assign M_AXI_AWID[index]    = '0;
      assign M_AXI_AWADDR[index]  = '0;
      assign M_AXI_AWLEN[index]   = '0;
      assign M_AXI_AWSIZE[index]  = '0;
      assign M_AXI_AWBURST[index] = '0;
      assign M_AXI_AWVALID[index] = 1'b0;
      assign M_AXI_WID[index]     = '0;
      assign M_AXI_WDATA[index]   = '0;
      assign M_AXI_WSTRB[index]   = '0;
      assign M_AXI_WLAST[index]   = 1'b0;
      assign M_AXI_WVALID[index]  = 1'b0;
      assign M_AXI_BREADY[index]  = 1'b0;
      assign M_AXI_ARID[index]    = '0;
      assign M_AXI_ARADDR[index]  = '0;
      assign M_AXI_ARLEN[index]   = '0;
      assign M_AXI_ARSIZE[index]  = '0;
      assign M_AXI_ARBURST[index] = '0;
      assign M_AXI_ARVALID[index] = 1'b0;
      assign M_AXI_RREADY[index]  = 1'b0;

      assign S_AXI_AWREADY[index] = 1'b0;
      assign S_AXI_WREADY[index]  = 1'b0;
      assign S_AXI_BID[index]     = '0;
      assign S_AXI_BRESP[index]   = '0;
      assign S_AXI_BVALID[index]  = 1'b0;
      assign S_AXI_ARREADY[index] = 1'b0;
      assign S_AXI_RID[index]     = '0;
      assign S_AXI_RDATA[index]   = '0;
      assign S_AXI_RRESP[index]   = '0;
      assign S_AXI_RLAST[index]   = 1'b0;
      assign S_AXI_RVALID[index]  = 1'b0;
    end
  endgenerate

  axi_interconnect #(
    .WIDTH_CID(4),
    .WIDTH_ID (AXI_M_ID_WIDTH),
    .WIDTH_AD (AXI_ADDR_WIDTH),
    .WIDTH_DA (AXI_DATA_WIDTH),
    .WIDTH_DS (AXI_DATA_WIDTH/8),
    .WIDTH_SID(AXI_S_ID_WIDTH)
  ) dut (
    .AXI_RSTn       (m_if.ARESETn),
    .AXI_CLK        (m_if.ACLK),
    .M_AXI_AWID     (M_AXI_AWID),
    .M_AXI_AWADDR   (M_AXI_AWADDR),
    .M_AXI_AWLEN    (M_AXI_AWLEN),
    .M_AXI_AWSIZE   (M_AXI_AWSIZE),
    .M_AXI_AWBURST  (M_AXI_AWBURST),
    .M_AXI_AWVALID  (M_AXI_AWVALID),
    .M_AXI_AWREADY  (M_AXI_AWREADY),
    .M_AXI_WID      (M_AXI_WID),
    .M_AXI_WDATA    (M_AXI_WDATA),
    .M_AXI_WSTRB    (M_AXI_WSTRB),
    .M_AXI_WLAST    (M_AXI_WLAST),
    .M_AXI_WVALID   (M_AXI_WVALID),
    .M_AXI_WREADY   (M_AXI_WREADY),
    .M_AXI_BID      (M_AXI_BID),
    .M_AXI_BRESP    (M_AXI_BRESP),
    .M_AXI_BVALID   (M_AXI_BVALID),
    .M_AXI_BREADY   (M_AXI_BREADY),
    .M_AXI_ARID     (M_AXI_ARID),
    .M_AXI_ARADDR   (M_AXI_ARADDR),
    .M_AXI_ARLEN    (M_AXI_ARLEN),
    .M_AXI_ARSIZE   (M_AXI_ARSIZE),
    .M_AXI_ARBURST  (M_AXI_ARBURST),
    .M_AXI_ARVALID  (M_AXI_ARVALID),
    .M_AXI_ARREADY  (M_AXI_ARREADY),
    .M_AXI_RID      (M_AXI_RID),
    .M_AXI_RDATA    (M_AXI_RDATA),
    .M_AXI_RRESP    (M_AXI_RRESP),
    .M_AXI_RLAST    (M_AXI_RLAST),
    .M_AXI_RVALID   (M_AXI_RVALID),
    .M_AXI_RREADY   (M_AXI_RREADY),
    .S_AXI_AWID     (S_AXI_AWID),
    .S_AXI_AWADDR   (S_AXI_AWADDR),
    .S_AXI_AWLEN    (S_AXI_AWLEN),
    .S_AXI_AWSIZE   (S_AXI_AWSIZE),
    .S_AXI_AWBURST  (S_AXI_AWBURST),
    .S_AXI_AWVALID  (S_AXI_AWVALID),
    .S_AXI_AWREADY  (S_AXI_AWREADY),
    .S_AXI_WID      (S_AXI_WID),
    .S_AXI_WDATA    (S_AXI_WDATA),
    .S_AXI_WSTRB    (S_AXI_WSTRB),
    .S_AXI_WLAST    (S_AXI_WLAST),
    .S_AXI_WVALID   (S_AXI_WVALID),
    .S_AXI_WREADY   (S_AXI_WREADY),
    .S_AXI_BID      (S_AXI_BID),
    .S_AXI_BRESP    (S_AXI_BRESP),
    .S_AXI_BVALID   (S_AXI_BVALID),
    .S_AXI_BREADY   (S_AXI_BREADY),
    .S_AXI_ARID     (S_AXI_ARID),
    .S_AXI_ARADDR   (S_AXI_ARADDR),
    .S_AXI_ARLEN    (S_AXI_ARLEN),
    .S_AXI_ARSIZE   (S_AXI_ARSIZE),
    .S_AXI_ARBURST  (S_AXI_ARBURST),
    .S_AXI_ARVALID  (S_AXI_ARVALID),
    .S_AXI_ARREADY  (S_AXI_ARREADY),
    .S_AXI_RID      (S_AXI_RID),
    .S_AXI_RDATA    (S_AXI_RDATA),
    .S_AXI_RRESP    (S_AXI_RRESP),
    .S_AXI_RLAST    (S_AXI_RLAST),
    .S_AXI_RVALID   (S_AXI_RVALID),
    .S_AXI_RREADY   (S_AXI_RREADY)
  );

endmodule

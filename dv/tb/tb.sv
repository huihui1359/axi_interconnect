`timescale 1ns/1ps

module tb;

  import uvm_pkg::*;
  import axi_types_pkg::*;
  import axi_env_pkg::*;
  import axi_seq_pkg::*;
  import axi_test_pkg::*;

  logic clk;
  logic rst_n;
  axi_env_cfg env_cfg;

  initial begin
    clk = 1'b0;
    forever #5ns clk = ~clk;
  end

  initial begin
    rst_n = 1'b0;
    repeat (2) @(posedge clk);
    @(negedge clk);
    rst_n = 1'b1;
  end

  axi_if #(
    .ADDR_WIDTH(AXI_ADDR_WIDTH),
    .DATA_WIDTH(AXI_DATA_WIDTH),
    .ID_WIDTH  (AXI_M_ID_WIDTH),
    .LEN_WIDTH (AXI_LEN_WIDTH)
  ) m_if (
    .ACLK   (clk),
    .ARESETn(rst_n)
  );

  axi_if #(
    .ADDR_WIDTH(AXI_ADDR_WIDTH),
    .DATA_WIDTH(AXI_DATA_WIDTH),
    .ID_WIDTH  (AXI_S_ID_WIDTH),
    .LEN_WIDTH (AXI_LEN_WIDTH)
  ) s_if (
    .ACLK   (clk),
    .ARESETn(rst_n)
  );

  axi_protocol_assertions #(
    .ADDR_WIDTH  (AXI_ADDR_WIDTH),
    .DATA_WIDTH  (AXI_DATA_WIDTH),
    .ID_WIDTH    (AXI_M_ID_WIDTH),
    .LEN_WIDTH   (AXI_LEN_WIDTH),
    .TB_IS_MASTER(1'b1)
  ) m_protocol_assertions (
    .ACLK   (m_if.ACLK),
    .ARESETn(m_if.ARESETn),
    .awid(m_if.awid), .awaddr(m_if.awaddr), .awlen(m_if.awlen),
    .awsize(m_if.awsize), .awburst(m_if.awburst),
    .awvalid(m_if.awvalid), .awready(m_if.awready),
    .wid(m_if.wid), .wdata(m_if.wdata), .wstrb(m_if.wstrb),
    .wlast(m_if.wlast), .wvalid(m_if.wvalid), .wready(m_if.wready),
    .bid(m_if.bid), .bresp(m_if.bresp),
    .bvalid(m_if.bvalid), .bready(m_if.bready),
    .arid(m_if.arid), .araddr(m_if.araddr), .arlen(m_if.arlen),
    .arsize(m_if.arsize), .arburst(m_if.arburst),
    .arvalid(m_if.arvalid), .arready(m_if.arready),
    .rid(m_if.rid), .rdata(m_if.rdata), .rresp(m_if.rresp),
    .rlast(m_if.rlast), .rvalid(m_if.rvalid), .rready(m_if.rready)
  );

  axi_protocol_assertions #(
    .ADDR_WIDTH  (AXI_ADDR_WIDTH),
    .DATA_WIDTH  (AXI_DATA_WIDTH),
    .ID_WIDTH    (AXI_S_ID_WIDTH),
    .LEN_WIDTH   (AXI_LEN_WIDTH),
    .TB_IS_MASTER(1'b0)
  ) s_protocol_assertions (
    .ACLK   (s_if.ACLK),
    .ARESETn(s_if.ARESETn),
    .awid(s_if.awid), .awaddr(s_if.awaddr), .awlen(s_if.awlen),
    .awsize(s_if.awsize), .awburst(s_if.awburst),
    .awvalid(s_if.awvalid), .awready(s_if.awready),
    .wid(s_if.wid), .wdata(s_if.wdata), .wstrb(s_if.wstrb),
    .wlast(s_if.wlast), .wvalid(s_if.wvalid), .wready(s_if.wready),
    .bid(s_if.bid), .bresp(s_if.bresp),
    .bvalid(s_if.bvalid), .bready(s_if.bready),
    .arid(s_if.arid), .araddr(s_if.araddr), .arlen(s_if.arlen),
    .arsize(s_if.arsize), .arburst(s_if.arburst),
    .arvalid(s_if.arvalid), .arready(s_if.arready),
    .rid(s_if.rid), .rdata(s_if.rdata), .rresp(s_if.rresp),
    .rlast(s_if.rlast), .rvalid(s_if.rvalid), .rready(s_if.rready)
  );

  wire [AXI_M_ID_WIDTH-1:0] M_AXI_AWID[0:AXI_DUT_NUM_MASTERS-1];
  wire [AXI_ADDR_WIDTH-1:0] M_AXI_AWADDR[0:AXI_DUT_NUM_MASTERS-1];
  wire [AXI_LEN_WIDTH-1:0] M_AXI_AWLEN[0:AXI_DUT_NUM_MASTERS-1];
  wire [2:0] M_AXI_AWSIZE[0:AXI_DUT_NUM_MASTERS-1];
  wire [1:0] M_AXI_AWBURST[0:AXI_DUT_NUM_MASTERS-1];
  wire M_AXI_AWVALID[0:AXI_DUT_NUM_MASTERS-1];
  wire M_AXI_AWREADY[0:AXI_DUT_NUM_MASTERS-1];

  wire [AXI_M_ID_WIDTH-1:0] M_AXI_WID[0:AXI_DUT_NUM_MASTERS-1];
  wire [AXI_DATA_WIDTH-1:0] M_AXI_WDATA[0:AXI_DUT_NUM_MASTERS-1];
  wire [(AXI_DATA_WIDTH/8)-1:0] M_AXI_WSTRB[0:AXI_DUT_NUM_MASTERS-1];
  wire M_AXI_WLAST[0:AXI_DUT_NUM_MASTERS-1];
  wire M_AXI_WVALID[0:AXI_DUT_NUM_MASTERS-1];
  wire M_AXI_WREADY[0:AXI_DUT_NUM_MASTERS-1];

  wire [AXI_M_ID_WIDTH-1:0] M_AXI_BID[0:AXI_DUT_NUM_MASTERS-1];
  wire [1:0] M_AXI_BRESP[0:AXI_DUT_NUM_MASTERS-1];
  wire M_AXI_BVALID[0:AXI_DUT_NUM_MASTERS-1];
  wire M_AXI_BREADY[0:AXI_DUT_NUM_MASTERS-1];

  wire [AXI_M_ID_WIDTH-1:0] M_AXI_ARID[0:AXI_DUT_NUM_MASTERS-1];
  wire [AXI_ADDR_WIDTH-1:0] M_AXI_ARADDR[0:AXI_DUT_NUM_MASTERS-1];
  wire [AXI_LEN_WIDTH-1:0] M_AXI_ARLEN[0:AXI_DUT_NUM_MASTERS-1];
  wire [2:0] M_AXI_ARSIZE[0:AXI_DUT_NUM_MASTERS-1];
  wire [1:0] M_AXI_ARBURST[0:AXI_DUT_NUM_MASTERS-1];
  wire M_AXI_ARVALID[0:AXI_DUT_NUM_MASTERS-1];
  wire M_AXI_ARREADY[0:AXI_DUT_NUM_MASTERS-1];

  wire [AXI_M_ID_WIDTH-1:0] M_AXI_RID[0:AXI_DUT_NUM_MASTERS-1];
  wire [AXI_DATA_WIDTH-1:0] M_AXI_RDATA[0:AXI_DUT_NUM_MASTERS-1];
  wire [1:0] M_AXI_RRESP[0:AXI_DUT_NUM_MASTERS-1];
  wire M_AXI_RLAST[0:AXI_DUT_NUM_MASTERS-1];
  wire M_AXI_RVALID[0:AXI_DUT_NUM_MASTERS-1];
  wire M_AXI_RREADY[0:AXI_DUT_NUM_MASTERS-1];

  wire [AXI_S_ID_WIDTH-1:0] S_AXI_AWID[0:AXI_DUT_NUM_SLAVES-1];
  wire [AXI_ADDR_WIDTH-1:0] S_AXI_AWADDR[0:AXI_DUT_NUM_SLAVES-1];
  wire [AXI_LEN_WIDTH-1:0] S_AXI_AWLEN[0:AXI_DUT_NUM_SLAVES-1];
  wire [2:0] S_AXI_AWSIZE[0:AXI_DUT_NUM_SLAVES-1];
  wire [1:0] S_AXI_AWBURST[0:AXI_DUT_NUM_SLAVES-1];
  wire S_AXI_AWVALID[0:AXI_DUT_NUM_SLAVES-1];
  wire S_AXI_AWREADY[0:AXI_DUT_NUM_SLAVES-1];

  wire [AXI_S_ID_WIDTH-1:0] S_AXI_WID[0:AXI_DUT_NUM_SLAVES-1];
  wire [AXI_DATA_WIDTH-1:0] S_AXI_WDATA[0:AXI_DUT_NUM_SLAVES-1];
  wire [(AXI_DATA_WIDTH/8)-1:0] S_AXI_WSTRB[0:AXI_DUT_NUM_SLAVES-1];
  wire S_AXI_WLAST[0:AXI_DUT_NUM_SLAVES-1];
  wire S_AXI_WVALID[0:AXI_DUT_NUM_SLAVES-1];
  wire S_AXI_WREADY[0:AXI_DUT_NUM_SLAVES-1];

  wire [AXI_S_ID_WIDTH-1:0] S_AXI_BID[0:AXI_DUT_NUM_SLAVES-1];
  wire [1:0] S_AXI_BRESP[0:AXI_DUT_NUM_SLAVES-1];
  wire S_AXI_BVALID[0:AXI_DUT_NUM_SLAVES-1];
  wire S_AXI_BREADY[0:AXI_DUT_NUM_SLAVES-1];

  wire [AXI_S_ID_WIDTH-1:0] S_AXI_ARID[0:AXI_DUT_NUM_SLAVES-1];
  wire [AXI_ADDR_WIDTH-1:0] S_AXI_ARADDR[0:AXI_DUT_NUM_SLAVES-1];
  wire [AXI_LEN_WIDTH-1:0] S_AXI_ARLEN[0:AXI_DUT_NUM_SLAVES-1];
  wire [2:0] S_AXI_ARSIZE[0:AXI_DUT_NUM_SLAVES-1];
  wire [1:0] S_AXI_ARBURST[0:AXI_DUT_NUM_SLAVES-1];
  wire S_AXI_ARVALID[0:AXI_DUT_NUM_SLAVES-1];
  wire S_AXI_ARREADY[0:AXI_DUT_NUM_SLAVES-1];

  wire [AXI_S_ID_WIDTH-1:0] S_AXI_RID[0:AXI_DUT_NUM_SLAVES-1];
  wire [AXI_DATA_WIDTH-1:0] S_AXI_RDATA[0:AXI_DUT_NUM_SLAVES-1];
  wire [1:0] S_AXI_RRESP[0:AXI_DUT_NUM_SLAVES-1];
  wire S_AXI_RLAST[0:AXI_DUT_NUM_SLAVES-1];
  wire S_AXI_RVALID[0:AXI_DUT_NUM_SLAVES-1];
  wire S_AXI_RREADY[0:AXI_DUT_NUM_SLAVES-1];

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
    for (genvar index = 1;
         index < AXI_DUT_NUM_MASTERS;
         index++) begin : inactive_master_ports
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
    end

    for (genvar index = 1;
         index < AXI_DUT_NUM_SLAVES;
         index++) begin : inactive_slave_ports
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

  initial begin
    env_cfg = axi_env_cfg #()::type_id::create("env_cfg");
    env_cfg.m_cfg[0].is_active = UVM_ACTIVE;
    env_cfg.m_cfg[0].drv_vif   = m_if;
    env_cfg.m_cfg[0].mon_vif   = m_if;
    env_cfg.s_cfg[0].is_active = UVM_ACTIVE;
    env_cfg.s_cfg[0].drv_vif   = s_if;
    env_cfg.s_cfg[0].mon_vif   = s_if;

    uvm_config_db#(axi_env_cfg)::set(
      null, "uvm_test_top", "env_cfg", env_cfg
    );
    uvm_root::get().set_timeout(100_000_000, 1'b1);
    run_test();
  end

  final begin
        uvm_report_server server;
        int err_num, fatal_num;
        integer exit_code;

        server = uvm_report_server::get_server();
        err_num = server.get_severity_count(UVM_ERROR);
        fatal_num = server.get_severity_count(UVM_FATAL);

        if (err_num != 0 || fatal_num != 0)begin
             $display("+------------------------+");
             $display("| T E S T    F A I L E D |");
             $display("+------------------------+");

        end else begin
              $display("+------------------------+");
              $display("| T E S T    P A S S E D |");
              $display("+------------------------+");

        end
    end

endmodule

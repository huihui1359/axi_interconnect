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
  axi_stage6_arbiter_bindings stage6_arbiter_bindings();

  initial begin : validate_build_configuration
    if ((AXI_DATA_WIDTH == 0) || ((AXI_DATA_WIDTH % 8) != 0))
      $fatal(1, "AXI_DATA_WIDTH must be a positive multiple of 8");
    if (AXI_S_ID_WIDTH != (AXI_CID_WIDTH + AXI_M_ID_WIDTH))
      $fatal(1, "AXI_S_ID_WIDTH must equal AXI_CID_WIDTH + AXI_M_ID_WIDTH");
    if ((AXI_NUM_MASTERS != 3) || (AXI_NUM_SLAVES != 3))
      $fatal(1, "Current interconnect RTL requires a 3x3 topology");
    if ((AXI_M_ID_WIDTH != 4) || (AXI_CID_WIDTH != 4) ||
        (AXI_LEN_WIDTH != 4))
      $fatal(1, "Current interconnect RTL requires MID/CID/LEN widths of 4");
  end

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
  ) m_if[AXI_NUM_MASTERS] (
    .ACLK   (clk),
    .ARESETn(rst_n)
  );

  axi_if #(
    .ADDR_WIDTH(AXI_ADDR_WIDTH),
    .DATA_WIDTH(AXI_DATA_WIDTH),
    .ID_WIDTH  (AXI_S_ID_WIDTH),
    .LEN_WIDTH (AXI_LEN_WIDTH)
  ) s_if[AXI_NUM_SLAVES] (
    .ACLK   (clk),
    .ARESETn(rst_n)
  );

  wire [AXI_M_ID_WIDTH-1:0] M_AXI_AWID[0:AXI_NUM_MASTERS-1];
  wire [AXI_ADDR_WIDTH-1:0] M_AXI_AWADDR[0:AXI_NUM_MASTERS-1];
  wire [AXI_LEN_WIDTH-1:0] M_AXI_AWLEN[0:AXI_NUM_MASTERS-1];
  wire [2:0] M_AXI_AWSIZE[0:AXI_NUM_MASTERS-1];
  wire [1:0] M_AXI_AWBURST[0:AXI_NUM_MASTERS-1];
  wire M_AXI_AWVALID[0:AXI_NUM_MASTERS-1];
  wire M_AXI_AWREADY[0:AXI_NUM_MASTERS-1];

  wire [AXI_M_ID_WIDTH-1:0] M_AXI_WID[0:AXI_NUM_MASTERS-1];
  wire [AXI_DATA_WIDTH-1:0] M_AXI_WDATA[0:AXI_NUM_MASTERS-1];
  wire [AXI_DATA_BYTES-1:0] M_AXI_WSTRB[0:AXI_NUM_MASTERS-1];
  wire M_AXI_WLAST[0:AXI_NUM_MASTERS-1];
  wire M_AXI_WVALID[0:AXI_NUM_MASTERS-1];
  wire M_AXI_WREADY[0:AXI_NUM_MASTERS-1];

  wire [AXI_M_ID_WIDTH-1:0] M_AXI_BID[0:AXI_NUM_MASTERS-1];
  wire [1:0] M_AXI_BRESP[0:AXI_NUM_MASTERS-1];
  wire M_AXI_BVALID[0:AXI_NUM_MASTERS-1];
  wire M_AXI_BREADY[0:AXI_NUM_MASTERS-1];

  wire [AXI_M_ID_WIDTH-1:0] M_AXI_ARID[0:AXI_NUM_MASTERS-1];
  wire [AXI_ADDR_WIDTH-1:0] M_AXI_ARADDR[0:AXI_NUM_MASTERS-1];
  wire [AXI_LEN_WIDTH-1:0] M_AXI_ARLEN[0:AXI_NUM_MASTERS-1];
  wire [2:0] M_AXI_ARSIZE[0:AXI_NUM_MASTERS-1];
  wire [1:0] M_AXI_ARBURST[0:AXI_NUM_MASTERS-1];
  wire M_AXI_ARVALID[0:AXI_NUM_MASTERS-1];
  wire M_AXI_ARREADY[0:AXI_NUM_MASTERS-1];

  wire [AXI_M_ID_WIDTH-1:0] M_AXI_RID[0:AXI_NUM_MASTERS-1];
  wire [AXI_DATA_WIDTH-1:0] M_AXI_RDATA[0:AXI_NUM_MASTERS-1];
  wire [1:0] M_AXI_RRESP[0:AXI_NUM_MASTERS-1];
  wire M_AXI_RLAST[0:AXI_NUM_MASTERS-1];
  wire M_AXI_RVALID[0:AXI_NUM_MASTERS-1];
  wire M_AXI_RREADY[0:AXI_NUM_MASTERS-1];

  wire [AXI_S_ID_WIDTH-1:0] S_AXI_AWID[0:AXI_NUM_SLAVES-1];
  wire [AXI_ADDR_WIDTH-1:0] S_AXI_AWADDR[0:AXI_NUM_SLAVES-1];
  wire [AXI_LEN_WIDTH-1:0] S_AXI_AWLEN[0:AXI_NUM_SLAVES-1];
  wire [2:0] S_AXI_AWSIZE[0:AXI_NUM_SLAVES-1];
  wire [1:0] S_AXI_AWBURST[0:AXI_NUM_SLAVES-1];
  wire S_AXI_AWVALID[0:AXI_NUM_SLAVES-1];
  wire S_AXI_AWREADY[0:AXI_NUM_SLAVES-1];

  wire [AXI_S_ID_WIDTH-1:0] S_AXI_WID[0:AXI_NUM_SLAVES-1];
  wire [AXI_DATA_WIDTH-1:0] S_AXI_WDATA[0:AXI_NUM_SLAVES-1];
  wire [AXI_DATA_BYTES-1:0] S_AXI_WSTRB[0:AXI_NUM_SLAVES-1];
  wire S_AXI_WLAST[0:AXI_NUM_SLAVES-1];
  wire S_AXI_WVALID[0:AXI_NUM_SLAVES-1];
  wire S_AXI_WREADY[0:AXI_NUM_SLAVES-1];

  wire [AXI_S_ID_WIDTH-1:0] S_AXI_BID[0:AXI_NUM_SLAVES-1];
  wire [1:0] S_AXI_BRESP[0:AXI_NUM_SLAVES-1];
  wire S_AXI_BVALID[0:AXI_NUM_SLAVES-1];
  wire S_AXI_BREADY[0:AXI_NUM_SLAVES-1];

  wire [AXI_S_ID_WIDTH-1:0] S_AXI_ARID[0:AXI_NUM_SLAVES-1];
  wire [AXI_ADDR_WIDTH-1:0] S_AXI_ARADDR[0:AXI_NUM_SLAVES-1];
  wire [AXI_LEN_WIDTH-1:0] S_AXI_ARLEN[0:AXI_NUM_SLAVES-1];
  wire [2:0] S_AXI_ARSIZE[0:AXI_NUM_SLAVES-1];
  wire [1:0] S_AXI_ARBURST[0:AXI_NUM_SLAVES-1];
  wire S_AXI_ARVALID[0:AXI_NUM_SLAVES-1];
  wire S_AXI_ARREADY[0:AXI_NUM_SLAVES-1];

  wire [AXI_S_ID_WIDTH-1:0] S_AXI_RID[0:AXI_NUM_SLAVES-1];
  wire [AXI_DATA_WIDTH-1:0] S_AXI_RDATA[0:AXI_NUM_SLAVES-1];
  wire [1:0] S_AXI_RRESP[0:AXI_NUM_SLAVES-1];
  wire S_AXI_RLAST[0:AXI_NUM_SLAVES-1];
  wire S_AXI_RVALID[0:AXI_NUM_SLAVES-1];
  wire S_AXI_RREADY[0:AXI_NUM_SLAVES-1];

  generate
    for (genvar index = 0;
         index < AXI_NUM_MASTERS;
         index++) begin : master_ports
      assign M_AXI_AWID[index] = m_if[index].awid;
      assign M_AXI_AWADDR[index] = m_if[index].awaddr;
      assign M_AXI_AWLEN[index] = m_if[index].awlen;
      assign M_AXI_AWSIZE[index] = m_if[index].awsize;
      assign M_AXI_AWBURST[index] = m_if[index].awburst;
      assign M_AXI_AWVALID[index] = m_if[index].awvalid;
      assign m_if[index].awready = M_AXI_AWREADY[index];
      assign M_AXI_WID[index] = m_if[index].wid;
      assign M_AXI_WDATA[index] = m_if[index].wdata;
      assign M_AXI_WSTRB[index] = m_if[index].wstrb;
      assign M_AXI_WLAST[index] = m_if[index].wlast;
      assign M_AXI_WVALID[index] = m_if[index].wvalid;
      assign m_if[index].wready = M_AXI_WREADY[index];
      assign m_if[index].bid = M_AXI_BID[index];
      assign m_if[index].bresp = M_AXI_BRESP[index];
      assign m_if[index].bvalid = M_AXI_BVALID[index];
      assign M_AXI_BREADY[index] = m_if[index].bready;
      assign M_AXI_ARID[index] = m_if[index].arid;
      assign M_AXI_ARADDR[index] = m_if[index].araddr;
      assign M_AXI_ARLEN[index] = m_if[index].arlen;
      assign M_AXI_ARSIZE[index] = m_if[index].arsize;
      assign M_AXI_ARBURST[index] = m_if[index].arburst;
      assign M_AXI_ARVALID[index] = m_if[index].arvalid;
      assign m_if[index].arready = M_AXI_ARREADY[index];
      assign m_if[index].rid = M_AXI_RID[index];
      assign m_if[index].rdata = M_AXI_RDATA[index];
      assign m_if[index].rresp = M_AXI_RRESP[index];
      assign m_if[index].rlast = M_AXI_RLAST[index];
      assign m_if[index].rvalid = M_AXI_RVALID[index];
      assign M_AXI_RREADY[index] = m_if[index].rready;

      axi_protocol_assertions #(
        .ADDR_WIDTH(AXI_ADDR_WIDTH), .DATA_WIDTH(AXI_DATA_WIDTH),
        .ID_WIDTH(AXI_M_ID_WIDTH), .LEN_WIDTH(AXI_LEN_WIDTH),
        .MAX_OUTSTANDING(4), .STAGE3_CHECKS(1'b1),
        .STAGE6_CHECKS(1'b1), .PORT_INDEX(index), .TB_IS_MASTER(1'b1)
      ) protocol_assertions (
        .ACLK(m_if[index].ACLK), .ARESETn(m_if[index].ARESETn),
        .awid(m_if[index].awid), .awaddr(m_if[index].awaddr),
        .awlen(m_if[index].awlen), .awsize(m_if[index].awsize),
        .awburst(m_if[index].awburst), .awvalid(m_if[index].awvalid),
        .awready(m_if[index].awready), .wid(m_if[index].wid),
        .wdata(m_if[index].wdata), .wstrb(m_if[index].wstrb),
        .wlast(m_if[index].wlast), .wvalid(m_if[index].wvalid),
        .wready(m_if[index].wready), .bid(m_if[index].bid),
        .bresp(m_if[index].bresp), .bvalid(m_if[index].bvalid),
        .bready(m_if[index].bready), .arid(m_if[index].arid),
        .araddr(m_if[index].araddr), .arlen(m_if[index].arlen),
        .arsize(m_if[index].arsize), .arburst(m_if[index].arburst),
        .arvalid(m_if[index].arvalid), .arready(m_if[index].arready),
        .rid(m_if[index].rid), .rdata(m_if[index].rdata),
        .rresp(m_if[index].rresp), .rlast(m_if[index].rlast),
        .rvalid(m_if[index].rvalid), .rready(m_if[index].rready)
      );
    end

    for (genvar index = 0;
         index < AXI_NUM_SLAVES;
         index++) begin : slave_ports
      assign s_if[index].awid = S_AXI_AWID[index];
      assign s_if[index].awaddr = S_AXI_AWADDR[index];
      assign s_if[index].awlen = S_AXI_AWLEN[index];
      assign s_if[index].awsize = S_AXI_AWSIZE[index];
      assign s_if[index].awburst = S_AXI_AWBURST[index];
      assign s_if[index].awvalid = S_AXI_AWVALID[index];
      assign S_AXI_AWREADY[index] = s_if[index].awready;
      assign s_if[index].wid = S_AXI_WID[index];
      assign s_if[index].wdata = S_AXI_WDATA[index];
      assign s_if[index].wstrb = S_AXI_WSTRB[index];
      assign s_if[index].wlast = S_AXI_WLAST[index];
      assign s_if[index].wvalid = S_AXI_WVALID[index];
      assign S_AXI_WREADY[index] = s_if[index].wready;
      assign S_AXI_BID[index] = s_if[index].bid;
      assign S_AXI_BRESP[index] = s_if[index].bresp;
      assign S_AXI_BVALID[index] = s_if[index].bvalid;
      assign s_if[index].bready = S_AXI_BREADY[index];
      assign s_if[index].arid = S_AXI_ARID[index];
      assign s_if[index].araddr = S_AXI_ARADDR[index];
      assign s_if[index].arlen = S_AXI_ARLEN[index];
      assign s_if[index].arsize = S_AXI_ARSIZE[index];
      assign s_if[index].arburst = S_AXI_ARBURST[index];
      assign s_if[index].arvalid = S_AXI_ARVALID[index];
      assign S_AXI_ARREADY[index] = s_if[index].arready;
      assign S_AXI_RID[index] = s_if[index].rid;
      assign S_AXI_RDATA[index] = s_if[index].rdata;
      assign S_AXI_RRESP[index] = s_if[index].rresp;
      assign S_AXI_RLAST[index] = s_if[index].rlast;
      assign S_AXI_RVALID[index] = s_if[index].rvalid;
      assign s_if[index].rready = S_AXI_RREADY[index];

      axi_protocol_assertions #(
        .ADDR_WIDTH(AXI_ADDR_WIDTH), .DATA_WIDTH(AXI_DATA_WIDTH),
        .ID_WIDTH(AXI_S_ID_WIDTH), .LEN_WIDTH(AXI_LEN_WIDTH),
        .MAX_OUTSTANDING(4), .STAGE3_CHECKS(1'b1),
        .STAGE6_CHECKS(1'b1), .PORT_INDEX(index), .TB_IS_MASTER(1'b0)
      ) protocol_assertions (
        .ACLK(s_if[index].ACLK), .ARESETn(s_if[index].ARESETn),
        .awid(s_if[index].awid), .awaddr(s_if[index].awaddr),
        .awlen(s_if[index].awlen), .awsize(s_if[index].awsize),
        .awburst(s_if[index].awburst), .awvalid(s_if[index].awvalid),
        .awready(s_if[index].awready), .wid(s_if[index].wid),
        .wdata(s_if[index].wdata), .wstrb(s_if[index].wstrb),
        .wlast(s_if[index].wlast), .wvalid(s_if[index].wvalid),
        .wready(s_if[index].wready), .bid(s_if[index].bid),
        .bresp(s_if[index].bresp), .bvalid(s_if[index].bvalid),
        .bready(s_if[index].bready), .arid(s_if[index].arid),
        .araddr(s_if[index].araddr), .arlen(s_if[index].arlen),
        .arsize(s_if[index].arsize), .arburst(s_if[index].arburst),
        .arvalid(s_if[index].arvalid), .arready(s_if[index].arready),
        .rid(s_if[index].rid), .rdata(s_if[index].rdata),
        .rresp(s_if[index].rresp), .rlast(s_if[index].rlast),
        .rvalid(s_if[index].rvalid), .rready(s_if[index].rready)
      );
    end
  endgenerate

  axi_interconnect #(
    .WIDTH_CID(AXI_CID_WIDTH),
    .WIDTH_ID (AXI_M_ID_WIDTH),
    .WIDTH_AD (AXI_ADDR_WIDTH),
    .WIDTH_DA (AXI_DATA_WIDTH),
    .WIDTH_DS (AXI_DATA_BYTES),
    .WIDTH_SID(AXI_S_ID_WIDTH)
  ) dut (
    .AXI_RSTn       (m_if[0].ARESETn),
    .AXI_CLK        (m_if[0].ACLK),
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
    env_cfg = axi_env_cfg::type_id::create("env_cfg");
    env_cfg.m_cfg[0].is_active = UVM_ACTIVE;
    env_cfg.m_cfg[0].drv_vif   = m_if[0];
    env_cfg.m_cfg[0].mon_vif   = m_if[0];
    env_cfg.m_cfg[1].is_active = UVM_ACTIVE;
    env_cfg.m_cfg[1].drv_vif   = m_if[1];
    env_cfg.m_cfg[1].mon_vif   = m_if[1];
    env_cfg.m_cfg[2].is_active = UVM_ACTIVE;
    env_cfg.m_cfg[2].drv_vif   = m_if[2];
    env_cfg.m_cfg[2].mon_vif   = m_if[2];
    env_cfg.s_cfg[0].is_active = UVM_ACTIVE;
    env_cfg.s_cfg[0].drv_vif   = s_if[0];
    env_cfg.s_cfg[0].mon_vif   = s_if[0];
    env_cfg.s_cfg[1].is_active = UVM_ACTIVE;
    env_cfg.s_cfg[1].drv_vif   = s_if[1];
    env_cfg.s_cfg[1].mon_vif   = s_if[1];
    env_cfg.s_cfg[2].is_active = UVM_ACTIVE;
    env_cfg.s_cfg[2].drv_vif   = s_if[2];
    env_cfg.s_cfg[2].mon_vif   = s_if[2];

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

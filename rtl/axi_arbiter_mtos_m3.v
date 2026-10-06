
module axi_arbiter_mtos_m3
#(parameter WIDTH_CID = 4
          , WIDTH_ID  = 4
          , WIDTH_SID = (WIDTH_CID+WIDTH_ID)
          , NUM       = 3
          )
(
      input  wire                  ARESETn
    , input  wire                  ACLK

    , input  wire  [NUM-1:0]       AWSELECT  // selected by address decoder
    , input  wire  [NUM-1:0]       AWVALID
    , input  wire  [NUM-1:0]       AWREADY
    , output wire  [NUM-1:0]       AWGRANT

    , input  wire  [NUM-1:0]       WSELECT
    , input  wire  [NUM-1:0]       WVALID
    , input  wire  [NUM-1:0]       WREADY
    , input  wire  [NUM-1:0]       WLAST
    , output wire  [NUM-1:0]       WGRANT

    , input  wire  [NUM-1:0]       ARSELECT  // selected by address decoder
    , input  wire  [NUM-1:0]       ARVALID
    , input  wire  [NUM-1:0]       ARREADY
    , output wire  [NUM-1:0]       ARGRANT
);


//-----------------------------------------------------------
// read-address arbiter
//-----------------------------------------------------------
wire [2:0] ARREQ;
wire       ARACCEPT;
assign ARREQ = ARSELECT & ARVALID;
assign ARACCEPT = |(ARGRANT & ARVALID & ARREADY);

round_robin_m2s u_arbiter_ar(
.clk    (ACLK   ),
.rst_n  (ARESETn),
.req    (ARREQ  ),
.accept (ARACCEPT),
.sel    (ARGRANT)
);

//-----------------------------------------------------------
// write-address arbiter
//-----------------------------------------------------------
wire [2:0] AWREQ;
wire       AWACCEPT;
assign AWREQ = AWSELECT & AWVALID;
assign AWACCEPT = |(AWGRANT & AWVALID & AWREADY);

round_robin_m2s u_arbiter_aw(
.clk    (ACLK   ),
.rst_n  (ARESETn),
.req    (AWREQ  ),
.accept (AWACCEPT),
.sel    (AWGRANT)
);

//-----------------------------------------------------------
// write-data arbiter
//-----------------------------------------------------------
wire [2:0] WREQ;
wire       WACCEPT;

assign WREQ = WSELECT & WVALID;
assign WACCEPT = |(WGRANT & WVALID & WREADY);

round_robin_m2s u_arbiter_w(
.clk    (ACLK   ),
.rst_n  (ARESETn),
.req    (WREQ  ),
.accept (WACCEPT),
.sel    (WGRANT)
);

endmodule

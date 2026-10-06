//---------------------------------------------------------------------------
module axi_arbiter_stom_s3
#(parameter NUM=3)
(
  input  wire           ARESETn
, input  wire           ACLK

, input  wire  [NUM:0]  BSELECT  // selected by comparing trans_id
, input  wire  [NUM:0]  BVALID
, input  wire  [NUM:0]  BREADY
, output wire  [NUM:0]  BGRANT

, input  wire  [NUM:0]  RSELECT  // selected by comparing trans_id
, input  wire  [NUM:0]  RVALID
, input  wire  [NUM:0]  RREADY
, input  wire  [NUM:0]  RLAST
, output wire  [NUM:0]  RGRANT
);

//-----------------------------------------------------------
// read-data arbiter
//-----------------------------------------------------------
//-----------------------------------------------------------
wire [3:0] RREQ;
wire       RACCEPT;
assign RREQ = RSELECT & RVALID;
assign RACCEPT = |(RGRANT & RVALID & RREADY);

round_robin_s2m u_arbiter_r(
.clk    (ACLK   ),
.rst_n  (ARESETn),
.req    (RREQ  ),
.accept (RACCEPT),
.sel    (RGRANT)
);

//-----------------------------------------------------------
// write-response arbiter
//-----------------------------------------------------------
wire [3:0] BREQ;
wire       BACCEPT;
assign BREQ = BSELECT & BVALID;
assign BACCEPT = |(BGRANT & BVALID & BREADY);

round_robin_s2m u_arbiter_b(
.clk    (ACLK   ),
.rst_n  (ARESETn),
.req    (BREQ  ),
.accept (BACCEPT),
.sel    (BGRANT)
);

endmodule

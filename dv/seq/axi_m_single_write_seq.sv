`ifndef AXI_M_SINGLE_WRITE_SEQ_SV
`define AXI_M_SINGLE_WRITE_SEQ_SV

class axi_m_single_write_seq #(
  int unsigned ADDR_WIDTH = AXI_ADDR_WIDTH,
  int unsigned DATA_WIDTH = AXI_DATA_WIDTH,
  int unsigned ID_WIDTH   = AXI_M_ID_WIDTH,
  int unsigned LEN_WIDTH  = AXI_LEN_WIDTH
) extends uvm_sequence #(
  axi_req_item #(ADDR_WIDTH, DATA_WIDTH, ID_WIDTH, LEN_WIDTH),
  axi_rsp_item #(DATA_WIDTH, ID_WIDTH, LEN_WIDTH)
);

  localparam int unsigned DATA_BYTES = DATA_WIDTH / 8;
  typedef axi_req_item #(
    ADDR_WIDTH, DATA_WIDTH, ID_WIDTH, LEN_WIDTH
  ) req_t;

  bit [ID_WIDTH-1:0] id;
  bit [ADDR_WIDTH-1:0] addr;
  bit [2:0] size;
  axi_burst_e burst;
  bit [DATA_WIDTH-1:0] data;
  bit [DATA_BYTES-1:0] strb;

  `uvm_object_param_utils(
    axi_m_single_write_seq #(ADDR_WIDTH, DATA_WIDTH, ID_WIDTH, LEN_WIDTH)
  )

  function new(string name = "axi_m_single_write_seq");
    super.new(name);
    id    = '0;
    addr  = '0;
    size  = $clog2(DATA_BYTES);
    burst = AXI_BURST_INCR;
    data  = '0;
    strb  = '1;
  endfunction

  virtual task body();
    req_t req;
    req = req_t::type_id::create("req");
    start_item(req);
    req.dir           = AXI_WRITE;
    req.id            = id;
    req.addr          = addr;
    req.len           = '0;
    req.size          = size;
    req.burst         = burst;
    req.addr_delay    = 0;
    req.w_start_delay = 0;
    req.wdata         = new[1];
    req.wstrb         = new[1];
    req.wbeat_gap     = new[1];
    req.wdata[0]      = data;
    req.wstrb[0]      = strb;
    req.wbeat_gap[0]  = 0;
    finish_item(req);
  endtask

endclass

`endif

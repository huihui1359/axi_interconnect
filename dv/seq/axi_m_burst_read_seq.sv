`ifndef AXI_M_BURST_READ_SEQ_SV
`define AXI_M_BURST_READ_SEQ_SV

class axi_m_burst_read_seq #(
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
  bit [LEN_WIDTH-1:0] len;
  bit [2:0] size;
  axi_burst_e burst;

  latency_gen addr_latency;

  `uvm_object_param_utils(
    axi_m_burst_read_seq #(ADDR_WIDTH, DATA_WIDTH, ID_WIDTH, LEN_WIDTH)
  )

  extern function new(string name = "axi_m_burst_read_seq");
  extern virtual task body();

endclass

function axi_m_burst_read_seq::new(
  string name = "axi_m_burst_read_seq"
);
  super.new(name);
  id           = '0;
  addr         = '0;
  len          = '0;
  size         = $clog2(DATA_BYTES);
  burst        = AXI_BURST_INCR;
  addr_latency = latency_gen::type_id::create("addr_latency");
endfunction

task axi_m_burst_read_seq::body();
  req_t req;
  req = req_t::type_id::create("req");
  start_item(req);

  if (!req.randomize() with {
    dir   == AXI_READ;
    id    == local::id;
    addr  == local::addr;
    len   == local::len;
    size  == local::size;
    burst == local::burst;
  })
    `uvm_fatal("AXI_M_READ_SEQ", "Failed to randomize read request")

  if (!addr_latency.randomize())
    `uvm_fatal("AXI_M_READ_ADDR_LATENCY",
               "Failed to randomize address latency")
  req.addr_delay = addr_latency.get_delay();

  finish_item(req);
endtask

`endif

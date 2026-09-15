`ifndef AXI_M_BURST_WRITE_SEQ_SV
`define AXI_M_BURST_WRITE_SEQ_SV

class axi_m_burst_write_seq #(
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
  bit [DATA_WIDTH-1:0] data_base;
  bit [DATA_WIDTH-1:0] write_data[];
  bit [DATA_BYTES-1:0] write_strb[];

  latency_gen addr_latency;
  latency_gen w_start_latency;
  latency_gen w_gap_latency;

  `uvm_object_param_utils(
    axi_m_burst_write_seq #(ADDR_WIDTH, DATA_WIDTH, ID_WIDTH, LEN_WIDTH)
  )

  extern function new(string name = "axi_m_burst_write_seq");
  extern virtual task body();

endclass

function axi_m_burst_write_seq::new(
  string name = "axi_m_burst_write_seq"
);
  super.new(name);
  id              = '0;
  addr            = '0;
  len             = '0;
  size            = $clog2(DATA_BYTES);
  burst           = AXI_BURST_INCR;
  data_base       = '0;
  write_data      = new[0];
  write_strb      = new[0];
  addr_latency    = latency_gen::type_id::create("addr_latency");
  w_start_latency = latency_gen::type_id::create("w_start_latency");
  w_gap_latency   = latency_gen::type_id::create("w_gap_latency");
endfunction

task axi_m_burst_write_seq::body();
  req_t req;
  req = req_t::type_id::create("req");
  start_item(req);

  if (!req.randomize() with {
    dir   == AXI_WRITE;
    id    == local::id;
    addr  == local::addr;
    len   == local::len;
    size  == local::size;
    burst == local::burst;
  })
    `uvm_fatal("AXI_M_WRITE_SEQ", "Failed to randomize write request")

  if ((write_data.size() != 0) &&
      (write_data.size() != (int'(len) + 1)))
    `uvm_fatal("AXI_M_WRITE_SEQ",
               "write_data length must equal len+1")
  if ((write_strb.size() != 0) &&
      (write_strb.size() != (int'(len) + 1)))
    `uvm_fatal("AXI_M_WRITE_SEQ",
               "write_strb length must equal len+1")

  foreach (req.wdata[index]) begin
    if (write_data.size() != 0)
      req.wdata[index] = write_data[index];
    else
      req.wdata[index] = data_base + index;

    if (write_strb.size() != 0)
      req.wstrb[index] = write_strb[index];
  end

  if (!addr_latency.randomize())
    `uvm_fatal("AXI_M_WRITE_ADDR_LATENCY",
               "Failed to randomize address latency")
  req.addr_delay = addr_latency.get_delay();

  if (!w_start_latency.randomize())
    `uvm_fatal("AXI_M_WRITE_START_LATENCY",
               "Failed to randomize W start latency")
  req.w_start_delay = w_start_latency.get_delay();

  foreach (req.wbeat_gap[index]) begin
    if (!w_gap_latency.randomize())
      `uvm_fatal("AXI_M_WRITE_GAP_LATENCY", $sformatf(
        "Failed to randomize W gap for beat %0d", index))
    req.wbeat_gap[index] = w_gap_latency.get_delay();
  end

  finish_item(req);
endtask

`endif

`ifndef AXI_CHANNEL_EVENT_SV
`define AXI_CHANNEL_EVENT_SV

class axi_channel_event #(
  int unsigned ADDR_WIDTH = AXI_ADDR_WIDTH,
  int unsigned DATA_WIDTH = AXI_DATA_WIDTH,
  int unsigned ID_WIDTH   = AXI_ID_WIDTH,
  int unsigned LEN_WIDTH  = AXI_LEN_WIDTH
) extends uvm_object;

  localparam int unsigned DATA_BYTES = DATA_WIDTH / 8;

  axi_channel_e                 channel;
  axi_side_e                    side;
  int unsigned                  port_index;
  longint unsigned              sample_cycle;

  logic [ID_WIDTH-1:0]          id;
  logic [ADDR_WIDTH-1:0]        addr;
  logic [LEN_WIDTH-1:0]         len;
  logic [2:0]                   size;
  logic [1:0]                   burst_raw;
  logic [DATA_WIDTH-1:0]        data;
  logic [DATA_BYTES-1:0]        strb;
  logic [1:0]                   resp_raw;
  logic                         last;

  `uvm_object_param_utils_begin(
    axi_channel_event #(ADDR_WIDTH, DATA_WIDTH, ID_WIDTH, LEN_WIDTH)
  )
    `uvm_field_enum(axi_channel_e, channel, UVM_DEFAULT)
    `uvm_field_enum(axi_side_e, side, UVM_DEFAULT)
    `uvm_field_int(port_index, UVM_DEFAULT)
    `uvm_field_int(sample_cycle, UVM_DEFAULT)
    `uvm_field_int(id, UVM_DEFAULT)
    `uvm_field_int(addr, UVM_DEFAULT)
    `uvm_field_int(len, UVM_DEFAULT)
    `uvm_field_int(size, UVM_DEFAULT)
    `uvm_field_int(burst_raw, UVM_DEFAULT)
    `uvm_field_int(data, UVM_DEFAULT)
    `uvm_field_int(strb, UVM_DEFAULT)
    `uvm_field_int(resp_raw, UVM_DEFAULT)
    `uvm_field_int(last, UVM_DEFAULT)
  `uvm_object_utils_end

  extern function new(string name = "axi_channel_event");
  extern function void clear_payload();
  extern function bit payload_equal(
    axi_channel_event #(ADDR_WIDTH, DATA_WIDTH, ID_WIDTH, LEN_WIDTH) rhs,
    bit compare_location = 1'b1
  );
  extern function string convert2string();

endclass

function axi_channel_event::new(string name = "axi_channel_event");
  super.new(name);
  clear_payload();
  channel      = AXI_CHANNEL_AW;
  side         = AXI_UPSTREAM;
  port_index   = 0;
  sample_cycle = 0;
endfunction

function void axi_channel_event::clear_payload();
  id        = '0;
  addr      = '0;
  len       = '0;
  size      = '0;
  burst_raw = '0;
  data      = '0;
  strb      = '0;
  resp_raw  = '0;
  last      = '0;
endfunction

function bit axi_channel_event::payload_equal(
  axi_channel_event #(ADDR_WIDTH, DATA_WIDTH, ID_WIDTH, LEN_WIDTH) rhs,
  bit compare_location = 1'b1
);
  if (rhs == null)
    return 1'b0;

  if ((channel != rhs.channel) || (side != rhs.side))
    return 1'b0;

  if (compare_location && (port_index != rhs.port_index))
    return 1'b0;

  case (channel)
    AXI_CHANNEL_AW,
    AXI_CHANNEL_AR: return ((id        === rhs.id)        &&
                            (addr      === rhs.addr)      &&
                            (len       === rhs.len)       &&
                            (size      === rhs.size)      &&
                            (burst_raw === rhs.burst_raw));

    AXI_CHANNEL_W:  return ((id   === rhs.id)   &&
                            (data === rhs.data) &&
                            (strb === rhs.strb) &&
                            (last === rhs.last));

    AXI_CHANNEL_B:  return ((id       === rhs.id) &&
                            (resp_raw === rhs.resp_raw));

    AXI_CHANNEL_R:  return ((id       === rhs.id)       &&
                            (data     === rhs.data)     &&
                            (resp_raw === rhs.resp_raw) &&
                            (last     === rhs.last));

    default: return 1'b0;
  endcase
endfunction

function string axi_channel_event::convert2string();
  return $sformatf(
    "side=%s port=%0d channel=%s cycle=%0d id=0x%0h addr=0x%0h len=%0d size=%0d burst=0x%0h data=0x%0h strb=0x%0h resp=0x%0h last=%0b",
    side.name(), port_index, channel.name(), sample_cycle, id, addr,
    len, size, burst_raw, data, strb, resp_raw, last
  );
endfunction

`endif

`ifndef AXI_REQ_ITEM_SV
`define AXI_REQ_ITEM_SV

class axi_req_item #(
  int unsigned ADDR_WIDTH = AXI_ADDR_WIDTH,
  int unsigned DATA_WIDTH = AXI_DATA_WIDTH,
  int unsigned ID_WIDTH   = AXI_ID_WIDTH,
  int unsigned LEN_WIDTH  = AXI_LEN_WIDTH
) extends uvm_sequence_item;

  localparam int unsigned DATA_BYTES = DATA_WIDTH / 8;
  localparam int unsigned MAX_SIZE   = $clog2(DATA_BYTES);

  // One item represents one complete read or write request burst.
  rand axi_dir_e                  dir;
  rand bit [ID_WIDTH-1:0]         id;
  rand bit [ADDR_WIDTH-1:0]       addr;
  rand bit [LEN_WIDTH-1:0]        len;
  rand bit [2:0]                  size;
  rand axi_burst_e                burst;

  // Write payload. WID is derived from id and WLAST from len.
  rand bit [DATA_WIDTH-1:0]       wdata[];
  rand bit [DATA_BYTES-1:0]       wstrb[];

  // Timing intent. The driver owns VALID/READY protocol behavior.
  rand int unsigned               addr_delay;
  rand int unsigned               w_start_delay;
  rand int unsigned               wbeat_gap[];

  `uvm_object_param_utils_begin(
    axi_req_item #(ADDR_WIDTH, DATA_WIDTH, ID_WIDTH, LEN_WIDTH)
  )
    `uvm_field_enum(axi_dir_e, dir, UVM_DEFAULT)
    `uvm_field_int(id, UVM_DEFAULT)
    `uvm_field_int(addr, UVM_DEFAULT)
    `uvm_field_int(len, UVM_DEFAULT)
    `uvm_field_int(size, UVM_DEFAULT)
    `uvm_field_enum(axi_burst_e, burst, UVM_DEFAULT)
    `uvm_field_array_int(wdata, UVM_DEFAULT)
    `uvm_field_array_int(wstrb, UVM_DEFAULT)
    `uvm_field_int(addr_delay, UVM_DEFAULT)
    `uvm_field_int(w_start_delay, UVM_DEFAULT)
    `uvm_field_array_int(wbeat_gap, UVM_DEFAULT)
  `uvm_object_utils_end

  constraint c_legal_attributes {
    size inside {[0:MAX_SIZE]};
    burst inside {AXI_BURST_FIXED, AXI_BURST_INCR, AXI_BURST_WRAP};
  }

  constraint c_wrap {
    if (burst == AXI_BURST_WRAP) {
      len inside {1, 3, 7, 15};
      (addr & ((1 << size) - 1)) == 0;
    }
  }

  constraint c_payload_size {
    if (dir == AXI_WRITE) {
      wdata.size() == int'(len) + 1;
      wstrb.size() == int'(len) + 1;
      wbeat_gap.size() == int'(len) + 1;
    }
    else {
      wdata.size() == 0;
      wstrb.size() == 0;
      wbeat_gap.size() == 0;
    }
  }

  constraint c_wstrb {
    if (dir == AXI_WRITE) {
      foreach (wstrb[i])
        (wstrb[i] & ~calc_legal_wstrb_mask(i)) == '0;
    }
  }

//TODO:自增的起始地址没有要求，INCR模式下自增，不用减去偏移量？？
  // FIXED and legal WRAP bursts cannot cross 4 KB with this AXI subset.
  constraint c_4kb {
    if (burst == AXI_BURST_INCR) {
      ((int'(addr[11:0]) -
        (int'(addr[11:0]) % (1 << size))) +
       ((int'(len) + 1) * (1 << size))) <= 4096;
    }
  }

  constraint c_solve_order {
    solve dir before wdata;
    solve dir before wstrb;
    solve dir before wbeat_gap;
    solve burst before len;
    solve size before addr;
    solve burst before addr;
    solve len before addr;
    solve addr before wstrb;
    solve len before wstrb;
    solve size before wstrb;
    solve burst before wstrb;
  }

  constraint c_default_distribution {
    dir dist {
      AXI_READ  := 1,
      AXI_WRITE := 1
    };

    burst dist {
      AXI_BURST_FIXED := 2,
      AXI_BURST_INCR  := 6,
      AXI_BURST_WRAP  := 2
    };

    len dist {
      0      :/ 20,
      [1:3]  :/ 25,
      [4:7]  :/ 20,
      [8:14] :/ 20,
      15     :/ 15
    };

    size dist {
      0 := 2,
      1 := 3,
      2 := 5
    };

    addr_delay dist {
      0      :/ 50,
      [1:3]  :/ 35,
      [4:15] :/ 15
    };

    w_start_delay dist {
      0      :/ 50,
      [1:3]  :/ 35,
      [4:15] :/ 15
    };

    foreach (wbeat_gap[i])
      wbeat_gap[i] dist {
        0      :/ 70,
        [1:3]  :/ 25,
        [4:10] :/ 5
      };
  }

  function new(string name = "axi_req_item");
    super.new(name);

    if ((DATA_WIDTH == 0) || ((DATA_WIDTH % 8) != 0))
      `uvm_fatal("AXI_REQ_PARAM", "DATA_WIDTH must be a non-zero multiple of 8")

    if ((DATA_BYTES & (DATA_BYTES - 1)) != 0)
      `uvm_fatal("AXI_REQ_PARAM", "DATA_BYTES must be a power of two")

    if ((ADDR_WIDTH == 0) || (ID_WIDTH == 0) || (LEN_WIDTH == 0))
      `uvm_fatal("AXI_REQ_PARAM", "ADDR/ID/LEN widths must be non-zero")
  endfunction

//TODO:这个函数有必要嘛？
  function int unsigned beat_count();
    return int'(len) + 1;
  endfunction

//TODO:这个函数是计算watrb，当首地址没有对齐的时候，掩码肯定要把没对齐的那部分置零，对齐之后呢？这个wstrb函数的逻辑是什么？我不需要额外把首地址传递进来嘛？
  // Required by c_wstrb; not an interface protocol checker.
  local function automatic bit [DATA_BYTES-1:0] calc_legal_wstrb_mask(
    int unsigned beat_index
  );
    bit [DATA_BYTES-1:0] mask;
    longint unsigned     bytes;
    longint unsigned     beats;
    longint unsigned     start_v;
    longint unsigned     aligned_start;
    longint unsigned     wrap_bytes;
    longint unsigned     wrap_base;
    longint unsigned     beat_addr_v;
    longint unsigned     aligned_beat;
    longint unsigned     last_byte;
    longint unsigned     byte_addr_v;

    mask          = '0;
    bytes         = 64'd1 << size;
    beats         = longint'(len) + 1;
    start_v       = longint'(addr);
    aligned_start = (start_v / bytes) * bytes;
    beat_addr_v   = start_v;

    case (burst)
      AXI_BURST_FIXED: beat_addr_v = start_v;

      AXI_BURST_INCR: begin
        if (beat_index != 0)
          beat_addr_v = aligned_start + (longint'(beat_index) * bytes);
      end

      AXI_BURST_WRAP: begin
        wrap_bytes = beats * bytes;
        wrap_base  = (start_v / wrap_bytes) * wrap_bytes;
        beat_addr_v = start_v + (longint'(beat_index) * bytes);
        beat_addr_v = wrap_base + ((beat_addr_v - wrap_base) % wrap_bytes);
      end

      default: beat_addr_v = start_v;
    endcase

    aligned_beat = (beat_addr_v / bytes) * bytes;
    last_byte    = aligned_beat + bytes - 1;

    for (int unsigned offset = 0; offset < DATA_BYTES; offset++) begin
      byte_addr_v = beat_addr_v + offset;
      if (byte_addr_v <= last_byte)
        mask[byte_addr_v % DATA_BYTES] = 1'b1;
    end

    return mask;
  endfunction
//TODO:这个函数是用来打印信息的吗？直接用uvm_info来打印信息
  function string convert2string();
    return $sformatf(
      "dir=%s id=0x%0h addr=0x%0h len=%0d beats=%0d size=%0d burst=%s",
      dir.name(), id, addr, len, beat_count(), size, burst.name()
    );
  endfunction

endclass

`endif

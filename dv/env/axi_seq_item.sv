`ifndef AXI_SEQ_ITEM_SV
`define AXI_SEQ_ITEM_SV

import uvm_pkg::*;
`include "uvm_macros.svh"

import axi_types_pkg::*;

class axi_seq_item #(
  int unsigned ADDR_WIDTH = AXI_ADDR_WIDTH,
  int unsigned DATA_WIDTH = AXI_DATA_WIDTH,
  int unsigned ID_WIDTH   = AXI_ID_WIDTH,
  int unsigned LEN_WIDTH  = AXI_LEN_WIDTH
) extends uvm_sequence_item;

  localparam int unsigned DATA_BYTES = DATA_WIDTH / 8;
  localparam int unsigned MAX_SIZE   = $clog2(DATA_BYTES);

  // One item represents one complete read or write burst on one Master port.
  rand axi_dir_e                  dir;
  rand bit [ID_WIDTH-1:0]         id;
  rand bit [ADDR_WIDTH-1:0]       addr;
  rand bit [LEN_WIDTH-1:0]        len;
  rand bit [2:0]                  size;
  rand axi_burst_e                burst;

  // Write payload. Normal WID is derived from id and WLAST from len.
  rand bit [DATA_WIDTH-1:0]       wdata[];
  rand bit [DATA_BYTES-1:0]       wstrb[];

  // Timing intent. The driver owns VALID/READY protocol behavior.
  rand int unsigned               addr_delay;
  rand int unsigned               w_start_delay;
  rand int unsigned               wbeat_gap[];

  // Generation hints. The reference model must derive routing from addr.
  rand axi_region_e               addr_region;
  rand axi_data_pattern_e         data_pattern;

  // Negative-test controls. Set these before randomize().
  bit                             allow_unaligned  = 1'b1;
  bit                             force_4k_cross   = 1'b0;
  bit                             allow_zero_wstrb = 1'b0;

  // Optional response storage. These fields are not randomized stimulus.
  bit [DATA_WIDTH-1:0]            rdata[];
  bit [1:0]                       rresp[];
  axi_resp_e                      bresp = AXI_RESP_OKAY;

  // Debug metadata. The creating sequence/agent assigns these when needed.
  longint unsigned                txn_uid   = 0;
  int                             port_index = -1;

  `uvm_object_param_utils_begin(
    axi_seq_item #(ADDR_WIDTH, DATA_WIDTH, ID_WIDTH, LEN_WIDTH)
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
    `uvm_field_enum(axi_region_e, addr_region, UVM_DEFAULT | UVM_NOCOMPARE)
    `uvm_field_enum(axi_data_pattern_e, data_pattern, UVM_DEFAULT)
    `uvm_field_int(allow_unaligned, UVM_DEFAULT | UVM_NOCOMPARE)
    `uvm_field_int(force_4k_cross, UVM_DEFAULT | UVM_NOCOMPARE)
    `uvm_field_int(allow_zero_wstrb, UVM_DEFAULT | UVM_NOCOMPARE)
    `uvm_field_array_int(rdata, UVM_DEFAULT)
    `uvm_field_array_int(rresp, UVM_DEFAULT)
    `uvm_field_enum(axi_resp_e, bresp, UVM_DEFAULT)
    `uvm_field_int(txn_uid, UVM_DEFAULT | UVM_NOCOMPARE)
    `uvm_field_int(port_index, UVM_DEFAULT | UVM_NOCOMPARE)
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

  constraint c_optional_alignment {
    if (!allow_unaligned)
      (addr & ((1 << size) - 1)) == 0;
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
      foreach (wstrb[i]) {
        (wstrb[i] & ~calc_legal_wstrb_mask(
          addr, len, size, burst, i
        )) == '0;

        if (!allow_zero_wstrb)
          wstrb[i] != '0;
      }
    }
  }

  constraint c_4kb {
    if (force_4k_cross) {
      burst == AXI_BURST_INCR;
      ((int'(addr[11:0]) -
        (int'(addr[11:0]) % (1 << size))) +
       ((int'(len) + 1) * (1 << size))) > 4096;
    }
    else if (burst == AXI_BURST_INCR) {
      ((int'(addr[11:0]) -
        (int'(addr[11:0]) % (1 << size))) +
       ((int'(len) + 1) * (1 << size))) <= 4096;
    }
  }

  constraint c_solve_order {
    solve dir before wdata;
    solve dir before wstrb;
    solve dir before wbeat_gap;
    solve dir before data_pattern;
    solve burst before len;
    solve addr_region before addr;
    solve size before addr;
    solve burst before addr;
    solve len before addr;
    solve addr before wstrb;
    solve len before wstrb;
    solve size before wstrb;
    solve burst before wstrb;
  }

  constraint c_address_region {
    if (addr_region == AXI_REGION_S0)
      addr inside {[32'h0000_0000:32'h0000_0fff]};
    else if (addr_region == AXI_REGION_S1)
      addr inside {[32'h0000_2000:32'h0000_2fff]};
    else if (addr_region == AXI_REGION_S2)
      addr inside {[32'h0000_4000:32'h0000_4fff]};
    else
      !(addr inside {
        [32'h0000_0000:32'h0000_0fff],
        [32'h0000_2000:32'h0000_2fff],
        [32'h0000_4000:32'h0000_4fff]
      });
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

    addr_region dist {
      AXI_REGION_S0      := 3,
      AXI_REGION_S1      := 3,
      AXI_REGION_S2      := 3,
      AXI_REGION_DEFAULT := 1
    };

    data_pattern dist {
      AXI_DATA_RANDOM      := 12,
      AXI_DATA_ZERO        := 1,
      AXI_DATA_ONES        := 1,
      AXI_DATA_WALKING_ONE := 2,
      AXI_DATA_ADDRESS     := 2
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

  constraint c_read_data_pattern {
    if (dir == AXI_READ)
      data_pattern == AXI_DATA_RANDOM;
  }

  function new(string name = "axi_seq_item");
    super.new(name);

    if ((DATA_WIDTH == 0) || ((DATA_WIDTH % 8) != 0))
      `uvm_fatal("AXI_ITEM_PARAM", "DATA_WIDTH must be a non-zero multiple of 8")

    if ((DATA_BYTES & (DATA_BYTES - 1)) != 0)
      `uvm_fatal("AXI_ITEM_PARAM", "DATA_BYTES must be a power of two")

    if ((ADDR_WIDTH == 0) || (ID_WIDTH == 0) || (LEN_WIDTH == 0))
      `uvm_fatal("AXI_ITEM_PARAM", "ADDR/ID/LEN widths must be non-zero")
  endfunction

  function int unsigned beat_count();
    return int'(len) + 1;
  endfunction

  function int unsigned bytes_per_beat();
    return 1 << size;
  endfunction

  function bit [ADDR_WIDTH-1:0] beat_address(int unsigned beat_index);
    return calc_beat_address(addr, len, size, burst, beat_index);
  endfunction

  function bit [DATA_BYTES-1:0] legal_wstrb_mask(
    int unsigned beat_index
  );
    return calc_legal_wstrb_mask(addr, len, size, burst, beat_index);
  endfunction

  function bit burst_is_4k_legal();
    return calc_burst_is_4k_legal(addr, len, size, burst);
  endfunction

  function automatic bit calc_address_is_aligned(
    bit [ADDR_WIDTH-1:0] start_addr,
    bit [2:0]            size_i
  );
    longint unsigned bytes;

    bytes = 64'd1 << size_i;
    return ((longint'(start_addr) % bytes) == 0);
  endfunction

  function automatic bit [ADDR_WIDTH-1:0] calc_beat_address(
    bit [ADDR_WIDTH-1:0] start_addr,
    bit [LEN_WIDTH-1:0]  len_i,
    bit [2:0]            size_i,
    axi_burst_e          burst_i,
    int unsigned         beat_index
  );
    longint unsigned bytes;
    longint unsigned beats;
    longint unsigned start_v;
    longint unsigned aligned_start;
    longint unsigned wrap_bytes;
    longint unsigned wrap_base;
    longint unsigned address_v;

    bytes         = 64'd1 << size_i;
    beats         = longint'(len_i) + 1;
    start_v       = longint'(start_addr);
    aligned_start = (start_v / bytes) * bytes;
    address_v     = start_v;

    case (burst_i)
      AXI_BURST_FIXED: begin
        address_v = start_v;
      end

      AXI_BURST_INCR: begin
        if (beat_index == 0)
          address_v = start_v;
        else
          address_v = aligned_start + (longint'(beat_index) * bytes);
      end

      AXI_BURST_WRAP: begin
        wrap_bytes = beats * bytes;
        wrap_base  = (start_v / wrap_bytes) * wrap_bytes;
        address_v  = start_v + (longint'(beat_index) * bytes);
        address_v  = wrap_base + ((address_v - wrap_base) % wrap_bytes);
      end

      default: begin
        address_v = start_v;
      end
    endcase

    return address_v[ADDR_WIDTH-1:0];
  endfunction

  function automatic bit [DATA_BYTES-1:0] calc_legal_wstrb_mask(
    bit [ADDR_WIDTH-1:0] start_addr,
    bit [LEN_WIDTH-1:0]  len_i,
    bit [2:0]            size_i,
    axi_burst_e          burst_i,
    int unsigned         beat_index
  );
    bit [DATA_BYTES-1:0] mask;
    longint unsigned     bytes;
    longint unsigned     beat_addr_v;
    longint unsigned     aligned_beat;
    longint unsigned     first_byte;
    longint unsigned     last_byte;
    longint unsigned     byte_addr_v;

    mask         = '0;
    bytes        = 64'd1 << size_i;
    beat_addr_v  = longint'(calc_beat_address(
      start_addr, len_i, size_i, burst_i, beat_index
    ));
    aligned_beat = (beat_addr_v / bytes) * bytes;
    first_byte   = beat_addr_v;
    last_byte    = aligned_beat + bytes - 1;

    for (int unsigned offset = 0; offset < DATA_BYTES; offset++) begin
      byte_addr_v = first_byte + offset;
      if (byte_addr_v <= last_byte)
        mask[byte_addr_v % DATA_BYTES] = 1'b1;
    end

    return mask;
  endfunction

  function automatic bit calc_burst_is_4k_legal(
    bit [ADDR_WIDTH-1:0] start_addr,
    bit [LEN_WIDTH-1:0]  len_i,
    bit [2:0]            size_i,
    axi_burst_e          burst_i
  );
    longint unsigned bytes;
    longint unsigned beats;
    longint unsigned start_v;
    longint unsigned aligned_start;
    longint unsigned wrap_bytes;
    longint unsigned region_start;
    longint unsigned last_byte;

    bytes         = 64'd1 << size_i;
    beats         = longint'(len_i) + 1;
    start_v       = longint'(start_addr);
    aligned_start = (start_v / bytes) * bytes;
    region_start  = start_v;
    last_byte     = start_v;

    case (burst_i)
      AXI_BURST_FIXED: begin
        region_start = start_v;
        last_byte    = aligned_start + bytes - 1;
      end

      AXI_BURST_INCR: begin
        region_start = aligned_start;
        last_byte    = aligned_start + (beats * bytes) - 1;
      end

      AXI_BURST_WRAP: begin
        wrap_bytes   = beats * bytes;
        region_start = (start_v / wrap_bytes) * wrap_bytes;
        last_byte    = region_start + wrap_bytes - 1;
      end

      default: return 1'b0;
    endcase

    return ((region_start >> 12) == (last_byte >> 12));
  endfunction

  function void post_randomize();
    if (dir != AXI_WRITE)
      return;

    case (data_pattern)
      AXI_DATA_ZERO: begin
        foreach (wdata[i])
          wdata[i] = '0;
      end

      AXI_DATA_ONES: begin
        foreach (wdata[i])
          wdata[i] = '1;
      end

      AXI_DATA_WALKING_ONE: begin
        foreach (wdata[i]) begin
          wdata[i] = '0;
          wdata[i][i % DATA_WIDTH] = 1'b1;
        end
      end

      AXI_DATA_ADDRESS: begin
        foreach (wdata[i])
          wdata[i] = beat_address(i);
      end

      default: begin
        // AXI_DATA_RANDOM retains the solver-generated wdata values.
      end
    endcase
  endfunction

  function string convert2string();
    return $sformatf(
      "dir=%s id=0x%0h addr=0x%0h len=%0d beats=%0d size=%0d burst=%s region=%s",
      dir.name(), id, addr, len, beat_count(), size, burst.name(),
      addr_region.name()
    );
  endfunction

endclass

`endif

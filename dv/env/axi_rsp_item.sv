`ifndef AXI_RSP_ITEM_SV
`define AXI_RSP_ITEM_SV

class axi_rsp_item #(
  int unsigned DATA_WIDTH = AXI_DATA_WIDTH,
  int unsigned ID_WIDTH   = AXI_ID_WIDTH,
  int unsigned LEN_WIDTH  = AXI_LEN_WIDTH
) extends uvm_sequence_item;

  // These fields identify the accepted request and are copied before randomize().
  axi_dir_e                        dir;
  bit [ID_WIDTH-1:0]               id;
  bit [LEN_WIDTH-1:0]              len;

  // Only the payload for the selected direction is populated.
  rand bit [DATA_WIDTH-1:0]        rdata[];
  rand axi_resp_e                  rresp[];
  rand axi_resp_e                  bresp;

  // Delay before B or the first R beat; gaps are between adjacent R beats.
  rand int unsigned                rsp_delay;
  rand int unsigned                rbeat_gap[];

  `uvm_object_param_utils_begin(
    axi_rsp_item #(DATA_WIDTH, ID_WIDTH, LEN_WIDTH)
  )
    `uvm_field_enum(axi_dir_e, dir, UVM_DEFAULT)
    `uvm_field_int(id, UVM_DEFAULT)
    `uvm_field_int(len, UVM_DEFAULT)
    `uvm_field_array_int(rdata, UVM_DEFAULT)
    `uvm_field_array_enum(axi_resp_e, rresp, UVM_DEFAULT)
    `uvm_field_enum(axi_resp_e, bresp, UVM_DEFAULT)
    `uvm_field_int(rsp_delay, UVM_DEFAULT)
    `uvm_field_array_int(rbeat_gap, UVM_DEFAULT)
  `uvm_object_utils_end

  constraint c_payload_size {
    if (dir == AXI_READ) {
      rdata.size() == int'(len) + 1;
      rresp.size() == int'(len) + 1;
      rbeat_gap.size() == int'(len);
      bresp == AXI_RESP_OKAY;
    }
    else {
      rdata.size() == 0;
      rresp.size() == 0;
      rbeat_gap.size() == 0;
    }
  }

  // EXOKAY is excluded because the current request model has no exclusive access.
  constraint c_legal_response {
    if (dir == AXI_WRITE)
      bresp inside {AXI_RESP_OKAY, AXI_RESP_SLVERR, AXI_RESP_DECERR};

    if (dir == AXI_READ) {
      foreach (rresp[i])
        rresp[i] inside {AXI_RESP_OKAY, AXI_RESP_SLVERR, AXI_RESP_DECERR};
    }
  }

  constraint c_default_distribution {
    rsp_delay dist {
      0      :/ 50,
      [1:3]  :/ 35,
      [4:15] :/ 15
    };

    if (dir == AXI_WRITE) {
      bresp dist {
        AXI_RESP_OKAY   := 8,
        AXI_RESP_SLVERR := 1,
        AXI_RESP_DECERR := 1
      };
    }

    if (dir == AXI_READ) {
      foreach (rresp[i])
        rresp[i] dist {
          AXI_RESP_OKAY   := 8,
          AXI_RESP_SLVERR := 1,
          AXI_RESP_DECERR := 1
        };

      foreach (rbeat_gap[i])
        rbeat_gap[i] dist {
          0      :/ 70,
          [1:3]  :/ 25,
          [4:10] :/ 5
        };
    }
  }

  function new(string name = "axi_rsp_item");
    super.new(name);

    if ((DATA_WIDTH == 0) || ((DATA_WIDTH % 8) != 0))
      `uvm_fatal("AXI_RSP_PARAM", "DATA_WIDTH must be a non-zero multiple of 8")

    if ((ID_WIDTH == 0) || (LEN_WIDTH == 0))
      `uvm_fatal("AXI_RSP_PARAM", "ID/LEN widths must be non-zero")
  endfunction

  function int unsigned beat_count();
    return (dir == AXI_READ) ? (int'(len) + 1) : 0;
  endfunction

  function string convert2string();
    if (dir == AXI_READ) begin
      return $sformatf(
        "dir=%s id=0x%0h len=%0d beats=%0d rsp_delay=%0d",
        dir.name(), id, len, beat_count(), rsp_delay
      );
    end

    return $sformatf(
      "dir=%s id=0x%0h bresp=%s rsp_delay=%0d",
      dir.name(), id, bresp.name(), rsp_delay
    );
  endfunction

endclass

`endif

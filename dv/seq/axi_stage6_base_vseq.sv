`ifndef AXI_STAGE6_BASE_VSEQ_SV
`define AXI_STAGE6_BASE_VSEQ_SV

class axi_stage6_base_vseq extends uvm_sequence;

  axi_switch_ref_model #() map;

  `uvm_object_utils(axi_stage6_base_vseq)
  `uvm_declare_p_sequencer(axi_virtual_sequencer #())

  function new(string name = "axi_stage6_base_vseq");
    super.new(name);
    map = axi_switch_ref_model #()::type_id::create("map");
  endfunction

  virtual function bit [AXI_ADDR_WIDTH-1:0] route_address(
    int unsigned slave_index
  );
    case (slave_index)
      0: return 32'h0000_0100;
      1: return 32'h0000_2100;
      2: return 32'h0000_4100;
      default: begin
        `uvm_fatal("AXI_STAGE6_ROUTE", $sformatf(
          "Stage 6 does not support slave index %0d; use S0/S1/S2 only",
          slave_index))
        return '0;
      end
    endcase
  endfunction

  virtual function axi_route_e index_route(int unsigned slave_index);
    case (slave_index)
      0: return AXI_ROUTE_S0;
      1: return AXI_ROUTE_S1;
      2: return AXI_ROUTE_S2;
      default: begin
        `uvm_fatal("AXI_STAGE6_ROUTE", $sformatf(
          "Stage 6 does not support slave index %0d; use S0/S1/S2 only",
          slave_index))
        return AXI_ROUTE_INVALID;
      end
    endcase
  endfunction

  virtual task send_write(int unsigned master_index,
                          int unsigned slave_index,
                          bit [1:0] tag,
                          bit [AXI_DATA_WIDTH-1:0] data);
    axi_m_single_write_seq #() seq;
    bit [AXI_M_ID_WIDTH-1:0] target_id;
    bit [AXI_ADDR_WIDTH-1:0] target_addr;
    bit [AXI_DATA_WIDTH-1:0] target_data;

    target_id = map.build_master_id(index_route(slave_index), tag);
    target_addr = route_address(slave_index);
    target_data = data;

    `uvm_do_on_with(seq, p_sequencer.m_seqr[master_index], {
      id    == local::target_id;
      addr  == local::target_addr;
      data  == local::target_data;
      size  == $clog2(AXI_DATA_WIDTH / 8);
      burst == AXI_BURST_INCR;
      strb  == '1;
    })
  endtask

  virtual task send_read(int unsigned master_index,
                         int unsigned slave_index,
                         bit [1:0] tag);
    axi_m_single_read_seq #() seq;
    bit [AXI_M_ID_WIDTH-1:0] target_id;
    bit [AXI_ADDR_WIDTH-1:0] target_addr;

    target_id = map.build_master_id(index_route(slave_index), tag);
    target_addr = route_address(slave_index);

    `uvm_do_on_with(seq, p_sequencer.m_seqr[master_index], {
      id    == local::target_id;
      addr  == local::target_addr;
      size  == $clog2(AXI_DATA_WIDTH / 8);
      burst == AXI_BURST_INCR;
    })
  endtask

  virtual task run_responder(int unsigned slave_index,
                             int unsigned request_count,
                             int unsigned delay = 0);
    axi_s_stage6_reactive_seq #() seq;
    int unsigned target_count;
    int unsigned target_delay;
    bit [AXI_DATA_WIDTH-1:0] target_data_base;

    if (request_count == 0)
      return;
    target_count = request_count;
    target_delay = delay;
    target_data_base = 32'h6000_0000 + (slave_index << 16);

    `uvm_do_on_with(seq, p_sequencer.s_seqr[slave_index], {
      request_count == local::target_count;
      read_data_base == local::target_data_base;
      response_code == AXI_RESP_OKAY;
      response_delay == local::target_delay;
    })
  endtask

endclass

`endif

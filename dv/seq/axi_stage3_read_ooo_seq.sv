`ifndef AXI_STAGE3_READ_OOO_SEQ_SV
`define AXI_STAGE3_READ_OOO_SEQ_SV

class axi_stage3_read_ooo_seq extends axi_stage3_scenario_sequence;

  `uvm_object_utils(axi_stage3_read_ooo_seq)

  function new(string name = "axi_stage3_read_ooo_seq");
    super.new(name);
  endfunction

  virtual task body();
    bit [1:0] order[$] = '{2'b10, 2'b00, 2'b11, 2'b01};
    foreach (order[index])
      r_return_order.push_back(slave_id(32'h0000_0a00, order[index]));

    fork
      run_reactive();
      begin
        for (int unsigned tag = 0; tag < 4; tag++)
          send_read(tag[1:0], 32'h0000_0a00 + (tag * 32), tag + 1);
      end
    join
  endtask

endclass

`endif

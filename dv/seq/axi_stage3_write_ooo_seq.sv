`ifndef AXI_STAGE3_WRITE_OOO_SEQ_SV
`define AXI_STAGE3_WRITE_OOO_SEQ_SV

class axi_stage3_write_ooo_seq extends axi_stage3_scenario_sequence;

  `uvm_object_utils(axi_stage3_write_ooo_seq)

  function new(string name = "axi_stage3_write_ooo_seq");
    super.new(name);
  endfunction

  virtual task body();
    bit [1:0] order[$] = '{2'b11, 2'b01, 2'b00, 2'b10};
    foreach (order[index])
      b_return_order.push_back(slave_id(32'h0000_0800, order[index]));

    fork
      run_reactive();
      begin
        for (int unsigned tag = 0; tag < 4; tag++)
          send_write(tag[1:0], 32'h0000_0800 + (tag * 32), 2,
                     32'h2000_0000 + (tag * 32));
      end
    join
  endtask

endclass

`endif

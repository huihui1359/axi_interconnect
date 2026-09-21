`ifndef AXI_STAGE3_SAME_ID_ORDER_SEQ_SV
`define AXI_STAGE3_SAME_ID_ORDER_SEQ_SV

class axi_stage3_same_id_order_seq extends axi_stage3_scenario_sequence;

  `uvm_object_utils(axi_stage3_same_id_order_seq)

  function new(string name = "axi_stage3_same_id_order_seq");
    super.new(name);
    b_rsp_delay = 10;
    r_rsp_delay = 10;
  endfunction

  virtual task body();
    repeat (3) begin
      b_return_order.push_back(slave_id(32'h0000_0c00, 2'b01));
      r_return_order.push_back(slave_id(32'h0000_0d00, 2'b10));
    end

    fork
      run_reactive();
      begin
        for (int unsigned index = 0; index < 3; index++) begin
          send_write(2'b01, 32'h0000_0c00 + (index * 32), 2,
                     32'h3000_0000 + (index * 32));
          send_read(2'b10, 32'h0000_0d00 + (index * 32), index + 1);
        end
      end
    join
  endtask

endclass

`endif

`ifndef AXI_STAGE3_OUTSTANDING_STALL_SEQ_SV
`define AXI_STAGE3_OUTSTANDING_STALL_SEQ_SV

class axi_stage3_outstanding_stall_seq extends axi_stage3_scenario_sequence;

  `uvm_object_utils(axi_stage3_outstanding_stall_seq)

  function new(string name = "axi_stage3_outstanding_stall_seq");
    super.new(name);
    b_rsp_delay = 8;
    r_rsp_delay = 8;
    r_beat_gap  = 2;
  endfunction

  virtual task body();
    bit [1:0] response_order[$] = '{2'b11, 2'b01, 2'b10, 2'b00};
    foreach (response_order[index]) begin
      b_return_order.push_back(
        slave_id(32'h0000_0400, response_order[index])
      );
      r_return_order.push_back(
        slave_id(32'h0000_0900, response_order[index])
      );
    end

    fork
      run_reactive();
      begin
        for (int unsigned tag = 0; tag < 4; tag++) begin
          send_write(tag[1:0], 32'h0000_0400 + (tag * 32), 4,
                     32'h6000_0000 + (tag * 64), tag % 2, 1, 1);
          send_read(tag[1:0], 32'h0000_0900 + (tag * 32), 4, tag % 2);
        end
      end
    join
  endtask

endclass

`endif

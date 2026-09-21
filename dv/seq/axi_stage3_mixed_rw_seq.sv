`ifndef AXI_STAGE3_MIXED_RW_SEQ_SV
`define AXI_STAGE3_MIXED_RW_SEQ_SV

class axi_stage3_mixed_rw_seq extends axi_stage3_scenario_sequence;

  `uvm_object_utils(axi_stage3_mixed_rw_seq)

  function new(string name = "axi_stage3_mixed_rw_seq");
    super.new(name);
    r_beat_gap = 1;
  endfunction

  virtual task body();
    bit [1:0] request_tags[$] = '{2'b00, 2'b01, 2'b00, 2'b10};
    bit [1:0] response_tags[$] = '{2'b01, 2'b00, 2'b10, 2'b00};

    foreach (response_tags[index]) begin
      b_return_order.push_back(
        slave_id(32'h0000_0200, response_tags[index])
      );
      r_return_order.push_back(
        slave_id(32'h0000_0600, response_tags[index])
      );
    end

    fork
      run_reactive();
      begin
        foreach (request_tags[index]) begin
          send_write(request_tags[index],
                     32'h0000_0200 + (index * 32), 2,
                     32'h4000_0000 + (index * 32));
          send_read(request_tags[index],
                    32'h0000_0600 + (index * 32), 2);
        end
      end
    join
  endtask

endclass

`endif

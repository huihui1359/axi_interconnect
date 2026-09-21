`ifndef AXI_STAGE3_ID_MAPPING_SEQ_SV
`define AXI_STAGE3_ID_MAPPING_SEQ_SV

class axi_stage3_id_mapping_seq extends axi_stage3_scenario_sequence;

  `uvm_object_utils(axi_stage3_id_mapping_seq)

  function new(string name = "axi_stage3_id_mapping_seq");
    super.new(name);
    b_rsp_delay = 10;
    r_rsp_delay = 10;
  endfunction

  virtual task body();
    for (int unsigned tag = 0; tag < 4; tag++) begin
      b_return_order.push_back(slave_id(32'h0000_0300, tag[1:0]));
      r_return_order.push_back(slave_id(32'h0000_0700, tag[1:0]));
    end

    fork
      run_reactive();
      begin
        for (int unsigned tag = 0; tag < 4; tag++) begin
          send_write(tag[1:0], 32'h0000_0300 + (tag * 32), 1,
                     32'h5000_0000 + tag, 0, 8);
          send_read(tag[1:0], 32'h0000_0700 + (tag * 32), 1);
        end
      end
    join
  endtask

endclass

`endif

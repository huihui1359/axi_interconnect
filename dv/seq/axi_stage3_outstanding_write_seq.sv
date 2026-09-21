`ifndef AXI_STAGE3_OUTSTANDING_WRITE_SEQ_SV
`define AXI_STAGE3_OUTSTANDING_WRITE_SEQ_SV

class axi_stage3_outstanding_write_seq extends axi_stage3_scenario_sequence;

  int unsigned transaction_count;
  bit same_id;

  `uvm_object_utils(axi_stage3_outstanding_write_seq)

  function new(string name = "axi_stage3_outstanding_write_seq");
    super.new(name);
    transaction_count = 5;
    same_id = 1'b0;
    b_rsp_delay = 20;
  endfunction

  virtual task body();
    bit [1:0] tag;
    for (int unsigned index = 0; index < transaction_count; index++) begin
      tag = same_id ? 2'b00 : index[1:0];
      b_return_order.push_back(slave_id(32'h0000_0100, tag));
    end

    fork
      run_reactive();
      begin
        for (int unsigned index = 0; index < transaction_count; index++) begin
          tag = same_id ? 2'b00 : index[1:0];
          send_write(tag, 32'h0000_0100 + (index * 32), 2,
                     32'h1000_0000 + (index * 32));
        end
      end
    join
  endtask

endclass

`endif

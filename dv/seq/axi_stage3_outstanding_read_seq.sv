`ifndef AXI_STAGE3_OUTSTANDING_READ_SEQ_SV
`define AXI_STAGE3_OUTSTANDING_READ_SEQ_SV

class axi_stage3_outstanding_read_seq extends axi_stage3_scenario_sequence;

  int unsigned transaction_count;
  bit same_id;

  `uvm_object_utils(axi_stage3_outstanding_read_seq)

  function new(string name = "axi_stage3_outstanding_read_seq");
    super.new(name);
    transaction_count = 5;
    same_id = 1'b0;
    r_rsp_delay = 20;
  endfunction

  virtual task body();
    bit [1:0] tag;
    for (int unsigned index = 0; index < transaction_count; index++) begin
      tag = same_id ? 2'b00 : index[1:0];
      r_return_order.push_back(slave_id(32'h0000_0500, tag));
    end

    fork
      run_reactive();
      begin
        for (int unsigned index = 0; index < transaction_count; index++) begin
          tag = same_id ? 2'b00 : index[1:0];
          send_read(tag, 32'h0000_0500 + (index * 32), 3);
        end
      end
    join
  endtask

endclass

`endif

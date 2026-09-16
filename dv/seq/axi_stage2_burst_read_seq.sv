`ifndef AXI_STAGE2_BURST_READ_SEQ_SV
`define AXI_STAGE2_BURST_READ_SEQ_SV

class axi_stage2_burst_read_sequence extends axi_stage2_scenario_sequence;

  `uvm_object_utils(axi_stage2_burst_read_sequence)

  function new(string name = "axi_stage2_burst_read_sequence");
    super.new(name);
  endfunction

  virtual task body();
    int unsigned transaction_index;
    int unsigned wrap_lengths[4] = '{2, 4, 8, 16};

    transaction_index = 0;
    fork
      serve_responses(36, 32'h8100_0000);
      begin
        for (int unsigned beats = 1; beats <= 16; beats++) begin
          send_read(4'h5, 32'h0000_0100 + (transaction_index * 64),
                    beats, AXI_BURST_FIXED);
          transaction_index++;
        end

        for (int unsigned beats = 1; beats <= 16; beats++) begin
          send_read(4'h5, 32'h0000_0500 + ((beats - 1) * 64),
                    beats, AXI_BURST_INCR);
          transaction_index++;
        end

        foreach (wrap_lengths[index]) begin
          send_read(4'h5, 32'h0000_0900 + (index * 128),
                    wrap_lengths[index], AXI_BURST_WRAP);
          transaction_index++;
        end
      end
    join
  endtask

endclass

`endif

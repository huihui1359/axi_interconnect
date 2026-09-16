`ifndef AXI_STAGE2_BURST_WRITE_SEQ_SV
`define AXI_STAGE2_BURST_WRITE_SEQ_SV

class axi_stage2_burst_write_sequence extends axi_stage2_scenario_sequence;

  `uvm_object_utils(axi_stage2_burst_write_sequence)

  function new(string name = "axi_stage2_burst_write_sequence");
    super.new(name);
  endfunction

  virtual task body();
    int unsigned transaction_index;
    int unsigned wrap_lengths[4] = '{2, 4, 8, 16};

    transaction_index = 0;
    fork
      serve_responses(36, 32'h7100_0000);
      begin
        for (int unsigned beats = 1; beats <= 16; beats++) begin
          send_write(4'h5, 32'h0000_0100 + (transaction_index * 64),
                     beats, AXI_BURST_FIXED,
                     32'h1100_0000 + (transaction_index * 256));
          transaction_index++;
        end

        for (int unsigned beats = 1; beats <= 16; beats++) begin
          send_write(4'h5, 32'h0000_0500 + ((beats - 1) * 64),
                     beats, AXI_BURST_INCR,
                     32'h2100_0000 + ((beats - 1) * 256));
          transaction_index++;
        end

        foreach (wrap_lengths[index]) begin
          send_write(4'h5, 32'h0000_0900 + (index * 128),
                     wrap_lengths[index], AXI_BURST_WRAP,
                     32'h3100_0000 + (index * 256));
          transaction_index++;
        end
      end
    join
  endtask

endclass

`endif

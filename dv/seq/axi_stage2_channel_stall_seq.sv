`ifndef AXI_STAGE2_CHANNEL_STALL_SEQ_SV
`define AXI_STAGE2_CHANNEL_STALL_SEQ_SV

class axi_stage2_channel_stall_sequence extends axi_stage2_scenario_sequence;

  `uvm_object_utils(axi_stage2_channel_stall_sequence)

  function new(string name = "axi_stage2_channel_stall_sequence");
    super.new(name);
  endfunction

  virtual task body();
    randomize_fixed_latency(aw_latency, 0);
    randomize_fixed_latency(w_start_latency, 0);
    randomize_fixed_latency(w_gap_latency, 0);
    randomize_fixed_latency(ar_latency, 0);
    randomize_fixed_latency(b_latency, 0);
    randomize_fixed_latency(r_latency, 0);
    randomize_fixed_latency(r_gap_latency, 0);

    fork
      serve_responses(2, 32'h7400_0000);
      begin
        send_write(4'h5, 32'h0000_0500, 4, AXI_BURST_INCR,
                   32'h1400_0000);
        send_read(4'h5, 32'h0000_0900, 4, AXI_BURST_INCR);
      end
    join
  endtask

endclass

`endif

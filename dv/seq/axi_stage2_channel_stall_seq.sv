`ifndef AXI_STAGE2_CHANNEL_STALL_SEQ_SV
`define AXI_STAGE2_CHANNEL_STALL_SEQ_SV

class axi_stage2_channel_stall_sequence extends axi_stage2_scenario_sequence;

  `uvm_object_utils(axi_stage2_channel_stall_sequence)

  function new(string name = "axi_stage2_channel_stall_sequence");
    super.new(name);
  endfunction

  virtual task body();
    aw_latency.configure_fixed(0);
    w_start_latency.configure_fixed(0);
    w_gap_latency.configure_fixed(0);
    ar_latency.configure_fixed(0);
    b_latency.configure_fixed(0);
    r_latency.configure_fixed(0);
    r_gap_latency.configure_fixed(0);

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

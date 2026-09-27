`ifndef AXI_STAGE2_DELAY_GAP_SEQ_SV
`define AXI_STAGE2_DELAY_GAP_SEQ_SV

class axi_stage2_delay_gap_sequence extends axi_stage2_scenario_sequence;

  `uvm_object_utils(axi_stage2_delay_gap_sequence)

  function new(string name = "axi_stage2_delay_gap_sequence");
    super.new(name);
  endfunction

  virtual task body();
    randomize_fixed_latency(aw_latency, 2);
    randomize_fixed_latency(w_start_latency, 3);
    randomize_fixed_latency(ar_latency, 2);
    randomize_fixed_latency(b_latency, 5);
    randomize_fixed_latency(r_latency, 4);
    randomize_fixed_latency(r_gap_latency, 0);

    next_w_gaps = '{4, 1, 3, 2};
    next_r_gaps = '{3, 1, 2};

    fork
      serve_responses(2, 32'h7300_0000);
      begin
        send_write(4'h5, 32'h0000_0400, 4, AXI_BURST_INCR,
                   32'h1300_0000);
        send_read(4'h5, 32'h0000_0800, 4, AXI_BURST_INCR);
      end
    join
  endtask

endclass

`endif

`ifndef AXI_STAGE2_DELAY_GAP_SEQ_SV
`define AXI_STAGE2_DELAY_GAP_SEQ_SV

class axi_stage2_delay_gap_sequence extends axi_stage2_scenario_sequence;

  `uvm_object_utils(axi_stage2_delay_gap_sequence)

  function new(string name = "axi_stage2_delay_gap_sequence");
    super.new(name);
  endfunction

  virtual task body();
    aw_latency.configure_fixed(2);
    w_start_latency.configure_fixed(3);
    ar_latency.configure_fixed(2);
    b_latency.configure_fixed(5);
    r_latency.configure_fixed(4);
    r_gap_latency.configure_fixed(0);

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

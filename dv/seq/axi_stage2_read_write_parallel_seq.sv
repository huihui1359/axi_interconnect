`ifndef AXI_STAGE2_READ_WRITE_PARALLEL_SEQ_SV
`define AXI_STAGE2_READ_WRITE_PARALLEL_SEQ_SV

class axi_stage2_read_write_parallel_sequence
  extends axi_stage2_scenario_sequence;

  `uvm_object_utils(axi_stage2_read_write_parallel_sequence)

  function new(string name = "axi_stage2_read_write_parallel_sequence");
    super.new(name);
  endfunction

  virtual task body();
    randomize_fixed_latency(aw_latency, 0);
    randomize_fixed_latency(w_start_latency, 0);
    randomize_fixed_latency(w_gap_latency, 1);
    randomize_fixed_latency(ar_latency, 0);
    randomize_fixed_latency(b_latency, 2);
    randomize_fixed_latency(r_latency, 2);
    randomize_fixed_latency(r_gap_latency, 4);

    fork
      serve_responses(2, 32'h7500_0000);
      begin
        send_write(4'h5, 32'h0000_0600, 8, AXI_BURST_INCR,
                   32'h1500_0000);
        send_read(4'h5, 32'h0000_0a00, 8, AXI_BURST_INCR);
      end
    join
  endtask

endclass

`endif

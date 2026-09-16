`ifndef AXI_STAGE2_READ_WRITE_PARALLEL_SEQ_SV
`define AXI_STAGE2_READ_WRITE_PARALLEL_SEQ_SV

class axi_stage2_read_write_parallel_sequence
  extends axi_stage2_scenario_sequence;

  `uvm_object_utils(axi_stage2_read_write_parallel_sequence)

  function new(string name = "axi_stage2_read_write_parallel_sequence");
    super.new(name);
  endfunction

  virtual task body();
    aw_latency.configure_fixed(0);
    w_start_latency.configure_fixed(0);
    w_gap_latency.configure_fixed(1);
    ar_latency.configure_fixed(0);
    b_latency.configure_fixed(2);
    r_latency.configure_fixed(2);
    r_gap_latency.configure_fixed(4);

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

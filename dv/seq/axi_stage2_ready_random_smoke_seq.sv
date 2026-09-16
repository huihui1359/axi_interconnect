`ifndef AXI_STAGE2_READY_RANDOM_SMOKE_SEQ_SV
`define AXI_STAGE2_READY_RANDOM_SMOKE_SEQ_SV

class axi_stage2_ready_random_smoke_sequence
  extends axi_stage2_scenario_sequence;

  `uvm_object_utils(axi_stage2_ready_random_smoke_sequence)

  function new(string name = "axi_stage2_ready_random_smoke_sequence");
    super.new(name);
  endfunction

  virtual task body();
    aw_latency.configure_random(0, 10);
    w_start_latency.configure_random(0, 10);
    w_gap_latency.configure_random(0, 10);
    ar_latency.configure_random(0, 10);
    b_latency.configure_random(0, 10);
    r_latency.configure_random(0, 10);
    r_gap_latency.configure_random(0, 10);

    fork
      serve_responses(16, 32'h7600_0000);
      begin
        for (int unsigned index = 0; index < 8; index++) begin
          send_write(4'h5, 32'h0000_0100 + (index * 64),
                     index + 1, AXI_BURST_INCR,
                     32'h1600_0000 + (index * 256));
          send_read(4'h5, 32'h0000_0800 + (index * 64),
                    index + 1, AXI_BURST_INCR);
        end
      end
    join
  endtask

endclass

`endif

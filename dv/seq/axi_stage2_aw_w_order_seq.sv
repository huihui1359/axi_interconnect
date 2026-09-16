`ifndef AXI_STAGE2_AW_W_ORDER_SEQ_SV
`define AXI_STAGE2_AW_W_ORDER_SEQ_SV

class axi_stage2_aw_w_order_sequence extends axi_stage2_scenario_sequence;

  `uvm_object_utils(axi_stage2_aw_w_order_sequence)

  function new(string name = "axi_stage2_aw_w_order_sequence");
    super.new(name);
  endfunction

  virtual task body();
    b_latency.configure_fixed(0);
    w_gap_latency.configure_fixed(0);

    fork
      serve_responses(3, 32'h7200_0000);
      begin
        aw_latency.configure_fixed(0);
        w_start_latency.configure_fixed(6);
        send_write(4'h5, 32'h0000_0100, 4, AXI_BURST_INCR,
                   32'h1200_0000);

        aw_latency.configure_fixed(8);
        w_start_latency.configure_fixed(0);
        send_write(4'h5, 32'h0000_0200, 4, AXI_BURST_INCR,
                   32'h2200_0000);

        aw_latency.configure_fixed(0);
        w_start_latency.configure_fixed(0);
        send_write(4'h5, 32'h0000_0300, 4, AXI_BURST_INCR,
                   32'h3200_0000);
      end
    join
  endtask

endclass

`endif

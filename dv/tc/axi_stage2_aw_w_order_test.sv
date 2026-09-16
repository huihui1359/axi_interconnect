`ifndef AXI_STAGE2_AW_W_ORDER_TEST_SV
`define AXI_STAGE2_AW_W_ORDER_TEST_SV

class axi_stage2_aw_w_order_test extends axi_stage2_base_test;

  typedef virtual axi_if #(
    AXI_ADDR_WIDTH, AXI_DATA_WIDTH, AXI_M_ID_WIDTH, AXI_LEN_WIDTH
  ).mon_mp vif_t;

  `uvm_component_utils(axi_stage2_aw_w_order_test)

  function new(string name = "axi_stage2_aw_w_order_test",
               uvm_component parent = null);
    super.new(name, parent);
  endfunction

  extern task check_channel_order(vif_t vif);
  extern virtual task run_phase(uvm_phase phase);

endclass

task axi_stage2_aw_w_order_test::check_channel_order(vif_t vif);
  longint unsigned aw_cycle;
  longint unsigned first_w_cycle;
  longint unsigned last_w_cycle;
  longint unsigned cycle_count;

  cycle_count = 0;
  for (int unsigned transaction = 0; transaction < 3; transaction++) begin
    aw_cycle      = 0;
    first_w_cycle = 0;
    last_w_cycle  = 0;
    while ((aw_cycle == 0) || (last_w_cycle == 0)) begin
      @(posedge vif.ACLK);
      cycle_count++;
      if (vif.awvalid && vif.awready)
        aw_cycle = cycle_count;
      if (vif.wvalid && vif.wready) begin
        if (first_w_cycle == 0)
          first_w_cycle = cycle_count;
        if (vif.wlast)
          last_w_cycle = cycle_count;
      end
    end

    case (transaction)
      0: if (!(aw_cycle < first_w_cycle))
        `uvm_error("AXI_STAGE2_AW_W_ORDER", "AW-first scenario failed")
      1: if (!(last_w_cycle < aw_cycle))
        `uvm_error("AXI_STAGE2_AW_W_ORDER", "W-burst-first scenario failed")
      2: if (aw_cycle != first_w_cycle)
        `uvm_error("AXI_STAGE2_AW_W_ORDER", "Concurrent AW/W scenario failed")
    endcase
  end
endtask

task axi_stage2_aw_w_order_test::run_phase(uvm_phase phase);
  axi_stage2_aw_w_order_sequence scenario;

  phase.raise_objection(this);
  configure_ready_fixed(0, 0, 0, 0, 0);
  scenario = axi_stage2_aw_w_order_sequence::type_id::create("scenario");
  wait_for_reset_release();
  fork
    check_channel_order(env_cfg.m_cfg[0].mon_vif);
    run_stage2_scenario(scenario, 3, 0,
                        "axi_stage2_aw_w_order_test");
  join
  phase.drop_objection(this);
endtask

`endif

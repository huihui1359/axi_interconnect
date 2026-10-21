`ifndef TP_SID_RANDOM_SV
`define TP_SID_RANDOM_SV

// Covers: F04
// Testplan: tp_sid_random
// Minimum campaign: 10_000 transactions
// Expected result: PASS after the Stage 6 read-ID assertions accept ID 0..15
class tp_sid_random extends axi_cr_base_test;

  `uvm_component_utils(tp_sid_random)

  function new(string name = "tp_sid_random",
               uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual function void configure_cr_cfg();
    cr_cfg.transaction_count = 10_000;
    cr_cfg.ready_delay_min = 0;
    cr_cfg.ready_delay_max = 5;
  endfunction

  virtual task finish_stage6_test();
    int unsigned write_id;

    if ((cr_cfg.transaction_count >= 10_000) && (cr_vseq != null)) begin
      for (int unsigned master = 0;
           master < AXI_NUM_MASTERS; master++) begin
        for (int unsigned slave = 0;
             slave < AXI_NUM_SLAVES; slave++) begin
          for (int unsigned id = 0;
               id < (1 << AXI_M_ID_WIDTH); id++) begin
            if (cr_vseq.planned_id_count[master][slave][0][id] == 0)
              `uvm_error("AXI_CR_SID_COV", $sformatf(
                "Missing read SID combination M%0d S%0d original_id=0x%0h",
                master, slave, id))
          end
          for (int unsigned tag = 0; tag < 4; tag++) begin
            write_id = ((slave + 1) << 2) | tag;
            if (cr_vseq.planned_id_count[master][slave][1][write_id] == 0)
              `uvm_error("AXI_CR_SID_COV", $sformatf(
                "Missing legal write SID combination M%0d S%0d id=0x%0h",
                master, slave, write_id))
          end
        end
      end
    end
    else begin
      `uvm_info("AXI_CR_SID_COV",
        "Smoke-sized campaign: full SID closure check skipped", UVM_LOW)
    end
    super.finish_stage6_test();
  endtask

endclass

`endif

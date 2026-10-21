`ifndef AXI_CR_CONCURRENCY_VSEQ_SV
`define AXI_CR_CONCURRENCY_VSEQ_SV

class axi_cr_concurrency_vseq extends axi_cr_base_vseq;

  `uvm_object_utils(axi_cr_concurrency_vseq)

  int unsigned synchronized_round_count;
  int unsigned full_six_endpoint_round_count;

  function new(string name = "axi_cr_concurrency_vseq");
    super.new(name);
    synchronized_round_count = 0;
    full_six_endpoint_round_count = 0;
  endfunction

  protected function axi_route_e slave_route(int unsigned slave_index);
    case (slave_index)
      0: return AXI_ROUTE_S0;
      1: return AXI_ROUTE_S1;
      2: return AXI_ROUTE_S2;
      default: return AXI_ROUTE_INVALID;
    endcase
  endfunction

  virtual function void build_plan();
    axi_cr_op op;
    axi_route_e route;
    axi_dir_e direction;
    int unsigned master_index;
    int unsigned slave_index;
    int unsigned round_index;

    if (cfg == null)
      `uvm_fatal("AXI_CR_CONCURRENCY", "cfg must be assigned before start()")

    foreach (master_plan[index]) master_plan[index].delete();
    foreach (slave_request_count[index]) slave_request_count[index] = 0;
    foreach (planned_count[master, slave, dir])
      planned_count[master][slave][dir] = 0;
    foreach (planned_id_count[master, slave, dir, id])
      planned_id_count[master][slave][dir][id] = 0;
    generated_request_count = 0;

    for (int unsigned index = 0;
         index < cfg.transaction_count; index++) begin
      master_index = index % AXI_NUM_MASTERS;
      round_index = index / AXI_NUM_MASTERS;
      slave_index = (master_index + round_index) % AXI_NUM_SLAVES;
      route = slave_route(slave_index);
      direction = choose_direction();

      op = axi_cr_op::type_id::create($sformatf("concurrent_op_%0d", index));
      if (!op.build_request(cfg, master_index, route, direction))
        `uvm_fatal("AXI_CR_CONCURRENCY", $sformatf(
          "Failed to build operation %0d", index))

      master_plan[master_index].push_back(op);
      slave_request_count[slave_index]++;
      planned_count[master_index][slave_index]
        [(direction == AXI_READ) ? 0 : 1]++;
      planned_id_count[master_index][slave_index]
        [(direction == AXI_READ) ? 0 : 1][int'(op.req.id)]++;
      generated_request_count++;
    end
  endfunction

  protected task send_planned_operation(
    int unsigned master_index,
    int unsigned operation_index
  );
    axi_m_cr_seq seq;

    if (operation_index >= master_plan[master_index].size())
      return;
    seq = axi_m_cr_seq::type_id::create($sformatf(
      "m%0d_concurrent_req_%0d", master_index, operation_index));
    seq.source_req = master_plan[master_index][operation_index].req;
    seq.start(p_sequencer.m_seqr[master_index]);
  endtask

  virtual task body();
    int unsigned round_count;

    if (p_sequencer == null)
      `uvm_fatal("AXI_CR_CONCURRENCY", "Virtual sequencer is null")
    foreach (p_sequencer.m_seqr[index]) begin
      if (p_sequencer.m_seqr[index] == null)
        `uvm_fatal("AXI_CR_CONCURRENCY", $sformatf(
          "Master sequencer %0d is null", index))
    end
    foreach (p_sequencer.s_seqr[index]) begin
      if (p_sequencer.s_seqr[index] == null)
        `uvm_fatal("AXI_CR_CONCURRENCY", $sformatf(
          "Slave sequencer %0d is null", index))
    end

    build_plan();
    round_count = (cfg.transaction_count + AXI_NUM_MASTERS - 1) /
                  AXI_NUM_MASTERS;
    synchronized_round_count = round_count;
    full_six_endpoint_round_count =
      cfg.transaction_count / AXI_NUM_MASTERS;
    `uvm_info("AXI_CR_CONCURRENCY", $sformatf(
      "Generated %0d synchronized requests in %0d rounds",
      generated_request_count, round_count), UVM_LOW)

    fork
      run_slave_responder(0);
      run_slave_responder(1);
      run_slave_responder(2);
    join_none

    for (int unsigned round = 0; round < round_count; round++) begin
      fork
        send_planned_operation(0, round);
        send_planned_operation(1, round);
        send_planned_operation(2, round);
      join
    end
  endtask

endclass

`endif

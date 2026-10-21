`ifndef AXI_CR_BASE_VSEQ_SV
`define AXI_CR_BASE_VSEQ_SV

class axi_cr_base_vseq extends axi_stage6_base_vseq;

  axi_cr_cfg cfg;
  axi_cr_op master_plan[AXI_NUM_MASTERS][$];
  int unsigned slave_request_count[AXI_NUM_SLAVES];
  int unsigned planned_count[AXI_NUM_MASTERS][AXI_NUM_SLAVES][2];
  int unsigned planned_id_count[
    AXI_NUM_MASTERS
  ][AXI_NUM_SLAVES][2][1 << AXI_M_ID_WIDTH];
  int unsigned generated_request_count;

  `uvm_object_utils(axi_cr_base_vseq)

  function new(string name = "axi_cr_base_vseq");
    super.new(name);
    cfg = null;
    generated_request_count = 0;
    foreach (slave_request_count[index]) slave_request_count[index] = 0;
    foreach (planned_count[master, slave, direction])
      planned_count[master][slave][direction] = 0;
    foreach (planned_id_count[master, slave, direction, id])
      planned_id_count[master][slave][direction][id] = 0;
  endfunction

  protected function int unsigned choose_weighted(
    input int unsigned weights[]
  );
    int unsigned total;
    int unsigned pick;

    total = 0;
    foreach (weights[index]) total += weights[index];
    if (total == 0)
      `uvm_fatal("AXI_CR_WEIGHT", "Cannot choose from zero total weight")

    pick = $urandom_range(total - 1, 0);
    foreach (weights[index]) begin
      if (pick < weights[index]) return index;
      pick -= weights[index];
    end
    return weights.size() - 1;
  endfunction

  protected function axi_route_e choose_route();
    case (choose_weighted(cfg.route_weight))
      0: return AXI_ROUTE_S0;
      1: return AXI_ROUTE_S1;
      2: return AXI_ROUTE_S2;
      3: return AXI_ROUTE_DEFAULT;
      default: return AXI_ROUTE_INVALID;
    endcase
  endfunction

  protected function axi_dir_e choose_direction();
    int unsigned weights[2];
    weights[0] = cfg.read_weight;
    weights[1] = cfg.write_weight;
    return (choose_weighted(weights) == 0) ? AXI_READ : AXI_WRITE;
  endfunction

  protected function int signed route_to_slave(axi_route_e route);
    case (route)
      AXI_ROUTE_S0: return 0;
      AXI_ROUTE_S1: return 1;
      AXI_ROUTE_S2: return 2;
      default: return -1;
    endcase
  endfunction

  virtual function void build_plan();
    axi_cr_op op;
    axi_route_e route;
    axi_dir_e direction;
    int unsigned master_index;
    int signed slave_index;

    if (cfg == null)
      `uvm_fatal("AXI_CR_VSEQ", "cfg must be assigned before start()")

    foreach (master_plan[index]) master_plan[index].delete();
    foreach (slave_request_count[index]) slave_request_count[index] = 0;
    foreach (planned_count[master, slave, dir])
      planned_count[master][slave][dir] = 0;
    foreach (planned_id_count[master, slave, dir, id])
      planned_id_count[master][slave][dir][id] = 0;
    generated_request_count = 0;

    for (int unsigned index = 0;
         index < cfg.transaction_count;
         index++) begin
      master_index = choose_weighted(cfg.master_weight);
      route = choose_route();
      direction = choose_direction();

      op = axi_cr_op::type_id::create($sformatf("op_%0d", index));
      if (!op.build_request(cfg, master_index, route, direction))
        `uvm_fatal("AXI_CR_VSEQ", $sformatf(
          "Failed to build operation %0d", index))

      master_plan[master_index].push_back(op);
      slave_index = route_to_slave(route);
      if (slave_index >= 0) begin
        slave_request_count[slave_index]++;
        planned_count[master_index][slave_index]
          [(direction == AXI_READ) ? 0 : 1]++;
        planned_id_count[master_index][slave_index]
          [(direction == AXI_READ) ? 0 : 1][int'(op.req.id)]++;
      end
      generated_request_count++;
    end
  endfunction

  virtual task run_master_producer(int unsigned master_index);
    axi_m_cr_seq seq;

    for (int unsigned index = 0;
         index < master_plan[master_index].size();
         index++) begin
      seq = axi_m_cr_seq::type_id::create(
        $sformatf("m%0d_req_%0d", master_index, index));
      seq.source_req = master_plan[master_index][index].req;
      seq.start(p_sequencer.m_seqr[master_index]);
    end
  endtask

  virtual task run_slave_responder(int unsigned slave_index);
    axi_s_stage6_reactive_seq #() seq;
    int unsigned delay;

    if (slave_request_count[slave_index] == 0)
      return;

    if (cfg.response_delay_min == cfg.response_delay_max)
      delay = cfg.response_delay_min;
    else
      delay = $urandom_range(cfg.response_delay_max,
                             cfg.response_delay_min);

    seq = axi_s_stage6_reactive_seq #()::type_id::create(
      $sformatf("s%0d_responder", slave_index));
    seq.request_count = slave_request_count[slave_index];
    seq.read_data_base = 32'h7000_0000 + (slave_index << 16);
    seq.response_code = AXI_RESP_OKAY;
    seq.response_delay = delay;
    seq.start(p_sequencer.s_seqr[slave_index]);
  endtask

  virtual task body();
    if (p_sequencer == null)
      `uvm_fatal("AXI_CR_VSEQ", "Virtual sequencer is null")
    foreach (p_sequencer.m_seqr[index]) begin
      if (p_sequencer.m_seqr[index] == null)
        `uvm_fatal("AXI_CR_VSEQ", $sformatf(
          "Master sequencer %0d is null", index))
    end
    foreach (p_sequencer.s_seqr[index]) begin
      if (p_sequencer.s_seqr[index] == null)
        `uvm_fatal("AXI_CR_VSEQ", $sformatf(
          "Slave sequencer %0d is null", index))
    end

    build_plan();
    `uvm_info("AXI_CR_PLAN", $sformatf(
      "Generated %0d requests; S counts=%0d/%0d/%0d",
      generated_request_count, slave_request_count[0],
      slave_request_count[1], slave_request_count[2]), UVM_LOW)

    // Responders intentionally outlive body() when a planned request is
    // blocked before reaching a Slave. The base test owns completion through
    // scoreboard progress, so a missing request is reported by its watchdog
    // instead of deadlocking this virtual sequence in request_fifo.get().
    fork
      run_slave_responder(0);
      run_slave_responder(1);
      run_slave_responder(2);
    join_none

    fork
      run_master_producer(0);
      run_master_producer(1);
      run_master_producer(2);
    join
  endtask

endclass

`endif

`ifndef AXI_CHANNEL_FORWARDING_CHECKER_SV
`define AXI_CHANNEL_FORWARDING_CHECKER_SV

class axi_channel_forwarding_checker #(
  int unsigned ADDR_WIDTH  = AXI_ADDR_WIDTH,
  int unsigned DATA_WIDTH  = AXI_DATA_WIDTH,
  int unsigned M_ID_WIDTH  = AXI_M_ID_WIDTH,
  int unsigned S_ID_WIDTH  = AXI_S_ID_WIDTH,
  int unsigned LEN_WIDTH   = AXI_LEN_WIDTH,
  int unsigned NUM_MASTERS = AXI_ENV_NUM_MASTERS,
  int unsigned NUM_SLAVES  = AXI_ENV_NUM_SLAVES
) extends uvm_component;

  localparam int unsigned M_ID_COUNT = 1 << M_ID_WIDTH;
  localparam int unsigned S_ID_COUNT = 1 << S_ID_WIDTH;
  localparam int unsigned CHANNEL_COUNT = 5;

  uvm_tlm_analysis_fifo #(
    axi_channel_event #(ADDR_WIDTH, DATA_WIDTH, M_ID_WIDTH, LEN_WIDTH)
  ) m_event_fifo[NUM_MASTERS];
  uvm_tlm_analysis_fifo #(
    axi_channel_event #(ADDR_WIDTH, DATA_WIDTH, S_ID_WIDTH, LEN_WIDTH)
  ) s_event_fifo[NUM_SLAVES];

  axi_channel_event #(
    ADDR_WIDTH, DATA_WIDTH, S_ID_WIDTH, LEN_WIDTH
  ) exp_s_event[NUM_SLAVES][CHANNEL_COUNT][S_ID_COUNT][$];
  axi_channel_event #(
    ADDR_WIDTH, DATA_WIDTH, S_ID_WIDTH, LEN_WIDTH
  ) act_s_event[NUM_SLAVES][CHANNEL_COUNT][S_ID_COUNT][$];
  axi_channel_event #(
    ADDR_WIDTH, DATA_WIDTH, M_ID_WIDTH, LEN_WIDTH
  ) exp_m_event[NUM_MASTERS][CHANNEL_COUNT][M_ID_COUNT][$];
  axi_channel_event #(
    ADDR_WIDTH, DATA_WIDTH, M_ID_WIDTH, LEN_WIDTH
  ) act_m_event[NUM_MASTERS][CHANNEL_COUNT][M_ID_COUNT][$];

  int unsigned default_write_by_id[NUM_MASTERS][M_ID_COUNT];
  int unsigned default_read_beats[NUM_MASTERS][M_ID_COUNT][$];
  axi_switch_ref_model #(ADDR_WIDTH, M_ID_WIDTH, S_ID_WIDTH) map;
  bit enabled;
  int unsigned mismatch_count;
  int unsigned request_event_match_count;
  int unsigned response_event_match_count;

  `uvm_component_param_utils(
    axi_channel_forwarding_checker #(
      ADDR_WIDTH, DATA_WIDTH, M_ID_WIDTH, S_ID_WIDTH,
      LEN_WIDTH, NUM_MASTERS, NUM_SLAVES
    )
  )

  extern function new(string name = "axi_channel_forwarding_checker",
                      uvm_component parent = null);
  extern virtual function void build_phase(uvm_phase phase);
  extern virtual task run_phase(uvm_phase phase);
  extern task process_master_events(int unsigned master_index);
  extern task process_slave_events(int unsigned slave_index);
  extern function int signed route_to_index(axi_route_e route);
  function axi_channel_event #(
    ADDR_WIDTH, DATA_WIDTH, S_ID_WIDTH, LEN_WIDTH
  ) transform_request_event(
    int unsigned master_index,
    int unsigned slave_index,
    axi_channel_event #(
      ADDR_WIDTH, DATA_WIDTH, M_ID_WIDTH, LEN_WIDTH
    ) item
  );
    axi_channel_event #(ADDR_WIDTH, DATA_WIDTH, S_ID_WIDTH, LEN_WIDTH) result;
    axi_route_e route;
    case (slave_index)
      0: route = AXI_ROUTE_S0;
      1: route = AXI_ROUTE_S1;
      2: route = AXI_ROUTE_S2;
      default: route = AXI_ROUTE_INVALID;
    endcase
    result = axi_channel_event #(
      ADDR_WIDTH, DATA_WIDTH, S_ID_WIDTH, LEN_WIDTH
    )::type_id::create("expected_slave_event");
    result.channel = item.channel;
    result.side = AXI_DOWNSTREAM;
    result.port_index = slave_index;
    result.sample_cycle = item.sample_cycle;
    result.id = map.encode_sid(master_index, route, item.id);
    result.addr = item.addr;
    result.len = item.len;
    result.size = item.size;
    result.burst_raw = item.burst_raw;
    result.data = item.data;
    result.strb = item.strb;
    result.resp_raw = item.resp_raw;
    result.last = item.last;
    return result;
  endfunction

  function axi_channel_event #(
    ADDR_WIDTH, DATA_WIDTH, M_ID_WIDTH, LEN_WIDTH
  ) transform_response_event(
    int unsigned master_index,
    axi_channel_event #(
      ADDR_WIDTH, DATA_WIDTH, S_ID_WIDTH, LEN_WIDTH
    ) item
  );
    axi_channel_event #(ADDR_WIDTH, DATA_WIDTH, M_ID_WIDTH, LEN_WIDTH) result;
    result = axi_channel_event #(
      ADDR_WIDTH, DATA_WIDTH, M_ID_WIDTH, LEN_WIDTH
    )::type_id::create("expected_master_event");
    result.channel = item.channel;
    result.side = AXI_UPSTREAM;
    result.port_index = master_index;
    result.sample_cycle = item.sample_cycle;
    result.id = map.restore_id(item.id);
    result.addr = item.addr;
    result.len = item.len;
    result.size = item.size;
    result.burst_raw = item.burst_raw;
    result.data = item.data;
    result.strb = item.strb;
    result.resp_raw = item.resp_raw;
    result.last = item.last;
    return result;
  endfunction
  extern function void match_slave_event(int unsigned port_index,
                                         axi_channel_e channel,
                                         int unsigned id);
  extern function void match_master_event(int unsigned port_index,
                                          axi_channel_e channel,
                                          int unsigned id);
  extern function int unsigned pending_count();
  extern virtual function void check_phase(uvm_phase phase);

endclass

function axi_channel_forwarding_checker::new(
  string name = "axi_channel_forwarding_checker",
  uvm_component parent = null
);
  super.new(name, parent);
  enabled = 1'b0;
  mismatch_count = 0;
  request_event_match_count = 0;
  response_event_match_count = 0;
endfunction

function void axi_channel_forwarding_checker::build_phase(uvm_phase phase);
  super.build_phase(phase);
  map = axi_switch_ref_model #(
    ADDR_WIDTH, M_ID_WIDTH, S_ID_WIDTH
  )::type_id::create("map");
  foreach (m_event_fifo[index])
    m_event_fifo[index] = new($sformatf("m_event_fifo_%0d", index), this);
  foreach (s_event_fifo[index])
    s_event_fifo[index] = new($sformatf("s_event_fifo_%0d", index), this);
endfunction

task axi_channel_forwarding_checker::run_phase(uvm_phase phase);
  if (!enabled)
    return;
  for (int unsigned index = 0; index < NUM_MASTERS; index++) begin
    automatic int unsigned port_index = index;
    fork process_master_events(port_index); join_none
  end
  for (int unsigned index = 0; index < NUM_SLAVES; index++) begin
    automatic int unsigned port_index = index;
    fork process_slave_events(port_index); join_none
  end
  wait fork;
endtask

task axi_channel_forwarding_checker::process_master_events(
  int unsigned master_index
);
  axi_channel_event #(ADDR_WIDTH, DATA_WIDTH, M_ID_WIDTH, LEN_WIDTH) item;
  axi_channel_event #(ADDR_WIDTH, DATA_WIDTH, M_ID_WIDTH, LEN_WIDTH) snapshot;
  axi_channel_event #(ADDR_WIDTH, DATA_WIDTH, S_ID_WIDTH, LEN_WIDTH) expected;
  axi_route_e route;
  int signed slave_index;
  int unsigned id;
  int unsigned beats_left;
  bit expected_last;

  forever begin
    m_event_fifo[master_index].get(item);
    if ((item == null) || !$cast(snapshot, item.clone())) begin
      mismatch_count++;
      `uvm_error("AXI_CHK_CLONE", "Failed to clone master event")
      continue;
    end
    id = int'(snapshot.id);
    case (snapshot.channel)
      AXI_CHANNEL_AW,
      AXI_CHANNEL_AR: begin
        route = map.decode_address(snapshot.addr);
        slave_index = route_to_index(route);
        if (slave_index < 0) begin
          if (snapshot.channel == AXI_CHANNEL_AW)
            default_write_by_id[master_index][id]++;
          else
            default_read_beats[master_index][id].push_back(
              int'(snapshot.len) + 1);
        end
        else begin
          expected = transform_request_event(master_index,
                                             slave_index, snapshot);
          exp_s_event[slave_index][int'(snapshot.channel)]
                     [int'(expected.id)].push_back(expected);
          match_slave_event(slave_index, snapshot.channel,
                            int'(expected.id));
        end
      end

      AXI_CHANNEL_W: begin
        if (default_write_by_id[master_index][id] == 0) begin
          route = map.decode_w_target(snapshot.id);
          slave_index = route_to_index(route);
          if (slave_index < 0) begin
            mismatch_count++;
            `uvm_error("AXI_CHK_W_ROUTE", $sformatf(
              "M%0d W event ID 0x%0h has no legal destination",
              master_index, snapshot.id))
          end
          else begin
            expected = transform_request_event(master_index,
                                               slave_index, snapshot);
            exp_s_event[slave_index][int'(AXI_CHANNEL_W)]
                       [int'(expected.id)].push_back(expected);
            match_slave_event(slave_index, AXI_CHANNEL_W,
                              int'(expected.id));
          end
        end
      end

      AXI_CHANNEL_B: begin
        if (default_write_by_id[master_index][id] != 0) begin
          default_write_by_id[master_index][id]--;
          if (snapshot.resp_raw !== AXI_RESP_DECERR) begin
            mismatch_count++;
            `uvm_error("AXI_CHK_DEFAULT_B", "Default write did not return DECERR")
          end
        end
        else begin
          act_m_event[master_index][int'(AXI_CHANNEL_B)][id].push_back(snapshot);
          match_master_event(master_index, AXI_CHANNEL_B, id);
        end
      end

      AXI_CHANNEL_R: begin
        if (default_read_beats[master_index][id].size() != 0) begin
          beats_left = default_read_beats[master_index][id][0];
          expected_last = (beats_left == 1);
          if ((snapshot.resp_raw !== AXI_RESP_DECERR) ||
              (snapshot.data !== {DATA_WIDTH{1'b1}}) ||
              (snapshot.last !== expected_last)) begin
            mismatch_count++;
            `uvm_error("AXI_CHK_DEFAULT_R", $sformatf(
              "M%0d default R payload/last mismatch: %s",
              master_index, snapshot.convert2string()))
          end
          if (beats_left == 1)
            void'(default_read_beats[master_index][id].pop_front());
          else
            default_read_beats[master_index][id][0] = beats_left - 1;
        end
        else begin
          act_m_event[master_index][int'(AXI_CHANNEL_R)][id].push_back(snapshot);
          match_master_event(master_index, AXI_CHANNEL_R, id);
        end
      end
    endcase
  end
endtask

task axi_channel_forwarding_checker::process_slave_events(
  int unsigned slave_index
);
  axi_channel_event #(ADDR_WIDTH, DATA_WIDTH, S_ID_WIDTH, LEN_WIDTH) item;
  axi_channel_event #(ADDR_WIDTH, DATA_WIDTH, S_ID_WIDTH, LEN_WIDTH) snapshot;
  axi_channel_event #(ADDR_WIDTH, DATA_WIDTH, M_ID_WIDTH, LEN_WIDTH) expected;
  int signed master_index;
  int unsigned id;

  forever begin
    s_event_fifo[slave_index].get(item);
    if ((item == null) || !$cast(snapshot, item.clone())) begin
      mismatch_count++;
      `uvm_error("AXI_CHK_CLONE", "Failed to clone slave event")
      continue;
    end
    id = int'(snapshot.id);
    case (snapshot.channel)
      AXI_CHANNEL_AW,
      AXI_CHANNEL_W,
      AXI_CHANNEL_AR: begin
        act_s_event[slave_index][int'(snapshot.channel)][id].push_back(snapshot);
        match_slave_event(slave_index, snapshot.channel, id);
      end

      AXI_CHANNEL_B,
      AXI_CHANNEL_R: begin
        master_index = map.decode_master(snapshot.id);
        if ((master_index < 0) || (master_index >= int'(NUM_MASTERS))) begin
          mismatch_count++;
          `uvm_error("AXI_CHK_ILLEGAL_SID", $sformatf(
            "S%0d response SID 0x%0h has illegal source-master tag",
            slave_index, snapshot.id))
        end
        else begin
          expected = transform_response_event(master_index, snapshot);
          exp_m_event[master_index][int'(snapshot.channel)]
                     [int'(expected.id)].push_back(expected);
          match_master_event(master_index, snapshot.channel,
                             int'(expected.id));
        end
      end
    endcase
  end
endtask

function int signed axi_channel_forwarding_checker::route_to_index(
  axi_route_e route
);
  case (route)
    AXI_ROUTE_S0: return 0;
    AXI_ROUTE_S1: return 1;
    AXI_ROUTE_S2: return 2;
    default: return -1;
  endcase
endfunction

function void axi_channel_forwarding_checker::match_slave_event(
  int unsigned port_index,
  axi_channel_e channel,
  int unsigned id
);
  axi_channel_event #(ADDR_WIDTH, DATA_WIDTH, S_ID_WIDTH, LEN_WIDTH) expected;
  axi_channel_event #(ADDR_WIDTH, DATA_WIDTH, S_ID_WIDTH, LEN_WIDTH) actual;
  while ((exp_s_event[port_index][int'(channel)][id].size() != 0) &&
         (act_s_event[port_index][int'(channel)][id].size() != 0)) begin
    expected = exp_s_event[port_index][int'(channel)][id].pop_front();
    actual = act_s_event[port_index][int'(channel)][id].pop_front();
    if (!expected.payload_equal(actual)) begin
      mismatch_count++;
      `uvm_error("AXI_CHK_REQ_EVENT", $sformatf(
        "S%0d forwarding mismatch expected={%s} actual={%s}",
        port_index, expected.convert2string(), actual.convert2string()))
    end
    else request_event_match_count++;
  end
endfunction

function void axi_channel_forwarding_checker::match_master_event(
  int unsigned port_index,
  axi_channel_e channel,
  int unsigned id
);
  axi_channel_event #(ADDR_WIDTH, DATA_WIDTH, M_ID_WIDTH, LEN_WIDTH) expected;
  axi_channel_event #(ADDR_WIDTH, DATA_WIDTH, M_ID_WIDTH, LEN_WIDTH) actual;
  while ((exp_m_event[port_index][int'(channel)][id].size() != 0) &&
         (act_m_event[port_index][int'(channel)][id].size() != 0)) begin
    expected = exp_m_event[port_index][int'(channel)][id].pop_front();
    actual = act_m_event[port_index][int'(channel)][id].pop_front();
    if (!expected.payload_equal(actual)) begin
      mismatch_count++;
      `uvm_error("AXI_CHK_RSP_EVENT", $sformatf(
        "M%0d response forwarding mismatch expected={%s} actual={%s}",
        port_index, expected.convert2string(), actual.convert2string()))
    end
    else response_event_match_count++;
  end
endfunction

function int unsigned axi_channel_forwarding_checker::pending_count();
  int unsigned total;
  total = 0;
  foreach (m_event_fifo[index]) total += m_event_fifo[index].used();
  foreach (s_event_fifo[index]) total += s_event_fifo[index].used();
  foreach (exp_s_event[port, channel, id]) begin
    total += exp_s_event[port][channel][id].size();
    total += act_s_event[port][channel][id].size();
  end
  foreach (exp_m_event[port, channel, id]) begin
    total += exp_m_event[port][channel][id].size();
    total += act_m_event[port][channel][id].size();
  end
  foreach (default_write_by_id[port, id]) begin
    total += default_write_by_id[port][id];
    total += default_read_beats[port][id].size();
  end
  return total;
endfunction

function void axi_channel_forwarding_checker::check_phase(uvm_phase phase);
  super.check_phase(phase);
  if (enabled && (pending_count() != 0))
    `uvm_error("AXI_CHK_PENDING", $sformatf(
      "Channel forwarding checker has %0d pending events", pending_count()))
endfunction

`endif

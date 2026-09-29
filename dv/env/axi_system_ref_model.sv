`ifndef AXI_SYSTEM_REF_MODEL_SV
`define AXI_SYSTEM_REF_MODEL_SV

class axi_system_ref_model #(
  int unsigned ADDR_WIDTH  = AXI_ADDR_WIDTH,
  int unsigned DATA_WIDTH  = AXI_DATA_WIDTH,
  int unsigned M_ID_WIDTH  = AXI_M_ID_WIDTH,
  int unsigned S_ID_WIDTH  = AXI_S_ID_WIDTH,
  int unsigned LEN_WIDTH   = AXI_LEN_WIDTH,
  int unsigned NUM_MASTERS = AXI_ENV_NUM_MASTERS,
  int unsigned NUM_SLAVES  = AXI_ENV_NUM_SLAVES
) extends uvm_component;

  localparam int unsigned S_ID_COUNT = 1 << S_ID_WIDTH;

  uvm_tlm_analysis_fifo #(
    axi_req_item #(ADDR_WIDTH, DATA_WIDTH, M_ID_WIDTH, LEN_WIDTH)
  ) m_req_fifo[NUM_MASTERS];
  uvm_tlm_analysis_fifo #(
    axi_rsp_item #(DATA_WIDTH, S_ID_WIDTH, LEN_WIDTH)
  ) s_rsp_fifo[NUM_SLAVES];
  uvm_analysis_port #(
    axi_req_item #(ADDR_WIDTH, DATA_WIDTH, S_ID_WIDTH, LEN_WIDTH)
  ) s_req_ap[NUM_SLAVES];
  uvm_analysis_port #(
    axi_rsp_item #(DATA_WIDTH, M_ID_WIDTH, LEN_WIDTH)
  ) m_rsp_ap[NUM_MASTERS];

  axi_switch_ref_model #(ADDR_WIDTH, M_ID_WIDTH, S_ID_WIDTH) map;
  bit enabled;
  int unsigned error_count;
  int unsigned default_request_count;
  int unsigned pending_write_by_sid[NUM_SLAVES][S_ID_COUNT];
  int unsigned pending_read_by_sid[NUM_SLAVES][S_ID_COUNT];

  `uvm_component_param_utils(
    axi_system_ref_model #(
      ADDR_WIDTH, DATA_WIDTH, M_ID_WIDTH, S_ID_WIDTH,
      LEN_WIDTH, NUM_MASTERS, NUM_SLAVES
    )
  )

  extern function new(string name = "axi_system_ref_model",
                      uvm_component parent = null);
  extern virtual function void build_phase(uvm_phase phase);
  extern virtual task run_phase(uvm_phase phase);
  extern task process_master_requests(int unsigned master_index);
  extern task process_slave_responses(int unsigned slave_index);
  extern function int signed route_to_index(axi_route_e route);
  function axi_req_item #(
    ADDR_WIDTH, DATA_WIDTH, S_ID_WIDTH, LEN_WIDTH
  ) transform_request(
    int unsigned master_index,
    axi_route_e route,
    axi_req_item #(ADDR_WIDTH, DATA_WIDTH, M_ID_WIDTH, LEN_WIDTH) req
  );
    axi_req_item #(ADDR_WIDTH, DATA_WIDTH, S_ID_WIDTH, LEN_WIDTH) result;
    result = axi_req_item #(
      ADDR_WIDTH, DATA_WIDTH, S_ID_WIDTH, LEN_WIDTH
    )::type_id::create("expected_slave_req");
    result.dir = req.dir;
    result.id = map.encode_sid(master_index, route, req.id);
    result.addr = req.addr;
    result.len = req.len;
    result.size = req.size;
    result.burst = req.burst;
    result.addr_delay = 0;
    result.w_start_delay = 0;
    result.wdata = new[req.wdata.size()];
    result.wstrb = new[req.wstrb.size()];
    result.wbeat_gap = new[req.wbeat_gap.size()];
    foreach (req.wdata[index]) result.wdata[index] = req.wdata[index];
    foreach (req.wstrb[index]) result.wstrb[index] = req.wstrb[index];
    foreach (result.wbeat_gap[index]) result.wbeat_gap[index] = 0;
    return result;
  endfunction

  function axi_rsp_item #(
    DATA_WIDTH, M_ID_WIDTH, LEN_WIDTH
  ) transform_response(
    axi_rsp_item #(DATA_WIDTH, S_ID_WIDTH, LEN_WIDTH) rsp
  );
    axi_rsp_item #(DATA_WIDTH, M_ID_WIDTH, LEN_WIDTH) result;
    result = axi_rsp_item #(
      DATA_WIDTH, M_ID_WIDTH, LEN_WIDTH
    )::type_id::create("expected_master_rsp");
    result.dir = rsp.dir;
    result.id = map.restore_id(rsp.id);
    result.len = rsp.len;
    result.bresp = rsp.bresp;
    result.rdata = new[rsp.rdata.size()];
    result.rresp = new[rsp.rresp.size()];
    result.rbeat_gap = new[rsp.rbeat_gap.size()];
    result.rsp_delay = 0;
    foreach (rsp.rdata[index]) result.rdata[index] = rsp.rdata[index];
    foreach (rsp.rresp[index]) result.rresp[index] = rsp.rresp[index];
    foreach (result.rbeat_gap[index]) result.rbeat_gap[index] = 0;
    return result;
  endfunction

  function axi_rsp_item #(
    DATA_WIDTH, M_ID_WIDTH, LEN_WIDTH
  ) build_default_response(
    axi_req_item #(ADDR_WIDTH, DATA_WIDTH, M_ID_WIDTH, LEN_WIDTH) req
  );
    axi_rsp_item #(DATA_WIDTH, M_ID_WIDTH, LEN_WIDTH) result;
    result = axi_rsp_item #(
      DATA_WIDTH, M_ID_WIDTH, LEN_WIDTH
    )::type_id::create("expected_default_rsp");
    result.dir = req.dir;
    result.id = req.id;
    result.len = (req.dir == AXI_READ) ? req.len : '0;
    result.bresp = (req.dir == AXI_WRITE) ? AXI_RESP_DECERR : AXI_RESP_OKAY;
    result.rsp_delay = 0;
    if (req.dir == AXI_READ) begin
      result.rdata = new[int'(req.len) + 1];
      result.rresp = new[int'(req.len) + 1];
      result.rbeat_gap = new[int'(req.len)];
      foreach (result.rdata[index]) begin
        result.rdata[index] = '1;
        result.rresp[index] = AXI_RESP_DECERR;
      end
      foreach (result.rbeat_gap[index]) result.rbeat_gap[index] = 0;
    end
    else begin
      result.rdata = new[0];
      result.rresp = new[0];
      result.rbeat_gap = new[0];
    end
    return result;
  endfunction
  extern function int unsigned pending_count();
  extern virtual function void check_phase(uvm_phase phase);

endclass

function axi_system_ref_model::new(
  string name = "axi_system_ref_model",
  uvm_component parent = null
);
  super.new(name, parent);
  enabled = 1'b0;
  error_count = 0;
  default_request_count = 0;
endfunction

function void axi_system_ref_model::build_phase(uvm_phase phase);
  super.build_phase(phase);
  map = axi_switch_ref_model #(
    ADDR_WIDTH, M_ID_WIDTH, S_ID_WIDTH
  )::type_id::create("map");
  foreach (m_req_fifo[index]) begin
    m_req_fifo[index] = new($sformatf("m_req_fifo_%0d", index), this);
    m_rsp_ap[index] = new($sformatf("m_rsp_ap_%0d", index), this);
  end
  foreach (s_rsp_fifo[index]) begin
    s_rsp_fifo[index] = new($sformatf("s_rsp_fifo_%0d", index), this);
    s_req_ap[index] = new($sformatf("s_req_ap_%0d", index), this);
  end
endfunction

task axi_system_ref_model::run_phase(uvm_phase phase);
  if (!enabled)
    return;
  for (int unsigned index = 0; index < NUM_MASTERS; index++) begin
    automatic int unsigned master_index = index;
    fork process_master_requests(master_index); join_none
  end
  for (int unsigned index = 0; index < NUM_SLAVES; index++) begin
    automatic int unsigned slave_index = index;
    fork process_slave_responses(slave_index); join_none
  end
  wait fork;
endtask

task axi_system_ref_model::process_master_requests(
  int unsigned master_index
);
  axi_req_item #(ADDR_WIDTH, DATA_WIDTH, M_ID_WIDTH, LEN_WIDTH) req;
  axi_req_item #(ADDR_WIDTH, DATA_WIDTH, S_ID_WIDTH, LEN_WIDTH) expected_req;
  axi_rsp_item #(DATA_WIDTH, M_ID_WIDTH, LEN_WIDTH) expected_rsp;
  axi_route_e route;
  int signed slave_index;

  forever begin
    m_req_fifo[master_index].get(req);
    route = (req.dir == AXI_WRITE) ?
            map.decode_address(req.addr) : map.decode_address(req.addr);
    slave_index = route_to_index(route);
    if (slave_index >= 0) begin
      if ((req.dir == AXI_WRITE) && (map.decode_w_target(req.id) != route)) begin
        error_count++;
        `uvm_error("AXI_SYS_REF_W_ROUTE", $sformatf(
          "M%0d write ID 0x%0h does not encode address route %s",
          master_index, req.id, route.name()))
      end
      expected_req = transform_request(master_index, route, req);
      if (req.dir == AXI_WRITE)
        pending_write_by_sid[slave_index][int'(expected_req.id)]++;
      else
        pending_read_by_sid[slave_index][int'(expected_req.id)]++;
      s_req_ap[slave_index].write(expected_req);
    end
    else begin
      default_request_count++;
      expected_rsp = build_default_response(req);
      m_rsp_ap[master_index].write(expected_rsp);
    end
  end
endtask

task axi_system_ref_model::process_slave_responses(
  int unsigned slave_index
);
  axi_rsp_item #(DATA_WIDTH, S_ID_WIDTH, LEN_WIDTH) rsp;
  axi_rsp_item #(DATA_WIDTH, M_ID_WIDTH, LEN_WIDTH) expected_rsp;
  int signed master_index;
  axi_route_e encoded_route;

  forever begin
    s_rsp_fifo[slave_index].get(rsp);
    master_index = map.decode_master(rsp.id);
    if ((master_index < 0) || (master_index >= int'(NUM_MASTERS))) begin
      error_count++;
      `uvm_error("AXI_SYS_REF_ILLEGAL_MASTER", $sformatf(
        "S%0d response SID 0x%0h has illegal source-master tag",
        slave_index, rsp.id))
      continue;
    end
    case (rsp.id[S_ID_WIDTH-1 -: 2])
      2'b01: encoded_route = AXI_ROUTE_S0;
      2'b10: encoded_route = AXI_ROUTE_S1;
      2'b11: encoded_route = AXI_ROUTE_S2;
      default: encoded_route = AXI_ROUTE_INVALID;
    endcase
    if (route_to_index(encoded_route) != int'(slave_index)) begin
      error_count++;
      `uvm_error("AXI_SYS_REF_SID_ROUTE", $sformatf(
        "S%0d response SID 0x%0h encodes route %s",
        slave_index, rsp.id, encoded_route.name()))
      continue;
    end
    if (rsp.dir == AXI_WRITE) begin
      if (pending_write_by_sid[slave_index][int'(rsp.id)] == 0) begin
        error_count++;
        `uvm_error("AXI_SYS_REF_UNSOLICITED_B", $sformatf(
          "S%0d B response SID 0x%0h has no modeled request",
          slave_index, rsp.id))
        continue;
      end
      pending_write_by_sid[slave_index][int'(rsp.id)]--;
    end
    else begin
      if (pending_read_by_sid[slave_index][int'(rsp.id)] == 0) begin
        error_count++;
        `uvm_error("AXI_SYS_REF_UNSOLICITED_R", $sformatf(
          "S%0d R response SID 0x%0h has no modeled request",
          slave_index, rsp.id))
        continue;
      end
      pending_read_by_sid[slave_index][int'(rsp.id)]--;
    end
    expected_rsp = transform_response(rsp);
    m_rsp_ap[master_index].write(expected_rsp);
  end
endtask

function int signed axi_system_ref_model::route_to_index(axi_route_e route);
  case (route)
    AXI_ROUTE_S0: return 0;
    AXI_ROUTE_S1: return 1;
    AXI_ROUTE_S2: return 2;
    default: return -1;
  endcase
endfunction

function int unsigned axi_system_ref_model::pending_count();
  int unsigned total;
  total = 0;
  foreach (m_req_fifo[index]) total += m_req_fifo[index].used();
  foreach (s_rsp_fifo[index]) total += s_rsp_fifo[index].used();
  foreach (pending_write_by_sid[port, id]) begin
    total += pending_write_by_sid[port][id];
    total += pending_read_by_sid[port][id];
  end
  return total;
endfunction

function void axi_system_ref_model::check_phase(uvm_phase phase);
  super.check_phase(phase);
  if (enabled && (pending_count() != 0))
    `uvm_error("AXI_SYS_REF_PENDING", $sformatf(
      "Reference model has %0d unprocessed input items", pending_count()))
endfunction

`endif

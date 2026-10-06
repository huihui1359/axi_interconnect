`ifndef AXI_SYSTEM_COVERAGE_SV
`define AXI_SYSTEM_COVERAGE_SV

class axi_system_coverage extends uvm_component;

  uvm_tlm_analysis_fifo #(axi_m_req_t) m_req_fifo[AXI_NUM_MASTERS];
  axi_switch_ref_model map;
  bit enabled;
  int unsigned sampled_master;
  int unsigned sampled_slave;
  axi_dir_e sampled_dir;

  covergroup system_cg;
    option.per_instance = 1;
    cp_master: coverpoint sampled_master { bins ports[] = {[0:2]}; }
    cp_slave: coverpoint sampled_slave { bins normal[] = {[0:2]}; }
    cp_dir: coverpoint sampled_dir;
    master_x_slave_x_dir: cross cp_master, cp_slave, cp_dir;
  endgroup

  `uvm_component_utils(axi_system_coverage)

  extern function new(string name = "axi_system_coverage",
                      uvm_component parent = null);
  extern virtual function void build_phase(uvm_phase phase);
  extern virtual task run_phase(uvm_phase phase);
  extern task collect_master_requests(int unsigned master_index);

endclass

function axi_system_coverage::new(
  string name = "axi_system_coverage",
  uvm_component parent = null
);
  super.new(name, parent);
  enabled = 1'b0;
  system_cg = new();
endfunction

function void axi_system_coverage::build_phase(uvm_phase phase);
  super.build_phase(phase);
  map = axi_switch_ref_model::type_id::create("map");
  foreach (m_req_fifo[index])
    m_req_fifo[index] = new($sformatf("m_req_fifo_%0d", index), this);
endfunction

task axi_system_coverage::run_phase(uvm_phase phase);
  if (!enabled)
    return;
  for (int unsigned index = 0; index < AXI_NUM_MASTERS; index++) begin
    automatic int unsigned port_index = index;
    fork collect_master_requests(port_index); join_none
  end
  wait fork;
endtask

task axi_system_coverage::collect_master_requests(
  int unsigned master_index
);
  axi_m_req_t req;
  axi_route_e route;
  forever begin
    m_req_fifo[master_index].get(req);
    route = map.decode_address(req.addr);
    sampled_master = master_index;
    sampled_dir = req.dir;
    case (route)
      AXI_ROUTE_S0: sampled_slave = 0;
      AXI_ROUTE_S1: sampled_slave = 1;
      AXI_ROUTE_S2: sampled_slave = 2;
      default: begin
        `uvm_error("AXI_COV_UNMAPPED_ADDR", $sformatf(
          "M%0d Stage 6 coverage observed unmapped address 0x%0h",
          master_index, req.addr))
        continue;
      end
    endcase
    system_cg.sample();
  end
endtask

`endif

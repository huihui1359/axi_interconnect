`ifndef AXI_SWITCH_REF_MODEL_SV
`define AXI_SWITCH_REF_MODEL_SV

class axi_switch_ref_model #(
  int unsigned ADDR_WIDTH = AXI_ADDR_WIDTH,
  int unsigned M_ID_WIDTH = AXI_M_ID_WIDTH,
  int unsigned S_ID_WIDTH = AXI_S_ID_WIDTH
) extends uvm_object;

  typedef bit [M_ID_WIDTH-1:0] master_id_t;
  typedef bit [S_ID_WIDTH-1:0] slave_id_t;

  `uvm_object_param_utils(
    axi_switch_ref_model #(ADDR_WIDTH, M_ID_WIDTH, S_ID_WIDTH)
  )

  extern function new(string name = "axi_switch_ref_model");
  extern function axi_route_e decode_address(bit [ADDR_WIDTH-1:0] address);
  extern function axi_route_e decode_w_target(master_id_t id);
  extern function bit [1:0] master_to_tag(int unsigned port_index);
  extern function bit [1:0] slave_to_tag(axi_route_e route);
  extern function master_id_t build_master_id(
    axi_route_e route,
    bit [1:0] transaction_tag
  );
  extern function slave_id_t encode_sid(
    int unsigned master_index,
    axi_route_e route,
    master_id_t original_id
  );
  extern function int signed decode_master(slave_id_t sid);
  extern function master_id_t restore_id(slave_id_t sid);

endclass

function axi_switch_ref_model::new(string name = "axi_switch_ref_model");
  super.new(name);
  if ((M_ID_WIDTH != 4) || (S_ID_WIDTH != 8))
    `uvm_fatal("AXI_SWITCH_REF_PARAM",
               "Stage 3 switch model requires 4-bit MID and 8-bit SID")
endfunction

function axi_route_e axi_switch_ref_model::decode_address(
  bit [ADDR_WIDTH-1:0] address
);
  if (address inside {[32'h0000_0000:32'h0000_0fff]})
    return AXI_ROUTE_S0;
  if (address inside {[32'h0000_2000:32'h0000_2fff]})
    return AXI_ROUTE_S1;
  if (address inside {[32'h0000_4000:32'h0000_4fff]})
    return AXI_ROUTE_S2;
  return AXI_ROUTE_DEFAULT;
endfunction

function axi_route_e axi_switch_ref_model::decode_w_target(master_id_t id);
  case (id[M_ID_WIDTH-1 -: 2])
    2'b01: return AXI_ROUTE_S0;
    2'b10: return AXI_ROUTE_S1;
    2'b11: return AXI_ROUTE_S2;
    default: return AXI_ROUTE_INVALID;
  endcase
endfunction

function bit [1:0] axi_switch_ref_model::master_to_tag(
  int unsigned port_index
);
  case (port_index)
    0: return 2'b01;
    1: return 2'b10;
    2: return 2'b11;
    default: return 2'b00;
  endcase
endfunction

function bit [1:0] axi_switch_ref_model::slave_to_tag(axi_route_e route);
  case (route)
    AXI_ROUTE_S0: return 2'b01;
    AXI_ROUTE_S1: return 2'b10;
    AXI_ROUTE_S2: return 2'b11;
    default: return 2'b00;
  endcase
endfunction

function axi_switch_ref_model::master_id_t
axi_switch_ref_model::build_master_id(
  axi_route_e route,
  bit [1:0] transaction_tag
);
  return master_id_t'({slave_to_tag(route), transaction_tag});
endfunction

function axi_switch_ref_model::slave_id_t axi_switch_ref_model::encode_sid(
  int unsigned master_index,
  axi_route_e route,
  master_id_t original_id
);
  return slave_id_t'({slave_to_tag(route), master_to_tag(master_index),
                      original_id});
endfunction

function int signed axi_switch_ref_model::decode_master(slave_id_t sid);
  case (sid[5:4])
    2'b01: return 0;
    2'b10: return 1;
    2'b11: return 2;
    default: return -1;
  endcase
endfunction

function axi_switch_ref_model::master_id_t
axi_switch_ref_model::restore_id(slave_id_t sid);
  return master_id_t'(sid[M_ID_WIDTH-1:0]);
endfunction

`endif

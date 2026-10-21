`ifndef AXI_CR_OP_SV
`define AXI_CR_OP_SV

class axi_cr_op extends uvm_object;

  int unsigned master_index;
  axi_route_e route;
  axi_m_req_t req;

  `uvm_object_utils(axi_cr_op)

  function new(string name = "axi_cr_op");
    super.new(name);
    master_index = 0;
    route = AXI_ROUTE_INVALID;
    req = null;
  endfunction

  virtual function bit build_request(
    axi_cr_cfg cfg,
    int unsigned selected_master,
    axi_route_e selected_route,
    axi_dir_e selected_dir
  );
    bit [AXI_ADDR_WIDTH-1:0] address_low;
    bit [AXI_ADDR_WIDTH-1:0] address_high;
    bit [1:0] route_tag;

    int unsigned len_zero_weight;
    int unsigned len_one_weight;
    int unsigned len_other_weight;
    int unsigned len_fifteen_weight;
    int unsigned fixed_burst_weight;
    int unsigned incr_burst_weight;
    int unsigned wrap_burst_weight;
    int unsigned size_byte_weight;
    int unsigned size_halfword_weight;
    int unsigned size_word_weight;
    int unsigned request_delay_min;
    int unsigned request_delay_max;
    int unsigned write_gap_min;
    int unsigned write_gap_max;
    bit constrain_read_id_to_route;

    master_index = selected_master;
    route = selected_route;

    case (route)
      AXI_ROUTE_S0: begin
        address_low  = 32'h0000_0000;
        address_high = 32'h0000_0fff;
        route_tag    = 2'b01;
      end
      AXI_ROUTE_S1: begin
        address_low  = 32'h0000_2000;
        address_high = 32'h0000_2fff;
        route_tag    = 2'b10;
      end
      AXI_ROUTE_S2: begin
        address_low  = 32'h0000_4000;
        address_high = 32'h0000_4fff;
        route_tag    = 2'b11;
      end
      default: begin
        `uvm_error("AXI_CR_OP", $sformatf(
          "Unsupported positive-traffic route %s", route.name()))
        return 1'b0;
      end
    endcase

    len_zero_weight     = cfg.len_zero_weight;
    len_one_weight      = cfg.len_one_weight;
    len_other_weight    = cfg.len_other_weight;
    len_fifteen_weight  = cfg.len_fifteen_weight;
    fixed_burst_weight  = cfg.fixed_burst_weight;
    incr_burst_weight   = cfg.incr_burst_weight;
    wrap_burst_weight   = cfg.wrap_burst_weight;
    size_byte_weight    = cfg.size_byte_weight;
    size_halfword_weight = cfg.size_halfword_weight;
    size_word_weight    = cfg.size_word_weight;
    request_delay_min   = cfg.request_delay_min;
    request_delay_max   = cfg.request_delay_max;
    write_gap_min       = cfg.write_gap_min;
    write_gap_max       = cfg.write_gap_max;
    constrain_read_id_to_route = cfg.constrain_read_id_to_route;

    req = axi_m_req_t::type_id::create("req");
    req.c_default_distribution.constraint_mode(0);
    if (!req.randomize() with {
      dir == local::selected_dir;
      addr inside {[local::address_low:local::address_high]};
      len dist {
        0      := local::len_zero_weight,
        1      := local::len_one_weight,
        [2:14] :/ local::len_other_weight,
        15     := local::len_fifteen_weight
      };
      burst dist {
        AXI_BURST_FIXED := local::fixed_burst_weight,
        AXI_BURST_INCR  := local::incr_burst_weight,
        AXI_BURST_WRAP  := local::wrap_burst_weight
      };
      size dist {
        0 := local::size_byte_weight,
        1 := local::size_halfword_weight,
        2 := local::size_word_weight
      };
      addr_delay inside {
        [local::request_delay_min:local::request_delay_max]
      };
      w_start_delay inside {
        [local::request_delay_min:local::request_delay_max]
      };
      foreach (wbeat_gap[index])
        wbeat_gap[index] inside {
          [local::write_gap_min:local::write_gap_max]
        };
      if (local::selected_dir == AXI_WRITE)
        id[AXI_M_ID_WIDTH-1 -: 2] == local::route_tag;
      if ((local::selected_dir == AXI_READ) &&
          local::constrain_read_id_to_route)
        id[AXI_M_ID_WIDTH-1 -: 2] == local::route_tag;
    }) begin
      `uvm_error("AXI_CR_OP", $sformatf(
        "Failed to randomize M%0d %s request for %s",
        master_index, selected_dir.name(), route.name()))
      return 1'b0;
    end

    return 1'b1;
  endfunction

  virtual function string convert2string();
    if (req == null)
      return $sformatf("master=%0d route=%s req=null",
                       master_index, route.name());
    return $sformatf("master=%0d route=%s %s",
                     master_index, route.name(), req.convert2string());
  endfunction

endclass

`endif

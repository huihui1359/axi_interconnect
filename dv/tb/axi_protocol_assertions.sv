module axi_protocol_assertions(axi_if bus);

  property p_aw_stable;
    @(posedge bus.ACLK) disable iff (!bus.ARESETn)
      bus.awvalid && !bus.awready
      |=> bus.awvalid && $stable({bus.awid, bus.awaddr, bus.awlen,
                                  bus.awsize, bus.awburst});
  endproperty

  property p_w_stable;
    @(posedge bus.ACLK) disable iff (!bus.ARESETn)
      bus.wvalid && !bus.wready
      |=> bus.wvalid && $stable({bus.wid, bus.wdata, bus.wstrb, bus.wlast});
  endproperty

  property p_b_stable;
    @(posedge bus.ACLK) disable iff (!bus.ARESETn)
      bus.bvalid && !bus.bready
      |=> bus.bvalid && $stable({bus.bid, bus.bresp});
  endproperty

  property p_ar_stable;
    @(posedge bus.ACLK) disable iff (!bus.ARESETn)
      bus.arvalid && !bus.arready
      |=> bus.arvalid && $stable({bus.arid, bus.araddr, bus.arlen,
                                  bus.arsize, bus.arburst});
  endproperty

  property p_r_stable;
    @(posedge bus.ACLK) disable iff (!bus.ARESETn)
      bus.rvalid && !bus.rready
      |=> bus.rvalid && $stable({bus.rid, bus.rdata, bus.rresp, bus.rlast});
  endproperty

  property p_aw_known;
    @(posedge bus.ACLK) disable iff (!bus.ARESETn)
      bus.awvalid && bus.awready
      |-> !$isunknown({bus.awid, bus.awaddr, bus.awlen,
                       bus.awsize, bus.awburst});
  endproperty

  property p_w_known_and_last;
    @(posedge bus.ACLK) disable iff (!bus.ARESETn)
      bus.wvalid && bus.wready
      |-> (!$isunknown({bus.wid, bus.wdata, bus.wstrb, bus.wlast}) &&
           (bus.wlast === 1'b1));
  endproperty

  property p_b_known;
    @(posedge bus.ACLK) disable iff (!bus.ARESETn)
      bus.bvalid && bus.bready
      |-> !$isunknown({bus.bid, bus.bresp});
  endproperty

  property p_ar_known;
    @(posedge bus.ACLK) disable iff (!bus.ARESETn)
      bus.arvalid && bus.arready
      |-> !$isunknown({bus.arid, bus.araddr, bus.arlen,
                       bus.arsize, bus.arburst});
  endproperty

  property p_r_known_and_last;
    @(posedge bus.ACLK) disable iff (!bus.ARESETn)
      bus.rvalid && bus.rready
      |-> (!$isunknown({bus.rid, bus.rdata, bus.rresp, bus.rlast}) &&
           (bus.rlast === 1'b1));
  endproperty

  ap_aw_stable: assert property (p_aw_stable);
  ap_w_stable:  assert property (p_w_stable);
  ap_b_stable:  assert property (p_b_stable);
  ap_ar_stable: assert property (p_ar_stable);
  ap_r_stable:  assert property (p_r_stable);
  ap_aw_known:  assert property (p_aw_known);
  ap_w_known:   assert property (p_w_known_and_last);
  ap_b_known:   assert property (p_b_known);
  ap_ar_known:  assert property (p_ar_known);
  ap_r_known:   assert property (p_r_known_and_last);

endmodule

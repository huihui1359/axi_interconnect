`ifndef AXI_PROTOCOL_ASSERTIONS_SV
`define AXI_PROTOCOL_ASSERTIONS_SV

import uvm_pkg::*;

module axi_protocol_assertions #(
  int unsigned ADDR_WIDTH       = 32,
  int unsigned DATA_WIDTH       = 32,
  int unsigned ID_WIDTH         = 4,
  int unsigned LEN_WIDTH        = 4,
  int unsigned MAX_OUTSTANDING  = 4,
  bit          TB_IS_MASTER     = 1'b1,
  bit          STAGE3_CHECKS    = 1'b0,
  bit          STAGE6_CHECKS    = 1'b0,
  int unsigned PORT_INDEX       = 0
) (
  input logic ACLK,
  input logic ARESETn,

  input logic [ID_WIDTH-1:0] awid,
  input logic [ADDR_WIDTH-1:0] awaddr,
  input logic [LEN_WIDTH-1:0] awlen,
  input logic [2:0] awsize,
  input logic [1:0] awburst,
  input logic awvalid,
  input logic awready,

  input logic [ID_WIDTH-1:0] wid,
  input logic [DATA_WIDTH-1:0] wdata,
  input logic [(DATA_WIDTH/8)-1:0] wstrb,
  input logic wlast,
  input logic wvalid,
  input logic wready,

  input logic [ID_WIDTH-1:0] bid,
  input logic [1:0] bresp,
  input logic bvalid,
  input logic bready,

  input logic [ID_WIDTH-1:0] arid,
  input logic [ADDR_WIDTH-1:0] araddr,
  input logic [LEN_WIDTH-1:0] arlen,
  input logic [2:0] arsize,
  input logic [1:0] arburst,
  input logic arvalid,
  input logic arready,

  input logic [ID_WIDTH-1:0] rid,
  input logic [DATA_WIDTH-1:0] rdata,
  input logic [1:0] rresp,
  input logic rlast,
  input logic rvalid,
  input logic rready
);

  localparam int unsigned ID_COUNT = 1 << ID_WIDTH;

  int unsigned aw_outstanding_by_id[ID_COUNT];
  int unsigned w_outstanding_by_id[ID_COUNT];
  int unsigned ar_outstanding_by_id[ID_COUNT];
  int unsigned aw_len_by_id[ID_COUNT][$];
  int unsigned completed_w_count_by_id[ID_COUNT][$];
  int unsigned ar_len_by_id[ID_COUNT][$];

  bit w_active;
  logic [ID_WIDTH-1:0] active_wid;
  int unsigned w_beat_count;
  bit r_active;
  logic [ID_WIDTH-1:0] active_rid;
  int unsigned active_rlen;
  int unsigned r_beat_count;
  int unsigned b_eligible_count;

  // Function: 将断言失败统一转换为带指定report ID的UVM_ERROR。
  function void report_assertion_error(string report_id);
    uvm_report_error(report_id, "AXI protocol assertion failed");
  endfunction

  // Function: 汇总所有ID当前尚未返回B响应的写地址事务数量。
  function automatic int unsigned write_outstanding();
    int unsigned total;
    total = 0;
    foreach (aw_outstanding_by_id[id])
      total += aw_outstanding_by_id[id];
    return total;
  endfunction

  // Function: 汇总所有ID当前尚未完成R响应的读地址事务数量。
  function automatic int unsigned read_outstanding();
    int unsigned total;
    total = 0;
    foreach (ar_outstanding_by_id[id])
      total += ar_outstanding_by_id[id];
    return total;
  endfunction

  // Function: 按Stage 3/Stage 6及接口ID位宽检查完整ID编码是否合法。
  function automatic bit valid_stage3_id(logic [ID_WIDTH-1:0] id);
    longint unsigned id_value;
    if ($isunknown(id))
      return 1'b0;
    id_value = longint'(id);
    if (STAGE6_CHECKS && (ID_WIDTH == 4))
      return (((id_value >> 2) & 2'b11) != 2'b00);
    if (STAGE6_CHECKS && (ID_WIDTH == 8))
      return ((((id_value >> 6) & 2'b11) == (PORT_INDEX + 1)) &&
              (((id_value >> 4) & 2'b11) != 2'b00) &&
              (((id_value >> 2) & 2'b11) ==
               ((id_value >> 6) & 2'b11)));
    if (ID_WIDTH == 4)
      return ((id_value >> 2) & 2'b11) == 2'b01;
    if (ID_WIDTH == 8)
      return (((id_value >> 6) & 2'b11) == 2'b01) &&
             (((id_value >> 4) & 2'b11) == 2'b01) &&
             (((id_value >> 2) & 2'b11) == 2'b01);
    return 1'b1;
  endfunction

  // Function: 检查8-bit SID中的master tag是否为允许的非零/指定编码。
  function automatic bit valid_stage3_master_tag(
    logic [ID_WIDTH-1:0] id
  );
    longint unsigned id_value;
    if ($isunknown(id))
      return 1'b0;
    id_value = longint'(id);
    if (STAGE6_CHECKS && (ID_WIDTH == 8))
      return (((id_value >> 4) & 2'b11) != 2'b00);
    if (ID_WIDTH == 8)
      return ((id_value >> 4) & 2'b11) == 2'b01;
    return 1'b1;
  endfunction

  // Function: 检查8-bit SID中的源slave tag与路由slave tag是否一致。
  function automatic bit valid_stage3_slave_tag(
    logic [ID_WIDTH-1:0] id
  );
    longint unsigned id_value;
    if ($isunknown(id))
      return 1'b0;
    id_value = longint'(id);
    if (ID_WIDTH == 8)
      return (((id_value >> 6) & 2'b11) ==
              ((id_value >> 2) & 2'b11));
    return 1'b1;
  endfunction

  // Function: 根据地址窗口计算目标route tag，并检查ID高位路由字段是否匹配。
  function automatic bit id_matches_address(
    logic [ID_WIDTH-1:0] id,
    logic [ADDR_WIDTH-1:0] address
  );
    logic [1:0] route_tag;
    route_tag = 2'b00;
    if (address inside {[32'h0000_0000:32'h0000_0fff]})
      route_tag = 2'b01;
    else if (address inside {[32'h0000_2000:32'h0000_2fff]})
      route_tag = 2'b10;
    else if (address inside {[32'h0000_4000:32'h0000_4fff]})
      route_tag = 2'b11;
    if (route_tag == 2'b00)
      return 1'b1;
    if (ID_WIDTH == 4)
      return id[ID_WIDTH-1 -: 2] == route_tag;
    if (ID_WIDTH == 8)
      return id[ID_WIDTH-1 -: 2] == route_tag;
    return 1'b1;
  endfunction

  // Function: 按ID配对AWLEN与已完成W burst的beat数，并检查二者一致。
  function automatic void pair_write_context(int unsigned id);
    int unsigned expected_count;
    int unsigned observed_count;
    if ((aw_len_by_id[id].size() == 0) ||
        (completed_w_count_by_id[id].size() == 0))
      return;

    expected_count = aw_len_by_id[id].pop_front() + 1;
    observed_count = completed_w_count_by_id[id].pop_front();
    // ORD-IMM-001: 已完成W burst的beat数必须等于配对AWLEN加1。
    assert (observed_count == expected_count)
      else report_assertion_error("AXI_ASSERT_W_COUNT");
  endfunction

  // AXI-SVA-001: AW发生反压时，AWVALID及全部AW payload必须保持稳定。
  property p_aw_stable;
    @(posedge ACLK) disable iff (ARESETn !== 1'b1)
      awvalid && !awready |=>
        awvalid && $stable({awid, awaddr, awlen, awsize, awburst});
  endproperty

  // AXI-SVA-002: W发生反压时，WVALID及全部W payload必须保持稳定。
  property p_w_stable;
    @(posedge ACLK) disable iff (ARESETn !== 1'b1)
      wvalid && !wready |=>
        wvalid && $stable({wid, wdata, wstrb, wlast});
  endproperty

  // AXI-SVA-003: B发生反压时，BVALID及全部B payload必须保持稳定。
  property p_b_stable;
    @(posedge ACLK) disable iff (ARESETn !== 1'b1)
      bvalid && !bready |=> bvalid && $stable({bid, bresp});
  endproperty

  // AXI-SVA-004: BVALID只能在已有完整W burst或本周期刚完成W burst时出现。
  property p_b_causality;
    @(posedge ACLK) disable iff (ARESETn !== 1'b1)
      bvalid |-> ((b_eligible_count != 0) ||
                  (wvalid && wready && wlast));
  endproperty

  // AXI-SVA-005: AR发生反压时，ARVALID及全部AR payload必须保持稳定。
  property p_ar_stable;
    @(posedge ACLK) disable iff (ARESETn !== 1'b1)
      arvalid && !arready |=>
        arvalid && $stable({arid, araddr, arlen, arsize, arburst});
  endproperty

  // AXI-SVA-006: R发生反压时，RVALID及全部R payload必须保持稳定。
  property p_r_stable;
    @(posedge ACLK) disable iff (ARESETn !== 1'b1)
      rvalid && !rready |=>
        rvalid && $stable({rid, rdata, rresp, rlast});
  endproperty

  a_aw_stable: assert property (p_aw_stable)
    else report_assertion_error("AXI_ASSERT_AW_STABLE");
  a_w_stable: assert property (p_w_stable)
    else report_assertion_error("AXI_ASSERT_W_STABLE");
  a_b_stable: assert property (p_b_stable)
    else report_assertion_error("AXI_ASSERT_B_STABLE");
  a_b_causality: assert property (p_b_causality)
    else report_assertion_error("AXI_ASSERT_B_CAUSALITY");
  a_ar_stable: assert property (p_ar_stable)
    else report_assertion_error("AXI_ASSERT_AR_STABLE");
  a_r_stable: assert property (p_r_stable)
    else report_assertion_error("AXI_ASSERT_R_STABLE");

  generate
    if (TB_IS_MASTER) begin : master_reset_outputs
      // RST-SVA-001: Master侧复位期间所有由Master驱动的控制输出必须为0。
      property p_master_outputs_reset;
        @(posedge ACLK)
          ARESETn === 1'b0 |->
            !awvalid && !wvalid && !bready && !arvalid && !rready;
      endproperty
      a_master_outputs_reset: assert property (p_master_outputs_reset)
        else report_assertion_error("AXI_ASSERT_MASTER_RESET_OUTPUTS");
    end
    else begin : slave_reset_outputs
      // RST-SVA-002: Slave侧复位期间所有由Slave驱动的控制输出必须为0。
      property p_slave_outputs_reset;
        @(posedge ACLK)
          ARESETn === 1'b0 |->
            !awready && !wready && !bvalid && !arready && !rvalid;
      endproperty
      a_slave_outputs_reset: assert property (p_slave_outputs_reset)
        else report_assertion_error("AXI_ASSERT_SLAVE_RESET_OUTPUTS");
    end
  endgenerate

  always @(posedge ACLK) begin
    int unsigned id;
    int unsigned current_count;
    int unsigned expected_count;

    if (ARESETn !== 1'b1) begin
      foreach (aw_outstanding_by_id[index]) begin
        aw_outstanding_by_id[index] = 0;
        w_outstanding_by_id[index]  = 0;
        ar_outstanding_by_id[index] = 0;
        aw_len_by_id[index].delete();
        completed_w_count_by_id[index].delete();
        ar_len_by_id[index].delete();
      end
      w_active        = 1'b0;
      active_wid      = '0;
      w_beat_count    = 0;
      r_active        = 1'b0;
      active_rid      = '0;
      active_rlen     = 0;
      r_beat_count    = 0;
      b_eligible_count = 0;
    end
    else begin
      // AXI-IMM-001: 复位释放后，五通道VALID/READY控制信号不得包含X/Z。
      assert (!$isunknown({awvalid, awready, wvalid, wready,
                           bvalid, bready, arvalid, arready,
                           rvalid, rready}))
        else report_assertion_error("AXI_ASSERT_CONTROL_X");

      if (awvalid && awready) begin
        // AXI-IMM-002: AW握手时，AW ID、地址及burst属性不得包含X/Z。
        assert (!$isunknown({awid, awaddr, awlen, awsize, awburst}))
          else report_assertion_error("AXI_ASSERT_AW_PAYLOAD_X");
        if (!$isunknown(awid)) begin
          id = int'(awid);
          aw_outstanding_by_id[id]++;
          aw_len_by_id[id].push_back(int'(awlen));
          pair_write_context(id);
          if (STAGE3_CHECKS) begin
            // ID-IMM-001: AWID完整编码必须符合当前Stage及接口位宽规则。
            assert (valid_stage3_id(awid))
              else report_assertion_error("AXI_ASSERT_AW_ID");
            // ID-IMM-002: AWID中的master tag必须合法。
            assert (valid_stage3_master_tag(awid))
              else report_assertion_error("AXI_ASSERT_AW_MASTER_TAG");
            // ID-IMM-003: AWID中的源slave tag与路由slave tag必须一致。
            assert (valid_stage3_slave_tag(awid))
              else report_assertion_error("AXI_ASSERT_AW_SLAVE_TAG");
            if (STAGE6_CHECKS)
              // ID-IMM-004: AWID中的目标路由字段必须匹配AWADDR地址窗口。
              assert (id_matches_address(awid, awaddr))
                else report_assertion_error("AXI_ASSERT_AW_ROUTE");
          end
        end
      end

      if (wvalid && wready) begin
        // AXI-IMM-003: W握手时，W ID、数据、字节使能和WLAST不得包含X/Z。
        assert (!$isunknown({wid, wdata, wstrb, wlast}))
          else report_assertion_error("AXI_ASSERT_W_PAYLOAD_X");
        if (!$isunknown(wid)) begin
          id = int'(wid);
          if (!w_active) begin
            w_active     = 1'b1;
            active_wid   = wid;
            w_beat_count = 0;
          end
          else begin
            // ORD-IMM-002: 同一个未完成W burst内的WID必须保持不变。
            assert (wid === active_wid)
              else report_assertion_error("AXI_ASSERT_WID_STABLE");
          end

          current_count = w_beat_count + 1;
          w_beat_count  = current_count;
          if (aw_len_by_id[id].size() != 0) begin
            expected_count = aw_len_by_id[id][0] + 1;
            if (current_count < expected_count)
              // ORD-IMM-003: 到达AWLEN指定的最后beat前不得提前置WLAST。
              assert (!wlast)
                else report_assertion_error("AXI_ASSERT_WLAST_EARLY");
            else if (current_count == expected_count)
              // ORD-IMM-004: 到达AWLEN指定的最后beat时必须置WLAST。
              assert (wlast)
                else report_assertion_error("AXI_ASSERT_WLAST_MISSING");
            else
              // ORD-IMM-005: W burst beat数不得超过配对AWLEN加1。
              assert (1'b0)
                else report_assertion_error("AXI_ASSERT_W_COUNT_EXCESS");
          end

          if (wlast) begin
            completed_w_count_by_id[id].push_back(current_count);
            w_outstanding_by_id[id]++;
            b_eligible_count++;
            pair_write_context(id);
            w_active     = 1'b0;
            w_beat_count = 0;
          end
          if (STAGE3_CHECKS) begin
            // ID-IMM-005: WID完整编码必须符合当前Stage及接口位宽规则。
            assert (valid_stage3_id(wid))
              else report_assertion_error("AXI_ASSERT_W_ID");
            // ID-IMM-006: WID中的master tag必须合法。
            assert (valid_stage3_master_tag(wid))
              else report_assertion_error("AXI_ASSERT_W_MASTER_TAG");
            // ID-IMM-007: WID中的源slave tag与路由slave tag必须一致。
            assert (valid_stage3_slave_tag(wid))
              else report_assertion_error("AXI_ASSERT_W_SLAVE_TAG");
          end
        end
      end

      if (arvalid && arready) begin
        // AXI-IMM-004: AR握手时，AR ID、地址及burst属性不得包含X/Z。
        assert (!$isunknown({arid, araddr, arlen, arsize, arburst}))
          else report_assertion_error("AXI_ASSERT_AR_PAYLOAD_X");
        if (!$isunknown(arid)) begin
          id = int'(arid);
          ar_outstanding_by_id[id]++;
          ar_len_by_id[id].push_back(int'(arlen));
          if (STAGE3_CHECKS) begin
            // ID-IMM-008: ARID完整编码必须符合当前Stage及接口位宽规则。
            assert (valid_stage3_id(arid))
              else report_assertion_error("AXI_ASSERT_AR_ID");
            // ID-IMM-009: ARID中的master tag必须合法。
            assert (valid_stage3_master_tag(arid))
              else report_assertion_error("AXI_ASSERT_AR_MASTER_TAG");
            // ID-IMM-010: ARID中的源slave tag与路由slave tag必须一致。
            assert (valid_stage3_slave_tag(arid))
              else report_assertion_error("AXI_ASSERT_AR_SLAVE_TAG");
            if (STAGE6_CHECKS)
              // ID-IMM-011: ARID中的目标路由字段必须匹配ARADDR地址窗口。
              assert (id_matches_address(arid, araddr))
                else report_assertion_error("AXI_ASSERT_AR_ROUTE");
          end
        end
      end

      if (bvalid && bready) begin
        // AXI-IMM-005: B握手时，BID和BRESP不得包含X/Z。
        assert (!$isunknown({bid, bresp}))
          else report_assertion_error("AXI_ASSERT_B_PAYLOAD_X");
        if (!$isunknown(bid)) begin
          id = int'(bid);
          if (STAGE3_CHECKS) begin
            // ID-IMM-012: BID完整编码必须符合当前Stage及接口位宽规则。
            assert (valid_stage3_id(bid))
              else report_assertion_error("AXI_ASSERT_B_ID");
            // ID-IMM-013: BID中的master tag必须合法。
            assert (valid_stage3_master_tag(bid))
              else report_assertion_error("AXI_ASSERT_B_MASTER_TAG");
            // ID-IMM-014: BID中的源slave tag与路由slave tag必须一致。
            assert (valid_stage3_slave_tag(bid))
              else report_assertion_error("AXI_ASSERT_B_SLAVE_TAG");
            if ((aw_outstanding_by_id[id] == 0) &&
                (w_outstanding_by_id[id] == 0)) begin
              // ORD-IMM-006: B响应必须存在同ID的AW和已完成W burst上下文。
              assert (1'b0)
                else report_assertion_error("AXI_ASSERT_B_NO_PENDING");
            end
            else begin
              // ORD-IMM-007: B响应不得使同ID写地址outstanding计数下溢。
              assert (aw_outstanding_by_id[id] != 0)
                else report_assertion_error("AXI_ASSERT_B_AW_UNDERFLOW");
              // ORD-IMM-008: B响应前必须已完成同ID的W burst，保持同ID顺序。
              assert (w_outstanding_by_id[id] != 0)
                else report_assertion_error("AXI_ASSERT_B_SAME_ID_ORDER");
            end
          end
          if (aw_outstanding_by_id[id] != 0)
            aw_outstanding_by_id[id]--;
          if (w_outstanding_by_id[id] != 0)
            w_outstanding_by_id[id]--;
          if (b_eligible_count != 0)
            b_eligible_count--;
        end
      end

      if (rvalid && rready) begin
        // AXI-IMM-006: R握手时，RID、数据、响应和RLAST不得包含X/Z。
        assert (!$isunknown({rid, rdata, rresp, rlast}))
          else report_assertion_error("AXI_ASSERT_R_PAYLOAD_X");
        if (!$isunknown(rid)) begin
          id = int'(rid);
          if (!r_active) begin
            // ORD-IMM-009: 新R burst必须能找到同ID的未完成AR上下文。
            assert (ar_len_by_id[id].size() != 0)
              else report_assertion_error("AXI_ASSERT_R_CAUSALITY");
            if (ar_len_by_id[id].size() != 0) begin
              r_active     = 1'b1;
              active_rid   = rid;
              active_rlen  = ar_len_by_id[id][0];
              r_beat_count = 0;
            end
          end
          else begin
            // ORD-IMM-010: 同一个未完成R burst内的RID必须保持不变。
            assert (rid === active_rid)
              else report_assertion_error("AXI_ASSERT_RID_STABLE");
          end

          if (r_active) begin
            current_count = r_beat_count + 1;
            expected_count = active_rlen + 1;
            r_beat_count = current_count;
            if (current_count < expected_count)
              // ORD-IMM-011: 到达ARLEN指定的最后beat前不得提前置RLAST。
              assert (!rlast)
                else report_assertion_error("AXI_ASSERT_RLAST_EARLY");
            else if (current_count == expected_count)
              // ORD-IMM-012: 到达ARLEN指定的最后beat时必须置RLAST。
              assert (rlast)
                else report_assertion_error("AXI_ASSERT_RLAST_MISSING");
            else
              // ORD-IMM-013: R burst beat数不得超过配对ARLEN加1。
              assert (1'b0)
                else report_assertion_error("AXI_ASSERT_R_COUNT_EXCESS");

            if (rlast) begin
              id = int'(active_rid);
              if (ar_len_by_id[id].size() != 0)
                expected_count = ar_len_by_id[id].pop_front();
              if (ar_outstanding_by_id[id] == 0)
                // ORD-IMM-014: RLAST完成时不得使同ID读outstanding计数下溢。
                assert (1'b0)
                  else report_assertion_error("AXI_ASSERT_R_UNDERFLOW");
              else
                ar_outstanding_by_id[id]--;
              r_active     = 1'b0;
              r_beat_count = 0;
            end
          end
          if (STAGE3_CHECKS) begin
            // ID-IMM-015: RID完整编码必须符合当前Stage及接口位宽规则。
            assert (valid_stage3_id(rid))
              else report_assertion_error("AXI_ASSERT_R_ID");
            // ID-IMM-016: RID中的master tag必须合法。
            assert (valid_stage3_master_tag(rid))
              else report_assertion_error("AXI_ASSERT_R_MASTER_TAG");
            // ID-IMM-017: RID中的源slave tag与路由slave tag必须一致。
            assert (valid_stage3_slave_tag(rid))
              else report_assertion_error("AXI_ASSERT_R_SLAVE_TAG");
          end
        end
      end

      if (STAGE3_CHECKS) begin
        // ORD-IMM-015: 全部ID合计的写outstanding数量不得超过配置上限。
        assert (write_outstanding() <= MAX_OUTSTANDING)
          else report_assertion_error("AXI_ASSERT_WRITE_OUTSTANDING");
        // ORD-IMM-016: 全部ID合计的读outstanding数量不得超过配置上限。
        assert (read_outstanding() <= MAX_OUTSTANDING)
          else report_assertion_error("AXI_ASSERT_READ_OUTSTANDING");
      end
    end
  end

endmodule

`endif

`ifndef AXI_STAGE6_VSEQS_SV
`define AXI_STAGE6_VSEQS_SV

// 测试点：遍历 3x3 Master/Slave 路由矩阵，每个组合各发送一笔写和一笔读。
class axi_stage6_route_matrix_vseq extends axi_stage6_base_vseq;
  `uvm_object_utils(axi_stage6_route_matrix_vseq)
  function new(string name="axi_stage6_route_matrix_vseq"); super.new(name); endfunction
  virtual task body();
    fork
      run_responder(0, 6); run_responder(1, 6); run_responder(2, 6);
      begin
        for (int m = 0; m < 3; m++) begin
          automatic int master = m;
          fork begin
            for (int s = 0; s < 3; s++) begin
              send_write(master, s, s, 32'h1000_0000 + (master << 8) + s);
              send_read(master, s, s);
            end
          end join_none
        end
        wait fork;
      end
    join
  endtask
endclass

// 测试点：M0 使用 4 种 transaction tag 向 S0 交替读写，检查 ID 编码与返回 ID。
class axi_stage6_id_matrix_vseq extends axi_stage6_base_vseq;
  `uvm_object_utils(axi_stage6_id_matrix_vseq)
  function new(string name="axi_stage6_id_matrix_vseq"); super.new(name); endfunction
  virtual task body();
    fork
      run_responder(0, 4);
      begin
        for (int tag = 0; tag < 4; tag++) begin
          if ((tag & 1) == 0) send_write(0, 0, tag, 32'h2000_0000 + tag);
          else send_read(0, 0, tag);
        end
      end
    join
  endtask
endclass

// 测试点：M0 并发访问 S0/S1/S2，检查单 Master 多目标路由与并行处理。
class axi_stage6_multi_slave_parallel_vseq extends axi_stage6_base_vseq;
  `uvm_object_utils(axi_stage6_multi_slave_parallel_vseq)
  function new(string name="axi_stage6_multi_slave_parallel_vseq"); super.new(name); endfunction
  virtual task body();
    fork
      run_responder(0, 1); run_responder(1, 1); run_responder(2, 1);
      send_read(0, 0, 0); send_read(0, 1, 1); send_read(0, 2, 2);
    join
  endtask
endclass

// 测试点：M0/M1/M2 同时写 S0，检查多 Master 写请求仲裁及请求无丢失。
class axi_stage6_multi_master_write_arb_vseq extends axi_stage6_base_vseq;
  `uvm_object_utils(axi_stage6_multi_master_write_arb_vseq)
  function new(string name="axi_stage6_multi_master_write_arb_vseq"); super.new(name); endfunction
  virtual task body();
    fork
      run_responder(0, 3, 2);
      send_write(0, 0, 0, 32'h3000_0000);
      send_write(1, 0, 1, 32'h3000_0001);
      send_write(2, 0, 2, 32'h3000_0002);
    join
  endtask
endclass

// 测试点：M0/M1/M2 同时读 S1，检查多 Master 读请求仲裁及响应返回。
class axi_stage6_multi_master_read_arb_vseq extends axi_stage6_base_vseq;
  `uvm_object_utils(axi_stage6_multi_master_read_arb_vseq)
  function new(string name="axi_stage6_multi_master_read_arb_vseq"); super.new(name); endfunction
  virtual task body();
    fork
      run_responder(1, 3, 2);
      send_read(0, 1, 0); send_read(1, 1, 1); send_read(2, 1, 2);
    join
  endtask
endclass

// 测试点：M0 同时读取 S0/S1/S2，检查多 Slave 响应返回到同一 Master 时的仲裁。
class axi_stage6_response_arb_vseq extends axi_stage6_base_vseq;
  `uvm_object_utils(axi_stage6_response_arb_vseq)
  function new(string name="axi_stage6_response_arb_vseq"); super.new(name); endfunction
  virtual task body();
    fork
      run_responder(0, 1, 2); run_responder(1, 1, 2); run_responder(2, 1, 2);
      send_read(0, 0, 0); send_read(0, 1, 1); send_read(0, 2, 2);
    join
  endtask
endclass

// 测试点：三个 Master 使用相同原始 ID 读取 S1，检查源端口隔离与响应 ID 恢复。
class axi_stage6_cross_master_same_id_vseq extends axi_stage6_base_vseq;
  `uvm_object_utils(axi_stage6_cross_master_same_id_vseq)
  function new(string name="axi_stage6_cross_master_same_id_vseq"); super.new(name); endfunction
  virtual task body();
    fork
      run_responder(1, 3);
      send_read(0, 1, 2); send_read(1, 1, 2); send_read(2, 1, 2);
    join
  endtask
endclass

// 测试点：三个 Master 各发出 4 笔跨 Slave 读请求，检查多端口 outstanding 处理。
class axi_stage6_multiport_outstanding_vseq extends axi_stage6_base_vseq;
  `uvm_object_utils(axi_stage6_multiport_outstanding_vseq)
  function new(string name="axi_stage6_multiport_outstanding_vseq"); super.new(name); endfunction
  virtual task body();
    fork
      run_responder(0, 4, 3); run_responder(1, 4, 3); run_responder(2, 4, 3);
      begin
        for (int m = 0; m < 3; m++) begin
          automatic int master = m;
          fork begin
            for (int n = 0; n < 4; n++)
              send_read(master, (master + n) % 3, n);
          end join_none
        end
        wait fork;
      end
    join
  endtask
endclass

// 测试点：每个 Master/Slave 组合随机执行一次读或写，随机 tag/data 做全端口冒烟。
class axi_stage6_random_smoke_vseq extends axi_stage6_base_vseq;
  `uvm_object_utils(axi_stage6_random_smoke_vseq)
  function new(string name="axi_stage6_random_smoke_vseq"); super.new(name); endfunction
  virtual task body();
    fork
      run_responder(0, 3); run_responder(1, 3); run_responder(2, 3);
      begin
        for (int m = 0; m < 3; m++) begin
          automatic int master = m;
          fork begin
            for (int s = 0; s < 3; s++) begin
              if ($urandom_range(0, 1))
                send_write(master, s, $urandom_range(0, 3), $urandom());
              else
                send_read(master, s, $urandom_range(0, 3));
            end
          end join_none
        end
        wait fork;
      end
    join
  endtask
endclass

`endif

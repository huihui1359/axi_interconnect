`ifndef AXI_M_AGENT_CFG_SV
`define AXI_M_AGENT_CFG_SV
//m_agent_cfg和s_agent_cfg中有很多重复参数变量定义，导致代码有些冗余，能不能合并简化一下？成为一个整体axi_cfg？

class axi_m_agent_cfg #(
  int unsigned ADDR_WIDTH = AXI_ADDR_WIDTH,
  int unsigned DATA_WIDTH = AXI_DATA_WIDTH,
  int unsigned ID_WIDTH   = AXI_M_ID_WIDTH,
  int unsigned LEN_WIDTH  = AXI_LEN_WIDTH
) extends uvm_object;

  typedef virtual axi_if #(
    ADDR_WIDTH, DATA_WIDTH, ID_WIDTH, LEN_WIDTH
  ).m_drv_mp drv_vif_t;

  typedef virtual axi_if #(
    ADDR_WIDTH, DATA_WIDTH, ID_WIDTH, LEN_WIDTH
  ).mon_mp mon_vif_t;

  uvm_active_passive_enum is_active;
  int unsigned            port_index; //当前master端口编号，区分多个master端口
  drv_vif_t               drv_vif;
  mon_vif_t               mon_vif;
  int unsigned            max_read_outstanding; //允许同时存在的未完成的读事务数量
  int unsigned            max_write_outstanding;
  bit                     request_prefetch_enabled;

  `uvm_object_param_utils_begin(
    axi_m_agent_cfg #(ADDR_WIDTH, DATA_WIDTH, ID_WIDTH, LEN_WIDTH)
  )
    `uvm_field_enum(uvm_active_passive_enum, is_active, UVM_DEFAULT)
    `uvm_field_int(port_index, UVM_DEFAULT)
    `uvm_field_int(max_read_outstanding, UVM_DEFAULT)
    `uvm_field_int(max_write_outstanding, UVM_DEFAULT)
    `uvm_field_int(request_prefetch_enabled, UVM_DEFAULT)
  `uvm_object_utils_end

  function new(string name = "axi_m_agent_cfg");
    super.new(name);
    is_active             = UVM_ACTIVE;
    port_index            = 0;
    drv_vif               = null;
    mon_vif               = null;
    max_read_outstanding  = 4;
    max_write_outstanding = 4;
    request_prefetch_enabled = 1'b1;
  endfunction

endclass

`endif

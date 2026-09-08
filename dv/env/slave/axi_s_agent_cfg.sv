`ifndef AXI_S_AGENT_CFG_SV
`define AXI_S_AGENT_CFG_SV

class axi_s_agent_cfg #(
  int unsigned ADDR_WIDTH = AXI_ADDR_WIDTH,
  int unsigned DATA_WIDTH = AXI_DATA_WIDTH,
  int unsigned ID_WIDTH   = AXI_S_ID_WIDTH,
  int unsigned LEN_WIDTH  = AXI_LEN_WIDTH
) extends uvm_object;

  typedef virtual axi_if #(
    ADDR_WIDTH, DATA_WIDTH, ID_WIDTH, LEN_WIDTH
  ).s_drv_mp drv_vif_t;

  typedef virtual axi_if #(
    ADDR_WIDTH, DATA_WIDTH, ID_WIDTH, LEN_WIDTH
  ).mon_mp mon_vif_t;

  uvm_active_passive_enum is_active;
  int unsigned            port_index;
  drv_vif_t               drv_vif;
  mon_vif_t               mon_vif;
  axi_ready_mode_e        awready_mode;
  axi_ready_mode_e        wready_mode;
  axi_ready_mode_e        arready_mode;

  `uvm_object_param_utils_begin(
    axi_s_agent_cfg #(ADDR_WIDTH, DATA_WIDTH, ID_WIDTH, LEN_WIDTH)
  )
    `uvm_field_enum(uvm_active_passive_enum, is_active, UVM_DEFAULT)
    `uvm_field_int(port_index, UVM_DEFAULT)
    `uvm_field_enum(axi_ready_mode_e, awready_mode, UVM_DEFAULT)
    `uvm_field_enum(axi_ready_mode_e, wready_mode, UVM_DEFAULT)
    `uvm_field_enum(axi_ready_mode_e, arready_mode, UVM_DEFAULT)
  `uvm_object_utils_end

  function new(string name = "axi_s_agent_cfg");
    super.new(name);
    is_active    = UVM_ACTIVE;
    port_index   = 0;
    drv_vif      = null;
    mon_vif      = null;
    awready_mode = ALWAYS_READY;
    wready_mode  = ALWAYS_READY;
    arready_mode = ALWAYS_READY;
  endfunction

endclass

`endif

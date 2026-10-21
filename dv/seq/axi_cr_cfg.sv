`ifndef AXI_CR_CFG_SV
`define AXI_CR_CFG_SV

class axi_cr_cfg extends uvm_object;

  int unsigned transaction_count;

  int unsigned master_weight[AXI_NUM_MASTERS];
  int unsigned route_weight[4];
  int unsigned read_weight;
  int unsigned write_weight;

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
  int unsigned ready_delay_min;
  int unsigned ready_delay_max;
  int unsigned response_delay_min;
  int unsigned response_delay_max;

  int unsigned max_read_outstanding;
  int unsigned max_write_outstanding;
  int unsigned no_progress_timeout_cycles;
  bit request_prefetch_enabled;

  bit allow_default_read;
  bit allow_default_write;
  bit allow_illegal_write_id;
  bit constrain_read_id_to_route;

  `uvm_object_utils(axi_cr_cfg)

  extern function new(string name = "axi_cr_cfg");
  extern function void apply_plusargs();
  extern function void validate();
  extern function int unsigned expected_response_count();
  extern function string convert2string();

endclass

function axi_cr_cfg::new(string name = "axi_cr_cfg");
  super.new(name);

  transaction_count = 10_000;

  foreach (master_weight[index]) master_weight[index] = 1;
  route_weight[0] = 1;
  route_weight[1] = 1;
  route_weight[2] = 1;
  route_weight[3] = 0;
  read_weight     = 1;
  write_weight    = 1;

  // Keep the reusable foundation single-beat by default. Burst-focused tests
  // explicitly enable the other bins after the monitors support interleaving.
  len_zero_weight    = 100;
  len_one_weight     = 0;
  len_other_weight   = 0;
  len_fifteen_weight = 0;

  fixed_burst_weight = 2;
  incr_burst_weight  = 6;
  wrap_burst_weight  = 2;

  size_byte_weight     = 2;
  size_halfword_weight = 3;
  size_word_weight     = 5;

  request_delay_min = 0;
  request_delay_max = 3;
  write_gap_min     = 0;
  write_gap_max     = 3;
  ready_delay_min   = 0;
  ready_delay_max   = 5;
  response_delay_min = 0;
  response_delay_max = 3;

  max_read_outstanding  = 1;
  max_write_outstanding = 1;
  no_progress_timeout_cycles = 5_000;
  request_prefetch_enabled = 1'b0;

  allow_default_read    = 1'b0;
  allow_default_write   = 1'b0;
  allow_illegal_write_id = 1'b0;
  constrain_read_id_to_route = 1'b0;
endfunction

function void axi_cr_cfg::apply_plusargs();
  int unsigned value;

  if ($value$plusargs("AXI_CR_NUM_TXN=%d", value))
    transaction_count = value;
  if ($value$plusargs("AXI_CR_READY_MIN=%d", value))
    ready_delay_min = value;
  if ($value$plusargs("AXI_CR_READY_MAX=%d", value))
    ready_delay_max = value;
  if ($value$plusargs("AXI_CR_NO_PROGRESS=%d", value))
    no_progress_timeout_cycles = value;
  if ($value$plusargs("AXI_CR_READ_WEIGHT=%d", value))
    read_weight = value;
  if ($value$plusargs("AXI_CR_WRITE_WEIGHT=%d", value))
    write_weight = value;
  if ($value$plusargs("AXI_CR_M0_WEIGHT=%d", value))
    master_weight[0] = value;
  if ($value$plusargs("AXI_CR_M1_WEIGHT=%d", value))
    master_weight[1] = value;
  if ($value$plusargs("AXI_CR_M2_WEIGHT=%d", value))
    master_weight[2] = value;
  if ($value$plusargs("AXI_CR_S0_WEIGHT=%d", value))
    route_weight[0] = value;
  if ($value$plusargs("AXI_CR_S1_WEIGHT=%d", value))
    route_weight[1] = value;
  if ($value$plusargs("AXI_CR_S2_WEIGHT=%d", value))
    route_weight[2] = value;
endfunction

function void axi_cr_cfg::validate();
  int unsigned master_total;
  int unsigned route_total;

  master_total = 0;
  route_total  = 0;
  foreach (master_weight[index]) master_total += master_weight[index];
  foreach (route_weight[index]) route_total += route_weight[index];

  if (transaction_count == 0)
    `uvm_fatal("AXI_CR_CFG", "transaction_count must be greater than zero")
  if (master_total == 0)
    `uvm_fatal("AXI_CR_CFG", "At least one Master weight must be non-zero")
  if (route_total == 0)
    `uvm_fatal("AXI_CR_CFG", "At least one route weight must be non-zero")
  if ((read_weight + write_weight) == 0)
    `uvm_fatal("AXI_CR_CFG", "Read/write weights must not both be zero")
  if ((len_zero_weight + len_one_weight + len_other_weight +
       len_fifteen_weight) == 0)
    `uvm_fatal("AXI_CR_CFG", "Burst length weights must not all be zero")
  if ((fixed_burst_weight + incr_burst_weight +
       wrap_burst_weight) == 0)
    `uvm_fatal("AXI_CR_CFG", "Burst type weights must not all be zero")
  if ((size_byte_weight + size_halfword_weight +
       size_word_weight) == 0)
    `uvm_fatal("AXI_CR_CFG", "Transfer size weights must not all be zero")

  if (request_delay_min > request_delay_max)
    `uvm_fatal("AXI_CR_CFG", "Invalid request delay range")
  if (write_gap_min > write_gap_max)
    `uvm_fatal("AXI_CR_CFG", "Invalid write beat gap range")
  if (ready_delay_min > ready_delay_max)
    `uvm_fatal("AXI_CR_CFG", "Invalid READY delay range")
  if (response_delay_min > response_delay_max)
    `uvm_fatal("AXI_CR_CFG", "Invalid response delay range")
  if (!(max_read_outstanding inside {[1:4]}))
    `uvm_fatal("AXI_CR_CFG", "max_read_outstanding must be in [1:4]")
  if (!(max_write_outstanding inside {[1:4]}))
    `uvm_fatal("AXI_CR_CFG", "max_write_outstanding must be in [1:4]")
  if (no_progress_timeout_cycles == 0)
    `uvm_fatal("AXI_CR_CFG", "no_progress_timeout_cycles must be non-zero")

  // The first CR infrastructure milestone intentionally supports only
  // positive traffic to the three real targets. Default and malformed-WID
  // traffic require dedicated prediction and expected-error handling.
  if ((route_weight[3] != 0) || allow_default_read || allow_default_write)
    `uvm_fatal("AXI_CR_CFG",
      "Default-route traffic is not enabled in the CR foundation yet")
  if (allow_illegal_write_id)
    `uvm_fatal("AXI_CR_CFG",
      "Illegal write IDs require the dedicated negative-test infrastructure")
endfunction

function int unsigned axi_cr_cfg::expected_response_count();
  return transaction_count;
endfunction

function string axi_cr_cfg::convert2string();
  return $sformatf(
    {"transactions=%0d master_weights=%0d/%0d/%0d ",
     "route_weights=%0d/%0d/%0d/%0d rw_weights=%0d/%0d ",
     "ready_delay=%0d..%0d outstanding_r/w=%0d/%0d prefetch=%0b ",
     "read_id_route_subset=%0b"},
    transaction_count,
    master_weight[0], master_weight[1], master_weight[2],
    route_weight[0], route_weight[1], route_weight[2], route_weight[3],
    read_weight, write_weight, ready_delay_min, ready_delay_max,
    max_read_outstanding, max_write_outstanding,
    request_prefetch_enabled, constrain_read_id_to_route
  );
endfunction

`endif

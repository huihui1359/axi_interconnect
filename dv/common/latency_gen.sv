`ifndef LATENCY_GEN_SV
`define LATENCY_GEN_SV

`include "uvm_macros.svh"
import uvm_pkg::*;

class latency_gen extends uvm_object;
  `uvm_object_utils(latency_gen)

  typedef enum int unsigned {
    LAT_MODE_FIXED,
    LAT_MODE_RANDOM,
    LAT_MODE_BURST
  } latency_mode_e;

  rand latency_mode_e mode;
  rand int unsigned   min_delay;
  rand int unsigned   max_delay;
  rand int unsigned   burst_len;
  rand int unsigned   delay;

  int unsigned fixed_delay;

  local bit          burst_active;
  local int unsigned active_burst_len;
  local int unsigned burst_count;
  local bit          first_burst;

  constraint c_mode {
    if (burst_active)
      mode == LAT_MODE_BURST;
    else
      soft mode == LAT_MODE_FIXED;
  }

  constraint c_defaults {
    soft min_delay == 0;
    soft max_delay == 100;
    soft burst_len == 1;
  }

  constraint c_delay_range {
    min_delay <= max_delay;
    burst_len inside {[1:16]};

    if (burst_active)
      burst_len == active_burst_len;
  }

  constraint c_delay {
    if (mode == LAT_MODE_FIXED)
      delay == fixed_delay;
    else if (mode == LAT_MODE_RANDOM)
      delay inside {[min_delay:max_delay]};
    else if (mode == LAT_MODE_BURST) {
      if (!first_burst && (burst_count == 0))
        delay inside {[min_delay:max_delay]};
      else
        delay == 0;
    }
  }

  constraint c_order {
    solve mode before delay;
    solve min_delay before delay;
    solve max_delay before delay;
    solve burst_len before delay;
  }

  extern function new(string name = "latency_gen");
  extern function void configure_fixed(int unsigned delay_cycles);
  extern function void configure_random(int unsigned minimum,
                                        int unsigned maximum);
  extern function void configure_burst(int unsigned minimum,
                                       int unsigned maximum,
                                       int unsigned length);
  extern virtual function int unsigned get_delay();

endclass

function latency_gen::new(string name = "latency_gen");
  super.new(name);
  fixed_delay       = 0;
  burst_active      = 1'b0;
  active_burst_len = 0;
  burst_count    = 0;
  first_burst    = 1'b1;
endfunction

function void latency_gen::configure_fixed(int unsigned delay_cycles);
  mode.rand_mode(0);
  mode          = LAT_MODE_FIXED;
  fixed_delay   = delay_cycles;
  burst_active  = 1'b0;
  burst_count   = 0;
  first_burst   = 1'b1;
endfunction

function void latency_gen::configure_random(
  int unsigned minimum,
  int unsigned maximum
);
  if (minimum > maximum)
    `uvm_fatal("LATENCY_CONFIG", "minimum must not exceed maximum")

  mode.rand_mode(0);
  min_delay.rand_mode(0);
  max_delay.rand_mode(0);
  mode             = LAT_MODE_RANDOM;
  min_delay        = minimum;
  max_delay        = maximum;
  burst_active     = 1'b0;
  active_burst_len = 0;
  burst_count      = 0;
  first_burst      = 1'b1;
endfunction

function void latency_gen::configure_burst(
  int unsigned minimum,
  int unsigned maximum,
  int unsigned length
);
  if ((minimum > maximum) || !(length inside {[1:16]}))
    `uvm_fatal("LATENCY_CONFIG", "Invalid burst latency configuration")

  mode.rand_mode(0);
  min_delay.rand_mode(0);
  max_delay.rand_mode(0);
  burst_len.rand_mode(0);
  mode             = LAT_MODE_BURST;
  min_delay        = minimum;
  max_delay        = maximum;
  burst_len        = length;
  burst_active     = 1'b0;
  active_burst_len = 0;
  burst_count      = 0;
  first_burst      = 1'b1;
endfunction

function int unsigned latency_gen::get_delay();
  if (mode == LAT_MODE_BURST) begin
    if (!burst_active) begin
      burst_active     = 1'b1;
      active_burst_len = burst_len;
      burst_count      = 0;
    end

    `uvm_info(get_type_name(),
              $sformatf("mode=%s burst_count=%0d burst_len=%0d delay=%0d",
                        mode.name(), burst_count, active_burst_len, delay),
              UVM_HIGH)

    if (burst_count == (active_burst_len - 1)) begin
      burst_active = 1'b0;
      burst_count  = 0;
      first_burst  = 1'b0;
    end
    else begin
      burst_count++;
    end
  end
  else begin
    burst_active     = 1'b0;
    active_burst_len = 0;
    burst_count      = 0;
    first_burst      = 1'b1;

    `uvm_info(get_type_name(),
              $sformatf("mode=%s delay=%0d", mode.name(), delay),
              UVM_HIGH)
  end

  return delay;
endfunction

`endif

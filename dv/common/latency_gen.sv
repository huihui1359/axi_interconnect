// crush: break long runs of same-class delays on the emitted output.
//   crush_en && N consecutive "small"  delays -> force one crush_large_val
//   crush_en && N consecutive "large"  delays -> force one crush_small_val
//   Classification is done on the returned delay value (not on mode);
//   applied at the get_delay() return boundary.

`ifndef LATENCY_GEN_SV
`define LATENCY_GEN_SV

class latency_gen extends uvm_object;
    `uvm_object_utils(latency_gen)

    typedef enum int unsigned {
        LAT_MODE_FIXED, //fixed_delay cant change 
        LAT_MODE_ZERO, //get_delay 0
        LAT_MODE_HUGE, //get_delay max
        LAT_MODE_RANDOM, //random in [min_delay:max_delay]
        LAT_MODE_BURST //burst_count in burst_len
    } latency_mode_e;

    rand latency_mode_e mode;
    rand int unsigned   min_delay; //putin or default
    rand int unsigned   max_delay;
    rand int unsigned   burst_len;
    rand int unsigned   delay;

    int unsigned fixed_delay;

    // crush config (non-random, set manually; off by default)
    bit          crush_en        = 0;   // master enable
    int unsigned crush_small_th;        // d <= th      => "small"
    int unsigned crush_large_th;        // d >= th      => "large"
    int unsigned crush_small_run;       // N smalls then force one crush_large_val
    int unsigned crush_large_run;       // N larges  then force one crush_small_val
    int unsigned crush_small_val;       // forced small output
    int unsigned crush_large_val;       // forced large output

    local int unsigned consec_small = 0;
    local int unsigned consec_large = 0;

    local bit          burst_active     = 0;
    local int unsigned active_burst_len = 0;
    local int unsigned burst_count      = 0;
    local bit          first_burst      = 1;

    int unsigned MAX_DELAY_CAP = 200;

    constraint c_mode {
            mode dist {
                LAT_MODE_FIXED  := 1,
                LAT_MODE_ZERO   := 1,
                LAT_MODE_HUGE   := 1,
                LAT_MODE_RANDOM := 6,
                LAT_MODE_BURST  := 1
            };
    }

    constraint c_delay_range {
        min_delay <= max_delay;
        burst_len inside {[1:256]};
        min_delay <= MAX_DELAY_CAP;
        max_delay <= MAX_DELAY_CAP;

        if(burst_active)
            burst_len == active_burst_len;
    }

    constraint c_delay {
        if(mode == LAT_MODE_FIXED)
            delay == fixed_delay;
        else if(mode == LAT_MODE_ZERO)
            delay == 0;
        else if(mode == LAT_MODE_HUGE)
            delay == MAX_DELAY_CAP;
        else if(mode == LAT_MODE_RANDOM)
            delay inside {[min_delay:max_delay]};
        else if(mode == LAT_MODE_BURST) {
            if(!first_burst && (burst_count == 0))
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

    function new(string name = "latency_gen");
        super.new(name);
        fixed_delay = 5;
        crush_small_th  = 8;            // d <= 8   => small
        crush_large_th  = 64;           // d >= 64  => large
        crush_small_run = 10;            // 100 smalls then one large
        crush_large_run = 10;            // 100 larges  then one small
        crush_small_val = 0;
        crush_large_val = MAX_DELAY_CAP;
    endfunction

    extern virtual function int unsigned get_delay();
    extern virtual function int unsigned crush(int unsigned d);
    extern virtual function void burst_reset();
endclass

function int unsigned latency_gen::get_delay();
    if(mode == LAT_MODE_BURST) begin
        if(!burst_active) begin
            burst_active     = 1;
            active_burst_len = burst_len;
            burst_count      = 0;
        end

        `uvm_info(get_type_name(),
                  $sformatf("mode=%s burst_count=%0d burst_len=%0d delay=%0d",
                            mode.name(), burst_count, active_burst_len, delay),
                  UVM_HIGH)

        if(burst_count == (active_burst_len - 1)) begin
            burst_active = 0;
            burst_count  = 0;
            first_burst  = 0; //whether is the first group
        end
        else begin
            burst_count++;
        end
    end
    else begin
        burst_active     = 0;
        active_burst_len = 0;
        burst_count      = 0;
        first_burst      = 1;

        `uvm_info(get_type_name(),
                  $sformatf("mode=%s delay=%0d", mode.name(), delay),
                  UVM_HIGH)
    end

    // `uvm_info(get_type_name(),
    //             $sformatf("mode=%s burst_count=%0d burst_active=%0d first_burst=%0d",
    //                 mode.name(),burst_count,burst_active,first_burst),
    //             UVM_HIGH)

    return crush(delay);
endfunction


function int unsigned latency_gen::crush(int unsigned d);
    if(!crush_en)
        return d; // crush disabled: pass-through

    if(d <= crush_small_th) begin
        consec_large = 0;
        consec_small++;
        if(consec_small >= crush_small_run) begin
            consec_small = 0;
            `uvm_info(get_type_name(),
                      $sformatf("CRUSH small->large: run=%0d raw=%0d -> %0d",
                                crush_small_run, d, crush_large_val),
                      UVM_HIGH)
            return crush_large_val;
        end
    end
    else if(d >= crush_large_th) begin
        consec_small = 0;
        consec_large++;
        if(consec_large >= crush_large_run) begin
            consec_large = 0;
            `uvm_info(get_type_name(),
                      $sformatf("CRUSH large->small: run=%0d raw=%0d -> %0d",
                                crush_large_run, d, crush_small_val),
                      UVM_HIGH)
            return crush_small_val;
        end
    end
    else begin
        consec_small = 0;
        consec_large = 0;
    end

    return d;
endfunction


function void latency_gen::burst_reset();

    burst_active     = 0;
    active_burst_len = 0;
    burst_count      = 0;
    first_burst      = 1;

    `uvm_info(get_type_name(),
            "burst_reset called: burst state cleared",UVM_HIGH)

endfunction

`endif


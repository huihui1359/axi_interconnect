class pad_buf_coverage extends uvm_obhect;
    `uvm_object_utils(pad_buf_covergae)
    covergroup cm_cg with function sample();
        pad_buf_if vif;
        cp_addr_alignment: coverpoint vif.scmd_addr[3:0]{
            bins aligned = {0};
            bins unaligned_front = {[1:7]};
            bins unaligned_behind = {[8:15]};
        }
        cp_blen: coverpoint vif.scmd_blen{
            bins one = {1};
            bins below_max = {[2:`MAX_BYTES-1]};
            bins at_max = {`MAX_BYTES};
            bins above_max = {`MAX_BYTES:`MAX_BYTES+10};
        }
        alignment_blen_cross: cross cp_addr_alignment,cp_blen;
        ignorebins bit_above_max = 
                binsof(cp_cache_hit.hit) && binsof(cp_blen.above_max);
    endgroup
endclass
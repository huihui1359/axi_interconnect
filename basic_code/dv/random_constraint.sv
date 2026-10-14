class packet
    
    typedef enum int unsigned {
        READ,
        WRITE,
        IDLE
    } mode_e;

    rand unsigned [7:0] len;
    rand mode_e mode;

    constraint c_len {
        len inside {[1:64]};
        len dist {
            [1:64]:/1,
             [4:64:4]:=3};
    }

    constraint c_mode {
        mode dist {
            IDLE:=10, 
            READ:=45, 
            WRITE:=45};
    }

endclass
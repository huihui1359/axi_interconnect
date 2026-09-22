module reorder (
    input            clk         ,
    input            rstn        ,
    
    input [7:0]      sid_0      ,
    input            sid_0_vld  ,

    input [7:0]      sid_1      ,
    input            sid_1_vld  ,

    input [7:0]      sid_2      ,
    input            sid_2_vld  ,

    input wire [7:0] rob_buffer [0:3] ,

    output reg [2:0] order_grant   
);

// This module is just checking if the sid is in the rob_buffer, and generate order_grant accordingly.
// so a better module name could be:
// outstanding_id_match     or
// id_eligibility_check     or
// transaction_trant_filter

always @(posedge clk) begin
    if(!rstn) begin
        order_grant <= 3'b000;
    end
    else begin
        order_grant[0] <= sid_0_vld &&
                          ((sid_0 == rob_buffer[0]) ||
                           (sid_0 == rob_buffer[1]) ||
                           (sid_0 == rob_buffer[2]) ||
                           (sid_0 == rob_buffer[3]));
        order_grant[1] <= sid_1_vld &&
                          ((sid_1 == rob_buffer[0]) ||
                           (sid_1 == rob_buffer[1]) ||
                           (sid_1 == rob_buffer[2]) ||
                           (sid_1 == rob_buffer[3]));
        order_grant[2] <= sid_2_vld &&
                          ((sid_2 == rob_buffer[0]) ||
                           (sid_2 == rob_buffer[1]) ||
                           (sid_2 == rob_buffer[2]) ||
                           (sid_2 == rob_buffer[3]));
    end
end

endmodule

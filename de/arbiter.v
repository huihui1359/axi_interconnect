module arbiter_4(
    input clk,
    input rst_n,
    input [3:0] req,
    input done,
    output reg [3:0] grant
);
    reg [3:0] pass;
    always@(posedge clk or negedge rst_n)begin
        if(!rst_n)
            grant <= 4'b0000;
        else begin
            if(reg[0]) begin grant[0] <= 1'b1;pass[0]<=1'b1;end
            else if(reg[1:0]==2'b10) grant <= 4'b0010;
            else if(reg[2:0]==3'b100) grant <= 4'b0100;
            else if(reg[3:0]==4'b1000) grant <= 4'b1000;
            else grant <= 4'b0000;
        end
    end



endmodule
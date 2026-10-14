module serial2parallel(
    input clk,
    input rst_n,
    input din,
    input din_valid,
    output reg [7:0] dout,
    output reg dout_valid
);
    reg [7:0] shift_reg;
    reg [3:0] cnt;

    always@(posedge clk or negedge rst_n)begin
        if(!rst_n)begin
            dout <= 8'd0;
            dout_valid <= 1'b0;
        end else begin
            dout_valid <= 1'b0;
            if(din_valid && (cnt == 4'd7))begin
                dout <= {shift_reg[6:0],din};
                dout_valid <= 1'b1;
            end 
        end
    end

    always@(posedge clk or negedge rst_n)begin
        if(!rst_n)
            cnt <= 4'd0;
        else if (din_valid)begin
            if(cnt==4'd7)
                cnt <= 4'd0;
            else
                cnt <= cnt + 1'b1;
        end
    end

    always@(posedge clk or negedge rst_n)begin
        if(!rst_n)
            shift_reg <= 8'd0;
        else if(din_valid)
            shift_reg <= {shift_reg[6:0],din};
    end
endmodule
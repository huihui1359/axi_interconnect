module round_robin_m2s (
    input        clk    ,
    input        rst_n  ,
 
    input  [2:0] req    ,
    input        accept ,
    output [2:0] sel     
);

reg [2:0]    last_winner   ;     
reg [2:0]    curr_winner   ;     
reg [2:0]    pending_winner;
reg          pending_valid ;

// Hold an unaccepted selection locally and advance fairness only on accept.
always @ (posedge clk or negedge rst_n) begin 
    if (rst_n == 1'b0) begin
        last_winner    <= 3'b0;
        pending_winner <= 3'b0;
        pending_valid  <= 1'b0;
    end
    else if (accept == 1'b1) begin
        last_winner   <= sel;
        pending_valid <= 1'b0;
    end
    else if ((pending_valid == 1'b0) && (|sel)) begin
        pending_winner <= sel;
        pending_valid  <= 1'b1;
    end
end 
 
always @ (*) begin 
    if (last_winner == 3'b001) begin      // 轮询当前队列 
        if(req[1] == 1'b1)
            curr_winner = 3'b010;           
        else if(req[2] == 1'b1)
            curr_winner = 3'b100;        
        else if(req[0] == 1'b1)
            curr_winner = 3'b001; 
        else  
            curr_winner = 3'b000;    
    end 
    else if(last_winner == 3'b010)begin 
        if(req[2] == 1'b1)
            curr_winner = 3'b100;        
        else if(req[0] == 1'b1)
            curr_winner = 3'b001; 
        else if(req[1] == 1'b1)
            curr_winner = 3'b010;    
        else  
            curr_winner = 3'b000;    
    end     
    else if(last_winner == 3'b100)begin 
        if(req[0] == 1'b1)
            curr_winner = 3'b001; 
        else if(req[1] == 1'b1)
            curr_winner = 3'b010;    
        else if(req[2] == 1'b1)
            curr_winner = 3'b100; 
        else  
            curr_winner = 3'b000;    
    end     
    else begin 
        if(req[0] == 1'b1)
            curr_winner = 3'b001; 
        else if(req[1] == 1'b1)
            curr_winner = 3'b010;    
        else if(req[2] == 1'b1)
            curr_winner = 3'b100; 
        else  
            curr_winner = 3'b000;    
    end     
end 
   
assign sel = pending_valid ? pending_winner : curr_winner;

endmodule

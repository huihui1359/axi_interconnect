property a_b;
    @(posedge clk) disable iff(!rst_n)
    $rose(a) |-> (($past(b,2)==1'b0) &&  ($past(b,1) == 1'b0)); //前两拍b为低电平
    //$rose(a) |-> ($past(b,3)==1'b1)&&($past(b,2)==1'b0)&&  ($past(b,1) == 1'b0); //前两拍是b的下降沿保持两拍
endproperty

assert property(a_b)
else `uvm_error("fail")

//req上升沿后，ack必须在1~5拍内出现，且只能出现一次
property req_appear_ack;
    @(posedge clk) disable iff (!rst_n)
    $rose(req) |-> ##[1:5] $rose(ack);
endproperty

property ack_after_req;
    @(posedge clk) disable iff (!rst_n)
    $rose(ack) |=> !$rose(ack) until $rose(req);
endproperty
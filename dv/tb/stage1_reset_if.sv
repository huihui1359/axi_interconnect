interface stage1_reset_if(input logic aclk);
  logic aresetn;

  task automatic apply_initial_reset(int unsigned active_cycles = 2);
    aresetn = 1'b0;
    repeat (active_cycles) @(posedge aclk);
    @(negedge aclk);
    aresetn = 1'b1;
  endtask

  task automatic pulse_reset(int unsigned active_cycles = 2);
    @(negedge aclk);
    aresetn = 1'b0;
    repeat (active_cycles) @(posedge aclk);
    @(negedge aclk);
    aresetn = 1'b1;
  endtask
endinterface

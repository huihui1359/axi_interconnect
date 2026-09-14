`ifndef PIN_PEER_CHECKER_SV
`define PIN_PEER_CHECKER_SV

class pin_peer_checker extends uvm_component;

  int unsigned match_count;
  int unsigned mismatch_count;

  `uvm_component_utils(pin_peer_checker)

  function new(string name = "pin_peer_checker", uvm_component parent = null);
    super.new(name, parent);
    match_count    = 0;
    mismatch_count = 0;
  endfunction

  function void check_condition(bit condition, string message);
    if (condition) begin
      match_count++;
    end
    else begin
      mismatch_count++;
      `uvm_error("PIN_PEER_CHECK", message)
    end
  endfunction

  function void clear();
    match_count    = 0;
    mismatch_count = 0;
  endfunction

endclass

`endif

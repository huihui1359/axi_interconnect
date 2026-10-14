  function void end_of_elaboration_phase(uvm_phase phase);
    `uvm_info("end_of_elaboration_phase", "is entered",UVM_LOW)
    super.end_of_elaboration_phase(phase);
  
    /**
     * Display the topology
     */
    uvm_top.print_topology();

    `uvm_info("end_of_elaboration_phase", "is exited",UVM_LOW)
  endfunction : end_of_elaboration_phase
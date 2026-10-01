`timescale 1ns/1ps

// Keep waveform instrumentation local to sim_vcs.  The block is bound into
// the verification top and becomes active only when +DUMP_FSDB is supplied.
module axi_fsdb_dump;
  string fsdb_file;

  initial begin
    if ($test$plusargs("DUMP_FSDB")) begin
      if (!$value$plusargs("FSDB_FILE=%s", fsdb_file))
        fsdb_file = "wave.fsdb";

      $display("[FSDB] dumping waveform to %s", fsdb_file);
      $fsdbDumpfile(fsdb_file);
      $fsdbDumpvars(0, tb, "+all");
      $fsdbDumpMDA();
    end
  end
endmodule

bind tb axi_fsdb_dump u_axi_fsdb_dump();

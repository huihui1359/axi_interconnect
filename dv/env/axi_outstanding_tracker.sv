`ifndef AXI_OUTSTANDING_TRACKER_SV
`define AXI_OUTSTANDING_TRACKER_SV

class axi_outstanding_tracker #(
  int unsigned ADDR_WIDTH = AXI_ADDR_WIDTH,
  int unsigned DATA_WIDTH = AXI_DATA_WIDTH,
  int unsigned ID_WIDTH   = AXI_ID_WIDTH,
  int unsigned LEN_WIDTH  = AXI_LEN_WIDTH
) extends uvm_component;

  localparam int unsigned ID_COUNT = 1 << ID_WIDTH;

  typedef axi_channel_event #(
    ADDR_WIDTH, DATA_WIDTH, ID_WIDTH, LEN_WIDTH
  ) event_t;

  uvm_analysis_imp #(event_t,
    axi_outstanding_tracker #(ADDR_WIDTH, DATA_WIDTH, ID_WIDTH, LEN_WIDTH)
  ) channel_export;

  int unsigned aw_observed_by_id[ID_COUNT];
  int unsigned wlast_observed_by_id[ID_COUNT];
  int unsigned ar_observed_by_id[ID_COUNT];
  int unsigned write_request_count_by_id[ID_COUNT];
  int unsigned write_completion_count_by_id[ID_COUNT];
  int unsigned read_request_count_by_id[ID_COUNT];
  int unsigned read_completion_count_by_id[ID_COUNT];
  int unsigned max_write_outstanding;
  int unsigned max_read_outstanding;
  int unsigned error_count;
  bit enabled;

  `uvm_component_param_utils(
    axi_outstanding_tracker #(ADDR_WIDTH, DATA_WIDTH, ID_WIDTH, LEN_WIDTH)
  )

  extern function new(string name = "axi_outstanding_tracker",
                      uvm_component parent = null);
  extern virtual function void build_phase(uvm_phase phase);
  extern virtual function void write(event_t item);
  extern function int unsigned write_outstanding();
  extern function int unsigned read_outstanding();
  extern function int unsigned pending_count();
  extern function void clear();
  extern virtual function void check_phase(uvm_phase phase);

endclass

function axi_outstanding_tracker::new(
  string name = "axi_outstanding_tracker",
  uvm_component parent = null
);
  super.new(name, parent);
  enabled = 1'b1;
  clear();
endfunction

function void axi_outstanding_tracker::build_phase(uvm_phase phase);
  super.build_phase(phase);
  channel_export = new("channel_export", this);
endfunction

function void axi_outstanding_tracker::write(event_t item);
  event_t snapshot;
  int unsigned id;

  if (!enabled)
    return;
  if ((item == null) || !$cast(snapshot, item.clone())) begin
    error_count++;
    `uvm_error("AXI_OUTSTANDING_TRACKER", "Failed to clone channel event")
    return;
  end
  if ($isunknown(snapshot.id)) begin
    error_count++;
    `uvm_error("AXI_OUTSTANDING_TRACKER", "Observed ID contains X/Z")
    return;
  end

  id = int'(snapshot.id);
  case (snapshot.channel)
    AXI_CHANNEL_AW: begin
      aw_observed_by_id[id]++;
      write_request_count_by_id[id]++;
    end

    AXI_CHANNEL_W: begin
      if (snapshot.last === 1'b1)
        wlast_observed_by_id[id]++;
    end

    AXI_CHANNEL_B: begin
      if ((aw_observed_by_id[id] == 0) ||
          (wlast_observed_by_id[id] == 0)) begin
        error_count++;
        `uvm_error("AXI_OUTSTANDING_TRACKER_B",
                   "B event underflowed observed AW/WLAST state")
      end
      else begin
        aw_observed_by_id[id]--;
        wlast_observed_by_id[id]--;
      end
      write_completion_count_by_id[id]++;
    end

    AXI_CHANNEL_AR: begin
      ar_observed_by_id[id]++;
      read_request_count_by_id[id]++;
    end

    AXI_CHANNEL_R: begin
      if (snapshot.last === 1'b1) begin
        if (ar_observed_by_id[id] == 0) begin
          error_count++;
          `uvm_error("AXI_OUTSTANDING_TRACKER_R",
                     "RLAST event underflowed observed AR state")
        end
        else begin
          ar_observed_by_id[id]--;
        end
        read_completion_count_by_id[id]++;
      end
    end
  endcase

  if (write_outstanding() > max_write_outstanding)
    max_write_outstanding = write_outstanding();
  if (read_outstanding() > max_read_outstanding)
    max_read_outstanding = read_outstanding();
endfunction

function int unsigned axi_outstanding_tracker::write_outstanding();
  int unsigned total;
  total = 0;
  foreach (aw_observed_by_id[id])
    total += aw_observed_by_id[id];
  return total;
endfunction

function int unsigned axi_outstanding_tracker::read_outstanding();
  int unsigned total;
  total = 0;
  foreach (ar_observed_by_id[id])
    total += ar_observed_by_id[id];
  return total;
endfunction

function int unsigned axi_outstanding_tracker::pending_count();
  int unsigned total;
  total = 0;
  foreach (aw_observed_by_id[id]) begin
    total += aw_observed_by_id[id];
    total += wlast_observed_by_id[id];
    total += ar_observed_by_id[id];
  end
  return total;
endfunction

function void axi_outstanding_tracker::clear();
  foreach (aw_observed_by_id[id]) begin
    aw_observed_by_id[id]              = 0;
    wlast_observed_by_id[id]           = 0;
    ar_observed_by_id[id]              = 0;
    write_request_count_by_id[id]      = 0;
    write_completion_count_by_id[id]   = 0;
    read_request_count_by_id[id]       = 0;
    read_completion_count_by_id[id]    = 0;
  end
  max_write_outstanding = 0;
  max_read_outstanding  = 0;
  error_count           = 0;
endfunction

function void axi_outstanding_tracker::check_phase(uvm_phase phase);
  super.check_phase(phase);
  if (enabled && (pending_count() != 0))
    `uvm_error("AXI_OUTSTANDING_TRACKER_PENDING", $sformatf(
      "Observed outstanding state is not empty: %0d", pending_count()))
endfunction

`endif

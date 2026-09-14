`ifndef AXI_BASIC_EVENT_COMPARATOR_SV
`define AXI_BASIC_EVENT_COMPARATOR_SV

class axi_basic_event_comparator #(
  int unsigned ADDR_WIDTH = AXI_ADDR_WIDTH,
  int unsigned DATA_WIDTH = AXI_DATA_WIDTH,
  int unsigned ID_WIDTH   = AXI_ID_WIDTH,
  int unsigned LEN_WIDTH  = AXI_LEN_WIDTH
) extends uvm_component;

  typedef axi_channel_event #(
    ADDR_WIDTH, DATA_WIDTH, ID_WIDTH, LEN_WIDTH
  ) event_t;

  uvm_analysis_imp_expected #(event_t,
    axi_basic_event_comparator #(ADDR_WIDTH, DATA_WIDTH, ID_WIDTH, LEN_WIDTH)
  ) expected_export;

  uvm_analysis_imp_actual #(event_t,
    axi_basic_event_comparator #(ADDR_WIDTH, DATA_WIDTH, ID_WIDTH, LEN_WIDTH)
  ) actual_export;

  event_t expected_q[$];
  event_t actual_q[$];

  int unsigned match_count;
  int unsigned mismatch_count;

  `uvm_component_param_utils(
    axi_basic_event_comparator #(ADDR_WIDTH, DATA_WIDTH, ID_WIDTH, LEN_WIDTH)
  )

  function new(string name = "axi_basic_event_comparator",
               uvm_component parent = null);
    super.new(name, parent);
    match_count    = 0;
    mismatch_count = 0;
  endfunction

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    expected_export = new("expected_export", this);
    actual_export   = new("actual_export", this);
  endfunction

  virtual function void write_expected(event_t event_in);
    event_t snapshot;
    if ((event_in == null) || !$cast(snapshot, event_in.clone())) begin
      mismatch_count++;
      `uvm_error("AXI_EVENT_CMP", "Failed to clone expected event")
      return;
    end
    expected_q.push_back(snapshot);
    compare_available();
  endfunction

  virtual function void write_actual(event_t event_in);
    event_t snapshot;
    if ((event_in == null) || !$cast(snapshot, event_in.clone())) begin
      mismatch_count++;
      `uvm_error("AXI_EVENT_CMP", "Failed to clone actual event")
      return;
    end
    actual_q.push_back(snapshot);
    compare_available();
  endfunction

  local function void compare_available();
    event_t expected_event;
    event_t actual_event;

    while ((expected_q.size() != 0) && (actual_q.size() != 0)) begin
      expected_event = expected_q.pop_front();
      actual_event   = actual_q.pop_front();

      if (expected_event.payload_equal(actual_event, 1'b1)) begin
        match_count++;
      end
      else begin
        mismatch_count++;
        `uvm_error(
          "AXI_EVENT_MISMATCH",
          $sformatf("Expected {%s}, actual {%s}",
                    expected_event.convert2string(),
                    actual_event.convert2string())
        )
      end
    end
  endfunction

  function int unsigned pending_expected();
    return expected_q.size();
  endfunction

  function int unsigned pending_actual();
    return actual_q.size();
  endfunction

  function void clear();
    expected_q.delete();
    actual_q.delete();
    match_count     = 0;
    mismatch_count  = 0;
  endfunction

  virtual function void check_phase(uvm_phase phase);
    super.check_phase(phase);
    compare_available();
    if ((expected_q.size() != 0) || (actual_q.size() != 0)) begin
      `uvm_error(
        "AXI_EVENT_PENDING",
        $sformatf("Unmatched events: expected=%0d actual=%0d",
                  expected_q.size(), actual_q.size())
      )
    end
  endfunction

endclass

`endif

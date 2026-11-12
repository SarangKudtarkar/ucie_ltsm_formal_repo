// Simplified UCIe-style link training state machine (LTSM) -- DUT for the
// formal flow. Not spec-complete: it models the bring-up / retrain / L1 /
// error-recovery skeleton with a per-state timeout.
module ucie_ltsm #(
  parameter int TIMEOUT = 16            // max cycles per handshake state (<= 255)
) (
  input  logic       clk,
  input  logic       rst_n,             // synchronous, active low
  input  logic       sb_rsp_valid,      // sideband partner response for current request
  input  logic       train_pass,        // PHY training result (qualified by sb_rsp_valid)
  input  logic       link_err,          // fatal link error while ACTIVE
  input  logic       lp_retrain_req,    // upper layer asks for retrain
  input  logic       lp_l1_req,         // upper layer asks for L1/L2 entry
  input  logic       lp_wake_req,       // upper layer asks to leave L1/L2
  output logic [3:0] state,
  output logic       sb_req_valid       // sideband request outstanding
);

  localparam logic [3:0] S_RESET      = 4'd0;
  localparam logic [3:0] S_SBINIT     = 4'd1;
  localparam logic [3:0] S_MBINIT     = 4'd2;
  localparam logic [3:0] S_MBTRAIN    = 4'd3;
  localparam logic [3:0] S_LINKINIT   = 4'd4;
  localparam logic [3:0] S_ACTIVE     = 4'd5;
  localparam logic [3:0] S_PHYRETRAIN = 4'd6;
  localparam logic [3:0] S_L1L2       = 4'd7;
  localparam logic [3:0] S_TRAINERROR = 4'd8;

  logic [3:0] state_d;
  logic [7:0] cnt;
  wire        timeout = (cnt == 8'(TIMEOUT - 1));

  always_comb begin
    state_d = state;
    case (state)
      S_RESET:      state_d = S_SBINIT;
      S_SBINIT:     if (sb_rsp_valid) state_d = S_MBINIT;
                    else if (timeout) state_d = S_TRAINERROR;
      S_MBINIT:     if (sb_rsp_valid) state_d = S_MBTRAIN;
                    else if (timeout) state_d = S_TRAINERROR;
      S_MBTRAIN:    if (sb_rsp_valid && train_pass) state_d = S_LINKINIT;
                    else if (timeout) state_d = S_TRAINERROR;   // failed training retries until timeout
      S_LINKINIT:   if (sb_rsp_valid) state_d = S_ACTIVE;
                    else if (timeout) state_d = S_TRAINERROR;
      S_ACTIVE:     if (link_err) state_d = S_TRAINERROR;
                    else if (lp_retrain_req) state_d = S_PHYRETRAIN;
                    else if (lp_l1_req) state_d = S_L1L2;
      S_PHYRETRAIN: if (sb_rsp_valid && train_pass) state_d = S_ACTIVE;
                    else if (timeout) state_d = S_TRAINERROR;
      S_L1L2:       if (lp_wake_req) state_d = S_MBTRAIN;
      S_TRAINERROR: state_d = S_RESET;
      default:      state_d = S_TRAINERROR;
    endcase
  end

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      state <= S_RESET;
      cnt   <= '0;
    end else begin
      state <= state_d;
      if (state_d != state)  cnt <= '0;
      else if (cnt != 8'hFF) cnt <= cnt + 8'd1;
    end
  end

  assign sb_req_valid = (state == S_SBINIT)   || (state == S_MBINIT)  ||
                        (state == S_MBTRAIN)  || (state == S_LINKINIT) ||
                        (state == S_PHYRETRAIN);
endmodule

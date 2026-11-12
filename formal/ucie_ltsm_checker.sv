// SVA checker for ucie_ltsm. Bound into the DUT (see ucie_ltsm_bind.sv).
module ucie_ltsm_checker #(
  parameter int TIMEOUT = 16
) (
  input logic       clk,
  input logic       rst_n,
  input logic       sb_rsp_valid,
  input logic       train_pass,
  input logic       link_err,
  input logic       lp_retrain_req,
  input logic       lp_l1_req,
  input logic       lp_wake_req,
  input logic [3:0] state,
  input logic       sb_req_valid,
  // DUT internal (bound by name): per-state cycle counter
  input logic [7:0] cnt
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

  default clocking cb @(posedge clk); endclocking
  default disable iff (!rst_n);

  wire in_training = state inside {S_SBINIT, S_MBINIT, S_MBTRAIN, S_LINKINIT, S_PHYRETRAIN};

  // ---------------------------------------------------------------- assumptions
  // Reset is applied only at the start; once released it stays released.
  // Responses are NOT constrained: spurious sideband responses are legal
  // stimulus and the DUT must ignore them (see the spurious checks below).
  asm_rst_stays_released: assume property (disable iff (1'b0) rst_n |=> rst_n);

  // ------------------------------------------------------ safety: state legality
  ast_state_encoding_valid: assert property (state <= S_TRAINERROR);

  ast_nxt_reset:      assert property (state == S_RESET      |=> state inside {S_RESET, S_SBINIT});
  ast_nxt_sbinit:     assert property (state == S_SBINIT     |=> state inside {S_SBINIT, S_MBINIT, S_TRAINERROR});
  ast_nxt_mbinit:     assert property (state == S_MBINIT     |=> state inside {S_MBINIT, S_MBTRAIN, S_TRAINERROR});
  ast_nxt_mbtrain:    assert property (state == S_MBTRAIN    |=> state inside {S_MBTRAIN, S_LINKINIT, S_TRAINERROR});
  ast_nxt_linkinit:   assert property (state == S_LINKINIT   |=> state inside {S_LINKINIT, S_ACTIVE, S_TRAINERROR});
  ast_nxt_active:     assert property (state == S_ACTIVE     |=> state inside {S_ACTIVE, S_PHYRETRAIN, S_L1L2, S_TRAINERROR});
  ast_nxt_phyretrain: assert property (state == S_PHYRETRAIN |=> state inside {S_PHYRETRAIN, S_ACTIVE, S_TRAINERROR});
  ast_nxt_l1l2:       assert property (state == S_L1L2       |=> state inside {S_L1L2, S_MBTRAIN});
  ast_nxt_trainerror: assert property (state == S_TRAINERROR |=> state == S_RESET);

  // ------------------------------------------------ safety: guarded transitions
  ast_active_needs_linkinit_rsp: assert property (
    ($past(state) == S_LINKINIT && state == S_ACTIVE) |-> $past(sb_rsp_valid));
  ast_linkinit_needs_train_pass: assert property (
    ($past(state) == S_MBTRAIN && state == S_LINKINIT) |-> $past(sb_rsp_valid && train_pass));
  ast_active_entry_pred: assert property (
    (state == S_ACTIVE && $past(state) != S_ACTIVE) |-> $past(state) inside {S_LINKINIT, S_PHYRETRAIN});
  ast_link_err_wins: assert property (
    (state == S_ACTIVE && link_err) |=> state == S_TRAINERROR);
  ast_retrain_serviced: assert property (
    (state == S_ACTIVE && !link_err && lp_retrain_req) |=> state == S_PHYRETRAIN);
  ast_wake_serviced: assert property (
    (state == S_L1L2 && lp_wake_req) |=> state == S_MBTRAIN);
  ast_sb_req_matches_state: assert property (sb_req_valid == in_training);

  // ------------------------------------- forward progress: bounded (no deadlock)
  ast_fp_sbinit:     assert property (state == S_SBINIT     |-> ##[1:TIMEOUT] state != S_SBINIT);
  ast_fp_mbinit:     assert property (state == S_MBINIT     |-> ##[1:TIMEOUT] state != S_MBINIT);
  ast_fp_mbtrain:    assert property (state == S_MBTRAIN    |-> ##[1:TIMEOUT] state != S_MBTRAIN);
  ast_fp_linkinit:   assert property (state == S_LINKINIT   |-> ##[1:TIMEOUT] state != S_LINKINIT);
  ast_fp_phyretrain: assert property (state == S_PHYRETRAIN |-> ##[1:TIMEOUT] state != S_PHYRETRAIN);

  // ------------------------------- forward progress: unbounded (no livelock)
  ast_live_training_resolves: assert property (
    in_training |-> s_eventually (state == S_ACTIVE || state == S_TRAINERROR));

  // Helper invariant (the ranking function behind the liveness argument): while
  // training, the per-state counter never reaches TIMEOUT, because the timeout
  // branch forces an exit at TIMEOUT-1. Without it, unreachable large cnt values
  // let the liveness engines build spurious loops, so ast_live_training_resolves
  // stays "bounded" (no cex up to depth N) instead of proven.
  ast_inv_cnt_bounded: assert property (in_training |-> cnt < TIMEOUT);

  // Safety form of the same claim, provable by induction with the invariant:
  // a training pass resolves within 4 states x TIMEOUT cycles.
  ast_fp_training_resolves: assert property (
    in_training |-> ##[1:4*TIMEOUT] (state == S_ACTIVE || state == S_TRAINERROR));

  // -------------------------------------------------------------------- covers
  cov_reach_reset:      cover property (state == S_RESET);
  cov_reach_sbinit:     cover property (state == S_SBINIT);
  cov_reach_mbinit:     cover property (state == S_MBINIT);
  cov_reach_mbtrain:    cover property (state == S_MBTRAIN);
  cov_reach_linkinit:   cover property (state == S_LINKINIT);
  cov_reach_active:     cover property (state == S_ACTIVE);
  cov_reach_phyretrain: cover property (state == S_PHYRETRAIN);
  cov_reach_l1l2:       cover property (state == S_L1L2);
  cov_reach_trainerror: cover property (state == S_TRAINERROR);

  cov_full_bringup: cover property (
    state == S_SBINIT ##[1:$] state == S_MBINIT ##[1:$] state == S_MBTRAIN ##[1:$]
    state == S_LINKINIT ##[1:$] state == S_ACTIVE);
  cov_retrain_roundtrip: cover property (
    state == S_ACTIVE ##[1:$] state == S_PHYRETRAIN ##[1:$] state == S_ACTIVE);
  cov_l1_roundtrip: cover property (
    state == S_ACTIVE ##[1:$] state == S_L1L2 ##[1:$] state == S_MBTRAIN ##[1:$] state == S_ACTIVE);
  cov_train_fail_retry: cover property (
    state == S_MBTRAIN && sb_rsp_valid && !train_pass ##1 state == S_MBTRAIN);
  cov_timeout_to_error: cover property (
    state == S_SBINIT ##[1:$] state == S_TRAINERROR);
  cov_error_recovers_to_active: cover property (
    state == S_TRAINERROR ##[1:$] state == S_ACTIVE);

  // ------------------------------------------------ spurious / illegal events
  // A sideband response with no request outstanding, or an out-of-order step,
  // must never move the machine.
  ast_spur_rsp_ignored_active: assert property (
    (state == S_ACTIVE && sb_rsp_valid && !link_err && !lp_retrain_req && !lp_l1_req)
      |=> state == S_ACTIVE);
  ast_spur_rsp_ignored_l1l2: assert property (
    (state == S_L1L2 && sb_rsp_valid && !lp_wake_req) |=> state == S_L1L2);
  ast_spur_pass_without_rsp: assert property (
    (state == S_MBTRAIN && train_pass && !sb_rsp_valid) |=> state inside {S_MBTRAIN, S_TRAINERROR});
  ast_spur_sbinit_needs_rsp: assert property (
    ($past(state) == S_SBINIT && state == S_MBINIT) |-> $past(sb_rsp_valid));
  ast_spur_mbinit_needs_rsp: assert property (
    ($past(state) == S_MBINIT && state == S_MBTRAIN) |-> $past(sb_rsp_valid));
  ast_spur_retrain_done_needs_pass: assert property (
    ($past(state) == S_PHYRETRAIN && state == S_ACTIVE) |-> $past(sb_rsp_valid && train_pass));
  // Upper-layer requests are ignored in training states (no state skipping).
  ast_spur_req_ignored_in_training: assert property (
    (in_training && (lp_retrain_req || lp_l1_req || lp_wake_req) && !sb_rsp_valid)
      |=> (state == $past(state) || state == S_TRAINERROR));

  // ------------------------------------------- vacuity: antecedent covers
  // Every implication above/earlier must have a reachable antecedent, otherwise
  // its assertion passes vacuously.
  cov_ante_active_needs_linkinit_rsp: cover property ($past(state) == S_LINKINIT && state == S_ACTIVE);
  cov_ante_linkinit_needs_pass:       cover property ($past(state) == S_MBTRAIN && state == S_LINKINIT);
  cov_ante_active_entry_pred:         cover property (state == S_ACTIVE && $past(state) != S_ACTIVE);
  cov_ante_link_err_wins:             cover property (state == S_ACTIVE && link_err);
  cov_ante_retrain_serviced:          cover property (state == S_ACTIVE && !link_err && lp_retrain_req);
  cov_ante_wake_serviced:             cover property (state == S_L1L2 && lp_wake_req);
  cov_ante_live_training:             cover property (in_training);
  cov_ante_spur_active:               cover property (
    state == S_ACTIVE && sb_rsp_valid && !link_err && !lp_retrain_req && !lp_l1_req);
  cov_ante_spur_l1l2:                 cover property (state == S_L1L2 && sb_rsp_valid && !lp_wake_req);
  cov_ante_spur_pass_no_rsp:          cover property (state == S_MBTRAIN && train_pass && !sb_rsp_valid);
  cov_ante_sbinit_to_mbinit:          cover property ($past(state) == S_SBINIT && state == S_MBINIT);
  cov_ante_mbinit_to_mbtrain:         cover property ($past(state) == S_MBINIT && state == S_MBTRAIN);
  cov_ante_retrain_done:              cover property ($past(state) == S_PHYRETRAIN && state == S_ACTIVE);
  cov_ante_req_in_training:           cover property (
    in_training && (lp_retrain_req || lp_l1_req || lp_wake_req) && !sb_rsp_valid);

endmodule

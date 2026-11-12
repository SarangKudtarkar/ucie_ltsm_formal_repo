// Data-integrity checker for ucie_flit_path (tracked-flit scoreboard).
// Bound into the DUT; internal signals connect by name.
module ucie_flit_checker #(
  parameter int W = 8
) (
  input logic         clk,
  input logic         rst_n,
  input logic         in_valid,
  input logic [W-1:0] in_data,
  input logic         in_ready,
  input logic         out_valid,
  input logic [W-1:0] out_data,
  input logic         err_inject,
  input logic [3:0]   err_bit,
  // DUT internals
  input logic         tx_busy,
  input logic [W-1:0] tx_buf,
  input logic         ack_valid_q,
  input logic         ack_nak_q,
  input logic         lnk_valid_q,
  input logic         lnk_corrupt_q,
  input logic         rx_crc_ok,
  input logic         do_accept,
  input logic         do_replay
);

  default clocking cb @(posedge clk); endclocking
  default disable iff (!rst_n);

  // ------------------------------------------------ tracked-flit scoreboard
  // tracked_idx is intentionally undriven: JasperGold treats it as a free
  // symbolic input, held constant by assume, so every flit index is covered.
  logic [3:0]   tracked_idx;
  logic [3:0]   in_cnt, out_cnt;          // saturating
  logic         tracked_written;
  logic [W-1:0] tracked_data;

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      in_cnt <= '0; out_cnt <= '0; tracked_written <= 1'b0; tracked_data <= '0;
    end else begin
      if (do_accept) begin
        if (in_cnt != 4'hF) in_cnt <= in_cnt + 4'd1;
        if (in_cnt == tracked_idx) begin
          tracked_written <= 1'b1;
          tracked_data    <= in_data;
        end
      end
      if (out_valid && out_cnt != 4'hF) out_cnt <= out_cnt + 4'd1;
    end
  end

  // ---------------------------------------------------------------- assumptions
  asm_rst_stays_released: assume property (disable iff (1'b0) rst_n |=> rst_n);
  asm_tracked_stable:     assume property ($stable(tracked_idx));
  asm_tracked_range:      assume property (tracked_idx < 4'd14);
  asm_err_bit_range:      assume property (err_bit < (W + 8));        // within {crc, data}
  // At most one corrupted transmission per flit: a replay is always clean.
  asm_one_error_per_flit: assume property (do_replay |-> !err_inject);

  // ------------------------------------------------------------ data integrity
  // The tracked flit is delivered unchanged and in order (index match).
  ast_di_data_match: assert property (
    (out_valid && out_cnt == tracked_idx) |-> (tracked_written && out_data == tracked_data));
  // No phantom flits: delivery only for a flit that was accepted.
  ast_di_no_phantom: assert property (
    out_valid |-> (out_cnt < in_cnt || in_cnt == 4'hF));
  // A corrupted frame is always detected and never delivered.
  ast_di_crc_detects: assert property (
    (lnk_valid_q && lnk_corrupt_q) |-> (!rx_crc_ok && !out_valid));
  ast_di_no_deliver_bad_crc: assert property (out_valid |-> rx_crc_ok);
  // A NAK always causes a (clean) replay on the next cycle.
  ast_di_nak_triggers_replay: assert property (
    (tx_busy && ack_valid_q && ack_nak_q) |=> (lnk_valid_q && !lnk_corrupt_q));
  // The replay buffer holds its content while a flit is outstanding.
  ast_di_replay_buf_stable: assert property (
    tx_busy |=> (!tx_busy || $stable(tx_buf)));
  // No duplicate delivery back-to-back (single outstanding flit).
  ast_di_no_back_to_back: assert property (out_valid |=> !out_valid);
  // Forward progress: an accepted flit is delivered even with one injected error.
  ast_di_fp_deliver: assert property (do_accept |-> ##[1:4] out_valid);

  // -------------------------------------------------------------------- covers
  cov_di_tracked_delivered: cover property (
    out_valid && out_cnt == tracked_idx && tracked_written);
  cov_di_corrupt_detected:  cover property (lnk_valid_q && lnk_corrupt_q && !rx_crc_ok);
  cov_di_corrupt_then_ok:   cover property (
    (lnk_valid_q && lnk_corrupt_q) ##[1:6] out_valid);
  cov_di_replay:            cover property (do_replay);
  cov_di_err_in_data:       cover property ((do_accept || do_replay) && err_inject && err_bit <  W);
  cov_di_err_in_crc:        cover property ((do_accept || do_replay) && err_inject && err_bit >= W);
  cov_di_two_flits:         cover property (out_valid ##[1:12] out_valid);
  cov_di_tracked_after_err: cover property (
    (lnk_valid_q && lnk_corrupt_q) ##[1:6] (out_valid && out_cnt == tracked_idx));

  // ------------------------------------------- vacuity: antecedent covers
  cov_ante_di_data_match:  cover property (out_valid && out_cnt == tracked_idx);
  cov_ante_di_phantom:     cover property (out_valid);
  cov_ante_di_crc:         cover property (lnk_valid_q && lnk_corrupt_q);
  cov_ante_di_nak:         cover property (tx_busy && ack_valid_q && ack_nak_q);
  cov_ante_di_buf_stable:  cover property (tx_busy);
  cov_ante_di_fp:          cover property (do_accept);

endmodule

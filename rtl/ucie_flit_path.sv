// Simplified UCIe-style D2D flit path: CRC-8 protected link with NAK/replay.
// Stop-and-wait (one flit outstanding) with a 1-bit sequence number.
// err_inject / err_bit model a single-bit corruption on the link and are
// free inputs for formal.
module ucie_flit_path #(
  parameter int W = 8
) (
  input  logic         clk,
  input  logic         rst_n,
  // transmit side
  input  logic         in_valid,
  input  logic [W-1:0] in_data,
  output logic         in_ready,
  // receive side
  output logic         out_valid,
  output logic [W-1:0] out_data,
  // link error injection (verification only)
  input  logic         err_inject,
  input  logic [3:0]   err_bit
);

  localparam int FW = W + 8;               // {crc8, data}

  function automatic logic [7:0] crc8(input logic [W-1:0] d);
    logic [7:0] c;
    c = 8'h00;
    for (int i = W - 1; i >= 0; i--) begin
      if (c[7] ^ d[i]) c = {c[6:0], 1'b0} ^ 8'h07;
      else             c = {c[6:0], 1'b0};
    end
    return c;
  endfunction

  // ---- transmitter / replay buffer
  logic         tx_busy, tx_seq;
  logic [W-1:0] tx_buf;
  logic         ack_valid_q, ack_nak_q, ack_seq_q;

  assign in_ready = !tx_busy;
  wire do_accept = in_valid && in_ready;
  wire do_replay = tx_busy && ack_valid_q && ack_nak_q;
  wire do_done   = tx_busy && ack_valid_q && !ack_nak_q && (ack_seq_q == tx_seq);
  wire tx_send   = do_accept || do_replay;

  wire [W-1:0]  tx_data_sel = do_accept ? in_data : tx_buf;
  wire [7:0]    tx_crc      = crc8(tx_data_sel);
  wire          inject      = tx_send && err_inject;
  wire [FW-1:0] frame       = {tx_crc, tx_data_sel};
  wire [FW-1:0] flip        = FW'(1) << err_bit;
  wire [FW-1:0] frame_tx    = inject ? (frame ^ flip) : frame;

  // ---- link registers
  logic         lnk_valid_q, lnk_seq_q, lnk_corrupt_q;
  logic [W-1:0] lnk_data_q;
  logic [7:0]   lnk_crc_q;

  // ---- receiver
  logic rx_exp_seq;
  wire  rx_crc_ok  = (crc8(lnk_data_q) == lnk_crc_q);
  wire  rx_deliver = lnk_valid_q && rx_crc_ok && (lnk_seq_q == rx_exp_seq);

  assign out_valid = rx_deliver;
  assign out_data  = lnk_data_q;

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      tx_busy       <= 1'b0;
      tx_seq        <= 1'b0;
      tx_buf        <= '0;
      lnk_valid_q   <= 1'b0;
      lnk_seq_q     <= 1'b0;
      lnk_corrupt_q <= 1'b0;
      lnk_data_q    <= '0;
      lnk_crc_q     <= '0;
      ack_valid_q   <= 1'b0;
      ack_nak_q     <= 1'b0;
      ack_seq_q     <= 1'b0;
      rx_exp_seq    <= 1'b0;
    end else begin
      lnk_valid_q <= tx_send;
      if (tx_send) begin
        {lnk_crc_q, lnk_data_q} <= frame_tx;
        lnk_seq_q               <= tx_seq;
        lnk_corrupt_q           <= inject;
      end

      if (do_accept) begin
        tx_buf  <= in_data;
        tx_busy <= 1'b1;
      end else if (do_done) begin
        tx_busy <= 1'b0;
        tx_seq  <= ~tx_seq;
      end

      ack_valid_q <= lnk_valid_q;
      ack_nak_q   <= !rx_crc_ok;
      ack_seq_q   <= lnk_seq_q;
      if (rx_deliver) rx_exp_seq <= ~rx_exp_seq;
    end
  end
endmodule

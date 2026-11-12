# UCIe LTSM Formal Verification (Cadence JasperGold)

Formal verification of a simplified UCIe-style link training state machine
(bring-up, retrain, L1/L2, error recovery, per-state timeout) using JasperGold FPV.

## Structure

```
ucie_ltsm_formal_repo/
├── rtl/ucie_ltsm.sv                  # DUT 1: simplified link training FSM
├── rtl/ucie_flit_path.sv             # DUT 2: CRC-8 flit path with NAK/replay
├── formal/ucie_ltsm_checker.sv       # LTSM: safety, forward progress, spurious, covers
├── formal/ucie_ltsm_bind.sv
├── formal/ucie_flit_checker.sv       # flit path: data integrity (tracked-flit scoreboard)
├── formal/ucie_flit_bind.sv
├── scripts/ucie_ltsm_formal.tcl      # JasperGold flow, LTSM
├── scripts/ucie_flit_formal.tcl      # JasperGold flow, flit path
├── reports/
└── README.md
```

## Approach

- Checker is bound into `ucie_ltsm`; RTL is not modified.
- LTSM environment assumption: reset only at the start (once released it stays
  released). Sideband responses are unconstrained on purpose, so spurious
  responses are exercised and must be ignored.
- Safety: legal next-state relation for every state, valid encodings, guarded
  transitions (ACTIVE only via LINKINIT/PHYRETRAIN, LINKINIT only after a
  passing training response), link error and retrain/wake priority, and
  `sb_req_valid` matching the handshake states.
- Forward progress (the focus):
  * Bounded: every handshake state exits within `TIMEOUT` cycles, so no deadlock.
  * Unbounded: from any training state the machine eventually reaches ACTIVE or
    TRAINERROR (`s_eventually`), so no livelock. A failed training result is
    retried only until the timeout.
- Covers: every state, full bring-up, retrain and L1 round trips, failed-training
  retry, timeout to TRAINERROR, and recovery from TRAINERROR back to ACTIVE.
- Spurious / illegal events (LTSM): sideband responses with no request, training
  pass without a response, and upper-layer requests during training must not move
  the machine; each guarded transition requires its enabling response.
- Vacuity: every implication has a `cov_ante_*` cover on its antecedent, so a
  passing assertion that never fires shows up as an unreachable cover.

## Data integrity (flit path)

`ucie_flit_path` is a stop-and-wait flit path: CRC-8, 1-bit sequence number,
NAK/replay, with a free single-bit error injector on the link.

- A free, constant `tracked_idx` (stable by assume) selects which accepted flit
  to track. The scoreboard stores that flit's data on accept and compares it at
  delivery when the delivery count matches, which checks content, order and
  exactly-once delivery without per-flit queues.
- No phantom flits (delivery only for accepted flits); a corrupted frame is
  always detected by CRC and never delivered; a NAK always causes a clean replay
  on the next cycle; the replay buffer is stable while a flit is outstanding.
- Forward progress: an accepted flit is delivered within 4 cycles, even with an
  injected error.
- Environment assumptions: at most one corrupted transmission per flit (a replay
  is clean) and the error bit position lies within `{crc, data}`.
- Covers: error in data bits, error in CRC bits, corrupt then replayed delivery,
  tracked flit delivered after an error, two flits back to back.

## Run

```
jg -no_gui -tcl scripts/ucie_ltsm_formal.tcl
jg -no_gui -tcl scripts/ucie_flit_formal.tcl
```

Older installs: `jaspergold -no_gui -tcl scripts/<script>.tcl`.

## Coverage

The Tcl flow also runs formal coverage (`check_cov`) after the proofs:

- Stimuli: what the covers and assumptions actually exercised.
- COI / proof / bound: which logic the assertions depend on, which is fully
  covered by the proofs, and how deep bounded proofs reach.
- Models: branch, statement, toggle, expression.

Outputs in `reports/`: `summary.rpt`, `properties.rpt`, `formal_coverage.rpt`,
`uncovered.rpt` (LTSM) and the same set prefixed `flit_` (flit path). Review `uncovered.rpt` and any unreachable covers to find
missing properties or over-constraining assumptions.

## Notes

- The DUT is a small teaching model, not the UCIe spec LTSM. To target real RTL,
  replace `rtl/`, keep the checker port names (or edit the bind), and update the
  state encodings in the checker.
- The flit path is a simplified model, not the UCIe D2D adapter: stop-and-wait
  instead of a sequence-numbered replay buffer, an 8-bit payload with CRC-8, and
  a clean ack channel. The single-bit-error guarantee relies on the CRC property
  that every single-bit error is detected; multi-bit or burst errors are out of
  scope.
- Check all covers (including every `cov_ante_*`) are reachable before trusting
  assertion passes.
- Keep `TIMEOUT` small for fast convergence; raise it once the flow is stable.
- A liveness assertion (`s_eventually`) reported as "bounded N" means no
  counterexample up to depth N, not a proof. `ast_live_training_resolves` is
  helped by the invariant `ast_inv_cnt_bounded` (proved first, then assumed) and
  backed by the safety form `ast_fp_training_resolves` (4 x TIMEOUT cycles).
- Not a signoff-complete proof.

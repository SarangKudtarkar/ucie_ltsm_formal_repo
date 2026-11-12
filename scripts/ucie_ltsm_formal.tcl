# JasperGold FPV flow for ucie_ltsm
# Run from the repo root:  jg -no_gui -tcl scripts/ucie_ltsm_formal.tcl

clear -all

analyze -sv12 rtl/ucie_ltsm.sv
analyze -sv12 formal/ucie_ltsm_checker.sv
analyze -sv12 formal/ucie_ltsm_bind.sv

elaborate -top ucie_ltsm

clock clk
reset -expression {!rst_n}

set_engine_mode Hp
set_prove_time_limit 1h

# Covers first: confirm the environment is not over-constrained
prove -property [get_property_list -include {type cover}]

# Helper invariant first, then reuse it as a lemma so the unbounded liveness
# assertion converges (otherwise it can stay "bounded" with no cex).
# Adjust the hierarchical name if your tool reports it differently.
set inv ucie_ltsm.u_ucie_ltsm_checker.ast_inv_cnt_bounded
prove -property $inv
assume -from_assert $inv

# The bounded form (4 x TIMEOUT cycles) logically implies the unbounded
# s_eventually property. Prove it, then reuse it as a lemma. Sound only if it
# proves: check it shows "proven" in the report before trusting the liveness pass.
set fp ucie_ltsm.u_ucie_ltsm_checker.ast_fp_training_resolves
prove -property $fp
assume -from_assert $fp

# Then everything
prove -all

file mkdir reports
report -summary -force -file reports/summary.rpt

# ------------------------------------------------------------- formal coverage
# Cover-property status (reachable / unreachable) and assertion roll-up
foreach st {proven cex undetermined covered unreachable} {
  puts "\[UCIE_FV\] $st : [llength [get_property_list -include [list status $st]]]"
}
report -file reports/properties.rpt -force

# Code coverage models measured against the proofs
check_cov -init -model {branch statement toggle expression} \
                -type  {stimuli coi proof bound}

# Stimuli coverage: what the covers + assumptions actually exercised
check_cov -measure -type stimuli

# COI / proof / bound coverage: what the assertions actually checked
check_cov -measure -type {coi proof bound} -time_limit 1h

# Reports
check_cov -report -type all -report_file reports/formal_coverage.rpt -force
check_cov -list  -status uncovered -type all -list_file reports/uncovered.rpt

puts "\[UCIE_FV\] Coverage reports written to reports/"

# JasperGold FPV flow for ucie_ltsm, in phases so results appear early:
#   1. covers + stimuli coverage      (minutes)
#   2. safety assertions
#   3. COI / proof / bound coverage + final reports
#   4. unbounded liveness (own task, last, with lemmas)
# Run from the repo root:  jg -no_gui -tcl scripts/ucie_ltsm_formal.tcl

set PFX ltsm
set CHK ucie_ltsm.u_ucie_ltsm_checker
set T_COVER  30m
set T_SAFETY 1h
set T_LIVE   20m
set T_COV    1h

file mkdir reports

# Print a status roll-up and write a report snapshot (survives a later kill/timeout)
proc snapshot {pfx tag} {
  foreach st {proven cex undetermined covered unreachable} {
    puts "\[UCIE_FV\] $pfx $tag $st : [llength [get_property_list -include [list status $st]]]"
  }
  report -file reports/${pfx}_${tag}.rpt -force
}

# Coverage helpers. check_cov option values differ between JasperGold versions
# (for example "-type all" is rejected by some), so every call is wrapped: a bad
# option prints a warning instead of aborting the whole flow.
proc cov_report {pfx tag types} {
  foreach t $types {
    if {[catch {check_cov -report -type $t -report_file reports/${pfx}_${tag}_${t}.rpt -force} msg]} {
      puts "\[UCIE_FV\] WARNING: check_cov -report -type $t failed: $msg"
    }
  }
}
proc cov_list_uncovered {pfx types} {
  foreach t $types {
    if {[catch {check_cov -list -status uncovered -type $t -list_file reports/${pfx}_uncovered_${t}.rpt} msg]} {
      puts "\[UCIE_FV\] WARNING: check_cov -list -type $t failed: $msg"
    }
  }
}
proc cov_measure {args} {
  if {[catch {check_cov -measure {*}$args} msg]} {
    puts "\[UCIE_FV\] WARNING: check_cov -measure $args failed: $msg"
  }
}

# ------------------------------------------------------------------ phase 0: setup
clear -all
analyze -sv12 rtl/ucie_ltsm.sv
analyze -sv12 formal/ucie_ltsm_checker.sv
analyze -sv12 formal/ucie_ltsm_bind.sv
# Coverage models (expression in particular) must be enabled before elaboration.
check_cov -init -model {branch statement toggle expression} \
                -type  {stimuli coi proof bound}

elaborate -top ucie_ltsm
clock clk
reset -expression {!rst_n}
set_engine_mode Hp

# --------------------------------------------- phase 1: covers + stimuli coverage
# Confirms the environment is not over-constrained and every antecedent is reachable.
prove -property [get_property_list -include {type cover}] -time_limit $T_COVER
snapshot $PFX phase1_covers

cov_measure -type stimuli
cov_report $PFX phase1 {stimuli}
puts "\[UCIE_FV\] $PFX stimuli coverage written"

# ----------------------------------------------------- phase 2: safety assertions
# Everything except the unbounded s_eventually property.
set asserts [get_property_list -include {type assert}]
set safety {}
set live   {}
foreach p $asserts {
  if {[string match *ast_live_* $p]} { lappend live $p } else { lappend safety $p }
}
prove -property $safety -time_limit $T_SAFETY
snapshot $PFX phase2_safety

# ------------------------------------------ phase 3: COI / proof / bound coverage
# Liveness is deliberately LAST, so nothing waits on the hardest proof.
cov_measure -type {coi proof bound} -time_limit $T_COV
cov_report $PFX final {stimuli checker formal bounded}
cov_list_uncovered $PFX {stimuli checker}

report -summary -force -file reports/${PFX}_summary.rpt
snapshot $PFX final
puts "\[UCIE_FV\] $PFX core results and coverage complete, reports in reports/"

# --------------------------------------------------- phase 4: liveness with lemmas
# Runs in its OWN task so the lemma assumptions and the long liveness proof never
# touch the covers or coverage data held in the embedded task.
# A lemma is assumed only if it is proven in the source task (checked BEFORE the
# copy, so it does not depend on whether the copy carries proof results).
set src [task -list -current]
set proven [get_property_list -include {status proven}]
task -create live_task -copy_all -source_task $src
task -set live_task

foreach lemma [list $CHK.ast_inv_cnt_bounded $CHK.ast_fp_training_resolves] {
  if {[lsearch -exact $proven $lemma] >= 0} {
    if {[catch {assume -from_assert $lemma} msg]} {
      puts "\[UCIE_FV\] WARNING: could not assume $lemma: $msg"
    } else {
      puts "\[UCIE_FV\] assumed proven lemma $lemma"
    }
  } else {
    puts "\[UCIE_FV\] WARNING: $lemma is not proven, not assumed (liveness stays bounded)"
  }
}
prove -property $live -time_limit $T_LIVE
snapshot $PFX phase4_liveness
task -set $src
puts "\[UCIE_FV\] $PFX flow complete"

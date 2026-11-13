# JasperGold FPV flow for ucie_flit_path (data integrity), in phases:
#   1. covers + stimuli coverage
#   2. assertions
#   3. COI / proof / bound coverage + final reports
# Run from the repo root:  jg -no_gui -tcl scripts/ucie_flit_formal.tcl

set PFX flit
set T_COVER 30m
set T_ASSERT 1h
set T_COV   1h

file mkdir reports

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
analyze -sv12 rtl/ucie_flit_path.sv
analyze -sv12 formal/ucie_flit_checker.sv
analyze -sv12 formal/ucie_flit_bind.sv
# Coverage models (expression in particular) must be enabled before elaboration.
check_cov -init -model {branch statement toggle expression} \
                -type  {stimuli coi proof bound}

elaborate -top ucie_flit_path
clock clk
reset -expression {!rst_n}
set_engine_mode Hp

# --------------------------------------------- phase 1: covers + stimuli coverage
prove -property [get_property_list -include {type cover}] -time_limit $T_COVER
snapshot $PFX phase1_covers

cov_measure -type stimuli
cov_report $PFX phase1 {stimuli}
puts "\[UCIE_FV\] $PFX stimuli coverage written"

# ----------------------------------------------------------- phase 2: assertions
prove -property [get_property_list -include {type assert}] -time_limit $T_ASSERT
snapshot $PFX phase2_assertions

# ------------------------------------------ phase 3: COI / proof / bound coverage
cov_measure -type {coi proof bound} -time_limit $T_COV
cov_report $PFX final {stimuli checker formal bounded}
cov_list_uncovered $PFX {stimuli checker}

report -summary -force -file reports/${PFX}_summary.rpt
snapshot $PFX final
puts "\[UCIE_FV\] $PFX flow complete, reports in reports/"

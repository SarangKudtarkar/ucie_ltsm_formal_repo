# JasperGold FPV flow for ucie_flit_path (data integrity)
# Run from the repo root:  jg -no_gui -tcl scripts/ucie_flit_formal.tcl

clear -all

analyze -sv12 rtl/ucie_flit_path.sv
analyze -sv12 formal/ucie_flit_checker.sv
analyze -sv12 formal/ucie_flit_bind.sv

elaborate -top ucie_flit_path

clock clk
reset -expression {!rst_n}

set_engine_mode Hp
set_prove_time_limit 1h

# Covers first: confirm the environment is not over-constrained
prove -property [get_property_list -include {type cover}]
prove -all

file mkdir reports
report -summary -force -file reports/flit_summary.rpt

foreach st {proven cex undetermined covered unreachable} {
  puts "\[UCIE_FV\] flit $st : [llength [get_property_list -include [list status $st]]]"
}
report -file reports/flit_properties.rpt -force

check_cov -init -model {branch statement toggle expression} \
                -type  {stimuli coi proof bound}
check_cov -measure -type stimuli
check_cov -measure -type {coi proof bound} -time_limit 1h
check_cov -report -type all -report_file reports/flit_formal_coverage.rpt -force
check_cov -list  -status uncovered -type all -list_file reports/flit_uncovered.rpt

puts "\[UCIE_FV\] Flit-path coverage reports written to reports/"

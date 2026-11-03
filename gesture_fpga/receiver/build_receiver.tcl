if {[catch {
 import_device eagle_s20.db -package EG4S20BG256
 open_project receiver_demo.prj
 elaborate -top receiver_demo
 read_adc receiver_pin.adc
 read_sdc receiver_timing.sdc
 optimize_rtl
 optimize_gate
 legalize_phy_inst
 update_timing
 place
 route
 update_timing -mode final
 report_timing_summary -file receiver_route.timing
 report_area -io_info -file receiver_phy.area
 bitgen -bit receiver_demo.bit
} build_error]} {
 puts stderr "RECEIVER BUILD FAILED: $build_error"
 exit 1
}
puts "RECEIVER BUILD COMPLETE"
exit 0

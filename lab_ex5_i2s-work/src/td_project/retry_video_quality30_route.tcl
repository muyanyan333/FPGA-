# Resume the current startup-fix netlist after a routing conflict.
# Run only after build_video_quality30.tcl has produced its PR database.
if {[catch {
import_device eagle_s20.db -package EG4S20BG256
open_project {full_camera_player.prj} -noanalyze
import_db video_quality30_seed7_pr.db
set_param place seed 11
place
route
update_timing -mode final
report_timing_summary -file video_quality30_route.timing
report_area -io_info -file video_quality30_phy.area
bitgen -bit video_quality30.bit
} route_error]} {
    puts stderr "VIDEO ROUTE FAILED: $route_error"
    exit 1
}
puts "VIDEO BUILD COMPLETE: video_quality30.bit"
exit 0

# Resume the current startup-fix netlist after a routing conflict.
# Run only after build_camera_player_video.tcl has produced its PR database.
if {[catch {
import_device eagle_s20.db -package EG4S20BG256
open_project {full_camera_player.prj} -noanalyze
import_db full_camera_player_pr.db
set_param place seed 7
place
route
update_timing -mode final
report_timing_summary -file camera_player_video_route.timing
report_area -io_info -file camera_player_video_phy.area
bitgen -bit camera_player_video.bit
} route_error]} {
    puts stderr "VIDEO ROUTE FAILED: $route_error"
    exit 1
}
puts "VIDEO BUILD COMPLETE: camera_player_video.bit"
exit 0

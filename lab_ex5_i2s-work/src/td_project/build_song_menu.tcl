if {[catch {
import_device eagle_s20.db -package EG4S20BG256
open_project {full_camera_player.prj}
elaborate -top top_video_player
read_adc ../user_source/constraints_source/pin.adc
read_sdc ../user_source/constraints_source/timing_video_no_camera.sdc
read_sdc -ip rfifo_32_32_512 ../user_source/hdl_source/ip/afifo_32_16_256.tcl
read_sdc -ip wfifo_32_32_512 ../user_source/hdl_source/ip/afifo_16_32_256.tcl
# TD's shipped AreaOptimizeHigh strategy. Video shares the frame and audio
# pipelines; map remaining control logic with area as the first priority.
set_param gate add_map_lut_struct high
set_param gate map_mode area_prior
set_param gate multi_thread_mapping partition
set_param rtl resource_sharing auto
set_param rtl shifter_style shifter_reg
optimize_rtl
optimize_gate -packarea video_song_menu_gate.area
legalize_phy_inst
update_timing
set_param place seed 7
place
route
update_timing -mode final
report_timing_summary -file video_song_menu_route.timing
report_area -io_info -file video_song_menu_phy.area
bitgen -bit video_song_menu.bit
} video_build_error]} {
    puts stderr "VIDEO BUILD FAILED: $video_build_error"
    exit 1
}
puts "VIDEO BUILD COMPLETE: video_song_menu.bit"
exit 0














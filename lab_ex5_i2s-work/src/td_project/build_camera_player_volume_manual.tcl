import_device eagle_s20.db -package EG4S20BG256
open_project {full_camera_player.prj}
elaborate -top top_camera_player
read_adc ../user_source/constraints_source/pin.adc
read_sdc ../user_source/constraints_source/timing_camera.sdc
read_sdc -ip rfifo_32_32_512 ../user_source/hdl_source/ip/afifo_32_16_256.tcl
read_sdc -ip wfifo_32_32_512 ../user_source/hdl_source/ip/afifo_16_32_256.tcl
optimize_rtl
optimize_gate -packarea camera_player_volume_manual_gate.area
legalize_phy_inst
update_timing
set_param place seed 2
place
route
update_timing -mode final
report_timing_summary -file camera_player_volume_manual_route.timing
report_area -io_info -file camera_player_volume_manual_phy.area
bitgen -bit camera_player_volume_manual.bit
exit












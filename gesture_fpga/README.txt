手势识别最终交付源码精简包（2026-11-04）

打包基准：camera_gesture_link_seg_work，最后交付的数码管显示+J2串口通信版本。
本次仅精简打包，所有保留的源码文件与原目录逐字节一致，没有修改功能。
此前反馈的 HDMI 手势信息不显示问题尚未完成实机定位，本包不代表该问题已修复。

发送板：src/td_project/full_camera_edge_preview.prj，顶层 top_camera_preview。
在 src/td_project 内运行 build_camera_gesture_link_seg.tcl。
接收板：receiver/receiver_demo.prj，顶层 receiver_demo。
在 receiver 内运行 build_receiver.tcl。
工具：Anlogic TD 6.2.168116，EG4S20BG256 器件支持。

J2-19 / GPIOB_16 / G1：发送板TX到接收板RX；另接GND。
UART 9600 8N1；A5 CODE ~CODE 5A；01张手、02握拳、03左挥、04右挥、00无目标。
显示规则与接线细节见两份 README.md。

为压缩体积，未包含位流、测试、报告、构建缓存、工具链、旧版本和历史资料。
工程保留供应商IP及其配置，仍需安装TD。请整体解压至短英文路径，保持目录结构。
主工程中原有 AutoExcluded 的音频ROM初始化路径保持原样，不参与当前顶层构建。
发送板原有整机时序违例仍存在，不能将生成位流等同于全部实机功能通过。

打包核验：全部工程路径引用可解析，保留源文件与原版本一致，发送板TD工程展开检查通过；未重新布局布线或声称修复此前实机问题。

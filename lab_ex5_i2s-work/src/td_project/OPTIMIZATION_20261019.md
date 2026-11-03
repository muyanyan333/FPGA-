# 摄像头 / 图片音乐合并版优化

## 改动

将 `sd_card_bmp.v` 的前后曲查找改为并行位图掩码和四层二分优先编码，替代十五次动态索引及串联优先选择。保留编号升序、空号跳过、首尾循环以及空列表和单曲行为。频谱绘制和靠右音乐属性栏沿用上一版。

## 验证

- `music_track_neighbors_tb.v` 对全部 65,536 个有效曲目位图 × 16 个当前位置，共 1,048,576 种组合，与原算法逐项比较，通过。
- `tb_uart_notice.v`：W02 与 ASRPRO 双向串口协议仿真通过。
- `audio_fft1024_tb.v`：100 Hz 峰值柱 2，4000 Hz 峰值柱 52，与上一版一致。
- `build_camera_player_optimized.tcl` 完成综合、布局、布线和 bitgen，日志无 ERROR/FATAL。

## 布线后结果

| 项目 | 上一版 FFT | 本版 |
| --- | ---: | ---: |
| LUT | 18072 | 17836 |
| BRAM9K | 55 | 55 |
| DSP | 11 | 11 |
| 50 MHz 域 setup slack | -0.418 ns | +0.170 ns |
| 全局 setup WNS | -6.699 ns | -6.699 ns |
| 全局 hold WNS | -1.415 ns | -1.540 ns |

全工程时序仍未收敛，SDRAM、HDMI、音频及跨域路径仍需继续处理；本版资源减少和 50 MHz 域 setup 改善不代表全工程时序通过。尚未验证实际开发板效果。

新版：`camera_player_optimized.bit`，已同步到默认文件 `camera_player.bit`。
上一版保留为 `camera_player_fft.bit`。

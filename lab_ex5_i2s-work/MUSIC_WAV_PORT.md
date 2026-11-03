# TF 音乐频谱与波形移植说明

> 2026-10-17：MVI 视频路径已从固件删除；音频仍走 WAV → PCM FIFO → I²S → HDMI。
> 同一路音频现在同时驱动歌词（LYR2，顶部）和竖排歌名（右侧），每 500 ms 前进一帧。
> 背景改用 `picture/` 的 12 张 640×480 BMP，音乐模式 10 秒轮播。新构建入口为
> `src/td_project/build_music_lyrics.tcl`，输出 `full_build_music_lyrics.bit`；
> 歌词/歌名格式见 `LYRIC_BITMAP_FORMAT.md`，媒体准备见 `tools/prepare_card.py`。

## 当前实现

工程入口是 `src/td_project/HDMI1.4b_Transmitter_v1.0.al`，顶层是 `top_tf_hdmi_audio.v`。音频路径为：exFAT 根目录文件发现 → TF 扇区读取 → PCM 帧 FIFO → I²S → HDMI 音频发送链。同一组采样送入 1024 点 FFT 与 640 点触发波形捕获。BMP 图片读取、按键、串口、转场和其他 OSD 仍沿用原路径。

画面参考 [Music-Spectrum](https://github.com/aystmjz/Music-Spectrum) 的整屏构图，适配 640×480 HDMI：80 根非线性频率分布的彩虹柱从画面底部升起，彩色波形横跨中央，使用强光混合叠加到 TF 图片。FFT 幅度开平方，波形触发前使用三级低通滤波。原项目的 Xilinx FFT/FIR/平方根 IP 未直接复制；滤波器实现和强光混合精度并非逐位相同。原 16 路 Goertzel、小面板和底部滚动署名已从顶层移除。

## TF 卡与音频文件

- 文件系统：与原图片扫描一致，为 exFAT 根目录。扫描根目录前 16 个普通文件，选择找到的首个 RIFF/WAVE 文件。原图片仍按已有规则最多选 7 张。
- 音频格式：48 kHz、16-bit、单声道或双声道、无压缩 PCM WAV；文件需是标准 44 字节 WAV 头，`data` 块紧跟 `fmt ` 块。读取到末尾后循环播放。
- BMP 为宽 320～1920、高 240～1080 的 24 位无压缩格式；硬件等比例适配到 640×480，空余区域补黑。
- 找不到有效 WAV 时继续使用原来的内部测试音。音频文件格式错误时不会开始 TF 音乐播放。
- 连续分配文件和有 FAT 簇链的文件均有读取路径。建议先用短音频和少量图片上板验证。

若手头 WAV 有额外的 `LIST`/`JUNK` 等块，需先转换为上述标准头。可使用音频转换工具导出 `48 kHz / 16-bit PCM / mono or stereo`，再确认 `data` 从文件偏移 44 开始。

## 主要文件

- `src/user_source/hdl_source/SD/bmp_read.v`：发现 WAV 和 exFAT 文件几何信息。
- `src/user_source/hdl_source/SD/exfat_pcm_wav_reader.v`：校验头、读取 PCM、循环播放。
- `src/user_source/hdl_source/SD/pcm_frame_fifo.v`：SD 时钟域到音频主时钟域的帧缓冲。
- `src/user_source/hdl_source/SD/sd_card_bmp.v`：在扇区边界调度 BMP/WAV 访问。
- `src/user_source/hdl_source/pcm_i2s_tx.v`：PCM 到 I²S。
- `src/user_source/hdl_source/SD/bmp_fit_scaler.v`：BMP 硬件缩放与黑边填充。
- `src/user_source/hdl_source/audio_fft1024.v`：1024 点 FFT、80 个非线性频点和幅度开平方。
- `src/user_source/hdl_source/audio_waveform_overlay.v`：640 点触发波形。
- `src/user_source/hdl_source/music_spectrum_visual.v`：整屏彩虹柱、中央波形及强光混合。

## 已验证与待验证

Icarus Verilog 仿真覆盖了 BMP/WAV 同时发现、BMP 候选文件加载匹配、WAV 帧读取、FIFO 到 I²S 接收器的样本传送、BMP 缩放与行填充、FFT 单音峰值、80 根频谱柱几何和强光混合、波形触发及视频帧切换。

2026-10-15 使用 TD 6.2.168116、EG4S20BG256 对独立工程副本完成综合、布局、布线和比特流生成，文件为 `src/td_project/full_build_probe.bit`。该副本使用与正式 `.al` 工程相同的顶层、RTL、引脚和时序约束，源码清单已比对一致。最终报告为 LUT 16,258/19,600、BRAM 54/64、DSP 15/29。原 16 路 Goertzel 版本为 LUT 17,215、BRAM 36、DSP 29；FFT 与 BMP 行缓存改变了资源分布。

**时序仍未达标**：最终路由报告 SWNS -6.699 ns、HWNS -1.528 ns。最差 setup 路径为原有外部 SDRAM 数据返回路径；SD 卡时钟域最差 setup 为 -3.504 ns，涉及 BMP 续簇地址计算。比特流可用于上板实验，但不能仅凭生成成功断言稳定运行。尚未连接开发板/下载器并验证真实 TF 卡持续读取、HDMI 音频输出和画面效果。

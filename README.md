# FPGA 多功能影音交互系统

## 手势识别 FPGA

手势发送板独立工程位于 [gesture_fpga](gesture_fpga/)。在 TD 中打开 [full_camera_edge_preview.prj](gesture_fpga/src/td_project/full_camera_edge_preview.prj)，对应构建脚本为 `build_camera_gesture_link_seg.tcl`。识别、挥手检测和 UART 发送逻辑分别见 `gesture_classifier.v`、`gesture_swipe.v` 和 `gesture_link_tx.v`。

连接影音主板时，手势板 TX 使用 J2 第 19 脚 GPIOB16（G1），影音主板 RX 使用 J1 第 5 脚 GPIOA4（H13），两板共地。串口为 9600 baud、8N1。主板用左挥、右挥切图。手势包内 `receiver/` 是独立接收演示工程，其接收引脚与影音主板不同。

基于 **HX4S20 / EG4S20BG256** 的 FPGA 多媒体作品，支持 TF 卡图片与音乐播放、HDMI 显示、OV2640 实时预览、ASRPRO 语音控制及 Android 蓝牙双向控制。

## 功能

| 模块 | 功能 |
| --- | --- |
| 图片 | 自动轮播、手动切换、直切 / 淡入淡出 / 滑动转场 |
| 图片属性 | 中文属性面板，亮度、对比度、尺寸、显示比例调节 |
| 音乐 | 曲目选择、上一首 / 下一首、播放 / 暂停、同步歌词与歌名 |
| 声音 | 11 档音量（0～10）、静音 / 恢复、1024 点 FFT 动态频谱 |
| 摄像头 | ATK-OV2640 DVP 采集，经 SDRAM 缓冲后输出 HDMI |
| 交互 | 板载按键、ASRPRO 语音、Android BLE、网页 BLE |
| 手机通知 | 中文文字转点阵，滚动显示、速度设置和定时清除 |

只有自动模式会定时切图；属性编辑通过按键保存退出。摄像头与图片音乐模式可切换，手机端控制 HDMI 模式，**不向手机传输摄像头视频**。语音工程配置了 528 条词条，唤醒词为“你好”，使用永久唤醒模式，上电后可直接说指令。更新需在天问 Block 重新生成并下载 ASRPRO 模型。

[TF 卡视频播放](docs/VIDEO_PLAYBACK.md)使用 MVI4 逐帧调色板视频和配套 PCM 音轨，目标 30 fps。演示基准为 video_quality30.bit。PC 蓝牙上位机支持参数总览。详见[发布说明](docs/PUBLISHING.md)。

## 目录

保留现有目录名，便于 TD 工程、语音生成器和 Android 资源同步脚本沿用相对路径。

```text
.
├── lab_ex5_i2s-work/                  # 当前 FPGA 主工程与网页
│   ├── src/user_source/hdl_source/    # 图像、音频、摄像头、UART、SDRAM
│   ├── src/user_source/constraints_source/ # 管脚和时序约束
│   ├── src/td_project/                # TD 工程与当前构建脚本
│   ├── src/test/                      # 转场、音量、自动模式等回归测试
│   ├── sim/                          # 其他有效仿真及仿真桩
│   ├── tools/                        # TF 卡媒体、歌词与中文面板工具
│   ├── media/playlist.csv            # 示例曲目编号与名称，不含音频
│   └── bluetooth_image_controller.html
├── lab_ex5_i2s/android_app/            # Android 应用源码与 BLE / 语音桥接
├── lab_ex5_i2s/bluetooth_image_controller.html # 同步的兼容入口
├── 语音控制/                         # ASRPRO 工程、生成器、词条验证
├── docs/                             # 构建、发布和第三方说明
└── requirements.txt                 # 媒体处理工具的 Python 依赖
```

## 硬件

- HX4S20 开发板，芯片 EG4S20BG256，使用 HDMI_B 输出。
- TF 卡：BMP 图片、48 kHz / 16 bit / 双声道 PCM WAV、LYR2 点阵歌词。
- W02 BLE 串口模块，UART 为 9600、8N1。
- ASRPRO 语音模块，独立双向 UART 为 9600、8N1。
- ATK-OV2640 18 针模块。

接线以 [pin.adc](lab_ex5_i2s-work/src/user_source/constraints_source/pin.adc) 为准。摄像头逐针接线见 [OV2640 接线说明](lab_ex5_i2s-work/OV2640_接入规划.md)，语音接线见 [ASRPRO 说明](lab_ex5_i2s-work/ASRPRO_VOICE_CONTROL.md)。

## 构建与使用

详见 [构建指南](docs/BUILD.md)。

1. 安装 Anlogic TD 6.2、对应 EG4 器件支持。
2. 在 `lab_ex5_i2s-work/src/td_project` 下运行 `build_camera_player_volume_manual.tcl`。顶层为 `top_camera_player`；GUI 可打开同目录的 `HDMI1.4b_Transmitter_v1.0.al`。
3. 下载生成的 `camera_player_volume_manual.bit`，按媒体工具说明准备自己的 TF 卡内容。
4. 构建 Android APK 后安装，允许附近设备权限，扫描 W02。出现实时状态回传后使用控制功能。
5. ASRPRO 的 `.hd` 工程需在天问 Block 中生成模型并下载到模块。

## 文档

- [构建指南](docs/BUILD.md)
- [控制逻辑优化记录](docs/OPTIMIZATION_20261020.md)
- [模式回传与通知优化及创新方向](docs/NEXT_STEPS_AND_OPTIMIZATION_20261020.md)
- [发布说明](docs/PUBLISHING.md)
- [第三方组件说明](docs/THIRD_PARTY.md)
- [蓝牙协议](lab_ex5_i2s-work/UART_BLUETOOTH_PROTOCOL.md)
- [音量与手动模式](lab_ex5_i2s-work/VOLUME_AND_MANUAL_MODE.md)
- [频谱语音控制](lab_ex5_i2s-work/SPECTRUM_VOICE_CONTROL.md)
- [安卓上位机](lab_ex5_i2s-work/ANDROID_CONTROLLER.md)
- [歌词点阵格式](lab_ex5_i2s-work/LYRIC_BITMAP_FORMAT.md)
- [完整语音词条](语音控制/词条清单.md)

## 当前验证范围

当前完整版本已生成 bit，历史布局布线资源占用为 LUT 18069 / 19600、BRAM 55 / 64、DSP 13 / 29、PLL 3 / 4。转场、自动模式、音量、串口协议及 Android JS 适配层有仿真或脚本验证。

最新实现报告仍有 setup WNS **−6.826 ns**、hold WNS **−1.540 ns**，尚未完成时序收敛；最新音量与手动模式版本仍需上板验证。10 月 20 日新增的模式回传快照修复已通过 UART 仿真，但尚未重新生成 bit；目录中的现有 bit 不包含该修复。Android 2.0.2 APK 已完成构建，手机 BLE 和语音识别尚未实机验证。不要将生成 bit / APK 等同于所有硬件功能已通过验证。

## 仓库内容与许可

工具链、缓存、签名密钥、个人歌曲和歌词、旧版工程及大体积生成文件不纳入 Git。APK 与 bit 适合通过 GitHub Releases 单独分发。

项目包含供应商 IP 和第三方参考实现，许可边界见 [第三方说明](docs/THIRD_PARTY.md)。仓库暂未指定统一开源许可证；公开源代码不代表所有文件均可任意再分发或商用。

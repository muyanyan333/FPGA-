# 第三方组件与工具

| 内容 | 来源 / 使用范围 |
| --- | --- |
| HDMI 发送核 | `hdl_source/hdmi1.4b_transmitter_core` 中的加密供应商 IP，需匹配 Anlogic TD |
| FIFO、PLL 与存储相关 IP | `hdl_source/IP`、`hdl_source/include`、`td_project/al_ip`；保留源文件原有版权信息 |
| OV2640 配置参考 | [Espressif esp32-camera](https://github.com/espressif/esp32-camera)、[ST OV2640](https://github.com/STMicroelectronics/stm32-ov2640)；具体历史参考见摄像头说明 |
| Python 媒体工具 | Pillow、imageio-ffmpeg；由用户安装，不随源码打包其运行时 |
| Android 构建 | Android SDK、Android Gradle Plugin、Gradle、JDK；由用户自行安装 |
| ASRPRO 编辑 / 模型工具 | 天问 Block；仓库保存项目和生成脚本，不包含模型服务账号或工具安装包 |

供应商 IP 不因本仓库公开而自动获得新的许可证。现有文件中未发现足以覆盖整个工程的统一授权文本；本说明只是来源清单，不替代各组件的原始许可。公开发布前需由项目作者确认第三方文件的分发权限；不允许公开的 IP 应从待提交内容中移除，并说明合法获取方式。

歌曲标题用于展示曲目配置，不附带歌曲音频、LRC 或点阵歌词。

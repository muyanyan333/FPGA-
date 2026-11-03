# 构建指南

以下命令从仓库根目录执行；工具路径使用自己电脑的安装位置。

## FPGA

环境：Anlogic TD 6.2.168116、EG4S20BG256 器件数据库。

```powershell
Set-Location lab_ex5_i2s-work/src/td_project
& '你的TD安装目录/bin/td_commands_prompt.exe' build_video_quality30.tcl
```

若 TD 终端入口参数与本机安装版本不同，可在 TD 命令环境中执行 `source build_video_quality30.tcl`。脚本必须从该目录运行。当前完整功能使用 TD 官方面积优先策略，旧构建入口不保证能容纳新增视频逻辑。

- 工程：`full_camera_player.prj`。
- GUI 工程：`HDMI1.4b_Transmitter_v1.0.al`。
- 顶层：`top_video_player`。
- 管脚：`../user_source/constraints_source/pin.adc`。
- 时序：`../user_source/constraints_source/timing_video_no_camera.sdc`。
- 输出：`video_quality30.bit`。

HDMI 和 SDRAM 等供应商 IP 需要兼容的 TD 工具及其器件库。具体组件范围见 [第三方说明](THIRD_PARTY.md)。

## Android

需要 JDK 17、Gradle 8.7、Android SDK Platform 34 和 Build Tools 34.0.0。Android Gradle Plugin 为 8.5.2，最低 Android 6.0。

配置 `JAVA_HOME`、`ANDROID_HOME`，确保 Python 与 Gradle 可运行；也可在 Android Studio 中打开 `lab_ex5_i2s/android_app`。SDK 路径可写入本机 `local.properties`，该文件不会提交。

```powershell
python lab_ex5_i2s/android_app/sync_controller.py
gradle -p lab_ex5_i2s/android_app assembleDebug
```

或使用可指定工具路径的脚本：

```powershell
./lab_ex5_i2s/android_app/build_apk.ps1 -PythonExe python -GradleExe gradle
```

首次构建需要联网下载 Gradle 依赖；本机依赖完整时可加 `-Offline`。脚本会优先使用仓库旁已安装的 `android_toolchain`，没有时使用环境中的工具。

APK 默认输出到 `lab_ex5_i2s/android_app/app/build/outputs/apk/debug/app-debug.apk`；PowerShell 脚本还会复制到 `lab_ex5_i2s-work/W02_Controller_Android.apk`。

新电脑会使用自己的 Android 调试签名。作者电脑的本地签名仅用于兼容旧 APK，不进入仓库。正式发布需自行配置发布签名并妥善保管。

## 语音工程

```powershell
python 语音控制/build_asrpro_project.py
python 语音控制/validate_voice_catalog.py
python lab_ex5_i2s/android_app/sync_controller.py
```

生成器从 `media/playlist.csv` 读取曲目，并同步两份网页的词条。修改后应再次同步 Android 资源。代码生成与词条校验不等同于 ASRPRO 模型生成；后者需使用天问 Block。

## 媒体准备

```powershell
python -m pip install -r requirements.txt
python lab_ex5_i2s-work/tools/build_single_track.py --help
python lab_ex5_i2s-work/tools/prepare_card.py --help
```

使用自己有权使用的音频和 LRC；歌词渲染需要中文字体。`prepare_card.py` 会操作指定 TF 卡，先使用其 `--dry-run` 参数核对路径。个人媒体不包含在公开仓库中，示例曲目名称只是当前界面配置。

## 软件验证

```powershell
python 语音控制/validate_voice_catalog.py
node lab_ex5_i2s/android_app/test_adapter.cjs
node lab_ex5_i2s/android_app/test_notice_connection.cjs
```

Verilog 测试源保存在 `lab_ex5_i2s-work/src/test` 与 `sim`，可使用 Icarus Verilog 编译运行。带加密 IP 的完整 FPGA 工程应以 TD 检查结果为准。

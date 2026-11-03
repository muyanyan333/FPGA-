# GitHub 发布说明

## 已整理的内容

- 保留当前 FPGA、Android 和 ASRPRO 三部分，以及有效工具与测试源。
- 移除旧版教学工程、过时音调 / ROM 播放器、废弃 Android Activity、旧构建脚本和调试产物。
- 清理前文件保存在本机 `_archive/repository_cleanup/obsolete_files.zip`，对应清单含 SHA256。该备份不提交 Git。
- `.gitignore` 排除工具链、缓存、本机 SDK 配置、签名密钥、歌曲、歌词和构建产物。

## 发布

在 GitHub 新建空仓库后，从本项目根目录执行：

```powershell
git init -b main
git add .
git diff --cached --stat
git commit -m "Initial project source"
git remote add origin https://github.com/你的用户名/你的仓库名.git
git push -u origin main
```

提交前查看文件列表，确认没有自己不打算公开的内容。本次整理不会创建远程仓库或执行推送。

## 发布附件

需要单独打包源码时，在仓库根目录运行：

```powershell
python tools/export_source.py
```

输出 `FPGA_Multimedia_GitHub_Source.zip`，包含 Git 可见文件和 SHA256 清单。导出工具检查私钥、个人媒体、大文件以及 FPGA 工程文件是否遗漏；本机缓存与备份不会进入包内。解压后的内容也可作为新仓库的初始文件。

APK 和 bit 不进入源码历史。建议在 GitHub Releases 上传经过验证的版本，并附上对应源码提交号、硬件型号、构建工具版本和实际验证范围。

演示附件为 `lab_ex5_i2s-work/src/td_project/video_quality30.bit`，使用 MVI4 视频与配套 WAV。该 bit 为历史演示构建，当前源码增加的 H6 按键音量尚未生成对应 bit。菜单重写版另有构建，发布基准使用原版。

源码包包含 PC 上位机 `lab_ex5_i2s-work/PC_FPGA_Controller.html` 和项目同步版技术报告。PC 页面通过 BLE 读取 FPGA 回传参数。报告和源码的功能状态以演示版、源码迭代及实机验证分别记录。

## 整理后的检查

2026-10-19：当前工程引用路径检查、Icarus Verilog 可读源代码语法检查、528 条语音词条及唤醒变体校验、Android JS 适配测试通过；移除旧 Activity 与资源后，Android `assembleDebug` 再次成功。语法检查没有替代加密 IP 的 TD 实现验证，未在本次整理中进行上板测试。

## 许可证

本次未替作者选择 MIT / GPL 等统一许可证。确认原创代码及供应商 IP 的授权范围后，再添加适当许可证。供应商器件手册、商业音频和歌词不包含在 Git 提交中。

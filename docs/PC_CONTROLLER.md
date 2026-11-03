# PC HTML BLE 上位机（2026-10-22）

入口：`lab_ex5_i2s-work/PC_FPGA_Controller.html`，已按用户要求改为 **W02 BLE**，
不是 USB 串口。单文件，无 CDN，不需要 COM 端口。无需改 FPGA 协议或 APK。

## 使用

1. 使用电脑 Chrome / Edge，打开电脑蓝牙，为 W02 和 FPGA 供电。
2. 若手机正在连接 W02，先断开手机端连接。
3. 打开 HTML，点击“扫描BLE”，在浏览器设备选择框中选择 W02；无需先系统配对。
4. 页面必须收到 FPGA 状态才视为链路可用；音量控件等收到 0x87 后启用。
5. 如本地文件环境不支持 Web Bluetooth，在仓库根目录运行：

```powershell
python -m http.server 8765 --bind 127.0.0.1 --directory lab_ex5_i2s-work
```

打开 `http://127.0.0.1:8765/PC_FPGA_Controller.html`。不使用远程普通 HTTP。
BLE 服务 UUID 为 `0000ffe0-0000-1000-8000-00805f9b34fb`，写入/通知均为
`0000ffe1-0000-1000-8000-00805f9b34fb`，可在设置页核对。
BLE 与 FPGA 之间的 W02 UART 仍为 9600 8N1，此参数不是 PC COM 设置。

## 功能

图片/亮度/对比度/尺寸/比例/转场、点歌/暂停、歌词/歌名/频谱、11 档音量与静音、
TF 卡视频切换、中文点阵通知、状态回传、日志、536 条语音/文字指令、演示模式。
PC 麦克风识别依赖浏览器语音服务及权限；文字指令无需麦克风。
“你好，播放视频”“停止视频”“音量小一点”等均保留。

视频输出在 FPGA HDMI 屏幕，不会传到 PC；当前 no-camera 视频固件不支持摄像头。
ASRPRO 离线识别仍须单独烧录最新 .hd 模型，页面不改变其永久唤醒设置。

## 维护与验证

PC 版复用已验证的 BLE 连接/重连、队列、通知订阅、协议和状态处理，生成器只
调整 PC 布局和说明，不再替换传输层。串口适配源码为早期尝试，不属于此入口。

```powershell
python tools/build_pc_controller.py
node tools/test_pc_controller.cjs
python 语音控制/validate_voice_catalog.py
```

BLE 模拟测试通过：FFE0 服务过滤、FFE1 写入与通知、先订阅再查询、音量/视频
字节、带偏移和分包的 RX、断线禁用、已授权绑定重连、取消选择。
未在电脑上实际连接 W02，不宣称真实蓝牙与麦克风识别已经验证。

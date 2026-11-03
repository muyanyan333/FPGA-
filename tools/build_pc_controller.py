"""Build a self-contained desktop BLE controller from the shared player UI."""
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "lab_ex5_i2s-work/bluetooth_image_controller.html"
OUTPUT = ROOT / "lab_ex5_i2s-work/PC_FPGA_Controller.html"
html = SOURCE.read_text(encoding="utf-8")

def replace(old, new):
    global html
    if old not in html:
        raise ValueError(f"Source marker missing: {old[:100]}")
    html = html.replace(old, new)

replace('<title>W02 影音控制台</title>', '<title>FPGA PC 影音控制台 · W02 BLE</title>')
replace('W02 · FPGA CONTROL', 'DESKTOP · FPGA CONTROL')
replace('<h1>影音控制台</h1>', '<h1>PC 影音控制台</h1>')
replace('图片、音乐与屏幕显示，一处掌控', 'W02 BLE 蓝牙直连 · 图片 / 音乐 / 视频 / 音量')
replace('点击“扫描BLE”直接选择模块，不需要先在系统中配对。网页需使用Android Chrome并通过HTTPS打开。',
        '使用桌面 Chrome / Edge，打开电脑蓝牙，点击“扫描BLE”选择 W02。无需 USB 串口或 COM 端口，也无需先在系统中配对。')
replace('点击顶部“扫描BLE”选择 W02 模块。手机请使用 Android Chrome，通过 HTTPS 打开本页面。',
        'PC 通过 Web Bluetooth 连接 W02 的 BLE GATT 服务。请断开手机与 W02 的连接后再扫描；若无法连接，请用 localhost 或 HTTPS 打开本页面。')
replace('用手机麦克风说出指令，经 W02 发给 FPGA', '用电脑麦克风或文字输入指令，经 W02 BLE 发给 FPGA')
replace('通知由手机渲染为点阵后发送，FPGA无需中文字库', '通知由电脑渲染为点阵后发送，FPGA无需中文字库')
replace('当前浏览器不支持Web Bluetooth。Android请使用Chrome并通过HTTPS打开。',
        '当前浏览器或页面环境不支持 Web Bluetooth。请使用桌面 Chrome / Edge，并通过 localhost 或 HTTPS 打开。')
replace('写入特征UUID（手机→模块）', '写入特征UUID（PC→W02）')
replace('通知特征UUID（模块→手机）', '通知特征UUID（W02→PC）')
replace('当前没有显示手机通知', '当前没有显示电脑通知')
# Desktop layout; preserve the existing mobile fallback and all control IDs.
replace('</style>', '''
    @media (min-width: 1050px) {
      .app { width: min(1340px, 96%); padding: 30px 28px 50px; }
      .nav { display: flex; flex-wrap: wrap; gap: 10px; }
      .nav-btn { flex: 1; min-width: 0; white-space: nowrap; font-size: 13px; }
      .page.active { display: grid; grid-template-columns: 1fr 1fr; gap: 0 18px; align-items: start; }
      .page-heading, .page > .note { grid-column: 1 / -1; }
      .page[data-page="settings"] > .card,
      .page[data-page="camera"] > .card,
      .page[data-page="commands"] > *, .page[data-page="voice"] > .card { grid-column: 1 / -1; }
      .connection-card { margin-bottom: 16px; }
      .music-tracks { grid-template-columns: repeat(4, 1fr); }
      .log { max-height: 360px; }
    }
  </style>''')
assert 'navigator.bluetooth.requestDevice(' in html
assert 'navigator.serial' not in html and 'pcSerial' not in html
assert 'startNotifications()' in html and 'voiceCommandCatalog' in html
OUTPUT.write_text(html, encoding='utf-8')
print(f'Built {OUTPUT}: {OUTPUT.stat().st_size} bytes (standalone, no CDN)')

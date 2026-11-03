"""Generate the ASRPRO configuration-mode Blockly project for the FPGA player."""

from __future__ import annotations

import csv
import json
import re
import sys
import xml.etree.ElementTree as ET
from dataclasses import dataclass
from pathlib import Path


ROOT = Path(__file__).resolve().parent
PLAYLIST = ROOT.parent / "lab_ex5_i2s-work" / "media" / "playlist.csv"
OUTPUT = ROOT / "语音控制.hd"
NS = "http://www.w3.org/1999/xhtml"
SLEEP_TIMEOUT_SECONDS = 1000
# TwenBlock ASRPRO setup: mode 1 = timed wake word; mode 2 calls
# set_wakeup_forever(). The timeout remains a valid, inactive UI field.
WAKE_MODE = 2
WAKE_WORD = "你好"
ET.register_namespace("", NS)


def tag(name: str) -> str:
    return f"{{{NS}}}{name}"


def field(parent: ET.Element, name: str, value: str | int) -> None:
    ET.SubElement(parent, tag("field"), {"name": name}).text = str(value)


def frame(command: int, argument: int = 0) -> str:
    assert 0 <= command <= 255 and 0 <= argument <= 255
    return f"A5 {command:02X} {argument:02X} {0xA5 ^ command ^ argument:02X}"


@dataclass(frozen=True)
class VoiceCommand:
    phrase: str
    command: int | None
    argument: int = 0
    response: str = ""


def recognition(parent: ET.Element, index: int, item: VoiceCommand) -> ET.Element:
    block = ET.SubElement(parent, tag("block"), {"type": "asr_easystart_recognize", "id": f"voice_{index:03d}"})
    for name, value in (
        ("ASR", item.phrase), ("IO", "-"), ("IO_mode", "-"),
        ("IO_status", "-------"),
        ("serial", "Serial" if item.command is not None else "-"),
        ("serial_bin", "HEX"),
        ("NAME", frame(item.command, item.argument) if item.command is not None else ""),
        # The FPGA reply, rather than recognition alone, confirms reception.
        ("huifu", item.response),
    ):
        field(block, name, value)
    return block


def commands() -> list[VoiceCommand]:
    items: list[VoiceCommand] = []

    def add(phrases: tuple[str, ...], command: int | None, argument: int = 0,
            response: str = "") -> None:
        items.extend(VoiceCommand(phrase, command, argument, response) for phrase in phrases)

    add(("查询设备状态", "检查设备连接", "设备在线吗", "刷新设备状态", "小美看看设备状态"), 0x01)
    add(("你会做什么", "语音控制帮助"), None,
        response="可以说下一张、上一首、播放歌名，也可以调节亮度、比例和歌词。")
    add(("图片有什么指令", "怎么控制图片"), None,
        response="可以说下一张、上一张、自动轮播、显示第几张、切换转场和调整图片比例。")
    add(("音乐有什么指令", "怎么控制音乐"), None,
        response="可以说播放歌名、上一首、下一首、暂停音乐、打开歌词或关闭歌名。")
    add(("你叫什么名字", "介绍一下自己"), None,
        response="我叫小美，是这台影音播放器的语音助手。")
    add(("讲个笑话", "来个冷笑话"), None,
        response="为什么音符不迷路？因为它总能找到节拍。")
    add(("夸夸我", "鼓励我一下"), None,
        response="你已经把图片、音乐和语音连在一起了，继续加油！")
    add(("来句诗", "念一句诗"), None,
        response="明月松间照，清泉石上流。")
    add(("今天开心吗", "小美开心吗"), None,
        response="能和你一起听歌看图，我很开心。")
    add(("晚安小美", "小美晚安"), None,
        response="晚安，愿你有个好梦。")
    add(("你喜欢哪首歌", "推荐一首歌"), None,
        response="可以试试心似烟火，也可以直接说播放心似烟火。")

    add(("音量大一点", "调大音量", "提高音量", "声音大一点", "大声一点"), 0x21)
    add(("音量小一点", "调小音量", "降低音量", "声音小一点", "小声一点"), 0x22)
    add(("静音", "关闭声音", "开启静音", "不要声音"), 0x23, 1)
    add(("取消静音", "恢复声音", "打开声音", "解除静音"), 0x23, 0)
    add(("切换静音",), 0x24)
    add(("最大音量", "音量最大", "音量开满"), 0x20, 10)
    add(("一半音量", "音量一半"), 0x20, 5)
    for level, numeral in enumerate("零一二三四五六七八九十"):
        add((f"音量设为{numeral}级", f"音量{numeral}级"), 0x20, level)
    add(("怎么控制音量", "音量有什么指令"), None,
        response="可以说音量大一点、音量小一点、音量五级、静音或取消静音。")

    add(("打开频谱", "开启频谱", "显示频谱", "打开音乐频谱", "显示底部频谱", "打开频率谱线", "显示频率谱线", "打开频谱柱"), 0x1E, 1)
    add(("关闭频谱", "隐藏频谱", "关闭音乐频谱", "隐藏底部频谱", "关闭频率谱线", "隐藏频率谱线", "关闭频谱柱", "收起频谱"), 0x1E, 0)
    add(("切换频谱", "切换频谱显示", "切换频率谱线", "切换底部频谱"), 0x1F)
    add(("频谱有什么指令", "怎么控制频谱"), None,
        response="可以说打开频谱、关闭频谱或者切换频谱，控制音乐画面底部的频率谱线。")

    add(("打开摄像头", "开启摄像头", "切换到摄像头", "查看实时画面", "摄像头模式", "实时预览"), 0x1D, 1)
    add(("关闭摄像头", "退出摄像头", "返回图片音乐", "回到图片音乐", "返回相册", "相册模式"), 0x1D, 0)
    add(("播放视频", "打开视频", "视频模式", "播放戒不掉", "播放TF卡视频"), 0x1D, 2)
    add(("停止视频", "关闭视频", "退出视频"), 0x1D, 0)
    add(("换下一幅", "翻到后面一张", "再看一张"), 0x04)
    add(("换上一幅", "翻到前面一张", "回看上一张"), 0x05)
    add(("先停一下音乐", "我想安静一下"), 0x0E, 0)
    add(("接着放音乐", "我想继续听歌"), 0x0E, 1)
    add(("开始欣赏图片",), 0x03)
    add(("先停在这张",), 0x06)
    for phrase, reply in (
        ("摄像头怎么用", "说打开摄像头看实时画面，说返回相册回到图片音乐。"),
        ("多久会退出", "现在是永久唤醒模式，上电后一直聆听，不会自动退出。"),
        ("再讲个笑话", "程序员为什么喜欢黑夜？因为白天的虫子太多了。"),
        ("讲个谐音梗", "小鸭子走进书店，说，我想买一本鸭力管理。"),
        ("说个绕口令", "四是四，十是十，十四是十四，四十是四十。"),
        ("再来个绕口令", "吃葡萄不吐葡萄皮，不吃葡萄倒吐葡萄皮。"),
        ("背一首静夜思", "床前明月光，疑是地上霜。举头望明月，低头思故乡。"),
        ("背一首春晓", "春眠不觉晓，处处闻啼鸟。夜来风雨声，花落知多少。"),
        ("来句励志的话", "不怕慢，就怕停。把眼前的一小步做好，就是进步。"),
        ("学习累了", "歇一歇眼睛，伸个懒腰，喝口水再继续。"),
        ("早上好小美", "早上好，愿你今天有好心情。"),
        ("下午好小美", "下午好，放松一下，听首喜欢的歌吧。"),
        ("谢谢小美", "不客气，需要时叫我就好。"),
        ("猜个谜语", "千条线，万条线，落在水里看不见。谜底是雨。"),
        ("再猜个谜语", "有面没有口，有脚没有手，虽然有四脚，自己不会走。谜底是桌子。"),
    ):
        add((phrase,), None, response=reply)

    add(("下一张", "下一张图片", "换一张图片", "切到下一张", "换个风景", "图片往后翻"), 0x04)
    add(("上一张", "上一张图片", "返回上一张", "切到上一张", "图片往前翻"), 0x05)
    add(("自动轮播", "自动播放图片", "开始轮播", "继续轮播", "让图片自己播放"), 0x03)
    add(("手动播放图片", "停止轮播", "手动切换图片", "我自己切图片"), 0x06)

    add(("切换转场", "换一种转场效果", "换个过渡效果"), 0x13)
    add(("直接切换", "关闭转场动画"), 0x07, 0)
    add(("淡入淡出", "使用淡入淡出"), 0x07, 1)
    add(("滑动切换", "使用滑动转场"), 0x07, 2)

    add(("调亮一点", "提高亮度", "图片亮一点", "再亮一点"), 0x14)
    add(("调暗一点", "降低亮度", "图片暗一点", "再暗一点"), 0x15)
    add(("亮度最高", "调到最亮", "让画面亮起来"), 0x08, 9)
    add(("亮度最低", "调到最暗"), 0x08, 0)
    add(("增加对比度", "对比度高一点"), 0x16)
    add(("减少对比度", "对比度低一点"), 0x17)
    add(("对比度最高",), 0x09, 9)
    add(("对比度最低",), 0x09, 0)

    add(("切换图片大小", "换一个图片尺寸", "换个图片尺寸"), 0x18)
    add(("显示大图", "图片放大", "使用大图"), 0x0B, 0)
    add(("显示中图", "使用中图"), 0x0B, 1)
    add(("显示小图", "图片缩小", "使用小图"), 0x0B, 2)
    add(("切换图片比例", "换一个画面比例", "换个画面比例"), 0x19)
    add(("原始比例", "恢复原始比例"), 0x0C, 0)
    add(("四比三比例", "设置四比三"), 0x0C, 1)
    add(("十六比九比例", "设置十六比九"), 0x0C, 2)
    add(("正方形比例", "设置一比一"), 0x0C, 3)

    add(("上一首", "上一首歌", "切换上一首"), 0x11)
    add(("下一首", "下一首歌", "切换下一首", "换首歌听听"), 0x12)
    add(("播放音乐", "继续播放音乐", "开始播放音乐", "来点音乐"), 0x0E, 1)
    add(("暂停音乐", "暂停播放", "停止音乐"), 0x0E, 0)
    add(("播放或暂停", "切换播放状态", "音乐暂停或继续"), 0x1C)
    add(("打开歌词", "显示歌词"), 0x0F, 1)
    add(("关闭歌词", "隐藏歌词"), 0x0F, 0)
    add(("切换歌词",), 0x1A)
    add(("打开歌名", "显示歌名"), 0x10, 1)
    add(("关闭歌名", "隐藏歌名"), 0x10, 0)
    add(("切换歌名",), 0x1B)

    for level, numeral in enumerate("零一二三四五六七八九"):
        add((f"亮度调到{numeral}档", f"亮度{numeral}级"), 0x08, level)
        add((f"对比度调到{numeral}档", f"对比度{numeral}级"), 0x09, level)

    numerals = (
        "一", "二", "三", "四", "五", "六", "七", "八",
        "九", "十", "十一", "十二", "十三", "十四", "十五", "十六",
    )
    for number, numeral in enumerate(numerals, start=1):
        add((f"显示第{numeral}张", f"切换到第{numeral}张图片",
             f"我想看第{numeral}张", f"播放第{numeral}张图片"), 0x02, number)
        add((f"打开第{numeral}张照片", f"看第{numeral}幅图片"), 0x02, number)
    for level, numeral in enumerate("零一二三四五六七八九"):
        add((f"亮度设为{numeral}级", f"画面亮度{numeral}档"), 0x08, level)
        add((f"对比度设为{numeral}级", f"画面对比度{numeral}档"), 0x09, level)
    with PLAYLIST.open(encoding="utf-8-sig", newline="") as source:
        for song in csv.DictReader(source):
            title, track = song["title"], int(song["track"])
            if not 1 <= track <= 16:
                raise ValueError(f"Invalid track number: {track}")
            add((f"播放{title}", f"我想听{title}", f"播放第{numerals[track - 1]}首",
                 f"来一首{title}", f"切换到{title}"),
                0x0D, track)
            add((f"放一首{title}", f"我要听{title}", f"给我播放{title}"), 0x0D, track)
    for phrases, command, argument in (
        (("再换一张", "往后换张图"), 0x04, 0),
        (("往前换张图", "回到前一张图片"), 0x05, 0),
        (("循环展示图片", "开启图片轮播"), 0x03, 0),
        (("固定当前图片", "暂停图片轮播"), 0x06, 0),
        (("取消切换特效", "图片直接跳转"), 0x07, 0),
        (("图片柔和过渡", "开启渐隐渐现"), 0x07, 1),
        (("图片滑过去", "开启横向滑动"), 0x07, 2),
        (("给我看看镜头", "我要看实时画面"), 0x1D, 1),
        (("回到照片界面", "退出实时画面"), 0x1D, 0),
        (("直接换下一首", "放下一首歌"), 0x12, 0),
        (("重听上一首歌", "放前一首歌"), 0x11, 0),
        (("音乐继续放", "把歌曲放起来"), 0x0E, 1),
        (("音乐先暂停", "暂停这首歌曲"), 0x0E, 0),
        (("把歌词打开", "我要看歌词"), 0x0F, 1),
        (("把歌词收起来", "歌词先关掉"), 0x0F, 0),
        (("把歌名显示出来", "看看歌曲名称"), 0x10, 1),
        (("把歌名隐藏起来", "歌名先关掉"), 0x10, 0),
        (("确认一下连接", "查看播放器状态"), 0x01, 0),
        (("图片用最大尺寸", "显示完整大图"), 0x0B, 0),
        (("切成宽屏比例", "图片使用十六比九"), 0x0C, 2),
    ):
        add(phrases, command, argument)
    for phrase, reply in (
        ("讲个小故事", "小蜗牛每天向前走一点，终于爬到了花园。慢一点没关系，方向对了就继续。"),
        ("再讲个小故事", "小星星以为自己不够亮，直到有人抬头说，今晚的星空真好看。你也有自己的光。"),
        ("讲个程序员笑话", "程序员去买菜，老板问要多少，他说，先给我一个测试样品。"),
        ("讲个动物笑话", "小企鹅为什么走路摇摇摆摆？因为它把每一步都走成了舞步。"),
        ("说句土味情话", "你知道我最喜欢什么画面吗？是你听歌时开心的样子。"),
        ("给我加个油", "加油，再试一次！每次调通一点，离成功就近一点。"),
        ("我有点紧张", "先慢慢呼吸，给自己一点时间，一步一步来就好。"),
        ("我有点无聊", "可以听一首歌，猜个谜语，或者打开摄像头看看身边的新画面。"),
        ("怎么放松一下", "伸个懒腰，看看窗外，再放一首自己喜欢的歌。"),
        ("来个顺口溜", "图片一张张，音乐轻轻唱，小美听你讲，快乐不打烊。"),
        ("背一首登鹳雀楼", "白日依山尽，黄河入海流。欲穷千里目，更上一层楼。"),
        ("背一首悯农", "锄禾日当午，汗滴禾下土。谁知盘中餐，粒粒皆辛苦。"),
        ("背一首咏鹅", "鹅，鹅，鹅，曲项向天歌。白毛浮绿水，红掌拨清波。"),
        ("七乘八等于几", "七乘八等于五十六。"),
        ("摄像头画面在哪里", "摄像头实时画面显示在连接 FPGA 的 HDMI 显示器上。上位机可以切换画面来源。"),
        ("怎么回到图片", "说返回相册，或者在上位机点击返回图片与音乐。"),
        ("语音能控制哪些属性", "可以控制图片尺寸、比例、亮度、对比度和转场，还能切歌、控制歌词歌名，以及切换摄像头。"),
    ):
        add((phrase,), None, response=reply)
    phrases = [item.phrase for item in items]
    if len(phrases) != len(set(phrases)):
        raise ValueError("Duplicate ASRPRO recognition phrase")
    return items


def sync_web_catalog(entries: list[VoiceCommand]) -> None:
    """Keep both local W02 pages consistent with the ASRPRO vocabulary."""
    with PLAYLIST.open(encoding="utf-8-sig", newline="") as source:
        songs = sorted(csv.DictReader(source), key=lambda song: int(song["track"]))
    if [int(song["track"]) for song in songs] != list(range(1, len(songs) + 1)):
        raise ValueError("Playlist track numbers must be consecutive from 1")
    names = json.dumps([song["title"] for song in songs], ensure_ascii=False)
    catalog = []
    for item in entries:
        action = {"reply": item.response} if item.command is None else {
            "command": item.command, "argument": item.argument, "label": item.phrase,
        }
        kind = {0x02: "image", 0x0D: "track", 0x08: "level", 0x09: "level"}.get(item.command)
        if kind:
            action["kind"] = kind
        catalog.append([item.phrase, action])
    generated = "  const voiceCommandCatalog = new Map(" + json.dumps(catalog, ensure_ascii=False, indent=2) + ");\n"
    for directory in ("lab_ex5_i2s-work", "lab_ex5_i2s"):
        path = ROOT.parent / directory / "bluetooth_image_controller.html"
        if not path.exists():
            continue
        content = path.read_text(encoding="utf-8")
        content = re.sub(r"  const songNames = .*?;", lambda _: f"  const songNames = {names};", content)
        content = re.sub(r"track: 1, trackCount: \d+, trackMap: 0x[0-9a-fA-F]+,",
                         "track: 1, trackCount: songNames.length, trackMap: (1 << songNames.length) - 1,", content)
        marker = "  const voiceCommandCatalog =" if "  const voiceCommandCatalog =" in content else "  const voiceLocalReplies ="
        start = content.index(marker)
        end = content.index("  let voiceRecognition", start)
        content = content[:start] + generated + content[end:]
        content = content.replace(
            "if (voiceLocalReplies.has(text)) return { reply: voiceLocalReplies.get(text) };",
            "if (voiceCommandCatalog.has(text)) return voiceCommandCatalog.get(text);",
        )
        content = re.sub(r"查阅 \d+ 条指令", f"查阅 {len(entries)} 条指令", content)
        content = re.sub(r"\d+ 条指令，按场景查找", f"{len(entries)} 条指令，按场景查找", content)
        path.write_text(content, encoding="utf-8")


def main() -> None:
    root = ET.Element(tag("xml"))
    setup = ET.SubElement(root, tag("block"), {"type": "asr_easystart_setup", "id": "voice_setup", "x": "0", "y": "0"})
    for name, value in (
        ("VOICE_SET", "小英-温和(V3)"), ("vol", 10), ("speed", 10),
        ("WELCOME", "语音控制已启动，永久唤醒，可以直接说音量小一点或下一张"),
        ("SLEEP", ""), ("play_vol", 7),
        ("mode", WAKE_MODE), ("second", SLEEP_TIMEOUT_SECONDS),
    ):
        field(setup, name, value)
    for number in range(10):
        field(setup, f"PIN{number}", 29)
        field(setup, f"STATE{number}", "input")
    for name, value in (
        ("baud", 9600), ("baud1", "-"), ("TX_1", 2),
        ("RX_1", 3), ("baud2", "-"), ("TX_2", 5), ("RX_2", 6),
    ):
        field(setup, name, value)

    wakeup = ET.SubElement(root, tag("block"), {"type": "asr_easystart_wakeup", "id": "voice_wakeup", "x": "0", "y": "460"})
    for name, value in (
        ("ASR", WAKE_WORD), ("IO", "-"), ("IO_mode", "-"),
        ("IO_status", "-"), ("serial", "-"), ("serial_bin", "HEX"),
        ("NAME", ""), ("huifu", "我在，可以说音量小一点、暂停音乐或下一张"),
    ):
        field(wakeup, name, value)

    current = wakeup
    entries = commands()
    for number, item in enumerate(entries, start=1):
        current = recognition(ET.SubElement(current, tag("next")), number, item)

    reply = ET.SubElement(ET.SubElement(current, tag("next")), tag("block"),
                          {"type": "asr_easystart_serial_rec", "id": "fpga_status_reply"})
    for name, value in (
        ("serial_rec", "Serial"), ("serial_bin_rec", "HEX"),
        ("NAME_rec", "5A 81"), ("IO", "-"), ("IO_mode", "-"),
        ("IO_status", "-------"), ("serial", "-"),
        ("serial_bin", "HEX"), ("NAME", ""),
        ("huifu", "FPGA已收到指令"),
    ):
        field(reply, name, value)

    # Blockly next chains add two XML levels per entry; size this for the
    # generated document instead of imposing the former arbitrary 300 cap.
    sys.setrecursionlimit(max(sys.getrecursionlimit(), len(entries) * 4 + 1000))
    xml = ET.tostring(root, encoding="unicode")
    parsed = ET.fromstring(xml)
    blocks = parsed.findall(f".//{tag('block')}[@type='asr_easystart_recognize']")
    if len(blocks) != len(entries) or not entries:
        raise ValueError("ASRPRO command count is invalid")
    replies = parsed.findall(f".//{tag('block')}[@type='asr_easystart_serial_rec']")
    if len(replies) != 1:
        raise ValueError("ASRPRO reply block is missing")
    for block in blocks:
        values = {item.attrib["name"]: item.text or "" for item in block.findall(tag("field"))}
        if values["serial"] == "-":
            if values["NAME"] or not values["huifu"]:
                raise ValueError(f"Invalid local response for {values['ASR']}")
            continue
        payload = bytes.fromhex(values["NAME"])
        if len(payload) != 4 or payload[0] != 0xA5 or payload[3] != (payload[0] ^ payload[1] ^ payload[2]):
            raise ValueError(f"Invalid UART frame for {values['ASR']}")
    footer = '\n<!-- edittype="asr_pro_e" -->\n<!-- officialLib="[]" -->\n<!-- personalLib="[]" -->\n'
    OUTPUT.write_bytes((xml + footer).encode("utf-8"))
    sync_web_catalog(entries)
    uart_count = sum(item.command is not None for item in entries)
    lines = [
        "# ASRPRO 语音词条清单", "",
        f"共 {len(entries)} 条：{uart_count} 条设备控制，{len(entries) - uart_count} 条本地回复。",
        f"唤醒词：{WAKE_WORD}。永久唤醒（mode={WAKE_MODE}）：上电后直接识别指令，不自动退出。", "",
        "更新工程后需重新生成并下载 ASRPRO 模型；此清单不表示模型已经编译或烧录。", "",
        "| 序号 | 短句 | 串口帧 / 本地回复 |", "| --- | --- | --- |",
    ]
    for index, item in enumerate(entries, 1):
        result = frame(item.command, item.argument) if item.command is not None else item.response
        lines.append(f"| {index} | {item.phrase} | {result} |")
    (ROOT / "词条清单.md").write_text("\n".join(lines) + "\n", encoding="utf-8")
    print(f"Wrote {OUTPUT.name}: {len(entries)} commands, 1 wake word, UART0 9600 baud")


if __name__ == "__main__":
    main()


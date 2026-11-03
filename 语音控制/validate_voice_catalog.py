"""Validate ASRPRO timeout and every real W02 parser result against the UART catalog."""
import json
import re
import subprocess
import tempfile
import xml.etree.ElementTree as ET
from pathlib import Path

from build_asrpro_project import (ROOT, NS, OUTPUT, commands, frame,
                                  SLEEP_TIMEOUT_SECONDS, WAKE_MODE, WAKE_WORD)

entries = commands()
root = ET.parse(OUTPUT).getroot()
timeout = root.find(f".//{{{NS}}}block[@type='asr_easystart_setup']/{{{NS}}}field[@name='second']")
assert timeout is not None and int(timeout.text) == SLEEP_TIMEOUT_SECONDS == 1000
def fields(block):
    assert block is not None, "Missing ASRPRO configuration block"
    return {field.attrib["name"]: field.text or "" for field in block.findall(f"{{{NS}}}field")}

setup = fields(root.find(f".//{{{NS}}}block[@type='asr_easystart_setup']"))
assert setup["mode"] == str(WAKE_MODE) == "2", "Permanent wake mode is not enabled"
assert setup["baud"] == "9600", "UART0 baud mismatch"
wakeup = fields(root.find(f".//{{{NS}}}block[@type='asr_easystart_wakeup']"))
assert wakeup["ASR"] == WAKE_WORD == "你好", "Wake word mismatch"
# Validate the real downloadable project, not only the generator/web tables.
blocks = root.findall(f".//{{{NS}}}block[@type='asr_easystart_recognize']")
assert len(blocks) == len(entries), "ASRPRO project/catalog length mismatch"
for block, entry in zip(blocks, entries):
    values = fields(block)
    assert values["ASR"] == entry.phrase, f"ASRPRO phrase mismatch: {entry.phrase}"
    assert values["huifu"] == entry.response, f"ASRPRO response mismatch: {entry.phrase}"
    expected = frame(entry.command, entry.argument) if entry.command is not None else ""
    assert values["NAME"] == expected, f"ASRPRO UART frame mismatch: {entry.phrase}"
    assert values["serial"] == ("Serial" if entry.command is not None else "-")
    assert values["serial_bin"] == "HEX"
print(f"PASS: actual ASRPRO XML, {len(entries)} phrases/frames; 9600 baud, 你好, permanent wake")
script_parts = []
for directory in ("lab_ex5_i2s-work", "lab_ex5_i2s"):
    path = ROOT.parent / directory / "bluetooth_image_controller.html"
    html = path.read_text(encoding="utf-8")
    code = re.search(r"<script>([\s\S]*?)</script>", html).group(1)
    catalog = code[code.index("  const voiceCommandCatalog ="):code.index("  let voiceRecognition")]
    parser = code[code.index("  function voiceNumber("):code.index("  function voiceFeedback(")]
    songs = re.search(r"  const songNames = .*?;", code).group(0)
    expected = [[e.phrase, e.command, e.argument, e.response] for e in entries]
    script_parts.append("new Function(" + json.dumps(code, ensure_ascii=False) + ");\n{\n" + songs + catalog + parser + "\nconst expected=" + json.dumps(expected, ensure_ascii=False) + ";\n" + """
for (const [phrase, command, argument, reply] of expected) {
  for (const utterance of [phrase, '小美，' + phrase + '，好吗', '你好，' + phrase + '，好吗']) {
    const actual = parseVoiceCommand(utterance);
    if (!actual || (command === null ? actual.reply !== reply :
        actual.command !== command || actual.argument !== argument)) {
      throw new Error('Voice catalog mismatch: ' + utterance + ' ' + JSON.stringify(actual));
    }
  }
}
for (const text of ['不要打开摄像头','小美别切换下一张','请不要暂停音乐','不用返回相册',null,42]) {
  if (parseVoiceCommand(text) !== null) throw new Error('Unexpected command: ' + text);
}
console.log(`PASS: ${expected.length} commands, ${expected.length * 2} wake-word/polite variants, negative and invalid inputs`);
}\n""")
    if "  async function sendDisplayMode(mode)" in code:
        mode_function = code[code.index("  async function sendDisplayMode(mode)"):code.index("  function voiceNumber(")]
        ack = code[code.index("      if (frame[1] === 0x86 &&"):code.index("      rxFrameCount++;")]
        script_parts.append("{\n" + """
let pendingDisplayMode=null, displayModeRequestId=0, displayModeTimer=null;
let linkToken=0, demoMode=false, state={displayMode:0};
let timers=new Map(), timerId=0, messages=[];
const render=()=>{}, log=value=>messages.push(value);
const setTimeout=fn=>{timers.set(++timerId,fn);return timerId;};
const clearTimeout=id=>timers.delete(id);
let sendCommand=async()=>true;
function acknowledge(mode) {
  const frame=[0x5A,0x86]; const nextState={...state,displayMode:mode};
""" + ack + "\n  state=nextState;\n}\n" + mode_function + """
async function checkModes() {
  const assert=(condition,label)=>{if(!condition) throw new Error(label);};
  await sendDisplayMode(1);
  acknowledge(0); assert(pendingDisplayMode===1,'stale status confirmed wrong mode');
  acknowledge(1); assert(pendingDisplayMode===null && timers.size===0,'matching ACK not cleared');
  await sendDisplayMode(0);
  timers.get(displayModeTimer)();
  assert(pendingDisplayMode===null && messages.length===1,'timeout not handled');
  let completeFirst;
  sendCommand=(command,arg)=>command===0x1D && arg===1 ?
    new Promise(resolve=>{completeFirst=resolve;}) : Promise.resolve(true);
  const first=sendDisplayMode(1);
  await sendDisplayMode(0);
  completeFirst(false); await first;
  assert(pendingDisplayMode===0,'old failure overwrote new request');
  acknowledge(0);
  const stale=sendDisplayMode(1);
  linkToken++; pendingDisplayMode=null; completeFirst(true); await stale;
  assert(pendingDisplayMode===null,'old connection changed current request');
  assert(await sendDisplayMode(7)===false,'invalid mode accepted');
  console.log('PASS: matching ACK, timeout, overlapping requests, reconnect, invalid mode');
}
checkModes().catch(error=>{console.error(error);process.exitCode=1;});
}\n""")
with tempfile.TemporaryDirectory() as temp:
    test = Path(temp) / "voice_catalog_check.js"
    test.write_text("\n".join(script_parts), encoding="utf-8")
    subprocess.run(["node", str(test)], check=True)
print("PASS: ASRPRO permanent wake enabled; timeout field is inactive")

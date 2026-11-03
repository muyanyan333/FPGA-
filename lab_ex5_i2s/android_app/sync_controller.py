"""Bundle the current complete controller with an Android BLE/speech adapter."""
from pathlib import Path
import re

app=Path(__file__).resolve().parent
source=app.parents[1]/'lab_ex5_i2s-work/bluetooth_image_controller.html'
html=source.read_text(encoding='utf-8')
def replace(old,new):
    global html
    assert old in html,old
    html=html.replace(old,new)

replace('<script>','''<script>
  const nativeAndroid = typeof AndroidController !== 'undefined';
  let nativeVoiceAvailable = false;
  let nativeWriteId = 0;
  const nativeWrites = new Map();
  function nativeWrite(bytes) {
    return new Promise((resolve,reject) => {
      const id=++nativeWriteId;
      const timer=setTimeout(()=>{nativeWrites.delete(id);reject(new Error('安卓蓝牙发送超时'));},8000);
      nativeWrites.set(id,{resolve,reject,timer});
      try { AndroidController.write(id,Array.from(bytes,b=>b.toString(16).padStart(2,'0')).join('')); }
      catch(error) {clearTimeout(timer);nativeWrites.delete(id);reject(error);}
    });
  }
  window.androidWriteDone=(id,error)=>{
    const item=nativeWrites.get(id);if(!item)return;
    clearTimeout(item.timer);nativeWrites.delete(id);
    if(error)item.reject(new Error(error));else item.resolve();
  };
''')
replace("els.voiceMicBtn.disabled = !SpeechRecognitionAPI;", "els.voiceMicBtn.disabled = nativeAndroid ? !nativeVoiceAvailable : !SpeechRecognitionAPI;")
replace('  function startVoiceRecognition() {','''  function startVoiceRecognition() {
    if(nativeAndroid) {
      if(voiceListening)AndroidController.stopVoice();else AndroidController.startVoice();
      return;
    }''')
replace('  function stopVoiceRecognition() {','''  function stopVoiceRecognition() {
    if(nativeAndroid) { if(voiceListening)AndroidController.stopVoice(); return; }''')
replace("    if (els.voiceSpeakToggle.checked && 'speechSynthesis' in window) {", "    if (nativeAndroid && els.voiceSpeakToggle.checked) AndroidController.speak(message);\n    else if (els.voiceSpeakToggle.checked && 'speechSynthesis' in window) {")
replace('  async function connectBluetooth() {','''  async function connectBluetooth() {
    if(nativeAndroid) {
      if(device?.gatt?.connected)AndroidController.disconnect();
      else AndroidController.connect(els.serviceUuid.value.trim(),els.writeUuid.value.trim(),els.notifyUuid.value.trim());
      return;
    }''')
replace('  setTimeout(autoReconnectBoundDevice, 350);','''  if(!nativeAndroid)setTimeout(autoReconnectBoundDevice,350);
  window.androidMessage=text=>{ log(text);showToast(text); };
  window.androidVoiceAvailable=available=>{
    nativeVoiceAvailable=available;updateAvailability();
    if(!available)els.voiceStatus.textContent='手机未安装语音识别服务，可输入文字指令';
  };
  window.androidVoiceState=(active,text)=>{
    voiceListening=active;els.voiceStatus.textContent=text;
    els.voiceMicBtn.textContent=active?'■ 停止聆听':'🎙 开始聆听';
    els.voiceMicBtn.classList.toggle('listening',active);
  };
  window.androidVoiceResult=text=>{els.voiceTextInput.value=text;executeVoice(text);};
  window.androidIncoming=bytes=>{if(!demoMode && device?.gatt?.connected)parseIncoming(Uint8Array.from(bytes));};
  window.androidConnected=name=>{
    ++linkToken;demoMode=false;state=emptyState();rxBuffer=[];rxFrameCount=0;lastRxAt=0;
    pendingDisplayMode=null;clearTimeout(displayModeTimer);
    writeQueue=Promise.resolve();
    writeCharacteristic={properties:{writeWithoutResponse:false},writeValue:nativeWrite,writeValueWithoutResponse:nativeWrite};
    device={gatt:{connected:true,disconnect:()=>AndroidController.disconnect()}};
    setConnected(true,name);els.connectBtn.textContent='断开连接';
    els.statusPill.textContent='已连接 · 等待回传';
    els.deviceHint.textContent='安卓 BLE 已连接 · 正在查询 FPGA';
    log('蓝牙通知已开启，等待 FPGA 实时状态');render();sendCommand(0x01,0);
  };
  window.androidDisconnected=reason=>{
    for(const id of Array.from(nativeWrites.keys()))window.androidWriteDone(id,reason);
    if(demoMode)return;
    ++linkToken;if(device?.gatt)device.gatt.connected=false;
    device=null;writeCharacteristic=null;notifyCharacteristic=null;state=emptyState();
    rxBuffer=[];rxFrameCount=0;lastRxAt=0;pendingDisplayMode=null;clearTimeout(displayModeTimer);
    setConnected(false);els.connectBtn.textContent='扫描BLE';els.deviceHint.textContent=reason;
    log(reason);render();
  };
  window.androidBack=()=>{if(location.hash && location.hash!=='#overview')showPage('overview');else AndroidController.close();};
  if(nativeAndroid){
    window.alert=text=>window.androidMessage(String(text));
    els.deviceHint.textContent='点击扫描BLE选择 W02，允许附近设备权限。无需浏览器或网页地址。';
    $('forgetBtn').textContent='断开当前连接';
    $('forgetBtn').onclick=()=>AndroidController.disconnect();
    document.querySelectorAll('.device-help').forEach(el=>el.textContent='选择 W02 模块即可连接，无需系统配对。');
  }
''')
html=html.replace('网页需使用Android Chrome并通过HTTPS打开。','安卓端使用原生蓝牙连接，无需系统配对。')
html=html.replace('手机请使用 Android Chrome，通过 HTTPS 打开本页面。','安卓端直接扫描 W02，页面随应用离线安装。')
assets=app/'app/src/main/assets'
assets.mkdir(parents=True,exist_ok=True)
(assets/'controller.html').write_text(html,encoding='utf-8')
assert all(token in html for token in ('0x87','volumeRange','恶作剧','voiceCommandCatalog','window.androidIncoming'))
print(f'Bundled current controller: {len(html.encode("utf-8"))} bytes')

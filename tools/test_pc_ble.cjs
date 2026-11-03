const fs=require('fs'),vm=require('vm'),assert=require('assert');
const html=fs.readFileSync(__dirname+'/../lab_ex5_i2s-work/PC_FPGA_Controller.html','utf8');
const code=html.match(/<script>([\s\S]*?)<\/script>/)[1];
new Function(code);
assert(html.includes('W02 BLE 蓝牙直连'));
assert(!html.includes('navigator.serial'));
const receiver=code.slice(code.indexOf('  function parseIncoming('),code.indexOf('  async function sendCommand('));
const sender=code.slice(code.indexOf('  async function sendCommand('),code.indexOf('  async function sendDisplayMode('));
const lifecycle=code.slice(code.indexOf('  async function connectDevice('),code.indexOf('  els.connectBtn.onclick = connectBluetooth;'));
let writes=[],subscribed=false,failPicker=false,requested=0;
const characteristic={properties:{writeWithoutResponse:false},
 async startNotifications(){subscribed=true;},
 async writeValue(data){assert(subscribed);writes.push([...data]);}};
const target={id:'test-w02',name:'W02',gatt:{connected:false,
 async connect(){this.connected=true;return this;},
 async getPrimaryService(uuid){assert(uuid.includes('ffe0'));return {
  async getCharacteristic(uuid){assert(uuid.includes('ffe1'));return characteristic;}
 };},
 disconnect(){this.connected=false;target.ongattserverdisconnected?.();}
}};
const ctx=vm.createContext({console,Uint8Array,queueMicrotask,Promise,
 setTimeout(fn,ms){if(ms===250)queueMicrotask(fn);return 0;},clearTimeout(){},
 alert(){throw Error('unexpected unsupported browser');},
 navigator:{bluetooth:{async requestDevice(options){requested++;assert(options.filters[0].services[0].includes('ffe0'));
  if(failPicker)throw Error('cancelled');return target;},async getDevices(){return [target];}}}
});
vm.runInContext(`
let device,writeCharacteristic,notifyCharacteristic,demoMode=false,linkToken=0;
let connectionPending=false,selectingDevice=false,rxBuffer=[],rxFrameCount=0,lastRxAt=0;
let pendingDisplayMode=null,displayModeTimer=null,writeQueue=Promise.resolve();
const emptyState=()=>({volume:10,muted:false,volumeStatusReady:false});let state=emptyState();
const els={deviceHint:{},deviceName:{},connectBtn:{},statusPill:{},noticeProgress:{},
 serviceUuid:{value:'0000ffe0-0000-1000-8000-00805f9b34fb'},
 writeUuid:{value:'0000ffe1-0000-1000-8000-00805f9b34fb'},
 notifyUuid:{value:'0000ffe1-0000-1000-8000-00805f9b34fb'}};
let saved=null;function savedDeviceId(){return saved;}function saveDeviceId(id){saved=id;}
function setConnected(){}function render(){}function updateAvailability(){}function updateLinkHealth(){}
function stopVoiceRecognition(){}function log(){}function showToast(){}function hex(){return '';}
function isReady(){return !!(device?.gatt?.connected&&writeCharacteristic);}
${receiver}\n${sender}\n${lifecycle}
`,ctx);
function frame(type,...payload){const f=[0x5a,type,...payload];while(f.length<7)f.push(0);return [...f,f.reduce((a,b)=>a^b,0)];}
function receive(bytes){const padded=Uint8Array.from([99,...bytes,99]);
 characteristic.oncharacteristicvaluechanged({target:{value:new DataView(padded.buffer,1,bytes.length)}});}
(async()=>{
 await ctx.connectBluetooth();assert.equal(requested,1);assert(subscribed);
 assert.equal(vm.runInContext('isReady()',ctx),true);
 assert.deepEqual(writes[0],[0xa5,1,0,0xa4]);
 await ctx.sendCommand(0x20,5);assert.deepEqual(writes.at(-1),[0xa5,0x20,5,0x80]);
 const f=frame(0x87,5,1);receive([9,...f.slice(0,3)]);receive(f.slice(3));
 assert.equal(vm.runInContext('state.volume===5&&state.muted&&state.volumeStatusReady',ctx),true);
 await ctx.sendCommand(0x1d,2);assert.deepEqual(writes.at(-1),[0xa5,0x1d,2,0xba]);
 await ctx.connectBluetooth();assert.equal(vm.runInContext('isReady()',ctx),false);
 assert.equal(await ctx.sendCommand(0x22,0),false);
 await ctx.connectBluetooth();assert.equal(requested,1,'should reuse permitted bound device');
 assert.equal(vm.runInContext('isReady()',ctx),true);
 target.gatt.disconnect();vm.runInContext('saved=null',ctx);failPicker=true;
 await ctx.connectBluetooth();assert.equal(vm.runInContext('selectingDevice||connectionPending',ctx),false);
 console.log('PASS: PC BLE syntax, service scan, GATT notifications before query, volume/video TX, offset/fragmented RX, disconnect, bound reconnect, picker failure');
})().catch(error=>{console.error(error);process.exitCode=1;});

const fs=require('fs'), vm=require('vm'), assert=require('assert');
const html=fs.readFileSync(__dirname+'/app/src/main/assets/controller.html','utf8');
const code=html.match(/<script>([\s\S]*?)<\/script>/)[1];
new Function(code);
const calls=[];
const context=vm.createContext({window:{},AndroidController:{write:(...args)=>calls.push(args)},setTimeout,clearTimeout,Uint8Array,console});
vm.runInContext(code.slice(0,code.indexOf('  const $ =')),context);
const receive=code.slice(code.indexOf('  function parseIncoming('),code.indexOf('  async function sendCommand('));
vm.runInContext(`
 let state={displayMode:0,volumeStatusReady:false}; let rxBuffer=[],rxFrameCount=0,lastRxAt=0,pendingDisplayMode=null,displayModeTimer=null;
 const els={statusPill:{textContent:'',title:''},deviceHint:{textContent:''}};
 let renderCount=0,healthCount=0;
 function updateLinkHealth(){healthCount++;} function render(){renderCount++;} function log(){} function hex(){return '';}
 ${receive}
`,context);
function frame(type,...payload){const a=[0x5a,type,...payload];while(a.length<7)a.push(0);return [...a,a.reduce((a,b)=>a^b,0)];}
const incoming=frame(0x86,1);
context.parseIncoming(Uint8Array.from([0,9,...incoming.slice(0,3)]));
assert.equal(vm.runInContext('rxFrameCount',context),0);
context.parseIncoming(Uint8Array.from(incoming.slice(3)));
assert.equal(vm.runInContext('state.displayMode',context),1);
const bad=frame(0x87,10,0);bad[7]^=1;
context.parseIncoming(Uint8Array.from([...bad,...frame(0x87,5,1)]));
assert.equal(vm.runInContext('rxFrameCount',context),2);
assert.equal(vm.runInContext('state.volume',context),5);
assert.equal(vm.runInContext('state.muted && state.volumeStatusReady && state.displayMode===1',context),true);
// Match the received mode, never the state from the previous frame.
vm.runInContext('pendingDisplayMode=0',context);
context.parseIncoming(Uint8Array.from(frame(0x86,0)));
assert.equal(vm.runInContext('pendingDisplayMode',context),null);
(function testVideoModeAndVolume(){
 vm.runInContext('pendingDisplayMode=2',context);
 context.parseIncoming(Uint8Array.from(frame(0x86,0)));
 assert.equal(vm.runInContext('pendingDisplayMode',context),2);
 context.parseIncoming(Uint8Array.from(frame(0x86,2)));
 assert.equal(vm.runInContext('state.displayMode',context),2);
 assert.equal(vm.runInContext('pendingDisplayMode',context),null);
 context.parseIncoming(Uint8Array.from(frame(0x86,2,4)));
 assert.equal(vm.runInContext('state.videoFlags',context),4);
 context.parseIncoming(Uint8Array.from(frame(0x87,4,1)));
 assert.equal(vm.runInContext('state.volume===4 && state.muted && state.displayMode===2',context),true);
 context.parseIncoming(Uint8Array.from(frame(0x86,1)));
 assert.equal(vm.runInContext('state.volume===4 && state.muted',context),true);
})();
vm.runInContext('pendingDisplayMode=0',context);
context.parseIncoming(Uint8Array.from(frame(0x86,1)));
assert.equal(vm.runInContext('pendingDisplayMode',context),0);
// A burst causes one UI refresh, including a trailing incomplete frame.
vm.runInContext('renderCount=0;healthCount=0',context);
context.parseIncoming(Uint8Array.from([...frame(0x87,3,0),...frame(0x86,0),...frame(0x87,7,1).slice(0,3)]));
assert.equal(vm.runInContext('renderCount',context),1);
assert.equal(vm.runInContext('healthCount',context),1);
context.parseIncoming(Uint8Array.from(frame(0x87,7,1).slice(3)));
assert.equal(vm.runInContext('state.volume',context),7);
assert.equal(vm.runInContext('pendingDisplayMode',context),null);
(async()=>{
 let resolved=false;
 const promise=context.nativeWrite(Uint8Array.from([0xa5,0x20,5,0x80])).then(()=>resolved=true);
 assert.equal(calls[0][1],'a5200580');await Promise.resolve();assert.equal(resolved,false);
 context.window.androidWriteDone(calls[0][0],null);await promise;assert.equal(resolved,true);
 const failed=context.nativeWrite(Uint8Array.from([0xa5,1,0,0xa4]));
 context.window.androidWriteDone(calls[1][0],'连接已断开');
 await assert.rejects(failed,/连接已断开/);
 context.window.androidWriteDone(calls[1][0],null);
 console.log('PASS: syntax, fragmented RX, checksum recovery, mode ACK matching, batched rendering, write acknowledgement and disconnect rejection');
})().catch(error=>{console.error(error);process.exitCode=1;});

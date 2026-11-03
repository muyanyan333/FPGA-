const fs = require('fs');
const path = require('path');
const vm = require('vm');
const assert = require('assert/strict');

function harness(file, {held = false, switchAtWrite = 0, switchAfterSend = false} = {}) {
  const html = fs.readFileSync(file, 'utf8');
  const code = html.slice(html.indexOf('  async function writeBulk('), html.indexOf('  async function connectDevice('));
  let release;
  const gate = held ? new Promise(resolve => { release = resolve; }) : Promise.resolve();
  const writes = [], queries = [];
  let context;
  const switchConnection = () => vm.runInContext('linkToken++; writeCharacteristic=newCharacteristic; device={gatt:{connected:true}};', context);
  const characteristic = name => ({properties:{writeWithoutResponse:true}, writeValueWithoutResponse:async bytes => {
    writes.push({name, bytes:Array.from(bytes)});
    if (switchAtWrite && writes.length === switchAtWrite) switchConnection();
  }});
  context = vm.createContext({Uint8Array, Promise,
    gate, oldCharacteristic:characteristic('old'), newCharacteristic:characteristic('new'),
    setTimeout:callback => { if (switchAfterSend && writes.length === 52) { switchAfterSend=false; switchConnection(); } callback(); },
    log(){}, alert(){}, updateAvailability(){}, render(){},
    isReady:() => true,
    sendCommand:async () => { queries.push(vm.runInContext('linkToken', context)); return true; },
    renderNoticeBitmap:() => ({bitmap:Uint8Array.from({length:1024},(_,i)=>i&255),width:48})
  });
  vm.runInContext(`
    let linkToken=1, writeQueue=gate, noticeSending=false, demoMode=false;
    let device={gatt:{connected:true}}, writeCharacteristic=oldCharacteristic;
    let state={};
    const els={noticeInput:{value:'测试'},noticeType:{value:'0'},noticeSpeed:{value:'1'},
      noticeDuration:{value:'0'},noticeProgress:{textContent:'unchanged'}};
    ${code}
  `, context);
  return {context,writes,queries,release,switchConnection,
    send:() => context.sendNotice(), value:expr => vm.runInContext(expr,context)};
}

(async()=>{
  for (const file of [path.join(__dirname,'../../lab_ex5_i2s-work/bluetooth_image_controller.html'),
                       path.join(__dirname,'app/src/main/assets/controller.html')]) {
    const normal=harness(file);
    await normal.send();
    const bytes=normal.writes.flatMap(w=>w.bytes);
    assert.equal(bytes.length,1029,'complete notice must be serialized');
    assert.equal(bytes[0],0xa6);assert.equal(bytes[2],48);
    assert.equal(bytes.slice(0,-1).reduce((a,b)=>a^b,0),bytes.at(-1));
    assert.deepEqual(normal.queries,[1]);

    const queued=harness(file,{held:true});
    const queuedSend=queued.send();
    queued.switchConnection();queued.release();await queuedSend;
    assert.equal(queued.writes.length,0,'queued notice must not migrate to a new connection');
    assert.equal(queued.queries.length,0);
    assert.equal(queued.value('noticeSending'),false);

    const ending=harness(file,{switchAtWrite:52});
    await ending.send();
    assert.equal(ending.queries.length,0,'old transfer must not query a new device after final packet');
    assert.equal(ending.value('els.noticeProgress.textContent').includes('已发送'),false);

    const delayed=harness(file,{switchAfterSend:true});
    await delayed.send();
    assert.equal(delayed.queries.length,0,'reconnect during pacing must cancel follow-up query');

    const duplicate=harness(file,{held:true});
    const first=duplicate.send();const second=duplicate.send();
    duplicate.release();await Promise.all([first,second]);
    assert.equal(duplicate.writes.length,52,'ignore a repeated send while the notice is pending');
  }
  console.log('PASS: notice integrity, queued reconnect, final-packet reconnect, delayed query and duplicate send (web + Android)');
})().catch(error=>{console.error(error);process.exitCode=1;});

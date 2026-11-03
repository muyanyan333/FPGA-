package com.wangzedong.fpgaimagecontroller;

import android.Manifest;
import android.app.*;
import android.bluetooth.*;
import android.bluetooth.le.*;
import android.content.*;
import android.content.pm.PackageManager;
import android.graphics.Color;
import android.os.*;
import android.provider.Settings;
import android.speech.*;
import android.speech.tts.TextToSpeech;
import android.webkit.*;
import android.widget.*;
import org.json.*;
import java.util.*;

/** Local UI with Android BLE transport. Every GATT operation is serialized on main. */
@SuppressWarnings({"MissingPermission", "deprecation"})
public final class ControllerActivity extends Activity {
    private static final int BLE_PERMISSION=41, MIC_PERMISSION=42;
    private static final UUID CCCD=UUID.fromString("00002902-0000-1000-8000-00805f9b34fb");
    private final Handler main=new Handler(Looper.getMainLooper());
    private final List<BluetoothDevice> devices=new ArrayList<>();
    private final Set<String> addresses=new HashSet<>();
    private final ArrayDeque<WriteJob> writes=new ArrayDeque<>();
    private BluetoothAdapter adapter;
    private BluetoothLeScanner scanner;
    private BluetoothGatt gatt;
    private BluetoothGattCharacteristic tx,rx;
    private WebView web;
    private AlertDialog scanDialog;
    private ArrayAdapter<String> scanRows;
    private boolean scanning,ready,writing,awaitingWriteCallback,destroyed,pageLoaded;
    private UUID serviceId,writeId,notifyId;
    private SpeechRecognizer recognizer;
    private int voiceGeneration;
    private TextToSpeech tts;
    private boolean ttsReady;
    private final Runnable scanTimeout=()->stopScan();
    private final Runnable connectTimeout=()->disconnect("连接超时，请检查模块后重试");
    private final Runnable writeTimeout=()->disconnect("蓝牙发送超时，请重新连接");
    private static final class WriteJob {
        final int id; final byte[] bytes; int offset;
        WriteJob(int id,byte[] bytes){this.id=id;this.bytes=bytes;}
    }

    @Override public void onCreate(Bundle state){
        super.onCreate(state);
        getWindow().setStatusBarColor(Color.rgb(8,17,31));
        getWindow().setNavigationBarColor(Color.rgb(8,17,31));
        BluetoothManager manager=(BluetoothManager)getSystemService(BLUETOOTH_SERVICE);
        adapter=manager==null?null:manager.getAdapter();
        web=new WebView(this); web.setBackgroundColor(Color.rgb(8,17,31));
        WebSettings settings=web.getSettings();
        settings.setJavaScriptEnabled(true); settings.setDomStorageEnabled(true);
        settings.setAllowFileAccess(false); settings.setAllowContentAccess(false);
        settings.setAllowFileAccessFromFileURLs(false); settings.setAllowUniversalAccessFromFileURLs(false);
        settings.setBlockNetworkLoads(true);
        web.addJavascriptInterface(new NativeBridge(),"AndroidController");
        web.setWebViewClient(new WebViewClient(){
            @Override public boolean shouldOverrideUrlLoading(WebView view,WebResourceRequest request){
                return !request.getUrl().toString().startsWith("file:///android_asset/controller.html");
            }
            @Override public boolean shouldOverrideUrlLoading(WebView view,String url){
                return !url.startsWith("file:///android_asset/controller.html");
            }
            @Override public void onPageFinished(WebView view,String url){
                pageLoaded=true;
                js("window.androidVoiceAvailable("+SpeechRecognizer.isRecognitionAvailable(ControllerActivity.this)+")");
            }
        });
        setContentView(web);
        web.loadUrl("file:///android_asset/controller.html");
        tts=new TextToSpeech(this,status->{
            if(status==TextToSpeech.SUCCESS){int result=tts.setLanguage(Locale.SIMPLIFIED_CHINESE);ttsReady=result>=0;}
        });
    }
    private void js(String code){
        if(!destroyed && pageLoaded) web.evaluateJavascript(code,null);
    }
    private void message(String text){js("window.androidMessage("+JSONObject.quote(text)+")");}
    private boolean permissions(){
        if(Build.VERSION.SDK_INT>=31) return checkSelfPermission(Manifest.permission.BLUETOOTH_SCAN)==PackageManager.PERMISSION_GRANTED && checkSelfPermission(Manifest.permission.BLUETOOTH_CONNECT)==PackageManager.PERMISSION_GRANTED;
        return checkSelfPermission(Manifest.permission.ACCESS_FINE_LOCATION)==PackageManager.PERMISSION_GRANTED;
    }
    private void beginScan(){
        if(scanning)return;
        if(gatt!=null && !ready){message("正在连接，请稍候");return;}
        if(adapter==null){message("此手机不支持蓝牙");return;}
        if(!permissions()){
            requestPermissions(Build.VERSION.SDK_INT>=31?new String[]{Manifest.permission.BLUETOOTH_SCAN,Manifest.permission.BLUETOOTH_CONNECT}:new String[]{Manifest.permission.ACCESS_FINE_LOCATION},BLE_PERMISSION);return;
        }
        if(!adapter.isEnabled()){
            new AlertDialog.Builder(this).setTitle("请开启蓝牙").setMessage("开启蓝牙后点击扫描，无需系统配对。")
                .setPositiveButton("蓝牙设置",(d,w)->startActivity(new Intent(Settings.ACTION_BLUETOOTH_SETTINGS))).setNegativeButton("取消",null).show();return;
        }
        if(Build.VERSION.SDK_INT<31){
            android.location.LocationManager lm=(android.location.LocationManager)getSystemService(LOCATION_SERVICE);
            if(lm!=null && !lm.isProviderEnabled(android.location.LocationManager.GPS_PROVIDER) && !lm.isProviderEnabled(android.location.LocationManager.NETWORK_PROVIDER)){
                new AlertDialog.Builder(this).setTitle("请开启位置服务").setMessage("Android 6～11 扫描蓝牙需要位置权限及位置服务。")
                    .setPositiveButton("位置设置",(d,w)->startActivity(new Intent(Settings.ACTION_LOCATION_SOURCE_SETTINGS))).setNegativeButton("取消",null).show();return;
            }
        }
        stopScan(); scanner=adapter.getBluetoothLeScanner();
        if(scanner==null){message("蓝牙扫描器不可用");return;}
        devices.clear();addresses.clear();
        scanRows=new ArrayAdapter<>(this,android.R.layout.simple_list_item_1,new ArrayList<>());
        scanDialog=new AlertDialog.Builder(this).setTitle("选择 W02 蓝牙模块（扫描中）")
            .setAdapter(scanRows,(dialog,index)->{if(index>=0 && index<devices.size()) connect(devices.get(index));})
            .setNegativeButton("取消",null).create();
        scanDialog.setOnDismissListener(dialog->stopScan());scanDialog.show();
        scanning=true;
        try {scanner.startScan(scanCallback);main.postDelayed(scanTimeout,8000);}catch(RuntimeException e){stopScan();message("扫描失败："+e.getMessage());}
    }
    private String name(BluetoothDevice device){String n=device.getName();return n==null||n.isEmpty()?"未命名 BLE 设备":n;}
    private final ScanCallback scanCallback=new ScanCallback(){
        @Override public void onScanResult(int type,ScanResult result){main.post(()->{
            if(!scanning)return;
            BluetoothDevice device=result.getDevice();
            if(addresses.add(device.getAddress())){devices.add(device);scanRows.add(name(device)+"\n"+device.getAddress()+" · "+result.getRssi()+" dBm");}
        });}
        @Override public void onScanFailed(int error){main.post(()->{stopScan();message("扫描失败（"+error+"），请重试");});}
    };
    private void stopScan(){
        if(scanning && scanner!=null && permissions()){try{scanner.stopScan(scanCallback);}catch(RuntimeException ignored){}}
        scanning=false;main.removeCallbacks(scanTimeout);
        if(scanDialog!=null && scanDialog.isShowing()) scanDialog.setTitle(devices.isEmpty()?"未发现设备，请确认 W02 已通电":"选择 W02 蓝牙模块");
    }
    private void connect(BluetoothDevice device){
        stopScan();disconnect("正在连接 "+name(device));
        message("正在连接 "+name(device)+"…");
        try {gatt=device.connectGatt(this,false,callback,BluetoothDevice.TRANSPORT_LE);main.postDelayed(connectTimeout,20000);}
        catch(RuntimeException e){disconnect("连接失败："+e.getMessage());}
    }
    private static boolean writable(BluetoothGattCharacteristic c){return c!=null && (c.getProperties()&12)!=0;}
    private static boolean notifiable(BluetoothGattCharacteristic c){return c!=null && (c.getProperties()&48)!=0;}
    private boolean selectCharacteristics(BluetoothGatt connection){
        BluetoothGattService service=connection.getService(serviceId);
        if(service!=null && writable(service.getCharacteristic(writeId)) && notifiable(service.getCharacteristic(notifyId))){
            tx=service.getCharacteristic(writeId);rx=service.getCharacteristic(notifyId);return true;
        }
        String[][] known={{"0000ffe0-0000-1000-8000-00805f9b34fb","0000ffe1-0000-1000-8000-00805f9b34fb","0000ffe1-0000-1000-8000-00805f9b34fb"},
            {"6e400001-b5a3-f393-e0a9-e50e24dcca9e","6e400002-b5a3-f393-e0a9-e50e24dcca9e","6e400003-b5a3-f393-e0a9-e50e24dcca9e"}};
        for(String[] ids:known){service=connection.getService(UUID.fromString(ids[0]));
            if(service!=null && writable(service.getCharacteristic(UUID.fromString(ids[1]))) && notifiable(service.getCharacteristic(UUID.fromString(ids[2])))){
                tx=service.getCharacteristic(UUID.fromString(ids[1]));rx=service.getCharacteristic(UUID.fromString(ids[2]));return true;
            }
        }
        return false;
    }
    private final BluetoothGattCallback callback=new BluetoothGattCallback(){
        @Override public void onConnectionStateChange(BluetoothGatt c,int status,int state){main.post(()->{
            if(c!=gatt)return;
            if(status==BluetoothGatt.GATT_SUCCESS && state==BluetoothProfile.STATE_CONNECTED){if(!c.discoverServices())disconnect("无法读取蓝牙服务");}
            else if(state==BluetoothProfile.STATE_DISCONNECTED || status!=BluetoothGatt.GATT_SUCCESS)disconnect("蓝牙已断开（"+status+"）");
        });}
        @Override public void onServicesDiscovered(BluetoothGatt c,int status){main.post(()->{
            if(c!=gatt)return;
            if(status!=BluetoothGatt.GATT_SUCCESS || !selectCharacteristics(c)){disconnect("未发现 W02 串口服务，请核对设置页 UUID");return;}
            BluetoothGattDescriptor descriptor=rx.getDescriptor(CCCD);
            if(descriptor==null || !c.setCharacteristicNotification(rx,true)){disconnect("模块缺少可用的数据通知");return;}
            byte[] value=(rx.getProperties()&BluetoothGattCharacteristic.PROPERTY_NOTIFY)!=0?BluetoothGattDescriptor.ENABLE_NOTIFICATION_VALUE:BluetoothGattDescriptor.ENABLE_INDICATION_VALUE;
            boolean accepted;
            if(Build.VERSION.SDK_INT>=33) accepted=c.writeDescriptor(descriptor,value)==BluetoothStatusCodes.SUCCESS;
            else{descriptor.setValue(value);accepted=c.writeDescriptor(descriptor);}
            if(!accepted)disconnect("无法启用数据回传");
        });}
        @Override public void onDescriptorWrite(BluetoothGatt c,BluetoothGattDescriptor d,int status){main.post(()->{
            if(c!=gatt || !CCCD.equals(d.getUuid()))return;
            if(status!=BluetoothGatt.GATT_SUCCESS){disconnect("启用回传失败（"+status+"）");return;}
            ready=true;main.removeCallbacks(connectTimeout);
            js("window.androidConnected("+JSONObject.quote(name(c.getDevice()))+")");
        });}
        private void incoming(BluetoothGatt c,BluetoothGattCharacteristic characteristic,byte[] value){
            if(value==null)return; byte[] copy=value.clone(); main.post(()->{
                if(c!=gatt || !ready || rx==null || !rx.getUuid().equals(characteristic.getUuid()))return;
                JSONArray bytes=new JSONArray();for(byte b:copy)bytes.put(b&255);
                js("window.androidIncoming("+bytes+")");
            });
        }
        @Override public void onCharacteristicChanged(BluetoothGatt c,BluetoothGattCharacteristic characteristic){if(Build.VERSION.SDK_INT<33)incoming(c,characteristic,characteristic.getValue());}
        @Override public void onCharacteristicChanged(BluetoothGatt c,BluetoothGattCharacteristic characteristic,byte[] value){incoming(c,characteristic,value);}
        @Override public void onCharacteristicWrite(BluetoothGatt c,BluetoothGattCharacteristic characteristic,int status){main.post(()->{
            if(c!=gatt || !writing || !awaitingWriteCallback || characteristic!=tx)return;
            awaitingWriteCallback=false;
            main.removeCallbacks(writeTimeout);
            if(status!=BluetoothGatt.GATT_SUCCESS){disconnect("蓝牙写入失败（"+status+"）");return;}
            WriteJob job=writes.peek(); if(job==null)return;
            job.offset+=Math.min(20,job.bytes.length-job.offset);
            // W02 forwards bytes at 9600 baud. Give each <=20 byte chunk 40 ms.
            main.postDelayed(()->{if(c!=gatt || writes.peek()!=job)return;writing=false;
                if(job.offset>=job.bytes.length){writes.poll();finishWrite(job.id,null);}pump();},40);
        });}
    };
    private void finishWrite(int id,String error){js("window.androidWriteDone("+id+","+(error==null?"null":JSONObject.quote(error))+")");}
    private void pump(){
        if(writing || writes.isEmpty() || !ready || gatt==null || tx==null)return;
        WriteJob job=writes.peek();byte[] chunk=Arrays.copyOfRange(job.bytes,job.offset,Math.min(job.offset+20,job.bytes.length));
        int type=(tx.getProperties()&BluetoothGattCharacteristic.PROPERTY_WRITE)!=0?BluetoothGattCharacteristic.WRITE_TYPE_DEFAULT:BluetoothGattCharacteristic.WRITE_TYPE_NO_RESPONSE;
        boolean accepted;
        try {
            if(Build.VERSION.SDK_INT>=33)accepted=gatt.writeCharacteristic(tx,chunk,type)==BluetoothStatusCodes.SUCCESS;
            else{tx.setWriteType(type);tx.setValue(chunk);accepted=gatt.writeCharacteristic(tx);}
        } catch(RuntimeException e) {
            disconnect("蓝牙不可用，请检查权限及蓝牙开关后重连");return;
        }
        if(!accepted){disconnect("蓝牙写入被拒绝，请重新连接");return;}
        writing=true;awaitingWriteCallback=true;main.postDelayed(writeTimeout,5000);
    }
    private void disconnect(String reason){
        main.removeCallbacks(connectTimeout);main.removeCallbacks(writeTimeout);
        ready=false;writing=false;awaitingWriteCallback=false;
        while(!writes.isEmpty())finishWrite(writes.poll().id,reason);
        BluetoothGatt old=gatt;gatt=null;tx=null;rx=null;
        if(old!=null){try{old.disconnect();}catch(RuntimeException ignored){} old.close();}
        js("window.androidDisconnected("+JSONObject.quote(reason)+")");
    }
    private void voiceState(boolean active,String text){js("window.androidVoiceState("+active+","+JSONObject.quote(text)+")");}
    private void stopVoice(){
        ++voiceGeneration;
        if(recognizer!=null){recognizer.cancel();recognizer.destroy();recognizer=null;}
        voiceState(false,"已停止聆听");
    }
    private void startVoice(){
        if(!SpeechRecognizer.isRecognitionAvailable(this)){voiceState(false,"手机未安装语音识别服务，可输入文字指令");return;}
        if(checkSelfPermission(Manifest.permission.RECORD_AUDIO)!=PackageManager.PERMISSION_GRANTED){requestPermissions(new String[]{Manifest.permission.RECORD_AUDIO},MIC_PERMISSION);return;}
        stopVoice();
        final int session=++voiceGeneration;
        {
            recognizer=SpeechRecognizer.createSpeechRecognizer(this);
            recognizer.setRecognitionListener(new RecognitionListener(){
                public void onReadyForSpeech(Bundle b){if(session==voiceGeneration)voiceState(true,"正在聆听，请说指令");}
                public void onBeginningOfSpeech(){} public void onRmsChanged(float rms){} public void onBufferReceived(byte[] b){}
                public void onEndOfSpeech(){if(session==voiceGeneration)voiceState(false,"正在识别…");}
                public void onError(int error){if(session!=voiceGeneration)return;++voiceGeneration;voiceState(false,"语音识别结束（"+error+"），可重试或输入文字指令");}
                public void onResults(Bundle b){if(session!=voiceGeneration)return;++voiceGeneration;ArrayList<String> words=b.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION);voiceState(false,"识别完成");
                    if(words!=null && !words.isEmpty())js("window.androidVoiceResult("+JSONObject.quote(words.get(0))+")");}
                public void onPartialResults(Bundle b){} public void onEvent(int type,Bundle b){}
            });
        }
        if(ttsReady)tts.stop();
        Intent intent=new Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH);
        intent.putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL,RecognizerIntent.LANGUAGE_MODEL_FREE_FORM);
        intent.putExtra(RecognizerIntent.EXTRA_LANGUAGE,"zh-CN");intent.putExtra(RecognizerIntent.EXTRA_MAX_RESULTS,1);
        try{recognizer.startListening(intent);voiceState(true,"准备聆听…");}catch(RuntimeException e){voiceState(false,"无法启动语音识别，可输入文字指令");}
    }
    public final class NativeBridge {
        @JavascriptInterface public void close(){main.post(()->finish());}
        @JavascriptInterface public void connect(String service,String write,String notify){main.post(()->{
            try{serviceId=UUID.fromString(service);writeId=UUID.fromString(write);notifyId=UUID.fromString(notify);beginScan();}
            catch(IllegalArgumentException e){message("UUID 格式错误，请检查设置页");}
        });}
        @JavascriptInterface public void disconnect(){main.post(()->{stopScan();ControllerActivity.this.disconnect("已主动断开");});}
        @JavascriptInterface public void write(int id,String hex){main.post(()->{
            if(!ready || gatt==null){finishWrite(id,"蓝牙未连接");return;}
            if(hex==null || hex.length()<2 || hex.length()>4096 || (hex.length()&1)!=0 || !hex.matches("[0-9a-fA-F]+") || writes.size()>=128){finishWrite(id,"发送数据无效或队列已满");return;}
            byte[] bytes=new byte[hex.length()/2];for(int i=0;i<bytes.length;i++)bytes[i]=(byte)Integer.parseInt(hex.substring(i*2,i*2+2),16);
            writes.add(new WriteJob(id,bytes));pump();
        });}
        @JavascriptInterface public void startVoice(){main.post(()->ControllerActivity.this.startVoice());}
        @JavascriptInterface public void stopVoice(){main.post(()->ControllerActivity.this.stopVoice());}
        @JavascriptInterface public void speak(String text){main.post(()->{if(ttsReady && text!=null && text.length()<500)tts.speak(text,TextToSpeech.QUEUE_FLUSH,null,"response");});}
    }
    @Override public void onRequestPermissionsResult(int request,String[] permissions,int[] results){
        super.onRequestPermissionsResult(request,permissions,results);
        if(request==BLE_PERMISSION){if(permissions())beginScan();else message("未授予附近设备权限，无法连接 W02");}
        if(request==MIC_PERMISSION){if(results.length>0 && results[0]==PackageManager.PERMISSION_GRANTED)startVoice();else voiceState(false,"麦克风权限未开启，可输入文字指令");}
    }
    @Override public void onBackPressed(){js("window.androidBack()");}
    @Override protected void onPause(){super.onPause();stopScan();stopVoice();if(ttsReady)tts.stop();}
    @Override protected void onDestroy(){
        stopScan();if(scanDialog!=null)scanDialog.dismiss();disconnect("应用已退出");
        if(recognizer!=null)recognizer.destroy();if(tts!=null)tts.shutdown();
        destroyed=true;main.removeCallbacksAndMessages(null);web.removeJavascriptInterface("AndroidController");web.destroy();super.onDestroy();
    }
}

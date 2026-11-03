  // PC transport adapter. The original controller keeps ownership of framing,
  // ACK checks, command queues and UI. This object replaces only BLE byte I/O.
  let pcSession = null, pcClosing = false;
  function pcResetUi(message) {
    ++linkToken;
    clearTimeout(displayModeTimer);
    pendingDisplayMode = null;
    device = null;
    writeCharacteristic = notifyCharacteristic = null;
    writeQueue = Promise.resolve();
    demoMode = false;
    rxBuffer = []; rxFrameCount = 0; lastRxAt = 0;
    state = emptyState();
    setConnected(false, 'FPGA · USB 串口');
    els.connectBtn.textContent = '连接串口';
    els.deviceHint.textContent = message;
    render();
  }
  async function pcClose(message = '串口已断开', expectedSession = pcSession) {
    const session = expectedSession;
    if (!session || session !== pcSession) return;
    if (session.closing) return session.closing;
    session.active = false;
    pcClosing = true; connectionPending = true;
    pcResetUi(message);
    session.closing = (async () => {
      await Promise.allSettled([
        session.reader ? session.reader.cancel() : Promise.resolve(),
        session.writer ? session.writer.abort('串口连接已关闭') : Promise.resolve()
      ]);
      if (session.readTask) await session.readTask;
      try { session.writer?.releaseLock(); } catch (_) {}
      try { await session.port.close(); } catch (error) {
        log(`串口关闭提示：${error.message}`);
      }
      if (session === pcSession) pcSession = null;
      pcClosing = false; connectionPending = false;
      updateAvailability();
    })();
    return session.closing;
  }
  async function pcReadLoop(session) {
    let reason = '串口数据流已结束，请重新连接';
    try {
      while (session.active) {
        const {value, done} = await session.reader.read();
        if (done) break;
        if (value && session.active && session === pcSession) parseIncoming(value);
      }
    } catch (error) {
      reason = `串口读取失败：${error.message}`;
    } finally {
      try { session.reader.releaseLock(); } catch (_) {}
      session.reader = null;
      // Schedule cleanup after this read task resolves; never await ourselves.
      if (session.active && session === pcSession)
        queueMicrotask(() => pcClose(reason, session).catch(error => log(error.message)));
    }
  }
  async function pcConnect() {
    if (connectionPending || selectingDevice || pcClosing) return;
    if (pcSession) { await pcClose(); return; }
    if (!navigator.serial || !window.isSecureContext) {
      showToast('请使用桌面 Chrome / Edge，在本地文件或 localhost 页面连接串口');
      log('当前浏览器或页面环境不支持 Web Serial；可先使用演示模式');
      return;
    }
    connectionPending = true;
    updateAvailability();
    let session;
    try {
      // Always user-initiated: do not automatically open unrelated COM ports.
      const port = await navigator.serial.requestPort();
      await port.open({baudRate:9600, dataBits:8, stopBits:1, parity:'none',
                       flowControl:'none', bufferSize:4096});
      session = {port, active:true, reader:null, writer:null, readTask:null, closing:null};
      pcSession = session;
      if (!port.readable || !port.writable) throw new Error('所选串口没有可用的数据流');
      session.writer = port.writable.getWriter();
      session.reader = port.readable.getReader();
      pcResetUi('9600 · 8N1 · 已打开串口，等待 FPGA 状态回传');
      const info = port.getInfo();
      const label = info.usbVendorId === undefined ? 'FPGA · 串口设备' :
        `FPGA · USB ${info.usbVendorId.toString(16).padStart(4,'0')}:${(info.usbProductId || 0).toString(16).padStart(4,'0')}`;
      // Compatibility facade for the existing connection guards, not a BLE link.
      device = {gatt:{connected:true}};
      writeCharacteristic = {
        properties:{writeWithoutResponse:false},
        async writeValue(bytes) {
          if (!session.active || session !== pcSession) throw new Error('串口连接已断开');
          try { await session.writer.write(Uint8Array.from(bytes)); }
          catch (error) {
            if (session.active) void pcClose(`串口写入失败：${error.message}`, session);
            throw error;
          }
          if (!session.active || session !== pcSession) throw new Error('串口连接已断开');
        }
      };
      session.readTask = pcReadLoop(session);
      setConnected(true, label);
      els.connectBtn.textContent = '断开串口';
      log('串口已打开：9600 baud / 8N1 / 无流控；已发送状态查询');
      await sendCommand(0x01,0);
    } catch (error) {
      if (session) await pcClose(`串口连接失败：${error.message}`,session);
      else if (error.name !== 'NotFoundError') {
        log(`串口连接失败：${error.message}`);
        showToast('无法打开串口：请关闭串口助手并检查 USB 转串口驱动');
      }
    } finally {
      if (!pcClosing) connectionPending = false;
      updateAvailability();
    }
  }
  navigator.serial?.addEventListener('disconnect', event => {
    if (pcSession && (event.target === pcSession.port || event.port === pcSession.port))
      void pcClose('USB 串口已拔出，请重新连接');
  });
  // PAGEHIDE may interrupt async cleanup; normal disconnect is preferred.
  window.addEventListener('pagehide', () => { if (pcSession) void pcClose(); });


# 两块 HX4S20 的手势通信

## 1. 两块板分别下载什么

- 摄像头/发送板：`src/td_project/camera_gesture_link.bit`，工程 `full_camera_edge_preview.prj`，顶层 `top_camera_preview`，构建 `build_camera_gesture_link.tcl`。
- 接收板演示：`receiver/receiver_demo.bit`，工程 `receiver_demo.prj`，顶层 `receiver_demo`，构建 `build_receiver.tcl`。

发送板以最新挥手轨迹修正版为基础，仅增加通信输出。通信发送的是识别模块真正产生的结果，不会使尚未识别出的动作自动成为有效手势。

## 2. 接线（仅两根信号连接）

| 发送板 | 接收板 | 作用 |
| --- | --- | --- |
| J2 第 19 脚，GPIOB_16，FPGA G1，输出 gesture_tx | J2 第 19 脚，GPIOB_16，FPGA G1，输入 gesture_rx | UART 数据 |
| J2 第 12 脚 GND，或第 30 脚 GND | J2 第 12 脚 GND，或第 30 脚 GND | 两板共地 |

发送板摄像头已经接在第 30 脚时，可用第 12 脚作通信共地。引脚依据用户原包《HX4S20开发板手册-HDL版2410》第 7 页 J2 排针表核对，G1 在原工程约束中未占用。按排针 1 脚标记/缺口确认方向，不要从照片镜像数脚。

两板各自供电，仅连接数据和地。数据是 3.3V TTL/CMOS UART，空闲高；不能接 J2-11 的 5V 电源脚，也不能直接接 RS232 电平。无需将两板 3.3V 或 5V 电源并接。

两块板不能都下载发送端位流后把 G1 相连；接收端 G1 必须配置为输入。原有 J1 蓝牙/语音串口继续保留，专用手势口在 J2。

## 3. 串口参数和帧格式

9600 baud，8 个数据位，无校验，1 个停止位（8N1），低位先发，无流控。发送逻辑时钟为 25MHz 视频时钟；接收板为板载 50MHz。两板不需要共用时钟。

每条指令固定四个二进制字节：`A5 CODE (~CODE & FF) 5A`。不是字符字符串，也没有回车换行。

| 动作 | CODE | 完整四字节（十六进制） | 接收脉冲 |
| --- | --- | --- | --- |
| 张手 OPEN | 01 | A5 01 FE 5A | open_pulse |
| 握拳 FIST | 02 | A5 02 FD 5A | fist_pulse |
| 向画面左侧挥手 LEFT | 03 | A5 03 FC 5A | left_pulse |
| 向画面右侧挥手 RIGHT | 04 | A5 04 FB 5A | right_pulse |
| 无目标 NONE，辅助状态 | 00 | A5 00 FF 5A | gesture_valid=1，四个动作脉冲均为 0 |

帧头 A5、反码校验和帧尾 5A 均正确，并且 CODE 为 0～4 时才接受。错误帧被丢弃；不完整帧有接收超时。每条帧约 4.17ms。

## 4. 发送时机

稳定分类首次进入 OPEN/FIST 或两者切换时发送；持续保持同一手形不重复发送。UNKNOWN 不作为动作发送，也不单独清除上次稳定状态。明确进入 NONE 后可发送 00，再次进入相同手形会重新发送。

每次确认的左右挥动发送一个动作事件。挥手与静态变化在同一时钟发生时，挥手优先。挥手后暂缓静态事件约 60 个显示帧（约 1 秒），避免移动过程中的分类跳变混入；若暂缓结束时静态结果确已改变，会补发当前稳定状态。

内部有四项事件缓冲。没有周期心跳或接收确认；若接收板单独复位且发送板一直保持同一姿态，需要换一次手势/移开再伸入，重新产生事件。接收端应按 gesture_valid 或四个 pulse 触发功能，不能根据一直保持的 last_code 每个时钟重复执行。

## 5. 接收板演示与功能接入

接收演示位流使用板上 4 个独立 LED 锁存显示最后一个有效动作：

| 接收事件 | 演示显示 |
| --- | --- |
| OPEN | LED1（A4）亮 |
| FIST | LED2（A3）亮 |
| LEFT | LED3（C10）亮 |
| RIGHT | LED4（B12）亮 |
| NONE | 四灯全灭 |

这些 LED 是通信演示，不是给你的最终功能指定动作。接入自己的工程时加入 `receiver/gesture_link_rx.v`，按 `receiver/receiver_example.v` 实例化；50MHz 时钟下参数保持 `CLK_HZ=50000000`。

`gesture_valid` 和四个 `*_pulse` 都只保持一个接收时钟周期（50MHz 下为 20ns），在同一 clk 的 always 块内作为使能使用，不要当作新的时钟。`gesture_code` 保留最近编号，适合读取状态。参考写法：

```verilog
always @(posedge clk) begin
    if (open_pulse) begin
        // 执行张手对应功能
    end
    if (fist_pulse) begin
        // 执行握拳对应功能
    end
    if (left_pulse) begin
        // 执行左挥对应功能
    end
    if (right_pulse) begin
        // 执行右挥对应功能
    end
end
```

默认接收演示工程将 RX 约束到 G1；整合到你的已有接收工程时，若该板的 G1 已被其他外设占用，可换另一个已核实空闲的 3.3V 输入脚，并同步修改接线和接收约束。发送板 G1 保持本协议定义。

## 6. 验证范围

`sim/tb_gesture_link.v` 在不同 25/50MHz 时钟间验证 UART 收发、五种编号、队列顺序、静态去重、UNKNOWN 不发送、挥手暂缓和恢复后状态发送、ready 门控、坏校验拒绝与重新同步。

`sim/tb_gesture_link_integration.v` 注入实际视觉模块接口的静态结果和挥手事件，检查从 `background_contour_view` 输出端经串口到接收脉冲的四种映射。它验证模块接线，不替代摄像头真实手势或两板实物接线测试。

发送端完整实现报告位于 `src/td_project/camera_gesture_link_*`；接收演示报告位于 `receiver/receiver_*`。真实两板联调仍需按上述接线下载后确认。摄像头识别与原工程的时序状态也需结合各自报告阅读。

## 本次实现结果

发送板和接收演示位流均已生成。发送端 setup/hold WNS 分别为 -5.826/0.004 ns，仍有原工程时序违例；接收端为 12.673/0.330 ns。串口收发及视觉模块接口注入仿真通过，实物连线与真实手势联调待验证。

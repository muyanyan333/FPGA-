`timescale 1ns/1ps
module tb_full;
reg clk, rst;
reg key_next, key_mode;
wire [3:0] state_code;
wire [15:0] bmp_width=640, bmp_height=480;
wire display_valid;
reg write_finish_toggle;
wire [1:0] write_buf_idx, disp_buf_idx;
wire [3:0] img_index;
wire auto_mode;
wire write_req;
reg write_req_ack;
wire write_en;
wire [31:0] write_data;
wire SD_nCS, SD_DCLK, SD_MOSI;
reg SD_MISO=1;

sd_card_bmp #(.CLK_FREQ_HZ(100_000), .SCAN_TARGET_COUNT(4)) dut(
    .clk(clk), .rst(rst), .key_next(key_next), .key_mode(key_mode),
    .key_mode_toggle(1'b0), .edit_active(1'b0),
    .remote_select_valid(1'b0), .remote_select_index(4'd0),
    .remote_auto(1'b0), .remote_next(1'b0), .remote_prev(1'b0),
    .state_code(state_code), .bmp_width(bmp_width), .bmp_height(bmp_height),
    .display_valid(display_valid), .write_finish_toggle(write_finish_toggle),
    .write_buf_idx(write_buf_idx), .disp_buf_idx(disp_buf_idx),
    .img_index(img_index), .auto_mode(auto_mode), .image_count(), .scan_complete(),
    .write_req(write_req), .write_req_ack(write_req_ack),
    .write_en(write_en), .write_data(write_data),
    .SD_nCS(SD_nCS), .SD_DCLK(SD_DCLK), .SD_MOSI(SD_MOSI), .SD_MISO(SD_MISO)
);

// ===== 模拟 SD 卡行为 =====
// 强制 sd_init_done
initial force dut.sd_init_done = 1'b1;

// 扇区读取行为：监控 sd_sec_read，模拟返回数据
reg [31:0] sim_addr;
integer byte_i;
reg [7:0] hdr [0:53];

// 构造一个合法 BMP header
function [7:0] header_byte;
    input [9:0] off;
    begin
        case (off)
            0:  header_byte = "B";
            1:  header_byte = "M";
            2:  header_byte = 8'h36;  // file size low (dummy)
            3:  header_byte = 8'h10;
            4:  header_byte = 8'h00;
            5:  header_byte = 8'h00;
            10: header_byte = 8'h36;  // pixel offset = 54
            18: header_byte = 8'h80;  // width 640 = 0x280
            19: header_byte = 8'h02;
            22: header_byte = 8'hE0;  // height 480 = 0x1E0
            23: header_byte = 8'h01;
            28: header_byte = 8'h18;  // 24 bpp
            30: header_byte = 8'h00;  // compression 0
            default: header_byte = 8'h00;
        endcase
    end
endfunction

initial begin
    force dut.sd_sec_read_data_valid = 1'b0;
    force dut.sd_sec_read_data = 8'h00;
    force dut.sd_sec_read_end = 1'b0;
end

// 响应读请求
reg reading;
always @(posedge clk) begin
    if (!dut.sd_sec_read) begin
        reading <= 1'b0;
        force dut.sd_sec_read_data_valid = 1'b0;
        force dut.sd_sec_read_end = 1'b0;
    end else if (!reading) begin
        reading <= 1'b1;
        sim_addr <= dut.sd_sec_read_addr;
        // 等待几个周期模拟命令
        repeat(5) @(posedge clk);
        // 输出512字节
        for (byte_i=0; byte_i<512; byte_i=byte_i+1) begin
            if (dut.sd_sec_read_addr < 32'd10) begin
                // header 扇区
                force dut.sd_sec_read_data = header_byte(byte_i[9:0]);
            end else begin
                force dut.sd_sec_read_data = byte_i[7:0];
            end
            force dut.sd_sec_read_data_valid = 1'b1;
            @(posedge clk);
        end
        force dut.sd_sec_read_data_valid = 1'b0;
        force dut.sd_sec_read_end = 1'b1;
        @(posedge clk);
        force dut.sd_sec_read_end = 1'b0;
    end
end

// ===== 模拟 frame_fifo_write 的握手 =====
always @(posedge clk) begin
    if (write_req && !write_req_ack)
        write_req_ack <= 1'b1;
    else if (!write_req)
        write_req_ack <= 1'b0;
end

// 模拟 SDRAM 写完成：write_req_ack 后等若干周期 toggle
reg [15:0] finish_cnt;
always @(posedge clk or posedge rst) begin
    if (rst) begin
        finish_cnt <= 0;
        write_finish_toggle <= 0;
    end else begin
        if (dut.load_start_pulse)
            finish_cnt <= 16'd200;
        else if (finish_cnt > 0) begin
            finish_cnt <= finish_cnt - 1;
            if (finish_cnt == 1)
                write_finish_toggle <= ~write_finish_toggle;
        end
    end
end

// ===== 按键任务 =====
task press_key3;
begin
    @(posedge clk); key_next = 0;
    repeat(2500) @(posedge clk);  // 去抖 20ms @100kHz = 2000 cycles
    key_next = 1;
    repeat(2500) @(posedge clk);
end
endtask

initial begin
    clk=0; rst=1; key_next=1; key_mode=1; write_req_ack=0;
    #100 rst=0;
    #200000;  // 等扫描+首图
    $display("first: img=%0d valid=%0d", img_index, display_valid);

    press_key3; $display("press1: img=%0d", img_index);
    press_key3; $display("press2: img=%0d", img_index);
    press_key3; $display("press3: img=%0d", img_index);
    press_key3; $display("press4: img=%0d", img_index);
    press_key3; $display("press5: img=%0d", img_index);
    press_key3; $display("press6: img=%0d", img_index);
    $finish;
end

always #5 clk=~clk;
endmodule

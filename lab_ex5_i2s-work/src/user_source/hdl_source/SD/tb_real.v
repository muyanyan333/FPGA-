`timescale 1ns/1ps
module tb_real;
reg clk, rst;
reg key_next, key_mode;
wire [3:0] state_code;
wire [15:0] bmp_width=32, bmp_height=24;
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

// mock frame_fifo_write 握手
always @(posedge clk or posedge rst) begin
    if (rst) write_req_ack<=0;
    else begin
        if (write_req && !write_req_ack) write_req_ack<=1;
        else if (!write_req) write_req_ack<=0;
    end
end

// mock SDRAM 写完成：load_start 后等 300 周期（约一帧）toggle
reg [15:0] fc;
always @(posedge clk or posedge rst) begin
    if (rst) begin fc<=0; write_finish_toggle<=0; end
    else begin
        if (dut.load_start_pulse) fc<=16'd300;
        else if (fc>0) begin
            fc<=fc-1;
            if (fc==1) write_finish_toggle<=~write_finish_toggle;
        end
    end
end

task press_key3;
begin
    @(posedge clk); key_next=0;
    repeat(2200) @(posedge clk);  // 按下保持 >20ms(2000cyc)
    key_next=1;
    repeat(2200) @(posedge clk);  // 松开
end
endtask

initial begin
    clk=0; rst=1; key_next=1; key_mode=1;
    #100 rst=0;
    #60000;  // 扫描+首图
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

`timescale 1ns/1ps
module tb_cycle;
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

sd_card_bmp #(.CLK_FREQ_HZ(1000), .SCAN_TARGET_COUNT(4)) dut(
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

// 强制内部状态，跳过真实SD卡初始化和扫描
initial begin
    // 等复位释放
    #100;
    // 强制 SD 初始化完成
    force dut.sd_init_done = 1'b1;
    // 强制 bmp_read 在 IDLE
    force dut.bmp_ready = 1'b1;
    force dut.scan_done = 1'b0;
    write_req_ack = 1'b0;
    write_finish_toggle = 0;

    // 手动注入4张图的 sector
    @(posedge clk);
    force dut.scan_found_valid = 1'b1;
    force dut.scan_found_sector = 32'd100;
    @(posedge clk);
    force dut.scan_found_sector = 32'd200;
    @(posedge clk);
    force dut.scan_found_sector = 32'd300;
    @(posedge clk);
    force dut.scan_found_sector = 32'd400;
    @(posedge clk);
    force dut.scan_found_valid = 1'b0;
    force dut.scan_done = 1'b1;

    // 现在等首图加载
    $display("=== after scan, img_found_count=%0d ===", dut.img_found_count);
end

// 模拟 write_req_ack 和 write_finish
always @(posedge clk) begin
    if (write_req && !write_req_ack) begin
        #1 write_req_ack = 1;
    end else if (!write_req) begin
        write_req_ack = 0;
    end
end

// 模拟加载完成：load_start 后等若干周期 toggle write_finish
reg [7:0] finish_cnt;
always @(posedge clk or posedge rst) begin
    if (rst) begin
        finish_cnt <= 0;
    end else begin
        if (dut.load_start_pulse) begin
            finish_cnt <= 8'd10;
        end else if (finish_cnt > 0) begin
            finish_cnt <= finish_cnt - 1;
            if (finish_cnt == 1)
                write_finish_toggle <= ~write_finish_toggle;
        end
    end
end

// 按键任务：按一下 KEY3
task press_key3;
begin
    @(posedge clk); key_next = 0;
    repeat(50) @(posedge clk);  // 去抖需要时间（CLK_FREQ=1000, 20ms=20 cycles）
    key_next = 1;
    repeat(50) @(posedge clk);
end
endtask

initial begin
    clk=0; rst=1; key_next=1; key_mode=1;
    #50 rst=0;
    #500;  // 等扫描和首图

    $display("=== first image, img_index=%0d display_valid=%0d ===", img_index, display_valid);

    // 按4次 KEY3
    press_key3;
    $display("after press 1: img_index=%0d", img_index);
    press_key3;
    $display("after press 2: img_index=%0d", img_index);
    press_key3;
    $display("after press 3: img_index=%0d", img_index);
    press_key3;
    $display("after press 4: img_index=%0d", img_index);
    press_key3;
    $display("after press 5: img_index=%0d", img_index);

    $finish;
end

always #5 clk=~clk;
endmodule

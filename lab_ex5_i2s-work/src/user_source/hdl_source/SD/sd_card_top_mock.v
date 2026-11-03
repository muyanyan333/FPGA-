// Mock SD 卡顶层：端口与真实 sd_card_top 完全一致，模拟扇区读取行为
module sd_card_top #(
    parameter SPI_LOW_SPEED_DIV = 248,
    parameter SPI_HIGH_SPEED_DIV = 0
)(
    input            clk,
    input            rst,
    input            video_fast_read,
    output           SD_nCS,
    output           SD_DCLK,
    output           SD_MOSI,
    input            SD_MISO,
    output reg       sd_init_done,
    input            sd_sec_read,
    input [31:0]     sd_sec_read_addr,
    output reg [7:0] sd_sec_read_data,
    output reg       sd_sec_read_data_valid,
    output reg       sd_sec_read_end,
    input            sd_sec_write,
    input [31:0]     sd_sec_write_addr,
    input [7:0]      sd_sec_write_data,
    output           sd_sec_write_data_req,
    output           sd_sec_write_end
);
assign SD_nCS=1; assign SD_DCLK=0; assign SD_MOSI=0;
assign sd_sec_write_data_req=0; assign sd_sec_write_end=0;

// 小图参数：32x24, 24bit → file_len = 32*24*3+54 = 2358, 5 扇区
// 4 张图 header 分别在扇区 0,5,10,15
localparam [31:0] FILE_LEN = 2358;

function is_header_sector;
    input [31:0] a;
    is_header_sector = (a==32'd0)||(a==32'd5)||(a==32'd10)||(a==32'd15);
endfunction

function [7:0] header_byte;
    input [8:0] off;
    begin
        case (off)
            9'd0:  header_byte = "B";
            9'd1:  header_byte = "M";
            9'd2:  header_byte = 8'h36;   // file_len 2358 = 0x936
            9'd3:  header_byte = 8'h09;
            9'd4:  header_byte = 8'h00;
            9'd5:  header_byte = 8'h00;
            9'd10: header_byte = 8'h36;   // pixel offset 54
            9'd18: header_byte = 8'h20;   // width 32
            9'd22: header_byte = 8'h18;   // height 24
            9'd28: header_byte = 8'h18;   // 24 bpp
            9'd30: header_byte = 8'h00;   // compression 0
            default: header_byte = 8'h00;
        endcase
    end
endfunction

localparam M_INIT=0, M_IDLE=1, M_DLY=2, M_DATA=3, M_END=4;
reg [2:0] mst;
reg [9:0] bcnt;
reg [15:0] init_cnt;

always @(posedge clk or posedge rst) begin
    if (rst) begin
        mst <= M_INIT; init_cnt<=0;
        sd_init_done<=0;
        sd_sec_read_data<=0; sd_sec_read_data_valid<=0; sd_sec_read_end<=0;
        bcnt<=0;
    end else begin
        case (mst)
        M_INIT: begin
            init_cnt <= init_cnt+1;
            if (init_cnt>=16'd100) begin
                sd_init_done<=1; mst<=M_IDLE;
            end
        end
        M_IDLE: begin
            sd_sec_read_data_valid<=0; sd_sec_read_end<=0;
            if (sd_sec_read) mst<=M_DLY;
        end
        M_DLY: begin
            // 模拟命令开销
            sd_sec_read_data_valid<=0;
            mst<=M_DATA; bcnt<=0;
        end
        M_DATA: begin
            sd_sec_read_data_valid<=1;
            if (is_header_sector(sd_sec_read_addr))
                sd_sec_read_data<=header_byte(bcnt[8:0]);
            else
                sd_sec_read_data<=bcnt[7:0];
            if (bcnt>=10'd511) begin
                sd_sec_read_data_valid<=0;
                mst<=M_END;
            end else
                bcnt<=bcnt+1;
        end
        M_END: begin
            sd_sec_read_end<=1;
            if (!sd_sec_read) begin
                sd_sec_read_end<=0;
                mst<=M_IDLE;
            end
        end
        endcase
    end
end
endmodule

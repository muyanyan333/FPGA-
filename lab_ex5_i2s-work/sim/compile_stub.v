// ============================================================
// 仅用于 iverilog 纯语法检查的临时 stub（不参与综合/打包）
// 覆盖：加密 IP、TD 原语、缺失的 test 顶层依赖
// ============================================================
`timescale 1ns/1ps

// ---- 加密：HDMI 1.4b 发射核 ----
module hdmi_1_4b_transmitter_core_wrapper #(
    parameter DEVICE            = "EG",
    parameter HTOTAL            = 800,
    parameter HSA               = 96,
    parameter HFP               = 16,
    parameter HBP               = 48,
    parameter HACTIVE           = 640,
    parameter VTOTAL            = 525,
    parameter VSA               = 2,
    parameter VFP               = 10,
    parameter VBP               = 33,
    parameter VACTIVE           = 480,
    parameter VIDEO_VIC         = 1,
    parameter VIDEO_TPG         = "Disable",
    parameter VIDEO_FORMAT      = "RGB",
    parameter AUDIO_SAMPLE_RATE = "48K",
    parameter IIC_SCL_DIV       = 250
)(
    input         I_pixel_clk,
    input         I_rst,
    input         I_edid_read_trig,
    output        O_edid_read_valid,
    output [7:0]  O_edid_read_data,
    input         I_axis_s_user,
    input         I_axis_s_valid,
    input         I_axis_s_last,
    input  [23:0] I_axis_s_data,
    output        O_axis_s_ready,
    input         I_audio_valid,
    input  [23:0] I_audio_left_data,
    input  [23:0] I_audio_right_data,
    input         I_acr_valid,
    input  [19:0] I_acr_cts,
    input  [19:0] I_acr_n,
    output        O_video_locked,
    output        O_ddc_scl,
    inout         IO_ddc_sda,
    output [9:0]  O_ch0_tmds_data,
    output [9:0]  O_ch1_tmds_data,
    output [9:0]  O_ch2_tmds_data,
    output [9:0]  O_clk_tmds_data
);
endmodule

// ---- 加密：SDRAM 控制器 ----
module sdr_as_ram #(
    parameter self_refresh_open = 1'b0
)(
    input         Sdr_clk,
    input         Sdr_clk_sft,
    input         Rst,
    output        Sdr_init_done,
    output        Sdr_init_ref_vld,
    output        Sdr_busy,
    input         App_ref_req,
    input         App_wr_en,
    input  [21:0] App_wr_addr,
    input  [3:0]  App_wr_dm,
    input  [31:0] App_wr_din,
    input         App_rd_en,
    input  [21:0] App_rd_addr,
    input         Sdr_rd_en,
    output [31:0] Sdr_rd_dout,
    output        SDRAM_CLK,
    output        SDR_RAS,
    output        SDR_CAS,
    output        SDR_WE,
    output [1:0]  SDR_BA,
    output [11:0] SDR_ADDR,
    output [3:0]  SDR_DM,
    inout  [31:0] SDR_DQ
);
endmodule

// ---- TD 原语：片内 SDRAM ----
module EG_PHY_SDRAM_2M_32(
    input         clk,
    input         ras_n,
    input         cas_n,
    input         we_n,
    input  [10:0] addr,
    input  [1:0]  ba,
    inout  [31:0] dq,
    input         cs_n,
    input         dm0,
    input         dm1,
    input         dm2,
    input         dm3,
    input         cke
);
endmodule

// ---- 顶层直接实例化的 TD IP / 原语 stub（为绕开失效 include 与 TD 专有原语）----
module sys_pll (
  input  refclk,
  input  reset,
  output clk0_out,
  output clk1_out,
  output clk2_out
);
endmodule

module video_pll (
  input  refclk,
  input  reset,
  output clk0_out,
  output clk1_out
);
endmodule

module PLL_HDMI_AUDIO (
  input  refclk,
  input  reset,
  output extlock,
  output clk0_out,
  output clk1_out,
  output clk2_out
);
endmodule

module sdram (
  input         Clk,
  input         Clk_sft,
  input         Rst,
  output        Sdr_init_done,
  output        Sdr_init_ref_vld,
  output        Sdr_busy,
  input         App_wr_en,
  input  [21:0] App_wr_addr,
  input  [3:0]  App_wr_dm,
  input  [31:0] App_wr_din,
  input         App_rd_en,
  input  [21:0] App_rd_addr,
  output        Sdr_rd_en,
  output [31:0] Sdr_rd_dout
);
endmodule

module EG_LOGIC_ODDR (
  input      clk,
  input      rst,
  input      d1,
  input      d0,
  output     q
);
endmodule

`timescale 1ns/1ps
// OV2640 VGA RGB565 output. Use the sensor's SVGA timing (up to 30 fps)
// and scale to VGA in the DSP; the original UXGA sensor timing is 15 fps.
// Base register sequence: STMicroelectronics stm32-ov2640/ov2640.c;
// SVGA sensor/DSP settings: Espressif esp32-camera ov2640_settings.h.
// ATK-OV2640 has its own oscillator; no XCLK pin is required.
module ov2640_sccb_init #(
    parameter CLK_HZ = 50000000,
    parameter TICK_DIV = 250
)(
    input wire clk,
    input wire rst,
    output reg scl,
    inout wire sda,
    output reg reset_n,
    output wire pwdn,
    output reg done,
    output reg error,
    input wire freeze_request,
    output reg freeze_applied
);
  assign pwdn = 1'b0;
  reg sda_low;
  assign sda = sda_low ? 1'b0 : 1'bz;
  localparam [3:0] RESET_WAIT=0, START_A=1, START_B=2,
                   BIT_LOW=3, BIT_HIGH=4, BIT_FALL=5,
                   ACK_LOW=6, ACK_HIGH=7, ACK_FALL=8,
                   STOP_A=9, STOP_B=10, STOP_C=11,
                   FINISH=12, PAUSE=14, RELEASE_WAIT=15;
  reg [3:0] state;
  reg [31:0] reset_count;
  reg [15:0] tick_count;
  reg [7:0] entry;
  reg [7:0] shift;
  reg [2:0] bit_no;
  reg [1:0] byte_no;
  reg [15:0] reg_pair;
  (* async_reg="true" *) reg [1:0] freeze_sync;
  reg command_freeze;
  always @(posedge clk or posedge rst) begin
    if(rst) freeze_sync<=0;
    else freeze_sync<={freeze_sync[0],freeze_request};
  end
  always @* begin
    case (entry)
      8'd0: reg_pair = 16'hff01;
      8'd1: reg_pair = 16'h1280;
      8'd2: reg_pair = 16'hff00;
      8'd3: reg_pair = 16'h2cff;
      8'd4: reg_pair = 16'h2edf;
      8'd5: reg_pair = 16'hff01;
      8'd6: reg_pair = 16'h3c32;
      8'd7: reg_pair = 16'h1100;
      8'd8: reg_pair = 16'h0902;
      8'd9: reg_pair = 16'h04a8;
      8'd10: reg_pair = 16'h13e5;
      8'd11: reg_pair = 16'h1448;
      8'd12: reg_pair = 16'h2c0c;
      8'd13: reg_pair = 16'h3378;
      8'd14: reg_pair = 16'h3a33;
      8'd15: reg_pair = 16'h3bfb;
      8'd16: reg_pair = 16'h3e00;
      8'd17: reg_pair = 16'h4311;
      8'd18: reg_pair = 16'h1610;
      8'd19: reg_pair = 16'h4a81;
      8'd20: reg_pair = 16'h2199;
      8'd21: reg_pair = 16'h2440;
      8'd22: reg_pair = 16'h2538;
      8'd23: reg_pair = 16'h2682;
      8'd24: reg_pair = 16'h5c00;
      8'd25: reg_pair = 16'h6300;
      8'd26: reg_pair = 16'h463f;
      8'd27: reg_pair = 16'h0c3c;
      8'd28: reg_pair = 16'h6170;
      8'd29: reg_pair = 16'h6280;
      8'd30: reg_pair = 16'h7c05;
      8'd31: reg_pair = 16'h2080;
      8'd32: reg_pair = 16'h2830;
      8'd33: reg_pair = 16'h6c00;
      8'd34: reg_pair = 16'h6d80;
      8'd35: reg_pair = 16'h6e00;
      8'd36: reg_pair = 16'h7002;
      8'd37: reg_pair = 16'h7194;
      8'd38: reg_pair = 16'h73c1;
      8'd39: reg_pair = 16'h3d38;
      8'd40: reg_pair = 16'h5a57;
      8'd41: reg_pair = 16'h1240;
      8'd42: reg_pair = 16'h1100;
      8'd43: reg_pair = 16'h1711;
      8'd44: reg_pair = 16'h1843;
      8'd45: reg_pair = 16'h1900;
      8'd46: reg_pair = 16'h1a4b;
      8'd47: reg_pair = 16'h3209;
      8'd48: reg_pair = 16'h030a;
      8'd49: reg_pair = 16'h37c0;
      8'd50: reg_pair = 16'h4fca;
      8'd51: reg_pair = 16'h50a8;
      8'd52: reg_pair = 16'h5a23;
      8'd53: reg_pair = 16'h6d00;
      8'd54: reg_pair = 16'h4203;
      8'd55: reg_pair = 16'h3992;
      8'd56: reg_pair = 16'h35da;
      8'd57: reg_pair = 16'h221a;
      8'd58: reg_pair = 16'h37c3;
      8'd59: reg_pair = 16'h2300;
      8'd60: reg_pair = 16'h34c0;
      8'd61: reg_pair = 16'h361a;
      8'd62: reg_pair = 16'h0688;
      8'd63: reg_pair = 16'h07c0;
      8'd64: reg_pair = 16'h0d87;
      8'd65: reg_pair = 16'h0e41;
      8'd66: reg_pair = 16'h4c00;
      8'd67: reg_pair = 16'hff00;
      8'd68: reg_pair = 16'he57f;
      8'd69: reg_pair = 16'hf9c0;
      8'd70: reg_pair = 16'h4124;
      8'd71: reg_pair = 16'he014;
      8'd72: reg_pair = 16'h76ff;
      8'd73: reg_pair = 16'h33a0;
      8'd74: reg_pair = 16'h4220;
      8'd75: reg_pair = 16'h4318;
      8'd76: reg_pair = 16'h4c00;
      8'd77: reg_pair = 16'h87d0;
      8'd78: reg_pair = 16'h883f;
      8'd79: reg_pair = 16'hd703;
      8'd80: reg_pair = 16'hd910;
      8'd81: reg_pair = 16'hd382;
      8'd82: reg_pair = 16'hc808;
      8'd83: reg_pair = 16'hc980;
      8'd84: reg_pair = 16'h7d00;
      8'd85: reg_pair = 16'h7c03;
      8'd86: reg_pair = 16'h7d48;
      8'd87: reg_pair = 16'h7c08;
      8'd88: reg_pair = 16'h7d20;
      8'd89: reg_pair = 16'h7d10;
      8'd90: reg_pair = 16'h7d0e;
      8'd91: reg_pair = 16'h9000;
      8'd92: reg_pair = 16'h910e;
      8'd93: reg_pair = 16'h911a;
      8'd94: reg_pair = 16'h9131;
      8'd95: reg_pair = 16'h915a;
      8'd96: reg_pair = 16'h9169;
      8'd97: reg_pair = 16'h9175;
      8'd98: reg_pair = 16'h917e;
      8'd99: reg_pair = 16'h9188;
      8'd100: reg_pair = 16'h918f;
      8'd101: reg_pair = 16'h9196;
      8'd102: reg_pair = 16'h91a3;
      8'd103: reg_pair = 16'h91af;
      8'd104: reg_pair = 16'h91c4;
      8'd105: reg_pair = 16'h91d7;
      8'd106: reg_pair = 16'h91e8;
      8'd107: reg_pair = 16'h9120;
      8'd108: reg_pair = 16'h9200;
      8'd109: reg_pair = 16'h9306;
      8'd110: reg_pair = 16'h93e3;
      8'd111: reg_pair = 16'h9302;
      8'd112: reg_pair = 16'h9302;
      8'd113: reg_pair = 16'h9300;
      8'd114: reg_pair = 16'h9304;
      8'd115: reg_pair = 16'h9300;
      8'd116: reg_pair = 16'h9303;
      8'd117: reg_pair = 16'h9300;
      8'd118: reg_pair = 16'h9300;
      8'd119: reg_pair = 16'h9300;
      8'd120: reg_pair = 16'h9300;
      8'd121: reg_pair = 16'h9300;
      8'd122: reg_pair = 16'h9300;
      8'd123: reg_pair = 16'h9300;
      8'd124: reg_pair = 16'h9600;
      8'd125: reg_pair = 16'h9708;
      8'd126: reg_pair = 16'h9719;
      8'd127: reg_pair = 16'h9702;
      8'd128: reg_pair = 16'h970c;
      8'd129: reg_pair = 16'h9724;
      8'd130: reg_pair = 16'h9730;
      8'd131: reg_pair = 16'h9728;
      8'd132: reg_pair = 16'h9726;
      8'd133: reg_pair = 16'h9702;
      8'd134: reg_pair = 16'h9798;
      8'd135: reg_pair = 16'h9780;
      8'd136: reg_pair = 16'h9700;
      8'd137: reg_pair = 16'h9700;
      8'd138: reg_pair = 16'hc3ef;
      8'd139: reg_pair = 16'hff00;
      8'd140: reg_pair = 16'hbadc;
      8'd141: reg_pair = 16'hbb08;
      8'd142: reg_pair = 16'hb624;
      8'd143: reg_pair = 16'hb833;
      8'd144: reg_pair = 16'hb720;
      8'd145: reg_pair = 16'hb930;
      8'd146: reg_pair = 16'hb3b4;
      8'd147: reg_pair = 16'hb4ca;
      8'd148: reg_pair = 16'hb543;
      8'd149: reg_pair = 16'hb05c;
      8'd150: reg_pair = 16'hb14f;
      8'd151: reg_pair = 16'hb206;
      8'd152: reg_pair = 16'hc700;
      8'd153: reg_pair = 16'hc651;
      8'd154: reg_pair = 16'hc511;
      8'd155: reg_pair = 16'hc49c;
      8'd156: reg_pair = 16'hbf00;
      8'd157: reg_pair = 16'hbc64;
      8'd158: reg_pair = 16'ha600;
      8'd159: reg_pair = 16'ha71e;
      8'd160: reg_pair = 16'ha76b;
      8'd161: reg_pair = 16'ha747;
      8'd162: reg_pair = 16'ha733;
      8'd163: reg_pair = 16'ha700;
      8'd164: reg_pair = 16'ha723;
      8'd165: reg_pair = 16'ha72e;
      8'd166: reg_pair = 16'ha785;
      8'd167: reg_pair = 16'ha742;
      8'd168: reg_pair = 16'ha733;
      8'd169: reg_pair = 16'ha700;
      8'd170: reg_pair = 16'ha723;
      8'd171: reg_pair = 16'ha71b;
      8'd172: reg_pair = 16'ha774;
      8'd173: reg_pair = 16'ha742;
      8'd174: reg_pair = 16'ha733;
      8'd175: reg_pair = 16'ha700;
      8'd176: reg_pair = 16'ha723;
      8'd177: reg_pair = 16'hc0c8;
      8'd178: reg_pair = 16'hc196;
      8'd179: reg_pair = 16'h8c00;
      8'd180: reg_pair = 16'h863d;
      8'd181: reg_pair = 16'h5092;
      8'd182: reg_pair = 16'h5190;
      8'd183: reg_pair = 16'h522c;
      8'd184: reg_pair = 16'h5300;
      8'd185: reg_pair = 16'h5400;
      8'd186: reg_pair = 16'h5588;
      8'd187: reg_pair = 16'h5a50;
      8'd188: reg_pair = 16'h5b3c;
      8'd189: reg_pair = 16'h5c00;
      8'd190: reg_pair = 16'hd304;
      8'd191: reg_pair = 16'h7f00;
      8'd192: reg_pair = 16'hda00;
      8'd193: reg_pair = 16'he51f;
      8'd194: reg_pair = 16'he167;
      8'd195: reg_pair = 16'he000;
      8'd196: reg_pair = 16'hdd7f;
      8'd197: reg_pair = 16'h0500;
      8'd198: reg_pair = 16'hff00;
      8'd199: reg_pair = 16'he004;
      8'd200: reg_pair = 16'hc064;
      8'd201: reg_pair = 16'hc14b;
      8'd202: reg_pair = 16'h863d;
      8'd203: reg_pair = 16'h5080;
      8'd204: reg_pair = 16'h51c8;
      8'd205: reg_pair = 16'h5296;
      8'd206: reg_pair = 16'h5300;
      8'd207: reg_pair = 16'h5400;
      8'd208: reg_pair = 16'h5500;
      8'd209: reg_pair = 16'h5700;
      8'd210: reg_pair = 16'h5a50;
      8'd211: reg_pair = 16'h5b3c;
      8'd212: reg_pair = 16'h5c00;
      8'd213: reg_pair = 16'hd304;
      8'd214: reg_pair = 16'he000;
      8'd215: reg_pair = 16'hff00;
      8'd216: reg_pair = 16'h0500;
      8'd217: reg_pair = 16'hda08;
      8'd218: reg_pair = 16'hda09;
      8'd219: reg_pair = 16'h9800;
      8'd220: reg_pair = 16'h9900;
      8'd221: reg_pair = 16'h0000;
      8'd222: reg_pair = 16'hff00;
      8'd223: reg_pair = 16'he004;
      8'd224: reg_pair = 16'hc064;
      8'd225: reg_pair = 16'hc14b;
      8'd226: reg_pair = 16'h863d;
      8'd227: reg_pair = 16'h5080;
      8'd228: reg_pair = 16'h51c8;
      8'd229: reg_pair = 16'h5296;
      8'd230: reg_pair = 16'h5300;
      8'd231: reg_pair = 16'h5400;
      8'd232: reg_pair = 16'h5500;
      8'd233: reg_pair = 16'h5700;
      8'd234: reg_pair = 16'h5aa0;
      8'd235: reg_pair = 16'h5b78;
      8'd236: reg_pair = 16'h5c00;
      8'd237: reg_pair = 16'hd302;
      8'd238: reg_pair = 16'he000;
      // Runtime exposure/gain/white-balance lock. Keep all other configured bits.
      8'd239: reg_pair = 16'hff01;
      8'd240: reg_pair = command_freeze ? 16'h13e0 : 16'h13e5;
      8'd241: reg_pair = 16'hff00;
      8'd242: reg_pair = command_freeze ? 16'hc3e7 : 16'hc3ef;
      default: reg_pair = 16'hffff;
    endcase
  end
  wire tick = tick_count == TICK_DIV-1;
  always @(posedge clk or posedge rst) begin
    if (rst) begin
      state <= RESET_WAIT; reset_count <= 0; tick_count <= 0;
      entry <= 0; shift <= 0; bit_no <= 7; byte_no <= 0;
      scl <= 1; sda_low <= 0;
      reset_n <= 0; done <= 0; error <= 0;
      freeze_applied<=0;command_freeze<=0;
    end else if (state == RESET_WAIT) begin
      if (reset_count == CLK_HZ/100) begin
        reset_n <= 1;
        // Let the sensor's oscillator and SCCB interface settle after reset.
        reset_count <= 0;
        state <= RELEASE_WAIT;
        tick_count <= 0;
      end else reset_count <= reset_count + 1'b1;
    end else if (state == RELEASE_WAIT) begin
      if (reset_count == CLK_HZ/100) begin
        state <= START_A;
        tick_count <= 0;
      end else reset_count <= reset_count + 1'b1;
    end else if (tick) begin
      tick_count <= 0;
      case (state)
        START_A: begin scl <= 1; sda_low <= 0; state <= START_B; end
        START_B: begin sda_low <= 1; shift <= 8'h60; byte_no <= 0;
                       bit_no <= 7; state <= BIT_LOW; end
        BIT_LOW: begin scl <= 0; sda_low <= ~shift[bit_no]; state <= BIT_HIGH; end
        BIT_HIGH: begin scl <= 1; state <= BIT_FALL; end
        BIT_FALL: begin scl <= 0;
          if (bit_no == 0) state <= ACK_LOW;
          else begin bit_no <= bit_no - 1'b1; state <= BIT_LOW; end
        end
        ACK_LOW: begin sda_low <= 0; state <= ACK_HIGH; end
        // SCCB write phases have a ninth Don't-Care bit, not an I2C ACK.
        // Release SDA for that bit and continue regardless of its level.
        ACK_HIGH: begin scl <= 1; state <= ACK_FALL; end
        ACK_FALL: begin scl <= 0;
          if (byte_no == 2) state <= STOP_A;
          else begin
            byte_no <= byte_no + 1'b1; bit_no <= 7;
            shift <= byte_no == 0 ? reg_pair[15:8] : reg_pair[7:0];
            state <= BIT_LOW;
          end
        end
        STOP_A: begin sda_low <= 1; state <= STOP_B; end
        STOP_B: begin scl <= 1; state <= STOP_C; end
        STOP_C: begin sda_low <= 0;
          if (entry == 8'd1) begin entry <= 8'd2; reset_count <= 0; state <= PAUSE; end
          else if (entry == 8'd238) begin done <= 1; state <= FINISH; end
          else if (entry == 8'd242) begin freeze_applied<=command_freeze;state<=FINISH;end
          else begin entry <= entry + 1'b1; state <= START_A; end
        end
        PAUSE: begin
          if (reset_count == CLK_HZ/(5*TICK_DIV)) state <= START_A;
          else reset_count <= reset_count + 1'b1;
        end
        FINISH: begin
          if(freeze_sync[1]!=freeze_applied) begin
            command_freeze<=freeze_sync[1];entry<=239;state<=START_A;
          end
        end
        default: state <= state;
      endcase
    end else tick_count <= tick_count + 1'b1;
  end
endmodule

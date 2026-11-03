// OV2640 RGB565 DVP, 640x480. A complete frame is written to the SDRAM
// buffer not currently selected for HDMI. Incomplete frames are discarded.
module ov2640_dvp_capture #(
    parameter FRAME_PIXELS = 307200
)(
    input wire pclk,
    input wire rst,
    input wire init_done,
    input wire vsync,
    input wire href,
    input wire [7:0] data,
    input wire write_ack,
    input wire write_finish_toggle,
    input wire write_full,
    output reg write_req,
    output reg write_en,
    output reg [31:0] write_data,
    output reg write_bank,
    output reg display_bank,
    output reg display_valid,
    output reg frame_error,
    output reg debug_ack_seen,
    output reg debug_href_seen,
    output reg debug_fifo_overflow,
    output reg debug_short_frame,
    output reg debug_pixels_complete,
    output reg debug_finish_seen
);
  localparam WAIT_INIT=0, WAIT_ACK=1, WAIT_NEXT=2,
             CAPTURE=3, WAIT_FINISH=4, PAD=5;
  reg [2:0] state;
  reg [1:0] ack_sync, finish_sync, full_sync;
  reg finish_seen;
  reg [1:0] init_sync;
  reg vsync_d;
  reg first_byte;
  reg [7:0] low_byte;
  reg [18:0] pixel_count;
  reg [18:0] accepted_count;
  wire frame_start = vsync && !vsync_d;
  wire finish_event = finish_sync[1] != finish_seen;
  always @(posedge pclk or posedge rst) begin
    if (rst) begin
      state <= WAIT_INIT;
      ack_sync <= 0; finish_sync <= 0; full_sync <= 0; init_sync <= 0;
      finish_seen <= 0;
      vsync_d <= 0; first_byte <= 1;
      low_byte <= 0; pixel_count <= 0; accepted_count <= 0;
      write_req <= 0; write_en <= 0; write_data <= 0;
      write_bank <= 0; display_bank <= 0;
      display_valid <= 0; frame_error <= 0;
      debug_ack_seen <= 0; debug_href_seen <= 0;
      debug_fifo_overflow <= 0; debug_short_frame <= 0;
      debug_pixels_complete <= 0; debug_finish_seen <= 0;
    end else begin
      ack_sync <= {ack_sync[0],write_ack};
      finish_sync <= {finish_sync[0],write_finish_toggle};
      full_sync <= {full_sync[0],write_full};
      init_sync <= {init_sync[0],init_done};
      vsync_d <= vsync;
      // HREF is the sensor's active-data indication. Count it independently
      // of the capture state so diagnostics do not confuse a missing frame
      // boundary with a missing HREF signal.
      if (href) debug_href_seen <= 1;
      write_en <= 0;
      case (state)
        // Arm SDRAM as soon as the camera is configured. Waiting for a
        // VSYNC here would skip a whole source frame on every cycle.
        WAIT_INIT: if (init_sync[1]) begin
          write_req <= 1; state <= WAIT_ACK;
        end
        WAIT_ACK: if (ack_sync[1]) begin
          write_req <= 0; state <= WAIT_NEXT; debug_ack_seen <= 1;
        end
        WAIT_NEXT: if (frame_start) begin
          pixel_count <= 0; accepted_count <= 0; first_byte <= 1;
          frame_error <= 0; state <= CAPTURE;
        end
        CAPTURE: begin
          if (frame_start && pixel_count != FRAME_PIXELS) begin
            frame_error <= 1; debug_short_frame <= 1; state <= PAD;
          end else if (href) begin
            if (first_byte) begin
              low_byte <= data; first_byte <= 0;
            end else begin
              first_byte <= 1;
              if (full_sync[1]) begin
                frame_error <= 1;
                debug_fifo_overflow <= 1;
              end
              else begin
                write_en <= 1;
                accepted_count <= accepted_count + 1'b1;
                write_data <= {
                  data[7:3],data[7:5],
                  data[2:0],low_byte[7:5],data[2:1],
                  low_byte[4:0],low_byte[4:2],8'h00
                };
              end
              if (pixel_count == FRAME_PIXELS-1) begin
                debug_pixels_complete <= 1;
                state <= (accepted_count == FRAME_PIXELS-1 && !full_sync[1]) ? WAIT_FINISH : PAD;
              end
              pixel_count <= pixel_count + 1'b1;
            end
          end else if (!href) first_byte <= 1;
        end
        PAD: if (!full_sync[1]) begin
          write_en <= 1;
          write_data <= 32'd0;
          accepted_count <= accepted_count + 1'b1;
          if (accepted_count == FRAME_PIXELS-1) state <= WAIT_FINISH;
        end
        WAIT_FINISH: if (finish_event) begin
          debug_finish_seen <= 1;
          finish_seen <= finish_sync[1];
          if (!frame_error && pixel_count == FRAME_PIXELS) begin
            display_bank <= write_bank;
            display_valid <= 1;
            write_bank <= ~write_bank;
          end
          // The just-completed bank is no longer being written; prepare the
          // opposite bank now so the next VSYNC can start capture directly.
          write_req <= 1;
          state <= WAIT_ACK;
        end
        default: state <= WAIT_INIT;
      endcase
    end
  end
endmodule

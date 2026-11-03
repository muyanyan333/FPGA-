// Resize a bottom-up 24-bit BMP into a bottom-up 640x480 frame.
// Aspect ratio is retained with black bars. Horizontal and vertical sampling
// use integer accumulators, so no per-pixel divider or multiplier is needed.
module bmp_fit_scaler #(
    parameter USE_VIEWPORT = 0,
    parameter USE_ASPECT = 0
)(
    input  wire        clk,
    input  wire        rst,
    input  wire        start,
    input  wire        go,
    input  wire [15:0] src_width,
    input  wire [15:0] src_height,
    input  wire [1:0]  viewport_mode, // 0=640x480, 1=512x384, 2=320x240
    input  wire [1:0]  aspect_mode,   // 0=original fit, 1=4:3, 2=16:9, 3=1:1
    input  wire        pixel_valid,
    input  wire [23:0] pixel_data,
    input  wire        write_full,
    output reg         ready_for_pixels,
    output wire        write_en,
    output wire [23:0] write_data,
    output reg         done,
    output reg         overflow
);
    localparam [2:0] ST_IDLE   = 3'd0;
    localparam [2:0] ST_DIV    = 3'd1;
    localparam [2:0] ST_WAIT   = 3'd2;
    localparam [2:0] ST_TOP    = 3'd3;
    localparam [2:0] ST_INPUT  = 3'd4;
    localparam [2:0] ST_BOTTOM = 3'd5;
    localparam [2:0] ST_DONE   = 3'd6;
    localparam [1:0] OUT_WAIT = 2'd0;
    localparam [1:0] OUT_READ = 2'd1;
    localparam [1:0] OUT_EMIT = 2'd2;

    reg [2:0] state;
    reg [1:0] out_state;
    // `go` may arrive while the aspect-ratio divider is still running.
    // Remember it until ST_WAIT instead of losing the one-cycle pulse.
    reg go_pending;
    reg [15:0] src_w, src_h;
    reg [9:0] fit_w, fit_h, pad_x, pad_y;
    reg [9:0] view_w, view_h;
    wire [1:0] selected_view = USE_VIEWPORT ? viewport_mode : 2'd0;
    wire [1:0] selected_aspect = USE_ASPECT ? aspect_mode : 2'd0;
    wire [9:0] base_w = (selected_view == 2'd1) ? 10'd512 :
                          (selected_view == 2'd2) ? 10'd320 : 10'd640;
    wire [9:0] base_h = (selected_view == 2'd1) ? 10'd384 :
                          (selected_view == 2'd2) ? 10'd240 : 10'd480;
    wire [9:0] request_w = (selected_aspect == 2'd3) ? base_h : base_w;
    wire [9:0] request_h = (selected_aspect == 2'd2) ?
                          ((selected_view == 2'd1) ? 10'd288 :
                           (selected_view == 2'd2) ? 10'd180 : 10'd360) : base_h;
    reg [20:0] div_rem;
    reg [15:0] div_den;
    reg [9:0] div_quot;
    reg wide_image;

    reg [10:0] in_x, in_y;
    reg [9:0] scaled_x;
    reg [11:0] h_acc, v_acc;
    reg capture_bank, row_end_pending, dup_pending;
    reg [10:0] dup_addr;
    reg [23:0] dup_data;
    reg [23:0] previous_pixel;
    reg row_seq, row_bank;
    reg [1:0] row_repeats;
    reg source_complete;

    reg seen_seq, display_bank;
    reg [1:0] rows_left;
    reg [9:0] out_x, out_y;

    // Only the current and previous lines are needed. No reset is required
    // because a line is read only after its selected pixels are written.
    reg [23:0] line_mem [0:2047];
    reg [23:0] line_read_data;
    wire [20:0] width_480 = ({5'd0,src_width} << 8) +
                              ({5'd0,src_width} << 7) +
                              ({5'd0,src_width} << 6) +
                              ({5'd0,src_width} << 5);
    wire [20:0] height_640 = ({5'd0,src_height} << 9) +
                               ({5'd0,src_height} << 7);
    // Constant shift/add products implement all viewport sizes without using
    // a variable multiplier. Compare against the selected viewport aspect.
    wire [20:0] width_base_h = (selected_view == 2'd1) ?
        (({5'd0,src_width} << 8) + ({5'd0,src_width} << 7)) :
        (selected_view == 2'd2) ? (width_480 >> 1) : width_480;
    wire [20:0] height_base_w = (selected_view == 2'd1) ?
        ({5'd0,src_height} << 9) :
        (selected_view == 2'd2) ? (height_640 >> 1) : height_640;
    wire [20:0] width_360 = ({5'd0,src_width} << 8) +
                              ({5'd0,src_width} << 6) +
                              ({5'd0,src_width} << 5) +
                              ({5'd0,src_width} << 3);
    wire [20:0] width_wide_h = (selected_view == 2'd1) ?
        (({5'd0,src_width} << 8) + ({5'd0,src_width} << 5)) :
        (selected_view == 2'd2) ? (width_360 >> 1) : width_360;
    wire [20:0] height_480 = ({5'd0,src_height} << 8) +
                               ({5'd0,src_height} << 7) +
                               ({5'd0,src_height} << 6) +
                               ({5'd0,src_height} << 5);
    wire [20:0] height_square_w = (selected_view == 2'd1) ?
        (({5'd0,src_height} << 8) + ({5'd0,src_height} << 7)) :
        (selected_view == 2'd2) ? (height_480 >> 1) : height_480;
    wire [20:0] width_view_h = (selected_aspect == 2'd2) ? width_wide_h : width_base_h;
    wire [20:0] height_view_w = (selected_aspect == 2'd3) ? height_square_w : height_base_w;
    wire [11:0] h_sum = h_acc + {2'd0,fit_w};
    wire [11:0] v_sum = v_acc + {2'd0,fit_h};
    wire filter_down = (src_w >= ({6'd0,fit_w} << 1)) && (in_x != 11'd0);
    wire [8:0] mean_r = {1'b0,previous_pixel[23:16]} + {1'b0,pixel_data[23:16]};
    wire [8:0] mean_g = {1'b0,previous_pixel[15:8]} + {1'b0,pixel_data[15:8]};
    wire [8:0] mean_b = {1'b0,previous_pixel[7:0]} + {1'b0,pixel_data[7:0]};
    wire [23:0] selected_pixel = filter_down ?
        {mean_r[8:1],mean_g[8:1],mean_b[8:1]} : pixel_data;
    wire h_one = h_sum >= {1'b0,src_w};
    wire h_two = h_sum >= ({1'b0,src_w} << 1);
    wire [1:0] repeats = (v_sum >= ({1'b0,src_h} << 1)) ? 2'd2 :
                         (v_sum >= {1'b0,src_h}) ? 2'd1 : 2'd0;
    wire first_write = (state == ST_INPUT) && pixel_valid &&
                       (in_y < src_h) && !dup_pending && h_one;
    wire [10:0] first_addr = {capture_bank,scaled_x};
    wire line_read = (state == ST_INPUT) && (out_state == OUT_READ) &&
                     (out_x >= pad_x) && (out_x < pad_x + fit_w);
    wire [10:0] read_addr = {display_bank,(out_x - pad_x)};
    wire pixel_in_range = (out_x >= pad_x) && (out_x < pad_x + fit_w);

    assign write_en = !write_full &&
                      ((state == ST_TOP) || (state == ST_BOTTOM && out_y < 10'd480) ||
                       (state == ST_INPUT && out_state == OUT_EMIT));
    assign write_data = (state == ST_INPUT && pixel_in_range) ? line_read_data : 24'd0;

    always @(posedge clk) begin
        if (dup_pending)
            line_mem[dup_addr] <= dup_data;
        else if (first_write)
            line_mem[first_addr] <= selected_pixel;
        if (line_read)
            line_read_data <= line_mem[read_addr];
    end

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            state <= ST_IDLE;
            out_state <= OUT_WAIT;
            go_pending <= 1'b0;
            src_w <= 16'd0; src_h <= 16'd0;
            fit_w <= 10'd0; fit_h <= 10'd0;
            view_w <= 10'd640; view_h <= 10'd480;
            pad_x <= 10'd0; pad_y <= 10'd0;
            div_rem <= 21'd0; div_den <= 16'd0;
            div_quot <= 10'd0; wide_image <= 1'b0;
            in_x <= 11'd0; in_y <= 11'd0; scaled_x <= 10'd0;
            h_acc <= 12'd0; v_acc <= 12'd0;
            capture_bank <= 1'b0; row_end_pending <= 1'b0;
            dup_pending <= 1'b0; dup_addr <= 11'd0; dup_data <= 24'd0;
            previous_pixel <= 24'd0;
            row_seq <= 1'b0; row_bank <= 1'b0; row_repeats <= 2'd0;
            source_complete <= 1'b0; seen_seq <= 1'b0;
            display_bank <= 1'b0; rows_left <= 2'd0;
            out_x <= 10'd0; out_y <= 10'd0;
            ready_for_pixels <= 1'b0; done <= 1'b0; overflow <= 1'b0;
        end else if (start) begin
            state <= ST_DIV;
            out_state <= OUT_WAIT;
            // Also covers the (legal) case where start and go coincide.
            go_pending <= go;
            src_w <= src_width; src_h <= src_height;
            view_w <= request_w; view_h <= request_h;
            wide_image <= width_view_h >= height_view_w;
            div_rem <= (width_view_h >= height_view_w) ? height_view_w : width_view_h;
            div_den <= (width_view_h >= height_view_w) ? src_width : src_height;
            div_quot <= 10'd0;
            in_x <= 11'd0; in_y <= 11'd0; scaled_x <= 10'd0;
            h_acc <= 12'd0; v_acc <= 12'd0;
            capture_bank <= 1'b0; row_end_pending <= 1'b0;
            dup_pending <= 1'b0; row_seq <= 1'b0;
            previous_pixel <= 24'd0;
            source_complete <= 1'b0; seen_seq <= 1'b0;
            rows_left <= 2'd0; out_x <= 10'd0; out_y <= 10'd0;
            ready_for_pixels <= 1'b0; done <= 1'b0; overflow <= 1'b0;
        end else begin
            if (go)
                go_pending <= 1'b1;
            case (state)
                ST_DIV: begin
                    if (div_den == 16'd0) begin
                        overflow <= 1'b1;
                        state <= ST_DONE;
                    end else if (div_rem >= {5'd0,div_den}) begin
                        div_rem <= div_rem - {5'd0,div_den};
                        div_quot <= div_quot + 10'd1;
                    end else begin
                        if (wide_image) begin
                            fit_w <= view_w;
                            fit_h <= div_quot;
                            pad_x <= (10'd640 - view_w) >> 1;
                            pad_y <= (10'd480 - div_quot) >> 1;
                        end else begin
                            fit_w <= div_quot;
                            fit_h <= view_h;
                            pad_x <= (10'd640 - div_quot) >> 1;
                            pad_y <= (10'd480 - view_h) >> 1;
                        end
                        state <= ST_WAIT;
                    end
                end
                ST_WAIT: if (go || go_pending) begin
                    go_pending <= 1'b0;
                    if (pad_y == 10'd0) begin
                        state <= ST_INPUT;
                        ready_for_pixels <= 1'b1;
                    end else state <= ST_TOP;
                end
                ST_TOP: if (write_en) begin
                    if (out_x == 10'd639) begin
                        out_x <= 10'd0;
                        out_y <= out_y + 10'd1;
                        if (out_y + 10'd1 == pad_y) begin
                            state <= ST_INPUT;
                            ready_for_pixels <= 1'b1;
                        end
                    end else out_x <= out_x + 10'd1;
                end
                ST_INPUT: begin
                    // Each input pixel is selected zero, one or two times.
                    if (dup_pending) begin
                        dup_pending <= 1'b0;
                        if (pixel_valid) overflow <= 1'b1;
                    end else if (row_end_pending) begin
                        row_end_pending <= 1'b0;
                        scaled_x <= 10'd0;
                        h_acc <= 12'd0;
                        capture_bank <= ~capture_bank;
                        in_y <= in_y + 11'd1;
                        if (repeats == 2'd2)
                            v_acc <= v_sum - ({1'b0,src_h} << 1);
                        else if (repeats == 2'd1)
                            v_acc <= v_sum - {1'b0,src_h};
                        else v_acc <= v_sum;
                        if (repeats != 2'd0) begin
                            if (row_seq != seen_seq || out_state != OUT_WAIT)
                                overflow <= 1'b1;
                            row_bank <= capture_bank;
                            row_repeats <= repeats;
                            row_seq <= ~row_seq;
                        end
                        if (in_y + 11'd1 == src_h)
                            source_complete <= 1'b1;
                    end else if (pixel_valid && in_y < src_h) begin
                        previous_pixel <= pixel_data;
                        if (in_x + 11'd1 == src_w) begin
                            in_x <= 11'd0;
                            row_end_pending <= 1'b1;
                        end else in_x <= in_x + 11'd1;
                        if (h_two) begin
                            h_acc <= h_sum - ({1'b0,src_w} << 1);
                            scaled_x <= scaled_x + 10'd2;
                            dup_pending <= 1'b1;
                            dup_addr <= {capture_bank,(scaled_x + 10'd1)};
                            dup_data <= selected_pixel;
                        end else if (h_one) begin
                            h_acc <= h_sum - {1'b0,src_w};
                            scaled_x <= scaled_x + 10'd1;
                        end else h_acc <= h_sum;
                    end

                    case (out_state)
                        OUT_WAIT: begin
                            if (row_seq != seen_seq) begin
                                seen_seq <= row_seq;
                                display_bank <= row_bank;
                                rows_left <= row_repeats;
                                out_state <= OUT_READ;
                            end else if (source_complete) state <= ST_BOTTOM;
                        end
                        OUT_READ: out_state <= OUT_EMIT;
                        OUT_EMIT: if (write_en) begin
                            if (out_x == 10'd639) begin
                                out_x <= 10'd0;
                                out_y <= out_y + 10'd1;
                                if (rows_left == 2'd1) begin
                                    rows_left <= 2'd0;
                                    out_state <= OUT_WAIT;
                                end else begin
                                    rows_left <= rows_left - 2'd1;
                                    out_state <= OUT_READ;
                                end
                            end else begin
                                out_x <= out_x + 10'd1;
                                out_state <= OUT_READ;
                            end
                        end
                        default: out_state <= OUT_WAIT;
                    endcase
                end
                ST_BOTTOM: begin
                    if (out_y == 10'd480) begin
                        state <= ST_DONE;
                        done <= 1'b1;
                    end else if (write_en) begin
                        if (out_x == 10'd639) begin
                            out_x <= 10'd0;
                            out_y <= out_y + 10'd1;
                        end else out_x <= out_x + 10'd1;
                    end
                end
                ST_DONE: done <= 1'b1;
                default: state <= ST_IDLE;
            endcase
        end
    end
endmodule

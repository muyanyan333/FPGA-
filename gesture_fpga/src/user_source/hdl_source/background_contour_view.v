`timescale 1ns/1ps
// Fixed-camera foreground contour. 4x4 block averages reduce memory and noise.
module background_contour_view #(
    parameter WIDTH=640,HEIGHT=480,DEBOUNCE_CYCLES=500000,
    parameter LOCK_EXPOSURE=0,SETTLE_FRAMES=60,FLUSH_FRAMES=16,GESTURES=0
)(
    input wire clk,rst,key_mode_n,key_level_n,key_bg_n,
    input wire in_vs,in_de,
    input wire [23:0] in_rgb,
    output reg out_vs,out_de,
    output reg [23:0] out_rgb,
    output reg freeze_request,
    input wire freeze_applied, output wire gesture_tx, output wire [2:0] gesture_display
);
    localparam SW=WIDTH/4,SH=HEIGHT/4,CELLS=SW*SH;
    wire mode_press,level_press,bg_press;
    contour_key #(.CYCLES(DEBOUNCE_CYCLES)) km(clk,rst,key_mode_n,mode_press);
    contour_key #(.CYCLES(DEBOUNCE_CYCLES)) kl(clk,rst,key_level_n,level_press);
    contour_key #(.CYCLES(DEBOUNCE_CYCLES)) kb(clk,rst,key_bg_n,bg_press);
    reg [1:0] mode_req,level_req,mode,level;
    reg prev_vs,prev_de,armed,pending,learning,bg_valid;
    reg [10:0] x,y;
    reg sample_en;
    reg [10:0] sample_x,sample_y;
    (* async_reg="true" *) reg [1:0] locked_sync;
    reg [2:0] calibration;
    reg [7:0] wait_frames;
    always @(posedge clk or posedge rst) begin
        if(rst) locked_sync<=0;
        else locked_sync<={locked_sync[0],freeze_applied};
    end
    wire frame_begin=in_de && armed;
    always @(posedge clk or posedge rst) begin
        if(rst) begin
            mode_req<=0;level_req<=1;mode<=0;level<=1;
            prev_vs<=0;prev_de<=0;armed<=1;pending<=0;
            learning<=0;bg_valid<=0;x<=0;y<=0;
            freeze_request<=0;calibration<=0;wait_frames<=0;
        end else begin
            prev_vs<=in_vs;prev_de<=in_de;
            if(mode_press) mode_req<=mode_req+2'd1;
            if(level_press) level_req<=level_req+2'd1;
            if(bg_press) begin
                if(LOCK_EXPOSURE) begin
                    freeze_request<=0;calibration<=1;pending<=0;bg_valid<=0;
                end else pending<=1;
            end
            if(prev_vs!=in_vs) begin
                armed<=1;x<=0;y<=0;mode<=mode_req;level<=level_req;
            end else begin
                if(in_de) x<=x+1'b1;else x<=0;
                if(prev_de && !in_de) y<=y+1'b1;
            end
            if(frame_begin) begin
                if(LOCK_EXPOSURE) case(calibration)
                    1: if(!locked_sync[1]) begin calibration<=2;wait_frames<=SETTLE_FRAMES;end
                    2: if(wait_frames==0) begin freeze_request<=1;calibration<=3;end
                       else wait_frames<=wait_frames-1'b1;
                    3: if(locked_sync[1]) begin calibration<=4;wait_frames<=FLUSH_FRAMES;end
                    4: if(wait_frames==0) begin calibration<=0;pending<=1;end
                       else wait_frames<=wait_frames-1'b1;
                endcase
                armed<=0;learning<=pending;
                if(pending) begin
                    pending<=0;bg_valid<=0;mode_req<=3;mode<=3;
                end
            end
            if(sample_en && learning && sample_x==SW-1 && sample_y==SH-1)
                bg_valid<=1;
        end
    end
    wire [7:0] gray={2'd0,in_rgb[23:18]}+{1'd0,in_rgb[15:9]}+{2'd0,in_rgb[7:2]};
    reg [9:0] horizontal;
    reg [11:0] vertical[0:SW-1];
    wire [9:0] htotal=horizontal+{2'd0,gray};
    wire [12:0] total={1'b0,vertical[x>>2]}+{3'd0,htotal};
    reg [5:0] average;
    always @(posedge clk or posedge rst) begin
        if(rst) begin horizontal<=0;sample_en<=0;sample_x<=0;sample_y<=0;average<=0;end
        else begin
            sample_en<=0;
            if(in_de) begin
                horizontal<=x[1:0]==0 ? {2'd0,gray} : htotal;
                if(x[1:0]==3) begin
                    if(y[1:0]==0) vertical[x>>2]<={2'd0,htotal};
                    else vertical[x>>2]<=total[11:0];
                    if(y[1:0]==3) begin
                        sample_en<=1;sample_x<=x>>2;sample_y<=y>>2;
                        average<=total[11:6]; // average of 16 pixels, quantized to six bits
                    end
                end
            end
        end
    end
    (* ram_style="block" *) reg [5:0] background[0:CELLS-1]; /* fehdl force_ram=1, ram_style="bram" */
    reg [5:0] reference,current;
    reg diff_en;
    reg [10:0] dx,dy;
    wire [14:0] sample_addr=sample_y*SW+sample_x;
    wire [5:0] difference=current>reference ? current-reference : reference-current;
    wire [5:0] threshold=level==0 ? 6'd3 : level==1 ? 6'd6 : level==2 ? 6'd10 : 6'd16;
    always @(posedge clk) begin
        if(sample_en) begin
            reference<=background[sample_addr];current<=average;
            if(learning) background[sample_addr]<=average;
        end
    end
    always @(posedge clk or posedge rst) begin
        if(rst) begin diff_en<=0;dx<=0;dy<=0;end
        else begin
            diff_en<=sample_en && bg_valid && !learning;
            dx<=sample_x;dy<=sample_y;
        end
    end
    wire majority_en,majority,unused_center;
    wire [10:0] mx,my;
    binary_window3 #(.WIDTH(SW)) clean(
        clk,rst,diff_en,difference>=threshold,dx,dy,
        majority_en,majority,unused_center,mx,my);
    wire contour_en,contour,filled;
    wire [10:0] cx,cy;
    binary_window3 #(.WIDTH(SW),.BORDER(1)) outline(
        clk,rst,majority_en,majority,mx,my,
        contour_en,contour,filled,cx,cy);
    (* ram_style="block" *) reg [1:0] mask0[0:CELLS-1]; /* fehdl force_ram=1, ram_style="bram" */
    (* ram_style="block" *) reg [1:0] mask1[0:CELLS-1]; /* fehdl force_ram=1, ram_style="bram" */
    reg write_bank,display_bank,commit,committed_bank,mask_valid;
    wire [14:0] write_addr=cy*SW+cx;
    wire [1:0] write_mask=(cx>=4 && cy>=4) ? {filled,contour} : 2'b00;
    always @(posedge clk or posedge rst) begin
        if(rst) begin
            write_bank<=1;display_bank<=0;commit<=0;committed_bank<=0;mask_valid<=0;
        end else begin
            if(contour_en && cx==SW-1 && cy==SH-1) begin commit<=1;committed_bank<=write_bank;end
            if(frame_begin) begin
                if(commit) begin display_bank<=committed_bank;write_bank<=~committed_bank;mask_valid<=1;commit<=0;end
                if(pending) begin mask_valid<=0;commit<=0;end
            end
            if(bg_press && LOCK_EXPOSURE) begin mask_valid<=0;commit<=0;end
        end
    end
    wire [10:0] rx=(x>>2)+2,ry=(y>>2)+2;
    wire display_inside=rx<SW && ry<SH && rx>=4 && ry>=4;
    wire [14:0] read_addr=display_inside ? ry*SW+rx : 15'd0;
    reg [1:0] mask0_read,mask1_read;
    wire [1:0] mask_read=display_bank ? mask1_read : mask0_read;
    always @(posedge clk) begin
        if(contour_en) begin
            if(write_bank) mask1[write_addr]<=write_mask;
            else mask0[write_addr]<=write_mask;
        end
        mask0_read<=mask0[read_addr];
        mask1_read<=mask1[read_addr];
    end
    reg [23:0] rgb_d;
    reg vs_d,de_d,inside_d;
    reg [10:0] x_d,y_d;
    wire visible=inside_d && mask_valid && bg_valid && !learning;
    wire [1:0] mask=visible ? mask_read : 2'b00;
    wire [23:0] view=mode==0 ? rgb_d : mode==1 ? (mask[1] ? 24'hffffff : 0) :
                       mode==2 ? (mask[0] ? 24'hffffff : 0) :
                                 (mask[0] ? 24'h00ffff : rgb_d);
    wire marker=x_d<32 && y_d<24;
    wire selected=y_d<8 ? x_d[4:3]==mode : x_d[4:3]==level;
    wire [23:0] status_color=(calibration!=0 || pending || learning) ? 24'hffff00 :
                              !bg_valid ? 24'hff0000 :
                              mask_valid ? 24'h00ff00 : 24'hffff00;
    wire gesture_ink;
    wire [23:0] gesture_rgb;
    generate if(GESTURES) begin : g_gesture
        wire [1:0] result,scene_reject;
        wire hand_found;
        wire [10:0] l,r,t,b;
        wire [6:0] percent;
        wire [6:0] envelope;
        wire [3:0] groups;
        wire ready=mask_valid && bg_valid && !learning && calibration==0;
        gesture_classifier #(.WIDTH(SW),.HEIGHT(SH)) classifier(
            .clk(clk),.rst(rst),.clear(!ready),
            .en(de_d && x_d[1:0]==0 && y_d[1:0]==0),.pixel(mask[1]),
            .x(x_d>>2),.y(y_d>>2),.frame_end(frame_begin),
            .gesture(result),.hand(hand_found),.left(l),.right(r),.top(t),.bottom(b),
            .fill_percent(percent),.finger_groups(groups),.envelope_percent(envelope),.scene_reject(scene_reject));
        wire [1:0] swipe_direction,swipe_event,motion_state;
        wire swipe_valid;
        wire [6:0] motion_distance;
        wire [2:0] motion_reason;
        gesture_motion motion(.clk(clk),.rst(rst),.clear(!ready),.sample(frame_begin),
            .hand(hand_found),.left(l),.right(r),.top(t),.bottom(b),
            .event_direction(swipe_event),.event_valid(swipe_valid),.display_direction(swipe_direction),
            .track_state(motion_state),.distance_value(motion_distance),.reason(motion_reason));
        wire link_overflow;
        gesture_link_tx link(.clk(clk),.rst(rst),.ready(ready),.sample(frame_begin),
            .pose(result),.swipe_valid(swipe_valid),.swipe_direction(swipe_event),
            .tx(gesture_tx),.overflow(link_overflow));
        wire [2:0] display_gesture=scene_reject==2 ? 3'd7 : scene_reject==1 ? 3'd6 : swipe_direction==1 ? 3'd4 : swipe_direction==2 ? 3'd5 : {1'b0,result};
        assign gesture_display=ready && hand_found ? display_gesture : 3'd0;
        gesture_osd #(.WIDTH(WIDTH),.HEIGHT(HEIGHT)) overlay(
            .x(x_d),.y(y_d),.ready(ready),.hand(hand_found),.gesture(display_gesture),
            .left(l),.right(r),.top(t),.bottom(b),.fill_percent(percent),
            .finger_groups(groups),.on(gesture_ink),.rgb(gesture_rgb),.envelope_percent(envelope),.motion_state(motion_state),.motion_distance(motion_distance),.motion_reason(motion_reason));
    end else begin : g_no_gesture
        assign gesture_ink=0;assign gesture_rgb=0;assign gesture_tx=1;assign gesture_display=0;
    end endgenerate
    always @(posedge clk or posedge rst) begin
        if(rst) begin
            rgb_d<=0;vs_d<=0;de_d<=0;inside_d<=0;x_d<=0;y_d<=0;
            out_vs<=0;out_de<=0;out_rgb<=0;
        end else begin
            rgb_d<=in_rgb;vs_d<=in_vs;de_d<=in_de;inside_d<=display_inside;x_d<=x;y_d<=y;
            out_vs<=vs_d;out_de<=de_d;
            out_rgb<=!de_d ? 0 : marker ?
                (y_d>=16 ? status_color : selected ? (y_d<8 ? 24'h00ff00 : 24'hffff00) : 24'h202020) :
                gesture_ink ? gesture_rgb : view;
        end
    end
endmodule

module contour_key #(parameter CYCLES=500000)(
    input wire clk,rst,key_n,output reg press
);
    (* async_reg="true" *) reg [1:0] sync;
    reg stable;reg [19:0] count;
    always @(posedge clk or posedge rst) begin
        if(rst) begin sync<=3;stable<=1;count<=0;press<=0;end
        else begin
            sync<={sync[0],key_n};press<=0;
            if(sync[1]==stable) count<=0;
            else if(count==CYCLES-1) begin stable<=sync[1];count<=0;press<=!sync[1];end
            else count<=count+1'b1;
        end
    end
endmodule

`timescale 1ns/1ps
// Coordinates are in the 160x120 foreground grid. Direction follows the image.
module gesture_swipe #(
 parameter DISTANCE=16,MAX_STEP=24,MAX_VERTICAL=18,WINDOW=60,
 parameter COOLDOWN=24,HOLD=36,ARM_FRAMES=3
)(
 input wire clk,rst,clear,sample,hand,
 input wire [1:0] pose,
 input wire [10:0] left,right,top,bottom,
 output reg [1:0] event_direction,
 output reg event_valid,
 output wire [1:0] display_direction,output wire [1:0] track_state
);
 wire [11:0] sum_x={1'b0,left}+{1'b0,right};
 wire [11:0] sum_y={1'b0,top}+{1'b0,bottom};
 wire [10:0] cx=sum_x[11:1],cy=sum_y[11:1];
 wire [10:0] width=right-left+1,height=bottom-top+1;
 reg tracking;
 reg [10:0] anchor_x,anchor_y,previous_x,previous_w,previous_h;
 reg [7:0] age,cooldown,hold_count,armed,steps;
 reg [1:0] direction,shown;
 wire [10:0] step_x=cx>previous_x ? cx-previous_x : previous_x-cx;
 wire [10:0] travel=cx>anchor_x ? cx-anchor_x : anchor_x-cx;
 wire [10:0] vertical=cy>anchor_y ? cy-anchor_y : anchor_y-cy;
 wire [10:0] dw=width>previous_w ? width-previous_w : previous_w-width;
 wire [10:0] dh=height>previous_h ? height-previous_h : previous_h-height;
 wire [1:0] movement=cx>previous_x ? 2'd2 : 2'd1;
 wire jump=step_x>MAX_STEP || vertical>MAX_VERTICAL ||
           dw>(previous_w>>2)+4 || dh>(previous_h>>2)+4;
 assign track_state=cooldown!=0 ? 2'd3 : tracking ? 2'd2 : armed!=0 ? 2'd1 : 2'd0;
 assign display_direction=hold_count!=0 ? shown : 2'd0;
 always @(posedge clk or posedge rst) begin
  if(rst) begin
   tracking<=0;anchor_x<=0;anchor_y<=0;previous_x<=0;previous_w<=0;previous_h<=0;
   age<=0;cooldown<=0;hold_count<=0;armed<=0;steps<=0;direction<=0;shown<=0;
   event_valid<=0;event_direction<=0;
  end else begin
   event_valid<=0;
   if(clear) begin
    tracking<=0;age<=0;cooldown<=0;hold_count<=0;armed<=0;steps<=0;direction<=0;shown<=0;
   end else if(sample) begin
    if(hold_count!=0) hold_count<=hold_count-1'b1;
    if(cooldown!=0) cooldown<=cooldown-1'b1;
    if(!hand || pose==0 || pose==2) begin
     tracking<=0;armed<=0;steps<=0;direction<=0;
    end else if(cooldown!=0) begin tracking<=0;armed<=0;end
    else if(!tracking) begin
     // Acquire a confirmed OPEN hand before following motion through UNKNOWN.
     if(pose!=1) armed<=0;
     else if(armed!=0 && (step_x>2 || dw>4 || dh>4)) armed<=0;
     else if(armed==ARM_FRAMES-1) begin
      tracking<=1;armed<=0;age<=0;steps<=0;direction<=0;
      anchor_x<=cx;anchor_y<=cy;
     end else armed<=armed+1'b1;
     previous_x<=cx;previous_w<=width;previous_h<=height;
    end else begin
     previous_x<=cx;previous_w<=width;previous_h<=height;
     if(jump || age==WINDOW-1) begin
      tracking<=0;armed<=0;steps<=0;direction<=0;
     end else begin
      age<=age+1'b1;
      if(step_x>0) begin
       if(direction!=0 && movement!=direction && step_x>=4) begin
        anchor_x<=cx;anchor_y<=cy;direction<=movement;steps<=0;age<=0;
       end else if(direction==0 || movement==direction) begin
        direction<=movement;
        if(steps<255) steps<=steps+1'b1;
        if(travel>=DISTANCE && travel>=vertical*2 && steps>=2 &&
          ((movement==1 && cx<anchor_x) || (movement==2 && cx>anchor_x))) begin
         event_direction<=movement;event_valid<=1;shown<=movement;hold_count<=HOLD;
         cooldown<=COOLDOWN;tracking<=0;armed<=0;steps<=0;
        end
       end
      end
     end
    end
   end
  end
 end
endmodule

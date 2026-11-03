`timescale 1ns/1ps
// Foreground trajectory detector, independent of static OPEN/FIST decisions.
module gesture_motion #(
 parameter DISTANCE=16,MAX_STEP=32,MAX_VERTICAL=24,WINDOW=96,
 parameter COOLDOWN=24,HOLD=60,LOSS_GRACE=6
)(
 input wire clk,rst,clear,sample,hand,
 input wire [10:0] left,right,top,bottom,
 output reg [1:0] event_direction,output reg event_valid,
 output wire [1:0] display_direction,track_state,
 output reg [6:0] distance_value,output reg [2:0] reason
);
 wire [11:0] sx={1'b0,left}+{1'b0,right},sy={1'b0,top}+{1'b0,bottom};
 wire [10:0] cx=sx[11:1],cy=sy[11:1],w=right-left+1,h=bottom-top+1;
 wire shape_ok=w>=8 && h>=8 && h*2>=w && h<=w*5;
 reg tracking;reg [10:0] ax,ay,px,pw,ph;
 reg [7:0] age,cooldown,hold_count,steps,gaps,reason_count;
 reg [1:0] direction,shown;
 wire [10:0] delta=cx>px ? cx-px : px-cx;
 wire [10:0] travel=cx>ax ? cx-ax : ax-cx;
 wire [10:0] vertical=cy>ay ? cy-ay : ay-cy;
 wire [10:0] dw=w>pw ? w-pw : pw-w,dh=h>ph ? h-ph : ph-h;
 wire [1:0] movement=cx>px ? 2'd2 : 2'd1;
 wire jump=delta>MAX_STEP || dw>(pw>>1)+8 || dh>(ph>>1)+8;
 assign display_direction=hold_count!=0 ? shown : 2'd0;
 assign track_state=cooldown!=0 ? 2'd3 : !tracking ? 2'd0 : steps==0 ? 2'd1 : 2'd2;
 always @(posedge clk or posedge rst) begin
  if(rst) begin
   tracking<=0;ax<=0;ay<=0;px<=0;pw<=0;ph<=0;age<=0;cooldown<=0;hold_count<=0;
   steps<=0;gaps<=0;direction<=0;shown<=0;event_direction<=0;event_valid<=0;distance_value<=0;reason<=0;reason_count<=0;
  end else begin
   event_valid<=0;
   if(clear) begin
    tracking<=0;age<=0;cooldown<=0;hold_count<=0;steps<=0;gaps<=0;direction<=0;shown<=0;
    distance_value<=0;reason<=0;reason_count<=0;
   end else if(sample) begin
    if(hold_count!=0) hold_count<=hold_count-1'b1;
    if(reason_count!=0) reason_count<=reason_count-1'b1;else reason<=0;
    if(cooldown!=0) begin cooldown<=cooldown-1'b1;tracking<=0;reason<=6;reason_count<=1;end
    else if(!hand || !shape_ok) begin
     reason<=!hand ? 1 : 2;reason_count<=30;
     if(tracking && gaps<LOSS_GRACE) begin gaps<=gaps+1'b1;age<=age+1'b1;end
     else begin tracking<=0;steps<=0;direction<=0;distance_value<=0;end
    end else begin
     gaps<=0;px<=cx;pw<=w;ph<=h;
     if(!tracking) begin
      tracking<=1;ax<=cx;ay<=cy;age<=0;steps<=0;direction<=0;distance_value<=0;
     end else if(jump || vertical>MAX_VERTICAL || age>=WINDOW-1) begin
      ax<=cx;ay<=cy;age<=0;steps<=0;direction<=0;distance_value<=0;
      reason<=jump ? 3 : vertical>MAX_VERTICAL ? 4 : 5;reason_count<=30;
     end else begin
      age<=age+1'b1;distance_value<=travel>99 ? 7'd99 : travel[6:0];
      if(delta!=0) begin
       if(direction!=0 && movement!=direction && delta>=4) begin
        ax<=px;ay<=cy;age<=0;steps<=1;direction<=movement;distance_value<=delta>99 ? 7'd99 : delta[6:0];
       end else if(direction==0 || movement==direction) begin
        direction<=movement;if(steps<255) steps<=steps+1'b1;
        if(travel>=DISTANCE && travel>=vertical*2 && steps>=1 &&
           ((movement==1 && cx<ax) || (movement==2 && cx>ax))) begin
         event_direction<=movement;event_valid<=1;shown<=movement;hold_count<=HOLD;
         cooldown<=COOLDOWN;tracking<=0;steps<=0;
        end
       end
      end
     end
    end
   end
  end
 end
endmodule

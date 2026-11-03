`timescale 1ns/1ps
// Dominant projection region + shape rules for one mostly upright hand.
module gesture_classifier #(parameter WIDTH=160,HEIGHT=120,MIN_AREA=80,CONFIRM_FRAMES=4)(
 input wire clk,rst,clear,en,pixel,frame_end,input wire [10:0] x,y,
 output reg [1:0] gesture,output reg hand,
 output reg [10:0] left,right,top,bottom,
 output reg [6:0] fill_percent,output reg [3:0] finger_groups,
 output reg [6:0] envelope_percent, output reg [1:0] scene_reject);
 reg [7:0] columns[0:WIDTH-1],rows[0:HEIGHT-1];
 reg [7:0] row_left[0:HEIGHT-1],row_right[0:HEIGHT-1];
 reg busy,initializing;reg [2:0] phase;reg [10:0] scan;
 reg [15:0] total_area;
 reg [15:0] upper_area;reg [WIDTH-1:0] hits,snap_hits;
 wire roi=x>=WIDTH/16 && x<WIDTH*15/16 && y>=HEIGHT/16 && y<HEIGHT-2;
 wire collect=!busy && en && pixel && roi;
 wire [10:0] bw=right-left+1,bh=bottom-top+1;
 wire [10:0] band_height=(bh*5)>>3,tip_height=bh>>2;
 wire upper_region=hand && x>=left && x<=right && y>=top && y<top+band_height;
 wire tip_region=hand && x>=left && x<=right && y>=top && y<top+tip_height;
 always @(posedge clk) if(!rst) begin
  if(busy && phase==0 && scan<WIDTH) columns[scan]<=0;
  else if(collect) columns[x]<=columns[x]+1'b1;
  if(busy && phase==2 && scan<HEIGHT) rows[scan]<=0;
  else if(collect) rows[y]<=rows[y]+1'b1;
  if(busy && phase==2 && scan<HEIGHT) begin row_left[scan]<=WIDTH;row_right[scan]<=0;end
  else if(collect && upper_region) begin
   if(x<row_left[y]) row_left[y]<=x;
   if(x>row_right[y]) row_right[y]<=x;
  end
 end
 wire [7:0] bin=phase==0 ? columns[scan] : rows[scan];
 reg [15:0] run_mass,best_x_mass,best_y_mass;
 reg [10:0] run_start,run_last,best_l,best_r,best_t,best_b;
 reg [1:0] empty_bins;reg active;
 wire [10:0] nw=best_r-best_l+1,nh=best_b-best_t+1;
 wire too_large=total_snapshot>=MIN_AREA && (total_snapshot>WIDTH*HEIGHT*3/8 || nw>WIDTH*7/8);
 wire scattered=best_x_mass*4<total_snapshot*3 || best_y_mass*4<total_snapshot*3;
 reg [15:0] total_snapshot;
 wire present=best_x_mass>=MIN_AREA && best_y_mass>=MIN_AREA && !too_large && !scattered;
 wire [10:0] dw=nw>bw ? nw-bw : bw-nw,dh=nh>bh ? nh-bh : bh-nh;
 wire [10:0] dx=best_l>left ? best_l-left : left-best_l;
 wire [10:0] dy=best_t>top ? best_t-top : top-best_t;
 // Clipped wrists are allowed; isolated boundary dots cannot veto a hand.
 wire geometry_ok=hand && present && nw>=8 && nh>=8 && nh*4>=nw*3 && nh<=nw*5 &&
  dw<=(bw>>1)+4 && dh<=(bh>>1)+4 && dx<=WIDTH/5 && dy<=HEIGHT/5;
 reg snap_ok,snap_present;reg [15:0] snap_upper,snap_band;
 reg [22:0] numerator;reg [6:0] percent;
 reg [15:0] envelope_area;
 reg [10:0] widest_row;
 reg [22:0] envelope_numerator;
 reg [6:0] envelope_value;
 wire row_span_valid=row_left[scan]<WIDTH && row_right[scan]>=row_left[scan];
 wire [10:0] row_span=row_right[scan]-row_left[scan]+1;
 reg tip_active,tip_gap;reg [7:0] tip_width;reg [3:0] groups;
 reg [1:0] candidate;reg [3:0] confirmed;
 wire [22:0] weighted=snap_upper*23'd100;
 // A closed fist is dense inside each row's own span even when its bounding
 // rectangle contains large empty corners due to tilt and an attached wrist.
 wire compact_fist=groups<=1 && envelope_area!=0 && weighted>=envelope_area*23'd85 &&
                   weighted>=snap_band*23'd45 && widest_row*3>=nw*2;
 wire [1:0] decision=!snap_present ? 0 : !snap_ok || snap_band==0 ? 3 :
  compact_fist ? 2 :
  (weighted<=snap_band*23'd58 || (groups>=2 && weighted<=snap_band*23'd68)) ? 1 :
  (weighted>=snap_band*23'd74 && groups<=1) ? 2 : 3;
 always @(posedge clk or posedge rst) begin
  if(rst) begin
   busy<=1;initializing<=1;phase<=0;scan<=0;upper_area<=0;total_area<=0;total_snapshot<=0;scene_reject<=0;hits<=0;snap_hits<=0;
   gesture<=0;hand<=0;left<=0;right<=0;top<=0;bottom<=0;fill_percent<=0;finger_groups<=0;
   active<=0;run_mass<=0;run_start<=0;run_last<=0;empty_bins<=0;
   best_x_mass<=0;best_y_mass<=0;best_l<=0;best_r<=0;best_t<=0;best_b<=0;
   snap_ok<=0;snap_present<=0;snap_upper<=0;snap_band<=0;numerator<=0;percent<=0;
   tip_active<=0;tip_gap<=0;tip_width<=0;groups<=0;candidate<=3;confirmed<=0;
   envelope_area<=0;widest_row<=0;envelope_numerator<=0;envelope_value<=0;envelope_percent<=0;
  end else if(clear) begin
   busy<=1;initializing<=1;phase<=0;scan<=0;upper_area<=0;total_area<=0;total_snapshot<=0;scene_reject<=0;hits<=0;
   active<=0;run_mass<=0;empty_bins<=0;best_x_mass<=0;best_y_mass<=0;
   gesture<=0;hand<=0;fill_percent<=0;finger_groups<=0;candidate<=3;confirmed<=0;
   envelope_area<=0;widest_row<=0;envelope_numerator<=0;envelope_value<=0;envelope_percent<=0;
  end else begin
   if(collect) begin
    total_area<=total_area+1'b1;
    if(upper_region) upper_area<=upper_area+1'b1;
    if(tip_region) hits[x]<=1;
   end
   if(frame_end && !busy) begin
    busy<=1;initializing<=0;phase<=0;scan<=0;
    active<=0;run_mass<=0;empty_bins<=0;best_x_mass<=0;best_y_mass<=0;
    total_snapshot<=total_area;total_area<=0;
    snap_hits<=hits;snap_upper<=upper_area;snap_band<=bw*band_height;
    numerator<=upper_area*23'd100;percent<=0;hits<=0;upper_area<=0;
    groups<=0;tip_active<=0;tip_gap<=0;tip_width<=0;
    envelope_area<=0;widest_row<=0;envelope_numerator<=upper_area*23'd100;envelope_value<=0;
   end else if(busy) begin
    if(!initializing && snap_band!=0 && numerator>=snap_band && percent<100) begin
     numerator<=numerator-snap_band;percent<=percent+1'b1;
    end
    case(phase)
    0,2: begin
     if(scan<(phase==0 ? WIDTH : HEIGHT)) begin
      scan<=scan+1'b1;
      if(!initializing) begin
       if(phase==2 && row_span_valid) begin
        envelope_area<=envelope_area+row_span;
        if(row_span>widest_row) widest_row<=row_span;
       end
       if(bin>=3) begin
        if(!active) begin active<=1;run_start<=scan;run_mass<=bin;end
        else run_mass<=run_mass+bin;
        run_last<=scan;empty_bins<=0;
       end else if(active) begin
        if(empty_bins==2) begin
         if(phase==0 && run_mass>best_x_mass) begin best_x_mass<=run_mass;best_l<=run_start;best_r<=run_last;end
         if(phase==2 && run_mass>best_y_mass) begin best_y_mass<=run_mass;best_t<=run_start;best_b<=run_last;end
         active<=0;run_mass<=0;empty_bins<=0;
        end else empty_bins<=empty_bins+1'b1;
       end
       if(phase==0) begin
        if(snap_hits[scan]) begin
         tip_gap<=0;
         if(!tip_active) begin tip_active<=1;tip_width<=1;end
         else begin
          if(tip_width==1 && groups<7) groups<=groups+1'b1;
          if(tip_width<255) tip_width<=tip_width+1'b1;
         end
        end else if(tip_active) begin
         if(tip_gap) begin tip_active<=0;tip_width<=0;tip_gap<=0;end else tip_gap<=1;
        end
       end
      end
     end else phase<=phase+1'b1;
    end
    1: begin
     if(active && run_mass>best_x_mass) begin best_x_mass<=run_mass;best_l<=run_start;best_r<=run_last;end
     phase<=2;scan<=0;active<=0;run_mass<=0;empty_bins<=0;
    end
    3: begin
     if(active && run_mass>best_y_mass) begin best_y_mass<=run_mass;best_t<=run_start;best_b<=run_last;end
     phase<=4;
    end
    4: begin
     if(initializing) begin busy<=0;initializing<=0;end
     else begin
      snap_present<=present;snap_ok<=geometry_ok;hand<=present;
      scene_reject<=too_large ? 2'd2 : scattered && total_snapshot>=MIN_AREA ? 2'd1 : 2'd0;
      if(present) begin left<=best_l;right<=best_r;top<=best_t;bottom<=best_b;end
      phase<=5;
     end
    end
    5: begin
     if(envelope_area!=0 && envelope_numerator>=envelope_area && envelope_value<100) begin
      envelope_numerator<=envelope_numerator-envelope_area;envelope_value<=envelope_value+1'b1;
     end else phase<=6;
    end
    6: begin
     busy<=0;fill_percent<=snap_band!=0 ? percent : 0;finger_groups<=groups;
     envelope_percent<=envelope_area!=0 ? envelope_value : 0;
     if(decision==3) begin gesture<=3;candidate<=3;confirmed<=0;end
     else if(decision!=candidate) begin candidate<=decision;confirmed<=1;gesture<=3;end
     else if(confirmed<CONFIRM_FRAMES) begin
      confirmed<=confirmed+1'b1;if(confirmed==CONFIRM_FRAMES-1) gesture<=decision;
     end
    end
    default:busy<=0;
    endcase
   end
  end
 end
endmodule

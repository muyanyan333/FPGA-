`timescale 1ns/1ps
// Two user-recorded prototypes; distances are feature distances, not probabilities.
module gesture_templates #(parameter SAMPLES=16,TIMEOUT_FRAMES=120)(
 input wire clk,rst,clear,update,valid,present,learn_open,learn_fist,
 input wire [6:0] fill_value,envelope_value,input wire [3:0] groups,
 output wire [1:0] decision,output reg [1:0] saved,learning,retry
);
 reg [6:0] ofill,oenv,ffill,fenv;
 reg [3:0] ogroups,fgroups;
 reg [11:0] sum_f,sum_e;reg [9:0] sum_g;
 reg [7:0] count,timeout;
 function [9:0] distance;
 input [6:0] a,b,c,d;input [3:0] e,f;
 begin distance=(a>b ? a-b : b-a)*2+(c>d ? c-d : d-c)+(e>f ? e-f : f-e)*6;end
 endfunction
 wire [9:0] do_score=distance(fill_value,ofill,envelope_value,oenv,groups,ogroups);
 wire [9:0] df_score=distance(fill_value,ffill,envelope_value,fenv,groups,fgroups);
 wire [9:0] separation=distance(ofill,ffill,oenv,fenv,ogroups,fgroups);
 wire [6:0] mean_f=(sum_f+fill_value)/SAMPLES,mean_e=(sum_e+envelope_value)/SAMPLES;
 wire [3:0] mean_g=(sum_g+groups)/SAMPLES;
 wire [9:0] other_distance=learning==1 ? distance(mean_f,ffill,mean_e,fenv,mean_g,fgroups) :
                                                       distance(mean_f,ofill,mean_e,oenv,mean_g,ogroups);
 wire other_saved=learning==1 ? saved[1] : saved[0];
 assign decision=!present ? 0 : !valid || saved!=3 || learning!=0 || separation<28 ? 3 :
                  do_score<=50 && do_score+12<=df_score ? 1 :
                  df_score<=50 && df_score+12<=do_score ? 2 : 3;
 always @(posedge clk or posedge rst) begin
  if(rst) begin
   saved<=0;learning<=0;retry<=0;ofill<=0;oenv<=0;ffill<=0;fenv<=0;ogroups<=0;fgroups<=0;
   sum_f<=0;sum_e<=0;sum_g<=0;count<=0;timeout<=0;
  end else if(clear) begin
   learning<=0;retry<=0;sum_f<=0;sum_e<=0;sum_g<=0;count<=0;timeout<=0;
  end else if(learn_open || learn_fist) begin
   learning<=learn_open ? 1 : 2;retry<=0;
   if(learn_open) saved[0]<=0;else saved[1]<=0;
   sum_f<=0;sum_e<=0;sum_g<=0;count<=0;timeout<=0;
  end else if(update && learning!=0) begin
   timeout<=timeout+1'b1;
   if(timeout>=TIMEOUT_FRAMES-1) begin retry<=learning;learning<=0;end
   else if(!valid || !present) begin sum_f<=0;sum_e<=0;sum_g<=0;count<=0;end
   else if(count==SAMPLES-1) begin
    learning<=0;
    if(other_saved && other_distance<28) retry<=learning;
    else if(learning==1) begin ofill<=mean_f;oenv<=mean_e;ogroups<=mean_g;saved[0]<=1;end
    else begin ffill<=mean_f;fenv<=mean_e;fgroups<=mean_g;saved[1]<=1;end
   end else begin
    sum_f<=sum_f+fill_value;sum_e<=sum_e+envelope_value;sum_g<=sum_g+groups;count<=count+1'b1;
   end
  end
 end
endmodule

module gesture_key #(parameter DEBOUNCE=500000,HOLD=20000000)(
 input wire clk,rst,key_n,output reg short_press,long_press
);
 (* async_reg="true" *) reg [1:0] sync;
 reg stable,sent;reg [19:0] debounce;reg [24:0] held;
 always @(posedge clk or posedge rst) begin
  if(rst) begin sync<=3;stable<=1;sent<=0;debounce<=0;held<=0;short_press<=0;long_press<=0;end
  else begin
   sync<={sync[0],key_n};short_press<=0;long_press<=0;
   if(sync[1]==stable) debounce<=0;
   else if(debounce==DEBOUNCE-1) begin
    stable<=sync[1];debounce<=0;
    if(!sync[1]) begin held<=0;sent<=0;end
    else begin short_press<=!sent;held<=0;end
   end else debounce<=debounce+1'b1;
   if(!stable && !(sync[1] && debounce==DEBOUNCE-1)) begin
    if(held<HOLD) held<=held+1'b1;
    else if(!sent) begin long_press<=1;sent<=1;end
   end
  end
 end
endmodule

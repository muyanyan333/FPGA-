`timescale 1ns/1ps
module video_auto_return_tb;
reg clk=0,rst_n=0,request=0,done=0,scanned=0;reg [1:0] mode=0;
always #5 clk=~clk;
top #(.CAMERA_AVAILABLE(0)) dut(.clk(clk),.rst_n(rst_n),.key2(1'b1),.key3(1'b1),.key4(1'b1));
initial begin
 force dut.camera_mode_request=request;force dut.camera_mode_value=mode;
 force dut.video_playback_done=done;force dut.image_scan_done=scanned;force dut.image_count=5'd3;
 #2;repeat(3) @(negedge clk);rst_n=1;
 @(negedge clk);mode=2;request=1;@(negedge clk);request=0;
 repeat(45) @(negedge clk);
 if(dut.display_mode!==2) $fatal(1,"video request did not enter video mode");
 done=1;@(negedge clk);done=0;
 if(dut.display_mode!==0 || dut.mode_reset_count!==40) $fatal(1,"EOF did not return to images with pipeline reset");
 repeat(45) @(negedge clk);
 if(dut.display_mode!==0 || dut.mode_reset_count!==0) $fatal(1,"return did not settle");
 if(!dut.resume_images_pending || dut.resume_images_pulse) $fatal(1,"resume must wait for fresh image scan");
 scanned=1;#1;
 if(!dut.resume_images_pulse) $fatal(1,"missing automatic slideshow resume");
 @(negedge clk);
 if(dut.resume_images_pending) $fatal(1,"slideshow resume not one-shot");
 $display("PASS video EOF returns to images and resumes slideshow after scan");$finish;
end
initial begin #10000;$fatal(1,"timeout");end
endmodule

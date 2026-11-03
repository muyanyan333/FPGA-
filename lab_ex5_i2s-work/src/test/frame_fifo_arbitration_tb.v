`timescale 1ns/1ps
// Shared SDRAM command bus: concurrent frame writes and display reads,
// real asynchronous write FIFO, delayed read returns and output backpressure.
module frame_fifo_arbitration_tb;
reg clk=0, memclk=0, rst=1, wreq=0, rreq=0, feeding=0;
reg [31:0] offered=0; integer written=0, read_count=0, phase=0;
integer refresh_left=0, refresh_count=0;wire refresh_busy=refresh_left!=0;
reg [9:0] output_used=0; reg [3:0] returns=0;
wire wack,rack,wfinish,rfinish,wa,ra,wb,rb,clear,full,empty;
wire [8:0] used;wire [31:0] data;wire [20:0] wad,rad;
wire put=feeding && offered<307200 && !full;
wire consume=(phase%4==0) && output_used!=0;
always #10 clk=~clk;always #5 memclk=~memclk;
always @(posedge clk) if(put) offered<=offered+1;
wfifo_32_32_512 fifo(.clkw(clk),.clkr(memclk),.rst(rst||clear),.we(put),.di(offered),
 .re(wa),.dout(data),.full_flag(full),.empty_flag(empty),.rdusedw(used));
frame_fifo_write #(.BURST_SIZE(256)) writer(.rst(rst),.mem_clk(memclk),.Sdr_init_done(!rst),
 .Sdr_init_ref_vld(refresh_busy),.Sdr_busy(rb||refresh_busy),.App_rd_busy(rb),.O_wr_busy(wb),
 .App_wr_en(wa),.App_wr_addr(wad),.write_req(wreq),.write_v_flip(1'b0),
 .write_req_ack(wack),.write_finish(wfinish),.write_addr_0(21'd0),
 .write_addr_1(21'd307200),.write_addr_2(21'd0),.write_addr_3(21'd0),
 .write_addr_index(2'd0),.write_len(21'd307200),.fifo_aclr(clear),.rdusedw(used));
frame_fifo_read #(.OUTPUT_WIDTH(640),.BURST_SIZE(256)) reader(.rst(rst),.mem_clk(memclk),
 .Sdr_init_done(!rst),.Sdr_init_ref_vld(refresh_busy),.Sdr_busy(wb||refresh_busy),.Sdr_rd_en(returns[3]),
 .App_wr_busy(wb),.O_rd_busy(rb),.App_rd_en(ra),.App_rd_addr(rad),
 .read_req(rreq),.read_req_ack(rack),.read_finish(rfinish),.read_addr_0(21'd0),
 .read_addr_1(21'd307200),.read_addr_2(21'd0),.read_addr_3(21'd0),
 .read_addr_index(2'd0),.read_len(21'd307200),.slide_active(1'b0),
 .slide_progress(10'd0),.slide_old_index(2'd0),.slide_new_index(2'd1),
 .fifo_aclr(),.wrusedw(output_used[8:0]));
always @(posedge memclk) if(!rst) begin
 if(refresh_busy && (wa||ra)) $fatal(1,"command submitted during refresh");
 if(refresh_left>0) refresh_left<=refresh_left-1;
 else if(phase%83==0 && !(wb||rb||wa||ra)) begin refresh_left<=20;refresh_count=refresh_count+1;end
 phase=phase+1;returns<={returns[2:0],ra};
 case({returns[3],consume})
  2'b10:output_used<=output_used+1;
  2'b01:output_used<=output_used-1;
 endcase
 if(output_used>511) $fatal(1,"display FIFO overflow %d",output_used);
 if((wa&&ra)||(wb&&rb)) $fatal(1,"read/write command bus collision");
 if(wa) begin
  if(empty || wad!==written || data!==written) $fatal(1,"write data/address lost: n=%d addr=%d data=%d empty=%b",written,wad,data,empty);
  written=written+1;
 end
 if(ra) begin
  if(rad!==read_count) $fatal(1,"read address lost");
  read_count=read_count+1;
 end
end
initial begin
 #100;rst=0;repeat(5) @(negedge clk);wreq=1;rreq=1;
 wait(wack&&rack);@(negedge clk);wreq=0;rreq=0;
 wait(!wack&&!rack);repeat(5) @(negedge clk);feeding=1;
 wait(wfinish);if(written!=307200) $fatal(1,"incomplete write frame");
 wait(rfinish);if(refresh_count<10) $fatal(1,"refresh coverage missing");if(read_count!=307200) $fatal(1,"incomplete read frame");
 $display("PASS shared SDRAM arbitration: 307200 write words/data + read addresses, no collision/underflow/overflow, periodic refresh backpressure");$finish;
end
initial begin #50000000;$fatal(1,"arbitration timeout written=%d read=%d",written,read_count);end
endmodule

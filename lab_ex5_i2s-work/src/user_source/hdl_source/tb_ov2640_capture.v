`timescale 1ns/1ps
module tb_ov2640_capture;
  reg pclk=0, rst=1, init_done=1, vsync=0, href=0;
  reg [7:0] data=0;
  reg write_ack=0, write_finish_toggle=0, write_full=0;
  wire write_req, write_en, write_bank, display_bank, display_valid, frame_error;
  wire [31:0] write_data;
  integer pixels=0;
  reg check_color=1;
  always #10 pclk=~pclk;
  ov2640_dvp_capture #(.FRAME_PIXELS(4)) dut(
    .pclk(pclk), .rst(rst), .init_done(init_done),
    .vsync(vsync), .href(href), .data(data),
    .write_ack(write_ack), .write_finish_toggle(write_finish_toggle),
    .write_full(write_full), .write_req(write_req),
    .write_en(write_en), .write_data(write_data),
    .write_bank(write_bank), .display_bank(display_bank),
    .display_valid(display_valid), .frame_error(frame_error)
  );
  always @(posedge pclk) if (write_en) begin
    if (check_color) case (pixels)
      0: if (write_data !== 32'hff000000) $fatal(1,"red conversion");
      1: if (write_data !== 32'h00ff0000) $fatal(1,"green conversion");
      2: if (write_data !== 32'h0000ff00) $fatal(1,"blue conversion");
      3: if (write_data !== 32'hffffff00) $fatal(1,"white conversion");
    endcase
    pixels=pixels+1;
  end
  task pulse_vsync;
    begin
      @(negedge pclk); vsync=1;
      repeat(3) @(negedge pclk);
      vsync=0;
    end
  endtask
  task byte_in(input [7:0] value);
    begin @(negedge pclk); href=1; data=value; end
  endtask
  initial begin
    repeat(4) @(negedge pclk); rst=0;
    repeat(5) @(negedge pclk);
    pulse_vsync;
    wait(write_req);
    repeat(3) @(negedge pclk); write_ack=1;
    repeat(4) @(negedge pclk); write_ack=0;
    pulse_vsync;
    byte_in(8'h00); byte_in(8'hf8);
    byte_in(8'he0); byte_in(8'h07);
    byte_in(8'h1f); byte_in(8'h00);
    byte_in(8'hff); byte_in(8'hff);
    @(negedge pclk); href=0;
    repeat(6) @(negedge pclk);
    if (pixels != 4 || frame_error) $fatal(1,"captured pixels=%0d error=%b",pixels,frame_error);
    write_finish_toggle=1;
    repeat(5) @(negedge pclk);
    if (!display_valid || display_bank || !write_bank)
      $fatal(1,"frame bank commit failed");
    // Drop an input pixel under FIFO backpressure; pad SDRAM to a complete
    // frame, then keep the previous displayed bank.
    pixels=0;
    check_color=0;
    write_full=1;
    repeat(4) @(negedge pclk);
    // The next write request must already be armed after commit; only one
    // VSYNC is needed to capture the next source frame.
    wait(write_req);
    repeat(3) @(negedge pclk); write_ack=1;
    repeat(4) @(negedge pclk); write_ack=0;
    pulse_vsync;
    byte_in(8'h00); byte_in(8'hf8);
    @(negedge pclk); write_full=0;
    byte_in(8'he0); byte_in(8'h07);
    byte_in(8'h1f); byte_in(8'h00);
    byte_in(8'hff); byte_in(8'hff);
    @(negedge pclk); href=0;
    repeat(12) @(negedge pclk);
    if (pixels != 4 || !frame_error) $fatal(1,"overflow recovery failed");
    write_finish_toggle=0;
    repeat(5) @(negedge pclk);
    if (display_bank || !write_bank) $fatal(1,"bad frame was displayed");
    // Some modules overlap VSYNC high with the first active HREF line.
    // HREF, not VSYNC level, qualifies data bytes after the frame edge.
    pixels=0;
    check_color=1;
    wait(write_req);
    repeat(3) @(negedge pclk); write_ack=1;
    repeat(4) @(negedge pclk); write_ack=0;
    @(negedge pclk); vsync=1;
    byte_in(8'h00); byte_in(8'hf8);
    byte_in(8'he0); byte_in(8'h07);
    byte_in(8'h1f); byte_in(8'h00);
    byte_in(8'hff); byte_in(8'hff);
    @(negedge pclk); href=0; vsync=0;
    repeat(6) @(negedge pclk);
    if (pixels != 4 || frame_error) $fatal(1,"VSYNC/HREF overlap lost pixels");
    write_finish_toggle=1;
    repeat(5) @(negedge pclk);
    if (!display_bank || write_bank) $fatal(1,"overlap frame was not committed");
    $display("PASS OV2640 DVP capture, RGB565 conversion, overlap and bank commit");
    $finish;
  end
  initial begin #100000; $fatal(1,"timeout"); end
endmodule

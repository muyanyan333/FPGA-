`timescale 1ns/1ps
module frame_fifo_read
#
(
	parameter MEM_DATA_BITS          = 32,
	parameter ADDR_BITS              = 21,
	parameter BURST_BITS             = 9,
	parameter FIFO_DEPTH             = 512,
	parameter BURST_SIZE             = 128,
	parameter SOURCE_WIDTH           = 640,
	parameter OUTPUT_WIDTH           = 1280
)               
(
	input                            rst,                  
	input                            mem_clk,                    // external memory controller user interface clock
	input							 Sdr_init_done,
	input							 Sdr_init_ref_vld,
    input							 Sdr_busy,
    input							 Sdr_rd_en,
	input							 App_wr_busy,
    output							 O_rd_busy,
	/*
    output reg                       rd_burst_req,               // to external memory controller,send out a burst read request  
	output reg[BURST_BITS - 1:0]     rd_burst_len,               // to external memory controller,data length of the burst read request, not bytes 
	output reg[ADDR_BITS - 1:0]      rd_burst_addr,              // to external memory controller,base address of the burst read request
	input                            rd_burst_data_valid,        // from external memory controller,read request data valid    
	input                            rd_burst_finish,            // from external memory controller,burst read finish
	*/
	output 							 App_rd_en,
	output  [ADDR_BITS - 1:0]		 App_rd_addr,
	
	input                            read_req,                   // data read module read request,keep '1' until read_req_ack = '1'
	output reg                       read_req_ack,               // data read module read request response
	output                           read_finish,                // data read module read request finish
	input[ADDR_BITS - 1:0]           read_addr_0,                // data read module read request base address 0, used when read_addr_index = 0
	input[ADDR_BITS - 1:0]           read_addr_1,                // data read module read request base address 1, used when read_addr_index = 1
	input[ADDR_BITS - 1:0]           read_addr_2,                // data read module read request base address 1, used when read_addr_index = 2
	input[ADDR_BITS - 1:0]           read_addr_3,                // data read module read request base address 1, used when read_addr_index = 3
	input[1:0]                       read_addr_index,            // select valid base address from read_addr_0 read_addr_1 read_addr_2 read_addr_3
	input[ADDR_BITS - 1:0]           read_len,                   // data read module read request data length
	input                            slide_active,               // new image enters from left, old image exits right
	input[9:0]                       slide_progress,             // transition boundary, 0..640
	input[1:0]                       slide_old_index,
	input[1:0]                       slide_new_index,
	output reg                       fifo_aclr,                  // to fifo asynchronous clear
	input[8:0]                      wrusedw                     // from fifo write used words (512 深 FIFO -> 9bit)

);
localparam ONE                       = 256'd1;                   //256 bit '1'   you can use ONE[n-1:0] for n bit '1'
localparam ZERO                      = 256'd0;                   //256 bit '0'
//read state machine code
localparam S_IDLE                    = 0;                        //idle state,waiting for frame read
localparam S_ACK                     = 1;                        //read request response
localparam S_CHECK_FIFO              = 2;                        //check the FIFO status, ensure that there is enough space to burst read
localparam S_READ_BURST              = 3;                        //begin a burst read
localparam S_READ_BURST_END          = 4;                        //a burst read complete
localparam S_END                     = 5;                        //a frame of data is read to complete

reg                                  read_req_d0;                //asynchronous read request, synchronize to 'mem_clk' clock domain,first beat
reg                                  read_req_d1;                //second
reg                                  read_req_d2;                //third,Why do you need 3 ? Here's the design habit
reg[ADDR_BITS - 1:0]                 read_len_d0;                //asynchronous read_len(read data length), synchronize to 'mem_clk' clock domain first
reg[ADDR_BITS - 1:0]                 read_len_d1;                //second
reg[ADDR_BITS - 1:0]                 read_len_latch;             //lock read data length
reg[ADDR_BITS - 1:0]                 read_cnt;                   //read data counter
reg[3:0]                             state;                      //state machine
reg[1:0]                             read_addr_index_d0;         //synchronize to 'mem_clk' clock domain first
reg[1:0]                             read_addr_index_d1;         //synchronize to 'mem_clk' clock domain second
reg                                  slide_active_d0, slide_active_d1;
reg[9:0]                             slide_progress_d0, slide_progress_d1;
reg[1:0]                             slide_old_index_d0, slide_old_index_d1;
reg[1:0]                             slide_new_index_d0, slide_new_index_d1;
reg                                  slide_active_latch;
reg[9:0]                             slide_progress_latch;
reg[ADDR_BITS - 1:0]                 slide_old_row_base;
reg[ADDR_BITS - 1:0]                 slide_new_row_base;
reg[ADDR_BITS - 1:0]                 normal_row_base;
reg[10:0]                            output_x;
reg[1:0]                             vertical_phase;
reg[9:0]                             scaled_x;
reg[1:0]                             horizontal_phase;
reg [ADDR_BITS - 1:0]	 App_rd_addr_r;

reg [BURST_BITS - 1:0]				burst_cnt;
wire								rd_burst_finish;
reg App_rd_en_r;
reg App_rd_en_d0;


reg fifo_read_room;
always @(posedge mem_clk or posedge rst) begin
    if(rst) fifo_read_room<=0;
    else if(state!=S_CHECK_FIFO || fifo_aclr) fifo_read_room<=0;
    else fifo_read_room<=wrusedw < (FIFO_DEPTH-BURST_SIZE);
end
wire rd_vld;
reg [3:0] rd_delay;

assign App_rd_addr = {App_rd_addr_r[ADDR_BITS - 1:0]};
assign rd_vld = (state == S_READ_BURST && burst_cnt >= BURST_SIZE);

assign O_rd_busy = (state == S_READ_BURST);//读指令期间
//burst_cnt代表发送的读指令
//但rd_burst_finish需要在发送完十个时钟后拉高，此时数据全部读出
assign rd_burst_finish = (rd_vld && rd_delay == 4'd10);
assign read_finish = (state == S_END) ? 1'b1 : 1'b0;             //read finish at state 'S_END'
assign App_rd_en = App_rd_en_d0 && !Sdr_init_ref_vld;
always@(posedge mem_clk or posedge rst)
begin
	if(rst == 1'b1)
	begin
		read_req_d0    <=  1'b0;
		read_req_d1    <=  1'b0;
		read_req_d2    <=  1'b0;
		read_len_d0    <=  ZERO[ADDR_BITS - 1:0];               //equivalent to read_len_d0 <= 0;
		read_len_d1    <=  ZERO[ADDR_BITS - 1:0];               //equivalent to read_len_d1 <= 0;
		read_addr_index_d0 <= 2'b00;
		read_addr_index_d1 <= 2'b00;
		slide_active_d0 <= 1'b0;
		slide_active_d1 <= 1'b0;
		slide_progress_d0 <= 10'd0;
		slide_progress_d1 <= 10'd0;
		slide_old_index_d0 <= 2'd0;
		slide_old_index_d1 <= 2'd0;
		slide_new_index_d0 <= 2'd0;
		slide_new_index_d1 <= 2'd0;
	end
	else
	begin
		read_req_d0    <=  read_req;
		read_req_d1    <=  read_req_d0;
		read_req_d2    <=  read_req_d1;     
		read_len_d0    <=  read_len;
		read_len_d1    <=  read_len_d0; 
		read_addr_index_d0 <= read_addr_index;
		read_addr_index_d1 <= read_addr_index_d0;
		slide_active_d0 <= slide_active;
		slide_active_d1 <= slide_active_d0;
		slide_progress_d0 <= slide_progress;
		slide_progress_d1 <= slide_progress_d0;
		slide_old_index_d0 <= slide_old_index;
		slide_old_index_d1 <= slide_old_index_d0;
		slide_new_index_d0 <= slide_new_index;
		slide_new_index_d1 <= slide_new_index_d0;
		
	end 
end

always @(posedge mem_clk or posedge rst)
begin
	if(rst || App_rd_en)begin
        rd_delay <= 4'd0;
    end
    else if(rd_delay < 4'd10)begin
    	rd_delay <= rd_delay + 1'b1;
    end
end
always @(posedge mem_clk or posedge rst)
begin
	if(rst == 1'b1)
	begin
		burst_cnt <= ZERO[BURST_BITS - 1:0];
		App_rd_addr_r <= ZERO[ADDR_BITS - 1:0];
		App_rd_en_d0 <= 1'b0;
		slide_active_latch <= 1'b0;
		slide_progress_latch <= 10'd0;
		slide_old_row_base <= ZERO[ADDR_BITS - 1:0];
		slide_new_row_base <= ZERO[ADDR_BITS - 1:0];
		normal_row_base <= ZERO[ADDR_BITS - 1:0];
		output_x <= 11'd0;
		vertical_phase <= 2'd0;
		scaled_x <= 10'd0;
		horizontal_phase <= 2'd0;
	end
	else begin
	
		if(state == S_CHECK_FIFO)
			burst_cnt <= ZERO[BURST_BITS - 1:0];
		else if(App_rd_en)
			burst_cnt <= burst_cnt + 1'b1;
		else
			burst_cnt <= burst_cnt;
		//
		if(state == S_ACK)
			begin
				slide_active_latch   <= slide_active_d1;
				slide_progress_latch <= (slide_progress_d1 > 10'd640) ? 10'd640 : slide_progress_d1;
				output_x              <= 11'd0;
				vertical_phase        <= 2'd0;
				scaled_x              <= 10'd0;
				horizontal_phase      <= 2'd0;
				if(slide_old_index_d1 == 2'd0)
					slide_old_row_base <= read_addr_0;
				else
					slide_old_row_base <= read_addr_1;
				if(slide_new_index_d1 == 2'd0)
					slide_new_row_base <= read_addr_0 + (10'd640 - slide_progress_d1);
				else
					slide_new_row_base <= read_addr_1 + (10'd640 - slide_progress_d1);

				if(read_addr_index_d1 == 2'd0)
					normal_row_base <= read_addr_0;
				else if(read_addr_index_d1 == 2'd1)
					normal_row_base <= read_addr_1;
				else if(read_addr_index_d1 == 2'd2)
					normal_row_base <= read_addr_2;
				else
					normal_row_base <= read_addr_3;

				if(slide_active_d1 && (slide_progress_d1 != 10'd0)) begin
					if(slide_new_index_d1 == 2'd0)
						App_rd_addr_r <= read_addr_0 + (10'd640 - slide_progress_d1);
					else
						App_rd_addr_r <= read_addr_1 + (10'd640 - slide_progress_d1);
				end else if(read_addr_index_d1 == 2'd0)
					App_rd_addr_r <= read_addr_0;
				else if(read_addr_index_d1 == 2'd1)
					App_rd_addr_r <= read_addr_1;
				else if(read_addr_index_d1 == 2'd2)
					App_rd_addr_r <= read_addr_2;
				else if(read_addr_index_d1 == 2'd3)
					App_rd_addr_r <= read_addr_3;
			end
        else if(App_rd_en) begin
            // Increment within each segment. Only jump at the slide boundary;
            // avoid recomputing base+x+offset on every 125 MHz pixel request.
            if(output_x == SOURCE_WIDTH - 1) begin
                output_x <= 0;
                normal_row_base <= normal_row_base + SOURCE_WIDTH;
                slide_old_row_base <= slide_old_row_base + SOURCE_WIDTH;
                slide_new_row_base <= slide_new_row_base + SOURCE_WIDTH;
                if(slide_active_latch && slide_progress_latch != 0)
                    App_rd_addr_r <= slide_new_row_base + SOURCE_WIDTH;
                else if(slide_active_latch)
                    App_rd_addr_r <= slide_old_row_base + SOURCE_WIDTH;
                else
                    App_rd_addr_r <= normal_row_base + SOURCE_WIDTH;
            end else begin
                output_x <= output_x + 1'b1;
                if(slide_active_latch && output_x + 11'd1 == slide_progress_latch)
                    App_rd_addr_r <= slide_old_row_base;
                else
                    App_rd_addr_r <= App_rd_addr_r + 1'b1;
            end
        end
		else
			App_rd_addr_r <= App_rd_addr_r;
		//
		if(App_rd_en_r && burst_cnt + App_rd_en < BURST_SIZE)
			App_rd_en_d0 <= 1'b1;
		else
			App_rd_en_d0 <= 1'b0;
	
	end		
end
always@(posedge mem_clk or posedge rst)
begin
	if(rst == 1'b1)
	begin
		state <= S_IDLE;
		read_len_latch <= ZERO[ADDR_BITS - 1:0];
		
		//rd_burst_addr <= ZERO[ADDR_BITS - 1:0];
		//rd_burst_req <= 1'b0;
		App_rd_en_r <= 1'b0;
		
		read_cnt <= ZERO[ADDR_BITS - 1:0];
		fifo_aclr <= 1'b0;
		//rd_burst_len <= ZERO[BURST_BITS - 1:0];
		read_req_ack <= 1'b0;
	end
	else
		case(state)
			//idle state,waiting for read, read_req_d2 == '1' goto the 'S_ACK'
			S_IDLE:
			begin
				if(read_req_d2 == 1'b1 && Sdr_init_done)
				begin
					state <= S_ACK;
				end
				read_req_ack <= 1'b0;
			end
			//'S_ACK' state completes the read request response, the FIFO reset, the address latch, and the data length latch
			S_ACK:
			begin
				if(read_req_d2 == 1'b0)
				begin
					state <= S_CHECK_FIFO;
					fifo_aclr <= 1'b0;
					read_req_ack <= 1'b0;
				end
				else
				begin
					//read request response
					read_req_ack <= 1'b1;
					//FIFO reset
					fifo_aclr <= 1'b1;
					//select valid base address from read_addr_0 read_addr_1 read_addr_2 read_addr_3
					/*
					if(read_addr_index_d1 == 2'd0)
						App_rd_addr <= read_addr_0;
					else if(read_addr_index_d1 == 2'd1)
						App_rd_addr <= read_addr_1;
					else if(read_addr_index_d1 == 2'd2)
						App_rd_addr <= read_addr_2;
					else if(read_addr_index_d1 == 2'd3)
						App_rd_addr <= read_addr_3;
					*/
					//latch data length
					read_len_latch <= read_len_d1;
				end
				//read data counter reset, read_cnt <= 0;
				read_cnt <= ZERO[ADDR_BITS - 1:0];
			end
			S_CHECK_FIFO:
			begin
				//if there is a read request at this time, enter the 'S_ACK' state
				if(read_req_d2 == 1'b1)
				begin
					state <= S_ACK;
				end
				//if the FIFO space is a burst read request, goto burst read state
				else if(fifo_read_room && !App_wr_busy && !Sdr_busy && !Sdr_init_ref_vld)
				begin
					state <= S_READ_BURST;
					//rd_burst_len <= BURST_SIZE[BURST_BITS - 1:0];
					//rd_burst_req <= 1'b1;
					App_rd_en_r <= 1'b1;
				end
			end
			
			S_READ_BURST:
			begin
				//burst finish  
				if(rd_burst_finish == 1'b1)
				begin
					App_rd_en_r <= 1'b0;
					state <= S_READ_BURST_END;
					//read counter + burst length
					read_cnt <= read_cnt + BURST_SIZE[ADDR_BITS - 1:0];
					//the next burst read address is generated
					//rd_burst_addr <= rd_burst_addr + BURST_SIZE[ADDR_BITS - 1:0];
				end     
			end
			S_READ_BURST_END:
			begin
				//if there is a read request at this time, enter the 'S_ACK' state
				if(read_req_d2 == 1'b1)
				begin
					state <= S_ACK;
				end
				//if the read counter value is less than the frame length, continue read,
				//otherwise the read is complete
				else if(read_cnt < read_len_latch)
				begin
					state <= S_CHECK_FIFO;
				end
				else
				begin
					state <= S_END;
				end
			end
			S_END:
			begin
				state <= S_IDLE;
			end
			default:
				state <= S_IDLE;
		endcase
end
endmodule

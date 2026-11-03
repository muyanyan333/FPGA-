// Portable radix-2 DIT FFT: one butterfly uses two reads and two writes.
// 1024 samples at 48 kHz give 46.875 Hz/bin. Each stage scales by 1/2.
// No Xilinx FFT/FIR/floating-point IP is required.
module audio_fft1024(
    input wire clk, input wire rst,
    input wire sample_valid, input wire signed [23:0] sample,
    input wire [6:0] bar_addr, output wire [5:0] bar_level,
    output reg spectrum_ready
);
    // PCM is 16-bit in the upper half of the HDMI sample. Two guard bits
    // preserve butterfly headroom while keeping each FFT RAM port at 18 bits.
    reg signed [17:0] real_mem [0:2047];
    reg signed [17:0] imag_mem [0:2047];
    reg signed [17:0] mem_read_re, mem_read_im;
    reg [5:0] levels [0:79];
    reg capture_bank, ready_bank, ready_valid, process_bank;
    reg [9:0] capture_index;
    reg [3:0] stage;
    reg [9:0] group_base, butterfly_index;
    reg [6:0] scan_index;
    reg [3:0] state;
    reg signed [17:0] a_re, a_im, b_re, b_im;
    reg signed [17:0] result_a_re, result_a_im, result_b_re, result_b_im;
    reg signed [17:0] scan_re, scan_im;
    integer k;

    localparam IDLE=4'd0, READ_A=4'd1, LATCH_A=4'd2,
               READ_B=4'd3, LATCH_B=4'd4, CALC=4'd5,
               WRITE_A=4'd6, WRITE_B=4'd7,
               SCAN_READ=4'd8, SCAN_LATCH=4'd9, SCAN_ACC=4'd10;

    // Dense bass bins and progressively wider spacing toward the treble.
    function [9:0] map_bar;
        input [6:0] column;
        begin
            case (column)
                7'd0: map_bar = 10'd1;
                7'd1: map_bar = 10'd1;
                7'd2: map_bar = 10'd2;
                7'd3: map_bar = 10'd3;
                7'd4: map_bar = 10'd4;
                7'd5: map_bar = 10'd5;
                7'd6: map_bar = 10'd6;
                7'd7: map_bar = 10'd7;
                7'd8: map_bar = 10'd8;
                7'd9: map_bar = 10'd9;
                7'd10: map_bar = 10'd10;
                7'd11: map_bar = 10'd11;
                7'd12: map_bar = 10'd12;
                7'd13: map_bar = 10'd13;
                7'd14: map_bar = 10'd14;
                7'd15: map_bar = 10'd15;
                7'd16: map_bar = 10'd16;
                7'd17: map_bar = 10'd17;
                7'd18: map_bar = 10'd18;
                7'd19: map_bar = 10'd19;
                7'd20: map_bar = 10'd21;
                7'd21: map_bar = 10'd22;
                7'd22: map_bar = 10'd23;
                7'd23: map_bar = 10'd24;
                7'd24: map_bar = 10'd25;
                7'd25: map_bar = 10'd27;
                7'd26: map_bar = 10'd28;
                7'd27: map_bar = 10'd29;
                7'd28: map_bar = 10'd31;
                7'd29: map_bar = 10'd32;
                7'd30: map_bar = 10'd33;
                7'd31: map_bar = 10'd35;
                7'd32: map_bar = 10'd36;
                7'd33: map_bar = 10'd38;
                7'd34: map_bar = 10'd39;
                7'd35: map_bar = 10'd41;
                7'd36: map_bar = 10'd43;
                7'd37: map_bar = 10'd45;
                7'd38: map_bar = 10'd46;
                7'd39: map_bar = 10'd48;
                7'd40: map_bar = 10'd50;
                7'd41: map_bar = 10'd52;
                7'd42: map_bar = 10'd55;
                7'd43: map_bar = 10'd57;
                7'd44: map_bar = 10'd59;
                7'd45: map_bar = 10'd62;
                7'd46: map_bar = 10'd65;
                7'd47: map_bar = 10'd67;
                7'd48: map_bar = 10'd70;
                7'd49: map_bar = 10'd73;
                7'd50: map_bar = 10'd77;
                7'd51: map_bar = 10'd80;
                7'd52: map_bar = 10'd84;
                7'd53: map_bar = 10'd88;
                7'd54: map_bar = 10'd92;
                7'd55: map_bar = 10'd97;
                7'd56: map_bar = 10'd101;
                7'd57: map_bar = 10'd106;
                7'd58: map_bar = 10'd112;
                7'd59: map_bar = 10'd118;
                7'd60: map_bar = 10'd124;
                7'd61: map_bar = 10'd131;
                7'd62: map_bar = 10'd138;
                7'd63: map_bar = 10'd145;
                7'd64: map_bar = 10'd154;
                7'd65: map_bar = 10'd163;
                7'd66: map_bar = 10'd172;
                7'd67: map_bar = 10'd182;
                7'd68: map_bar = 10'd193;
                7'd69: map_bar = 10'd205;
                7'd70: map_bar = 10'd218;
                7'd71: map_bar = 10'd232;
                7'd72: map_bar = 10'd247;
                7'd73: map_bar = 10'd263;
                7'd74: map_bar = 10'd280;
                7'd75: map_bar = 10'd299;
                7'd76: map_bar = 10'd320;
                7'd77: map_bar = 10'd342;
                7'd78: map_bar = 10'd365;
                7'd79: map_bar = 10'd391;
                default: map_bar = 10'd391;
            endcase
        end
    endfunction

    function [9:0] reverse10;
        input [9:0] value;
        integer i;
        begin for(i=0;i<10;i=i+1) reverse10[i]=value[9-i]; end
    endfunction
    // The 1024-point FFT twiddles have exact quadrant symmetry. Decode only
    // the first 129 coefficients; reconstruct the others with sign changes.
    function [31:0] twiddle_base;
        input [7:0] index;
        begin
            case (index)
                8'd0: twiddle_base = {16'sd32767,16'sd0};
                8'd1: twiddle_base = {16'sd32766,-16'sd201};
                8'd2: twiddle_base = {16'sd32765,-16'sd402};
                8'd3: twiddle_base = {16'sd32761,-16'sd603};
                8'd4: twiddle_base = {16'sd32757,-16'sd804};
                8'd5: twiddle_base = {16'sd32752,-16'sd1005};
                8'd6: twiddle_base = {16'sd32745,-16'sd1206};
                8'd7: twiddle_base = {16'sd32737,-16'sd1407};
                8'd8: twiddle_base = {16'sd32728,-16'sd1608};
                8'd9: twiddle_base = {16'sd32717,-16'sd1809};
                8'd10: twiddle_base = {16'sd32705,-16'sd2009};
                8'd11: twiddle_base = {16'sd32692,-16'sd2210};
                8'd12: twiddle_base = {16'sd32678,-16'sd2410};
                8'd13: twiddle_base = {16'sd32663,-16'sd2611};
                8'd14: twiddle_base = {16'sd32646,-16'sd2811};
                8'd15: twiddle_base = {16'sd32628,-16'sd3012};
                8'd16: twiddle_base = {16'sd32609,-16'sd3212};
                8'd17: twiddle_base = {16'sd32589,-16'sd3412};
                8'd18: twiddle_base = {16'sd32567,-16'sd3612};
                8'd19: twiddle_base = {16'sd32545,-16'sd3811};
                8'd20: twiddle_base = {16'sd32521,-16'sd4011};
                8'd21: twiddle_base = {16'sd32495,-16'sd4210};
                8'd22: twiddle_base = {16'sd32469,-16'sd4410};
                8'd23: twiddle_base = {16'sd32441,-16'sd4609};
                8'd24: twiddle_base = {16'sd32412,-16'sd4808};
                8'd25: twiddle_base = {16'sd32382,-16'sd5007};
                8'd26: twiddle_base = {16'sd32351,-16'sd5205};
                8'd27: twiddle_base = {16'sd32318,-16'sd5404};
                8'd28: twiddle_base = {16'sd32285,-16'sd5602};
                8'd29: twiddle_base = {16'sd32250,-16'sd5800};
                8'd30: twiddle_base = {16'sd32213,-16'sd5998};
                8'd31: twiddle_base = {16'sd32176,-16'sd6195};
                8'd32: twiddle_base = {16'sd32137,-16'sd6393};
                8'd33: twiddle_base = {16'sd32098,-16'sd6590};
                8'd34: twiddle_base = {16'sd32057,-16'sd6786};
                8'd35: twiddle_base = {16'sd32014,-16'sd6983};
                8'd36: twiddle_base = {16'sd31971,-16'sd7179};
                8'd37: twiddle_base = {16'sd31926,-16'sd7375};
                8'd38: twiddle_base = {16'sd31880,-16'sd7571};
                8'd39: twiddle_base = {16'sd31833,-16'sd7767};
                8'd40: twiddle_base = {16'sd31785,-16'sd7962};
                8'd41: twiddle_base = {16'sd31736,-16'sd8157};
                8'd42: twiddle_base = {16'sd31685,-16'sd8351};
                8'd43: twiddle_base = {16'sd31633,-16'sd8545};
                8'd44: twiddle_base = {16'sd31580,-16'sd8739};
                8'd45: twiddle_base = {16'sd31526,-16'sd8933};
                8'd46: twiddle_base = {16'sd31470,-16'sd9126};
                8'd47: twiddle_base = {16'sd31414,-16'sd9319};
                8'd48: twiddle_base = {16'sd31356,-16'sd9512};
                8'd49: twiddle_base = {16'sd31297,-16'sd9704};
                8'd50: twiddle_base = {16'sd31237,-16'sd9896};
                8'd51: twiddle_base = {16'sd31176,-16'sd10087};
                8'd52: twiddle_base = {16'sd31113,-16'sd10278};
                8'd53: twiddle_base = {16'sd31050,-16'sd10469};
                8'd54: twiddle_base = {16'sd30985,-16'sd10659};
                8'd55: twiddle_base = {16'sd30919,-16'sd10849};
                8'd56: twiddle_base = {16'sd30852,-16'sd11039};
                8'd57: twiddle_base = {16'sd30783,-16'sd11228};
                8'd58: twiddle_base = {16'sd30714,-16'sd11417};
                8'd59: twiddle_base = {16'sd30643,-16'sd11605};
                8'd60: twiddle_base = {16'sd30571,-16'sd11793};
                8'd61: twiddle_base = {16'sd30498,-16'sd11980};
                8'd62: twiddle_base = {16'sd30424,-16'sd12167};
                8'd63: twiddle_base = {16'sd30349,-16'sd12353};
                8'd64: twiddle_base = {16'sd30273,-16'sd12539};
                8'd65: twiddle_base = {16'sd30195,-16'sd12725};
                8'd66: twiddle_base = {16'sd30117,-16'sd12910};
                8'd67: twiddle_base = {16'sd30037,-16'sd13094};
                8'd68: twiddle_base = {16'sd29956,-16'sd13279};
                8'd69: twiddle_base = {16'sd29874,-16'sd13462};
                8'd70: twiddle_base = {16'sd29791,-16'sd13645};
                8'd71: twiddle_base = {16'sd29706,-16'sd13828};
                8'd72: twiddle_base = {16'sd29621,-16'sd14010};
                8'd73: twiddle_base = {16'sd29534,-16'sd14191};
                8'd74: twiddle_base = {16'sd29447,-16'sd14372};
                8'd75: twiddle_base = {16'sd29358,-16'sd14553};
                8'd76: twiddle_base = {16'sd29268,-16'sd14732};
                8'd77: twiddle_base = {16'sd29177,-16'sd14912};
                8'd78: twiddle_base = {16'sd29085,-16'sd15090};
                8'd79: twiddle_base = {16'sd28992,-16'sd15269};
                8'd80: twiddle_base = {16'sd28898,-16'sd15446};
                8'd81: twiddle_base = {16'sd28803,-16'sd15623};
                8'd82: twiddle_base = {16'sd28706,-16'sd15800};
                8'd83: twiddle_base = {16'sd28609,-16'sd15976};
                8'd84: twiddle_base = {16'sd28510,-16'sd16151};
                8'd85: twiddle_base = {16'sd28411,-16'sd16325};
                8'd86: twiddle_base = {16'sd28310,-16'sd16499};
                8'd87: twiddle_base = {16'sd28208,-16'sd16673};
                8'd88: twiddle_base = {16'sd28105,-16'sd16846};
                8'd89: twiddle_base = {16'sd28001,-16'sd17018};
                8'd90: twiddle_base = {16'sd27896,-16'sd17189};
                8'd91: twiddle_base = {16'sd27790,-16'sd17360};
                8'd92: twiddle_base = {16'sd27683,-16'sd17530};
                8'd93: twiddle_base = {16'sd27575,-16'sd17700};
                8'd94: twiddle_base = {16'sd27466,-16'sd17869};
                8'd95: twiddle_base = {16'sd27356,-16'sd18037};
                8'd96: twiddle_base = {16'sd27245,-16'sd18204};
                8'd97: twiddle_base = {16'sd27133,-16'sd18371};
                8'd98: twiddle_base = {16'sd27019,-16'sd18537};
                8'd99: twiddle_base = {16'sd26905,-16'sd18703};
                8'd100: twiddle_base = {16'sd26790,-16'sd18868};
                8'd101: twiddle_base = {16'sd26674,-16'sd19032};
                8'd102: twiddle_base = {16'sd26556,-16'sd19195};
                8'd103: twiddle_base = {16'sd26438,-16'sd19357};
                8'd104: twiddle_base = {16'sd26319,-16'sd19519};
                8'd105: twiddle_base = {16'sd26198,-16'sd19680};
                8'd106: twiddle_base = {16'sd26077,-16'sd19841};
                8'd107: twiddle_base = {16'sd25955,-16'sd20000};
                8'd108: twiddle_base = {16'sd25832,-16'sd20159};
                8'd109: twiddle_base = {16'sd25708,-16'sd20317};
                8'd110: twiddle_base = {16'sd25582,-16'sd20475};
                8'd111: twiddle_base = {16'sd25456,-16'sd20631};
                8'd112: twiddle_base = {16'sd25329,-16'sd20787};
                8'd113: twiddle_base = {16'sd25201,-16'sd20942};
                8'd114: twiddle_base = {16'sd25072,-16'sd21096};
                8'd115: twiddle_base = {16'sd24942,-16'sd21250};
                8'd116: twiddle_base = {16'sd24811,-16'sd21403};
                8'd117: twiddle_base = {16'sd24680,-16'sd21554};
                8'd118: twiddle_base = {16'sd24547,-16'sd21705};
                8'd119: twiddle_base = {16'sd24413,-16'sd21856};
                8'd120: twiddle_base = {16'sd24279,-16'sd22005};
                8'd121: twiddle_base = {16'sd24143,-16'sd22154};
                8'd122: twiddle_base = {16'sd24007,-16'sd22301};
                8'd123: twiddle_base = {16'sd23870,-16'sd22448};
                8'd124: twiddle_base = {16'sd23731,-16'sd22594};
                8'd125: twiddle_base = {16'sd23592,-16'sd22739};
                8'd126: twiddle_base = {16'sd23452,-16'sd22884};
                8'd127: twiddle_base = {16'sd23311,-16'sd23027};
                8'd128: twiddle_base = {16'sd23170,-16'sd23170};
                default: twiddle_base = {16'sd32767,16'sd0};
            endcase
        end
    endfunction
    function [31:0] twiddle;
        input [8:0] index;
        reg [7:0] base_index;
        reg [31:0] base_word;
        reg signed [15:0] re, im;
        begin
            if (index <= 9'd128)
                base_index = index[7:0];
            else if (index <= 9'd256)
                base_index = 9'd256 - index;
            else if (index <= 9'd384)
                base_index = index - 9'd256;
            else
                base_index = 10'd512 - {1'b0,index};
            base_word = twiddle_base(base_index);
            re = base_word[31:16];
            im = base_word[15:0];
            if (index <= 9'd128) twiddle = {re,im};
            else if (index <= 9'd256) twiddle = {-im,-re};
            else if (index <= 9'd384) twiddle = {im,-re};
            else twiddle = {-re,im};
        end
    endfunction
    function [18:0] abs18;
        input signed [17:0] value;
        begin abs18 = value[17] ? {1'b0,(~value+1'b1)} : {1'b0,value}; end
    endfunction

    // Six restoring steps approximate the reference square-root magnitude
    // without vendor IP or a general-purpose divider.
    function [5:0] sqrt12;
        input [11:0] number;
        reg [13:0] remainder;
        reg [5:0] root;
        reg [13:0] trial;
        integer bit_pair;
        begin
            remainder = 14'd0;
            root = 6'd0;
            for (bit_pair=5; bit_pair>=0; bit_pair=bit_pair-1) begin
                remainder = (remainder << 2) |
                            ((number >> (bit_pair*2)) & 12'd3);
                trial = ({8'd0,root} << 2) | 14'd1;
                if (remainder >= trial) begin
                    remainder = remainder - trial;
                    root = (root << 1) | 6'd1;
                end else root = root << 1;
            end
            sqrt12 = root;
        end
    endfunction

    wire [9:0] half_span = 10'd1 << stage;
    wire [10:0] span = 11'd2 << stage;
    wire [9:0] index_a = group_base + butterfly_index;
    wire [9:0] index_b = index_a + half_span;
    wire [8:0] tw_index = butterfly_index << (9-stage);
    wire [31:0] tw_word = twiddle(tw_index);
    wire signed [15:0] tw_re = tw_word[31:16];
    wire signed [15:0] tw_im = tw_word[15:0];
    wire signed [34:0] mult_re = b_re*tw_re - b_im*tw_im;
    wire signed [34:0] mult_im = b_re*tw_im + b_im*tw_re;
    wire signed [19:0] t_re = mult_re >>> 15;
    wire signed [19:0] t_im = mult_im >>> 15;
    wire [19:0] scan_magnitude = abs18(scan_re) + abs18(scan_im);
    wire [21:0] scan_scaled = scan_magnitude >> 3;
    wire [5:0] scan_root = sqrt12(scan_scaled > 22'd4095 ?
                                    12'd4095 : scan_scaled[11:0]);
    wire [5:0] scan_height = scan_root > 6'd50 ? 6'd50 : scan_root;
    assign bar_level = levels[bar_addr];

    // One synchronous read port and one write port per memory allow TD to
    // infer block RAM. Capture takes precedence over an FFT write for one clk.
    wire fft_write_a = state == WRITE_A;
    wire fft_write_b = state == WRITE_B;
    wire mem_write_en = sample_valid || fft_write_a || fft_write_b;
    wire [10:0] mem_write_addr = sample_valid ?
        {capture_bank,reverse10(capture_index)} :
        {process_bank,fft_write_b ? index_b : index_a};
    wire signed [17:0] mem_write_re = sample_valid ?
        {{2{sample[23]}},sample[23:8]} :
        fft_write_b ? result_b_re : result_a_re;
    wire signed [17:0] mem_write_im = sample_valid ? 18'sd0 :
        fft_write_b ? result_b_im : result_a_im;
    wire mem_read_en = !sample_valid &&
        (state == READ_A || state == READ_B || state == SCAN_READ);
    wire [10:0] mem_read_addr = {process_bank,
        state == READ_A ? index_a : state == READ_B ? index_b : map_bar(scan_index)};

    always @(posedge clk) begin
        if (mem_write_en && !rst) begin
            real_mem[mem_write_addr] <= mem_write_re;
            imag_mem[mem_write_addr] <= mem_write_im;
        end
        if (mem_read_en) begin
            mem_read_re <= real_mem[mem_read_addr];
            mem_read_im <= imag_mem[mem_read_addr];
        end
    end

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            capture_bank <= 1'b0; ready_bank <= 1'b0;
            ready_valid <= 1'b0; process_bank <= 1'b0;
            capture_index <= 10'd0; stage <= 4'd0;
            group_base <= 10'd0; butterfly_index <= 10'd0;
            scan_index <= 10'd0; state <= IDLE;
            spectrum_ready <= 1'b0;
            a_re <= 24'sd0; a_im <= 24'sd0;
            b_re <= 24'sd0; b_im <= 24'sd0;
            result_a_re <= 24'sd0; result_a_im <= 24'sd0;
            result_b_re <= 24'sd0; result_b_im <= 24'sd0;
            scan_re <= 24'sd0; scan_im <= 24'sd0;
            for(k=0;k<80;k=k+1) levels[k] <= 6'd0;
        end else begin
            if (sample_valid) begin
                if (capture_index == 10'd1023) begin
                    capture_index <= 10'd0;
                    ready_bank <= capture_bank;
                    ready_valid <= 1'b1;
                    capture_bank <= ~capture_bank;
                end else capture_index <= capture_index + 1'b1;
            end
            // A captured sample owns the RAM write port for this clock.
            // FFT processing pauses for that clock so synthesis can share one write port.
            if (!sample_valid) case(state)
                IDLE: if (ready_valid) begin
                    process_bank <= ready_bank;
                    ready_valid <= 1'b0;
                    stage <= 4'd0;
                    group_base <= 10'd0;
                    butterfly_index <= 10'd0;
                    state <= READ_A;
                end
                READ_A: state <= LATCH_A;
                LATCH_A: begin
                    a_re <= mem_read_re;
                    a_im <= mem_read_im;
                    state <= READ_B;
                end
                READ_B: state <= LATCH_B;
                LATCH_B: begin
                    b_re <= mem_read_re;
                    b_im <= mem_read_im;
                    state <= CALC;
                end
                CALC: begin
                    result_a_re <= ($signed({a_re[17],a_re}) + t_re) >>> 1;
                    result_a_im <= ($signed({a_im[17],a_im}) + t_im) >>> 1;
                    result_b_re <= ($signed({a_re[17],a_re}) - t_re) >>> 1;
                    result_b_im <= ($signed({a_im[17],a_im}) - t_im) >>> 1;
                    state <= WRITE_A;
                end
                WRITE_A: begin
                    state <= WRITE_B;
                end
                WRITE_B: begin
                    if (butterfly_index + 10'd1 < half_span)
                        butterfly_index <= butterfly_index + 1'b1;
                    else if ({1'b0,group_base} + span < 11'd1024) begin
                        butterfly_index <= 10'd0;
                        group_base <= group_base + span[9:0];
                    end else if (stage < 4'd9) begin
                        stage <= stage + 1'b1;
                        butterfly_index <= 10'd0;
                        group_base <= 10'd0;
                    end else begin
                        scan_index <= 7'd0;
                        state <= SCAN_READ;
                    end
                    if (state == WRITE_B && !(stage==4'd9 &&
                        butterfly_index + 10'd1 >= half_span &&
                        {1'b0,group_base}+span >= 11'd1024)) state <= READ_A;
                end
                SCAN_READ: state <= SCAN_LATCH;
                SCAN_LATCH: begin
                    scan_re <= mem_read_re;
                    scan_im <= mem_read_im;
                    state <= SCAN_ACC;
                end
                SCAN_ACC: begin
                    levels[scan_index] <= scan_height > levels[scan_index] ?
                        scan_height : (levels[scan_index] > 6'd2 ?
                        levels[scan_index] - 6'd2 : 6'd0);
                    if (scan_index == 7'd79) begin
                        spectrum_ready <= 1'b1;
                        state <= IDLE;
                    end else begin
                        scan_index <= scan_index + 1'b1;
                        state <= SCAN_READ;
                    end
                end
                default: state <= IDLE;
            endcase
        end
    end
endmodule


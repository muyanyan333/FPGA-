`timescale 1ns/1ps
// Four frame-latched views: raw, grayscale, binary edges, raw+cyan edges.
module camera_edge_view #(
    parameter integer WIDTH=640, HEIGHT=480,
    parameter integer DEBOUNCE_CYCLES=500000
)(
    input wire clk, rst,
    input wire key_mode_n, key_level_n,
    input wire in_vs, in_de,
    input wire [23:0] in_rgb,
    output wire out_vs, out_de,
    output wire [23:0] out_rgb
);
    (* async_reg="true" *) reg [1:0] km_sync, kl_sync;
    reg km_state, kl_state;
    reg [19:0] km_count, kl_count;
    reg [1:0] mode_request, level_request;
    reg [1:0] mode, level;
    reg prev_vs;
    always @(posedge clk or posedge rst) begin
        if(rst) begin
            km_sync<=3; kl_sync<=3; km_state<=1; kl_state<=1;
            km_count<=0; kl_count<=0;
            mode_request<=0; level_request<=1; mode<=0; level<=1; prev_vs<=0;
        end else begin
            km_sync<={km_sync[0],key_mode_n};
            kl_sync<={kl_sync[0],key_level_n};
            if(km_sync[1]==km_state) km_count<=0;
            else if(km_count==DEBOUNCE_CYCLES-1) begin
                km_state<=km_sync[1]; km_count<=0;
                if(!km_sync[1]) mode_request<=mode_request+2'd1;
            end else km_count<=km_count+1'b1;
            if(kl_sync[1]==kl_state) kl_count<=0;
            else if(kl_count==DEBOUNCE_CYCLES-1) begin
                kl_state<=kl_sync[1]; kl_count<=0;
                if(!kl_sync[1]) level_request<=level_request+2'd1;
            end else kl_count<=kl_count+1'b1;
            prev_vs<=in_vs;
            if(prev_vs!=in_vs) begin mode<=mode_request; level<=level_request; end
        end
    end
    wire [11:0] magnitude;
    wire [23:0] unused_binary;
    sobel_stream #(.WIDTH(WIDTH),.HEIGHT(HEIGHT)) u_sobel (
        .clk(clk),.rst(rst),.in_vs(in_vs),.in_de(in_de),.in_rgb(in_rgb),
        .out_vs(out_vs),.out_de(out_de),.out_rgb(unused_binary),
        .out_magnitude(magnitude)
    );
    reg [23:0] rgb0,rgb1,rgb2;
    always @(posedge clk or posedge rst) begin
        if(rst) begin rgb0<=0; rgb1<=0; rgb2<=0; end
        else begin rgb0<=in_rgb; rgb1<=rgb0; rgb2<=rgb1; end
    end
    wire [7:0] gray={2'b0,rgb2[23:18]}+{1'b0,rgb2[15:9]}+{2'b0,rgb2[7:2]};
    wire [11:0] threshold=level==0 ? 12'd24 : level==1 ? 12'd48 :
                          level==2 ? 12'd96 : 12'd192;
    wire edge_on=magnitude>=threshold;
    wire [23:0] view_rgb=mode==0 ? rgb2 : mode==1 ? {gray,gray,gray} :
                              mode==2 ? (edge_on ? 24'hffffff : 24'd0) :
                                        (edge_on ? 24'h00ffff : rgb2);
    // Upper-left indicators: top row=view 1..4, second row=threshold 1..4.
    reg [10:0] x,y;
    reg de_prev,vs_prev;
    always @(posedge clk or posedge rst) begin
        if(rst) begin x<=0;y<=0;de_prev<=0;vs_prev<=0;end
        else begin
            de_prev<=out_de; vs_prev<=out_vs;
            if(out_de) x<=x+1'b1; else x<=0;
            if(de_prev && !out_de) y<=y+1'b1;
            if(vs_prev!=out_vs) begin x<=0;y<=0;end
        end
    end
    wire marker=x<32 && y<16;
    wire selected=y<8 ? x[4:3]==mode : x[4:3]==level;
    assign out_rgb=!out_de ? 24'd0 : marker ?
                   (selected ? (y<8 ? 24'h00ff00 : 24'hffff00) : 24'h202020) : view_rgb;
endmodule

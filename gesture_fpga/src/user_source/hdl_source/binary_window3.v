`timescale 1ns/1ps
// Small distributed row buffers. Each enabled sample is one raster pixel.
module binary_window3 #(parameter WIDTH=160, parameter BORDER=0)(
    input wire clk,rst,en,pixel,
    input wire [10:0] x,y,
    output reg out_en,out_pixel,out_center,
    output reg [10:0] out_x,out_y
);
    reg row1[0:WIDTH-1],row2[0:WIDTH-1];
    reg a0,a1,b0,b1,c0,c1;
    wire t=row2[x],m=row1[x];
    wire [3:0] sum={3'd0,a0}+{3'd0,a1}+{3'd0,t}+
                   {3'd0,b0}+{3'd0,b1}+{3'd0,m}+
                   {3'd0,c0}+{3'd0,c1}+{3'd0,pixel};
    always @(posedge clk or posedge rst) begin
        if(rst) begin
            a0<=0;a1<=0;b0<=0;b1<=0;c0<=0;c1<=0;
            out_en<=0;out_pixel<=0;out_center<=0;out_x<=0;out_y<=0;
        end else begin
            out_en<=en;
            if(en) begin
                row2[x]<=row1[x];row1[x]<=pixel;
                if(x==0) begin a0<=0;b0<=0;c0<=0;end
                else begin a0<=a1;b0<=b1;c0<=c1;end
                a1<=t;b1<=m;c1<=pixel;
                out_x<=x;out_y<=y;
                out_center<=(x>=2 && y>=2) ? b1 : 1'b0;
                out_pixel<=(x>=2 && y>=2) &&
                           (BORDER ? (b1 && sum!=9) : sum>=5);
            end
        end
    end
endmodule

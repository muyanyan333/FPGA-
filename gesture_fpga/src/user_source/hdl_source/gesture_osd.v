`timescale 1ns/1ps
module gesture_osd #(parameter WIDTH=640,HEIGHT=480)(
    input wire [10:0] x,y,
    input wire ready,hand,
    input wire [2:0] gesture,
    input wire [10:0] left,right,top,bottom,
    input wire [6:0] fill_percent,
    input wire [3:0] finger_groups,
    output wire on,
    output wire [23:0] rgb,
    input wire [6:0] envelope_percent, input wire [1:0] motion_state, input wire [6:0] motion_distance, input wire [2:0] motion_reason
);
    function [34:0] font;
        input [7:0] c;
        begin case(c)
        "A":font={5'b01110,5'b10001,5'b10001,5'b11111,5'b10001,5'b10001,5'b10001};
        "D":font={5'b11110,5'b10001,5'b10001,5'b10001,5'b10001,5'b10001,5'b11110};
        "E":font={5'b11111,5'b10000,5'b10000,5'b11110,5'b10000,5'b10000,5'b11111};
        "F":font={5'b11111,5'b10000,5'b10000,5'b11110,5'b10000,5'b10000,5'b10000};
        "G":font={5'b01110,5'b10001,5'b10000,5'b10111,5'b10001,5'b10001,5'b01110};
        "I":font={5'b11111,5'b00100,5'b00100,5'b00100,5'b00100,5'b00100,5'b11111};
        "B":font={5'b11110,5'b10001,5'b10001,5'b11110,5'b10001,5'b10001,5'b11110};
        "C":font={5'b01111,5'b10000,5'b10000,5'b10000,5'b10000,5'b10000,5'b01111};
        "M":font={5'b10001,5'b11011,5'b10101,5'b10101,5'b10001,5'b10001,5'b10001};
        "H":font={5'b10001,5'b10001,5'b10001,5'b11111,5'b10001,5'b10001,5'b10001};
        "L":font={5'b10000,5'b10000,5'b10000,5'b10000,5'b10000,5'b10000,5'b11111};
        "R":font={5'b11110,5'b10001,5'b10001,5'b11110,5'b10100,5'b10010,5'b10001};
        "K":font={5'b10001,5'b10010,5'b10100,5'b11000,5'b10100,5'b10010,5'b10001};
        "N":font={5'b10001,5'b11001,5'b11001,5'b10101,5'b10011,5'b10011,5'b10001};
        "O":font={5'b01110,5'b10001,5'b10001,5'b10001,5'b10001,5'b10001,5'b01110};
        "P":font={5'b11110,5'b10001,5'b10001,5'b11110,5'b10000,5'b10000,5'b10000};
        "S":font={5'b01111,5'b10000,5'b10000,5'b01110,5'b00001,5'b00001,5'b11110};
        "T":font={5'b11111,5'b00100,5'b00100,5'b00100,5'b00100,5'b00100,5'b00100};
        "U":font={5'b10001,5'b10001,5'b10001,5'b10001,5'b10001,5'b10001,5'b01110};
        "W":font={5'b10001,5'b10001,5'b10001,5'b10101,5'b10101,5'b10101,5'b01010};
        "0":font={5'b01110,5'b10001,5'b10011,5'b10101,5'b11001,5'b10001,5'b01110};
        "1":font={5'b00100,5'b01100,5'b00100,5'b00100,5'b00100,5'b00100,5'b01110};
        "2":font={5'b01110,5'b10001,5'b00001,5'b00010,5'b00100,5'b01000,5'b11111};
        "3":font={5'b11110,5'b00001,5'b00001,5'b01110,5'b00001,5'b00001,5'b11110};
        "4":font={5'b00010,5'b00110,5'b01010,5'b10010,5'b11111,5'b00010,5'b00010};
        "5":font={5'b11111,5'b10000,5'b10000,5'b11110,5'b00001,5'b00001,5'b11110};
        "6":font={5'b01110,5'b10000,5'b10000,5'b11110,5'b10001,5'b10001,5'b01110};
        "7":font={5'b11111,5'b00001,5'b00010,5'b00100,5'b01000,5'b01000,5'b01000};
        "8":font={5'b01110,5'b10001,5'b10001,5'b01110,5'b10001,5'b10001,5'b01110};
        "9":font={5'b01110,5'b10001,5'b10001,5'b01111,5'b00001,5'b00001,5'b01110};
        ":":font={5'b00000,5'b00100,5'b00100,5'b00000,5'b00100,5'b00100,5'b00000};
        default:font=0;
        endcase end
    endfunction
    wire text_area=x>=36 && x<380 && y<46;
    wire second_line=y>=24;
    wire [11:0] center_sum={1'b0,left}+{1'b0,right};
    wire [10:0] center_x=center_sum[11:1];
    wire [4:0] index=(x-40)/12;
    reg [55:0] word;
    always @* begin
        if(!ready) word="WAIT   ";
        else case(gesture)
            0:word="NONE   ";1:word="OPEN   ";2:word="FIST   ";6:word="MULTI  ";7:word="BGCHECK";4:word="LEFT   ";5:word="RIGHT  ";default:word="UNKNOWN";
        endcase
    end
    reg [7:0] c;
    always @* begin
        c=" ";
        if(second_line) begin
            case(index)
            0:c="D";1:c=":";2:c="0"+(motion_distance/10);3:c="0"+(motion_distance%10);
            5:c="R";6:c=":";7:c="0"+motion_reason;
            9:c="C";10:c=":";11:c="0"+center_x/100;
            12:c="0"+(center_x%100)/10;13:c="0"+center_x%10;
            endcase
        end else if(index<7) c=word[55-index*8 -: 8];
        else case(index)
            8:c="F";9:c=":";10:c=fill_percent==100 ? "1" : "0";
            11:c="0"+(fill_percent%100)/10;12:c="0"+fill_percent%10;
            14:c="G";15:c=":";16:c="0"+finger_groups;
            24:c="M";25:c=":";26:c="0"+motion_state;
            18:c="E";19:c=":";20:c=envelope_percent==100 ? "1" : "0";
            21:c="0"+(envelope_percent%100)/10;22:c="0"+envelope_percent%10;
        endcase
    end
    wire [34:0] glyph=font(c);
    wire [3:0] col=((x-40)%12)>>1;
    wire [3:0] row=(y-(second_line ? 28 : 4))>>1;
    wire ink=x>=40 && x<364 && ((y>=4 && y<18) || (y>=28 && y<42)) && col<5 && glyph[34-row*5-col];
    wire [10:0] l=left<<2,r=(right<<2)+3,t=top<<2,b=(bottom<<2)+3;
    wire box=ready && hand && x>=l && x<=r && y>=t && y<=b && (x==l || x==r || y==t || y==b);
    wire roi=x>=WIDTH/16 && x<WIDTH*15/16 && y>=HEIGHT/16 && y<HEIGHT-8 &&
             (x==WIDTH/16 || x==WIDTH*15/16-1 || y==HEIGHT/16 || y==HEIGHT-9);
    wire [23:0] color=ready && gesture>=4 && gesture<=5 ? 24'h00ffff : !ready ? 24'hffff00 : gesture==1 ? 24'h00ff00 : gesture==2 ? 24'hffff00 : 24'hffffff;
    assign on=text_area || box || roi;
    assign rgb=text_area ? (ink ? color : 24'd0) : box ? color : 24'h404040;
endmodule

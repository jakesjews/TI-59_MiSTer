// SPDX-License-Identifier: GPL-2.0-or-later
// Capture the multiplexed LED strobes, including leading-zero suppression.
module ti59_display (
    input wire clk, reset, frame, retired, idle,
    input wire [3:0] digit, r5,
    input wire [63:0] a, b,
    input wire [15:0] fa,
    output reg [95:0] segments,
    output reg calc
);
    reg suppress;
    reg [1:0] decay [0:11];
    reg [1:0] calc_decay;
    wire [3:0] scan = digit - 4'd1;
    wire [3:0] value = a[{scan,2'b00} +: 4];
    wire [3:0] format = b[{scan,2'b00} +: 4];
    reg zero, blank;
    reg [7:0] glyph;
    function automatic [6:0] seven(input [3:0] v);
        // gfedcba
        case(v)
            0:seven=7'h3f; 1:seven=7'h06; 2:seven=7'h5b; 3:seven=7'h4f;
            4:seven=7'h66; 5:seven=7'h6d; 6:seven=7'h7d; 7:seven=7'h07;
            8:seven=7'h7f; 9:seven=7'h6f;10:seven=7'h77;11:seven=7'h7c;
           12:seven=7'h39;13:seven=7'h5e;14:seven=7'h79;15:seven=7'h71;
        endcase
    endfunction
    always @* begin
        zero = (scan == 13) ? 1'b1 : suppress;
        if (scan == 3 || r5 == scan || format[3]) zero = 0;
        if (scan == 2) zero = 1;
        blank = format == 3 || format == 7 || (format <= 4 && zero && value == 0);
        glyph = 0;
        if (!blank) case (format[2:0])
            0,1: glyph[6:0] = seven(value);
            2: glyph[6:0] = 7'h22;
            4: glyph[6:0] = 7'h02;
            5: glyph[6:0] = value == 0 && !format[3] ? 7'h40 : 7'h63;
            6: glyph[6:0] = 7'h40;
            default: begin end
        endcase
        glyph[7] = r5 == scan;
        if (!blank && format <= 1 && value != 0) zero = 0;
    end
    always @(posedge clk) begin
        if (reset) begin
            segments <= 0; suppress <= 1; calc <= 0; calc_decay <= 0;
            for(integer i=0;i<12;i=i+1) decay[i] <= 0;
        end else begin
            if (frame) begin
                for(integer i=0;i<12;i=i+1) begin
                    if (decay[i] != 0) decay[i] <= decay[i] - 2'd1;
                    else segments[i*8 +: 8] <= 0;
                end
                if (calc_decay != 0) calc_decay <= calc_decay - 2'd1;
                else calc <= 0;
            end
            if (retired) begin
                if (idle ? fa[14] : (fa != 0)) begin calc <= 1; calc_decay <= 2; end
                if (idle && scan >= 2 && scan <= 13) begin
                    segments[(scan-2)*8 +: 8] <= glyph;
                    decay[scan-2] <= 2;
                    suppress <= zero;
                end
            end
        end
    end
endmodule

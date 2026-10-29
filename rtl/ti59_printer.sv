// SPDX-License-Identifier: GPL-2.0-or-later
// Instruction-visible TMC0251 / PC-100 thermal printer. Twenty 6-bit glyphs
// arrive right-to-left. BUSY follows the PHI-derived instruction clock, including
// its idle divide-by-four. The paper is a 128x512 circular dot bitmap.
module ti59_printer (
    input wire clk, reset, clear_paper, retired,
    input wire [3:0] cmd,
    input wire [6:0] data,
    output wire busy, motor,
    input wire [15:0] read_addr,
    output wire pixel,
    output reg [8:0] paper_head,
    output reg line_printed,
    output reg [119:0] last_line
);
    reg paper [0:65535];
    reg [7:0] font [0:511];
    initial $readmemh("roms/printer_font.hex",font);
    reg [5:0] buffer [0:19];
    reg [4:0] pos;
    reg armed;
    reg [1:0] func_left;
    reg [17:0] func_chars;
    reg [12:0] busy_cycles, cycle_total, advance_phase;
    reg [4:0] advance_total;
    wire [13:0] advance_next = {1'b0,advance_phase}+{9'd0,advance_total};
    // Measured instruction counts cross-checked against Calc-U-59's PC-100
    // recording analysis. Rasterization and animation do not block the CPU.
    localparam [12:0] LINE_CYCLES=4165, FEED_CYCLES=1370;
    localparam [2:0] IDLE=0, CLEAR_ALL=1, CLEAR_LINE=2, FONT_WAIT=3, DRAW=4;
    reg [2:0] state;
    reg [15:0] wipe;
    reg [8:0] line_base;
    reg [4:0] column;
    reg [3:0] row;
    reg [2:0] dot_x;
    reg [4:0] glyph_q;
    wire [5:0] glyph = last_line[(19-int'(column))*6 +: 6];
    wire [8:0] font_addr = {glyph,row[3:1]};
    wire [8:0] draw_y = line_base + 9'd1 + {5'd0,row};
    wire [6:0] draw_x = 7'd4 + {2'd0,column}*7'd6 + {4'd0,dot_x};
    assign busy = busy_cycles != 0 || state == CLEAR_ALL;
    assign motor = busy_cycles != 0; // RAM initialization/clear is silent.

    // TI function names, per the hardware guide. Each tuple reads left-to-right.
    function automatic [18:0] mnemonic(input [6:0] code);
        case (code)
            7'h00: mnemonic={1'b1,6'd0,6'd0,6'd0};
            7'h11: mnemonic={1'b1,6'd0,6'd52,6'd0}; // =
            7'h12: mnemonic={1'b1,6'd0,6'd16,6'd0}; // -
            7'h13: mnemonic={1'b1,6'd0,6'd39,6'd0}; // +
            7'h16: mnemonic={1'b1,6'd0,6'd58,6'd0}; // divide
            7'h17: mnemonic={1'b1,6'd0,6'd40,6'd0}; // multiply
            7'h1a: mnemonic={1'b1,6'd40,6'd42,6'd37};
            7'h1b: mnemonic={1'b1,6'd37,6'd54,6'd0};
            7'h21: mnemonic={1'b1,6'd13,6'd23,6'd29};
            7'h22: mnemonic={1'b1,6'd20,6'd25,6'd34};
            7'h23: mnemonic={1'b1,6'd14,6'd27,6'd31};
            7'h26: mnemonic={1'b1,6'd13,6'd15,6'd0};
            7'h27: mnemonic={1'b1,6'd39,6'd51,6'd16};
            7'h2d: mnemonic={1'b1,6'd15,6'd15,6'd0};
            7'h31: mnemonic={1'b1,6'd44,6'd54,6'd0};
            7'h33: mnemonic={1'b1,6'd40,6'd56,6'd0};
            7'h36: mnemonic={1'b1,6'd2,6'd51,6'd40};
            7'h3c: mnemonic={1'b1,6'd42,6'd40,6'd0};
            7'h3d: mnemonic={1'b1,6'd36,6'd50,6'd37};
            7'h51: mnemonic={1'b1,6'd23,6'd25,6'd40};
            7'h53: mnemonic={1'b1,6'd27,6'd29,6'd24};
            7'h54: mnemonic={1'b1,6'd0,6'd49,6'd0};
            7'h56: mnemonic={1'b1,6'd13,6'd26,6'd30};
            7'h57: mnemonic={1'b1,6'd30,6'd20,6'd25};
            7'h5d: mnemonic={1'b1,6'd31,6'd11,6'd25};
            7'h61: mnemonic={1'b1,6'd30,6'd33,6'd24};
            7'h66: mnemonic={1'b1,6'd30,6'd31,6'd26};
            7'h67: mnemonic={1'b1,6'd0,6'd43,6'd0};
            7'h68: mnemonic={1'b1,6'd29,6'd13,6'd23};
            7'h69: mnemonic={1'b1,6'd63,6'd39,6'd0};
            7'h70: mnemonic={1'b1,6'd15,6'd29,6'd29};
            7'h71: mnemonic={1'b1,6'd0,6'd45,6'd0};
            7'h72: mnemonic={1'b1,6'd0,6'd46,6'd0};
            7'h73: mnemonic={1'b1,6'd23,6'd29,6'd25};
            7'h74: mnemonic={1'b1,6'd29,6'd33,6'd25};
            7'h76: mnemonic={1'b1,6'd19,6'd23,6'd31};
            7'h78: mnemonic={1'b1,6'd30,6'd31,6'd27};
            7'h7a: mnemonic={1'b1,6'd18,6'd31,6'd26};
            7'h7c: mnemonic={1'b1,6'd20,6'd17,6'd0};
            default: mnemonic=0;
        endcase
    endfunction
    wire [18:0] name_codes = mnemonic(data);
    wire [8:0] wipe_y = line_base + wipe[15:7];
    // Keep both RAM ports in the standard synchronous template. Gating the
    // read data before its register prevents Cyclone V block-RAM inference.
    reg paper_q;
    assign pixel = state != CLEAR_ALL && paper_q;
    wire paper_we = !reset && !clear_paper &&
                    (state==CLEAR_ALL || state==CLEAR_LINE || state==DRAW);
    wire [15:0] paper_waddr = state==CLEAR_ALL ? wipe :
                             state==CLEAR_LINE ? {wipe_y,wipe[6:0]} : {draw_y,draw_x};
    always @(posedge clk) begin
        paper_q <= paper[read_addr];
        if (paper_we) paper[paper_waddr] <= state==DRAW && dot_x<5 && glyph_q[4-dot_x];
    end
    always @(posedge clk) begin
        glyph_q <= 5'(font[font_addr]);
        line_printed <= 0;
        if (reset || clear_paper) begin
            state<=CLEAR_ALL; wipe<=0; paper_head<=0; line_base<=0;
            busy_cycles<=0; cycle_total<=0; advance_phase<=0; advance_total<=0;
            pos<=0; armed<=0; func_left<=0; func_chars<=0;
            last_line<=0; column<=0; row<=0; dot_x<=0;
            for(integer i=0;i<20;i=i+1) buffer[i]<=0;
        end else begin
            if (retired && busy_cycles!=0) begin
                busy_cycles<=busy_cycles-13'd1;
                if (advance_next >= {1'b0,cycle_total}) begin
                    advance_phase<=13'(advance_next-{1'b0,cycle_total});
                    paper_head<=paper_head+9'd1;
                end else advance_phase<=advance_next[12:0];
            end
            case (state)
                CLEAR_ALL: begin
                    wipe<=wipe+16'd1;
                    if (wipe==65535) state<=IDLE;
                end
                CLEAR_LINE: begin
                    wipe<=wipe+16'd1;
                    if (wipe == ({4'd0,advance_total,7'd0}-16'd1)) begin
                        if (advance_total==18) begin column<=0;row<=0;dot_x<=0;state<=FONT_WAIT;end
                        else state<=IDLE;
                    end
                end
                FONT_WAIT: state<=DRAW;
                DRAW: begin
                    if (dot_x==5) begin
                        dot_x<=0;
                        if (column==19) begin
                            column<=0;
                            if(row==13) state<=IDLE;
                            else begin row<=row+4'd1;state<=FONT_WAIT;end
                        end else begin column<=column+5'd1;state<=FONT_WAIT;end
                    end else dot_x<=dot_x+3'd1;
                end
                default: begin end
            endcase
            if (state!=CLEAR_ALL) begin
                if (func_left!=0) begin
                    buffer[pos]<=func_chars[5:0];func_chars<={6'd0,func_chars[17:6]};
                    pos<=pos==19 ? 5'd0 : pos+5'd1;func_left<=func_left-2'd1;
                end
                case (cmd)
                    6: if (armed) begin buffer[pos]<=data[5:0];pos<=pos==19 ? 5'd0 : pos+5'd1;end
                    7: if (armed && name_codes[18]) begin func_chars<=name_codes[17:0];func_left<=3;end
                    8: begin
                        for(integer i=0;i<20;i=i+1) buffer[i]<=0;
                        pos<=0;armed<=1;func_left<=0;
                    end
                    9: if (armed) begin buffer[pos]<=0;pos<=pos==19 ? 5'd0 : pos+5'd1;end
                    10: if (armed) begin
                        if (busy_cycles!=0) begin busy_cycles<=0;state<=IDLE;end
                        else begin
                            for(integer i=0;i<20;i=i+1) last_line[i*6 +: 6]<=buffer[i];
                            line_printed<=1;busy_cycles<=LINE_CYCLES;cycle_total<=LINE_CYCLES;
                            advance_phase<=0;advance_total<=18;line_base<=paper_head;
                            wipe<=0;state<=CLEAR_LINE;
                        end
                    end
                    11: begin
                        busy_cycles<=FEED_CYCLES;cycle_total<=FEED_CYCLES;
                        advance_phase<=0;advance_total<=9;line_base<=paper_head;
                        wipe<=0;state<=CLEAR_LINE;
                    end
                    default: begin end
                endcase
            end
        end
    end
endmodule

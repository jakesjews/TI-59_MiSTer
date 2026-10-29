// SPDX-License-Identifier: GPL-2.0-or-later
module ti59_system (
    input wire clk, reset, osd_open, mode_480p, direct_video, clear_paper,
    input wire [10:0] ps2_key,
    input wire [24:0] ps2_mouse,
    input wire [7:0] joystick,
    input wire [1:0] sound_level,
    input wire lib_wr,
    input wire [12:0] lib_waddr,
    input wire [7:0] lib_wdata,
    input wire card_download, card_wr,
    input wire [26:0] card_addr,
    input wire [7:0] card_dout,
    output wire card_busy,
    output wire native_480p, origin, ce_pixel, hs, vs, de, hblank, vblank,
    output wire [7:0] r,g,b,
    output wire running,
    output wire signed [15:0] audio,
    output wire audio_ce
);
    wire [111:0] keys, control_keys;
    wire card_present, card_clear;
    wire [111:0] gated_keys = {card_busy ? 37'd0 : control_keys[111:75],control_keys[74] && !card_present,
                  card_busy ? (card_clear ? 74'd1048576 : 74'd0) : control_keys[73:0]};
    // The connected printer and its latched TRACE switch remain present while
    // the card transport temporarily takes ownership of momentary buttons.
    assign keys = gated_keys | (112'd1 << 2) | (112'(trace_on) << 107);
    wire trace_on, printer_busy, paper_pixel, printer_motor, card_motor, key_click;
    wire [3:0] printer_cmd;
    wire [6:0] printer_data;
    wire [15:0] paper_read_addr;
    wire [8:0] paper_head;
    ti59_printer printer (.clk(clk),.reset(reset),.clear_paper(clear_paper),.retired(retired),
        .cmd(printer_cmd),.data(printer_data),.busy(printer_busy),.motor(printer_motor),
        .read_addr(paper_read_addr),.pixel(paper_pixel),.paper_head(paper_head),
        .line_printed(),.last_line());
    wire [5:0] selected;
    wire pressed;
    wire [9:0] mouse_x;
    wire [8:0] mouse_y;
    wire mouse_visible;
    ti59_input controls (.keys(control_keys),.osd_open(osd_open || card_busy),.*);
    ti59_audio sounds (.clk(clk),.reset(reset),.key_click(key_click),
        .card_motor(card_motor),.printer_motor(printer_motor),.level(sound_level),
        .audio(audio),.sample_ce(audio_ce));
    // Exact fractional enable: 455000/(2*16) instructions/second.
    // In display/IDLE mode the TP0301 divides the oscillator by four.
    reg [23:0] phase;
    wire [24:0] phase_next = {1'b0,phase} + (idle ? 25'd455 : 25'd1820);
    reg ce;
    always @(posedge clk) begin
        ce <= 0;
        if (reset) phase <= 0;
        else if (phase_next >= 25'd6451200) begin
            phase <= 24'(phase_next - 25'd6451200); ce <= 1;
        end else phase <= phase_next[23:0];
    end
    wire retired,idle;
    wire [3:0] digit,r5;
    wire [63:0] a,b_reg;
    wire [15:0] fa;
    tmc0501 cpu (
        .clk(clk),.reset(reset),.ce(ce),.keys(keys),
        .lib_wr(lib_wr),.lib_waddr(lib_waddr),.lib_wdata(lib_wdata),
        .card_data(card_data),.card_cmd(card_cmd),
        .printer_busy(printer_busy),.printer_cmd(printer_cmd),.printer_data(printer_data),
        .retired(retired),.pc(),.opcode(),.digit(digit),.r5(r5),.fa(fa),.fb(),.kr(),.sr(),
        .a(a),.b(b_reg),.c(),.d(),.e(),.idle(idle),.cond(),.running(running),.sout(),.ext(),.library_address()
    );
    wire frame,calc;
    wire [95:0] segments;
    ti59_display display (
        .clk(clk),.reset(reset),.frame(frame),
        .retired(retired),.idle(idle),
        .digit(digit),.r5(r5),.a(a),.b(b_reg),.fa(fa),.segments(segments),.calc(calc)
    );
    wire [7:0] card_data;
    wire [2:0] card_cmd;
    wire [9:0] card_x;
    wire card_visible, card_front, card_error;
    ti59_card reader (.clk(clk),.reset(reset),.frame(frame),.ready(!osd_open && idle && !printer_busy),
        .download(card_download),.wr(card_wr),.addr(card_addr),.dout(card_dout),
        .busy(card_busy),.clear_key(card_clear),.present(card_present),.data(card_data),.cmd(card_cmd),
        .card_x(card_x),.visible(card_visible),.front(card_front),.error(card_error),.motor(card_motor));
    ti59_video video (.*);
endmodule

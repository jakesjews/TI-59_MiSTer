// SPDX-License-Identifier: GPL-2.0-or-later
module ti59_input (
    input wire clk, reset, osd_open,
    input wire [10:0] ps2_key,
    input wire [24:0] ps2_mouse,
    input wire [7:0] joystick,
    output reg [111:0] keys,
    output reg [5:0] selected,
    output reg trace_on,
    output wire pressed,
    output reg key_click,
    output wire [9:0] mouse_x,
    output wire [8:0] mouse_y,
    output wire mouse_visible
);
    reg toggle, shift_l, shift_r, space_down;
    reg [8:0] held_scan;
    reg [5:0] held_key;
    reg [3:0] joy_old;
    wire shift = shift_l | shift_r;
    localparam NONE = 6'd63;
    wire [5:0] mouse_key, mouse_hover;
    wire mouse_update;
    ti59_mouse mouse (.blocked(osd_open),.*);
    reg [5:0] mapped;
    always @* begin
        mapped = NONE;
        case ({ps2_key[8],ps2_key[7:0]})
            9'h016,9'h069: mapped=36; // 1
            9'h01e,9'h072: mapped=37;
            9'h026,9'h07a: mapped=38;
            9'h025,9'h06b: mapped=31;
            9'h02e,9'h073: mapped=32;
            9'h036,9'h074: mapped=33;
            9'h03d,9'h06c: mapped=26;
            9'h03e: mapped=shift ? 6'd29 : 6'd27;
            9'h075: mapped=27;
            9'h046: mapped=shift ? 6'd22 : 6'd28;
            9'h07d: mapped=28;
            9'h045: mapped=shift ? 6'd23 : 6'd41;
            9'h070: mapped=41;
            9'h049,9'h071: mapped=42;
            9'h055: mapped=shift ? 6'd39 : 6'd44;
            9'h05a,9'h15a: mapped=44;
            9'h04e,9'h07b: mapped=34;
            9'h079: mapped=39;
            9'h07c: mapped=29;
            9'h04a,9'h14a: mapped=24;
            9'h01c,9'h005: mapped=0; // A-E / F1-F5
            9'h032,9'h006: mapped=1;
            9'h021,9'h004: mapped=2;
            9'h023,9'h00c: mapped=3;
            9'h024,9'h003: mapped=4;
            9'h00d,9'h035: mapped=5; // Tab / Y: 2nd
            9'h043: mapped=6;  // I: INV
            9'h04b: mapped=7;  // L: ln x
            9'h01a,9'h171: mapped=8;  // Z / Delete: CE
            9'h066,9'h076: mapped=9;  // Backspace / Escape: CLR
            9'h03c: mapped=10; // U: LRN
            9'h02a: mapped=11; // V: exchange X/T
            9'h042: mapped=12; // K: square
            9'h02b: mapped=13; // F: sqrt
            9'h015: mapped=14; // Q: reciprocal
            9'h033: mapped=15; // H: SST
            9'h04d: mapped=16; // P: STO
            9'h044: mapped=17; // O: RCL
            9'h03a: mapped=18; // M: SUM
            9'h01d: mapped=19; // W: power
            9'h03b: mapped=20; // J: BST
            9'h022: mapped=21; // X: EE
            9'h054: mapped=22; // [
            9'h05b: mapped=23; // ]
            9'h034: mapped=25; // G: GTO
            9'h01b: mapped=30; // S: SBR
            9'h02c: mapped=35; // T: RST
            9'h02d: mapped=40; // R: R/S
            9'h031: mapped=43; // N: sign
            9'h00b: mapped=45; // F6: PRINT
            9'h00a: mapped=46; // F8: TRACE switch
            9'h083: mapped=47; // F7: ADV
            default: begin end
        endcase
    end
    wire [3:0] joy_rise = joystick[3:0] & ~joy_old;
    always @(posedge clk) begin
        toggle <= ps2_key[10];
        joy_old <= joystick[3:0];
        if (reset) begin
            selected <= 36; held_key <= NONE; held_scan <= 0;
            shift_l <= 0; shift_r <= 0; space_down <= 0;
        end else if (osd_open) begin
            held_key <= NONE; space_down <= 0; shift_l <= 0; shift_r <= 0;
        end else begin
            if(held_key==NONE && !space_down && joystick[7:4]==0) begin
                if(mouse_key!=NONE) selected<=mouse_key;
                else if(mouse_update && mouse_hover!=NONE) selected<=mouse_hover;
            end
            if (joy_rise[0] && selected < 47) selected <= selected + 6'd1;
            if (joy_rise[1] && selected > 0) selected <= selected - 6'd1;
            if (joy_rise[2]) selected <= selected >= 45 ? (selected == 47 ? 6'd45 : selected + 6'd1) : (selected < 40 ? selected + 6'd5 : selected - 6'd40);
            if (joy_rise[3]) selected <= selected >= 45 ? (selected == 45 ? 6'd47 : selected - 6'd1) : (selected >= 5 ? selected - 6'd5 : selected + 6'd40);
            if (toggle != ps2_key[10]) begin
                if (!ps2_key[8] && ps2_key[7:0] == 8'h12) shift_l <= ps2_key[9];
                else if (!ps2_key[8] && ps2_key[7:0] == 8'h59) shift_r <= ps2_key[9];
                else if (!ps2_key[8] && ps2_key[7:0] == 8'h29) space_down <= ps2_key[9];
                else if (!ps2_key[9]) begin
                    if (held_scan == ps2_key[8:0]) held_key <= NONE;
                end else if (ps2_key[8]) begin
                    case (ps2_key[7:0])
                        8'h74: if (selected < 47) selected <= selected + 6'd1;
                        8'h6b: if (selected > 0) selected <= selected - 6'd1;
                        8'h72: selected <= selected >= 45 ? (selected == 47 ? 6'd45 : selected + 6'd1) : (selected < 40 ? selected + 6'd5 : selected - 6'd40);
                        8'h75: selected <= selected >= 45 ? (selected == 45 ? 6'd47 : selected - 6'd1) : (selected >= 5 ? selected - 6'd5 : selected + 6'd40);
                        default: begin held_key <= mapped; held_scan <= ps2_key[8:0]; end
                    endcase
                end else if (mapped != NONE) begin
                    held_key <= mapped; held_scan <= ps2_key[8:0]; selected <= mapped;
                end
            end
        end
    end
    reg [5:0] active_key;
    integer row, col, bit_number;
    always @* begin
        active_key = held_key!=NONE ? held_key : mouse_key;
        if (space_down || joystick[4]) active_key = selected;
        if (joystick[5]) active_key = 5;
        if (joystick[6]) active_key = 6;
        if (joystick[7]) active_key = 9;
        if (osd_open) active_key = NONE;
        keys = 0;
        keys[2] = 1; // Connected PC-100: KP.D0.
        keys[86] = active_key == 45; // PRINT: KP.D12.
        keys[84] = active_key == 47; // ADV: KN.D12.
        keys[107] = trace_on; // TRACE: KP.D15.
        keys[74] = 1; // Normally closed TI-59 card-absent switch: KR.D10.
        row = int'(active_key)/5 + 1;
        col = int'(active_key)%5;
        case (col)
            0: bit_number=1;
            1: bit_number=2;
            2: bit_number=3;
            3: bit_number=5;
            default: bit_number=6;
        endcase
        if (active_key < 45) keys[row*7+bit_number] = 1;
    end
    reg trace_held;
    reg [5:0] previous_key;
    always @(posedge clk) begin
        previous_key <= active_key;
        key_click <= active_key != NONE && active_key != previous_key;
        trace_held <= active_key == 46;
        if (reset) begin trace_on<=0;trace_held<=0;previous_key<=NONE;key_click<=0;end
        else if (active_key==46 && !trace_held) trace_on<=!trace_on;
    end
    assign pressed = active_key != NONE;
endmodule

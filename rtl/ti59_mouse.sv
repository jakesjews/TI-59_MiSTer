// SPDX-License-Identifier: GPL-2.0-or-later
module ti59_mouse #(
    parameter integer MIN_PRESS_CYCLES = 4032000 // 80 ms at 50.4 MHz
) (
    input wire clk, reset, blocked,
    input wire [24:0] ps2_mouse,
    output wire [9:0] mouse_x,
    output wire [8:0] mouse_y,
    output wire mouse_visible,
    output reg mouse_update,
    output reg [5:0] mouse_key,
    output wire [5:0] mouse_hover
);
    `include "rtl/ti59_panel.vh"
    localparam [5:0] NONE=63;
    localparam integer HOLD_BITS=$clog2(MIN_PRESS_CYCLES+1);
    reg [HOLD_BITS-1:0] hold_count;
    reg toggle, left_down, armed, seen;
    // Half-pixel accumulation preserves fine motion without rounding away
    // single-count reports. Coordinates are independent of output resolution.
    reg [10:0] x_half;
    reg [9:0] y_half;
    assign mouse_x=x_half[10:1];
    assign mouse_y=y_half[9:1];
    assign mouse_visible=seen && !blocked && !reset;
    wire packet=toggle!=ps2_mouse[24];
    wire unused_buttons=^ps2_mouse[3:1]; // Fixed marker, right and middle buttons.
    wire signed [11:0] dx=ps2_mouse[6] ? (ps2_mouse[4] ? -12'sd255 : 12'sd255) :
        $signed({{4{ps2_mouse[4]}},ps2_mouse[15:8]});
    wire signed [11:0] dy=ps2_mouse[7] ? (ps2_mouse[5] ? -12'sd255 : 12'sd255) :
        $signed({{4{ps2_mouse[5]}},ps2_mouse[23:16]});
    wire signed [11:0] nx=$signed({1'b0,x_half})+dx;
    wire signed [11:0] ny=$signed({2'b0,y_half})-dy; // PS/2 positive Y is up.
    wire [10:0] next_x=nx<0 ? 11'd0 : nx>1278 ? 11'd1278 : nx[10:0];
    wire [9:0] next_y=ny<0 ? 10'd0 : ny>958 ? 10'd958 : ny[9:0];
    function automatic [5:0] hit(input [9:0] x,input [8:0] y);
        integer i,pad;
        begin
            hit=NONE;
            for(i=0;i<48;i=i+1) begin
                pad=i<45 ? 2 : 1;
                if(int'(x)>=panel_key_x(i)-pad && int'(x)<panel_key_x(i)+panel_key_w(i)+pad &&
                   int'(y)>=panel_key_y(i)-pad && int'(y)<panel_key_y(i)+panel_key_h(i)+pad) hit=6'(i);
            end
        end
    endfunction
    assign mouse_hover=hit(mouse_x,mouse_y);
    wire [5:0] clicked_key=hit(next_x[10:1],next_y[9:1]);
    always @(posedge clk) begin
        toggle<=ps2_mouse[24]; mouse_update<=0;
        if(packet) left_down<=ps2_mouse[0];
        if(reset) begin
            x_half<=1000; y_half<=480; seen<=0;
            left_down<=ps2_mouse[0]; armed<=!ps2_mouse[0];
            mouse_key<=NONE; hold_count<=0;
        end else if(blocked) begin
            // Drain reports but do not move/click through the OSD or loader.
            // Require a fresh button-up report before accepting another press.
            armed<=0; mouse_key<=NONE; hold_count<=0;
        end else begin
            if(hold_count!=0) hold_count<=hold_count-1'b1;
            else if(!left_down) mouse_key<=NONE;
            if(packet) begin
                x_half<=next_x; y_half<=next_y;
                mouse_update<=dx!=0 || dy!=0 || left_down!=ps2_mouse[0];
                if(dx!=0 || dy!=0 || ps2_mouse[0]) seen<=1;
                if(!ps2_mouse[0]) armed<=1;
                if(ps2_mouse[0] && !left_down && armed && mouse_key==NONE && clicked_key!=NONE) begin
                    // Capture the original button through release; dragging
                    // never types adjacent keys or toggles TRACE repeatedly.
                    mouse_key<=clicked_key;
                    hold_count<=HOLD_BITS'(MIN_PRESS_CYCLES-1);
                end
            end
        end
    end
endmodule

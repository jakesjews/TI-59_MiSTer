// SPDX-License-Identifier: GPL-2.0-or-later
// Native 240p/480p raster; the photographic panel has 640x480 logical pixels.
module ti59_video (
    input wire clk, mode_480p, direct_video,
    input wire [95:0] segments,
    input wire calc,
    input wire [5:0] selected,
    input wire pressed,
    input wire [9:0] mouse_x,
    input wire [8:0] mouse_y,
    input wire mouse_visible,
    input wire [9:0] card_x,
    input wire card_visible, card_front, card_error,
    input wire printer_busy, trace_on, paper_pixel,
    input wire [8:0] paper_head,
    output wire [15:0] paper_read_addr,
    output wire origin,
    output reg native_480p = 0,
    output reg frame,
    output reg ce_pixel, hs, vs, de, hblank, vblank,
    output reg [7:0] r,g,b
);
    `include "rtl/ti59_panel.vh"
    reg [9:0] hc = 0, vc = 0;
    reg [1:0] divider = 0;
    wire tick = native_480p ? !divider[0] : divider == 0;
    assign origin = hc == 0 && vc == 0;
    wire [8:0] py = native_480p ? vc[8:0] : {vc[7:0],1'b0};
    wire active = hc < 640 && vc < (native_480p ? 480 : 240);
    wire hsync = !(hc >= 656 && hc < 752);
    wire vsync = native_480p ? !(vc >= 490 && vc < 492) : !(vc >= 244 && vc < 247);
    reg [7:0] panel [0:307199];
    reg [23:0] palette [0:255];
    reg [3:0] card_rom [0:8191];
    initial begin
        $readmemh("roms/panel.hex",panel);
        $readmemh("roms/panel_palette.hex",palette);
        $readmemh("roms/card.hex",card_rom);
    end
    wire [18:0] address = {1'b0,py,9'd0} + {3'd0,py,7'd0} + {9'd0,hc};
    // The ring head is the bottom of the visible paper. Latch once per frame
    // so the physical feed moves the entire printed page without tearing.
    reg [8:0] paper_head_view = 0;
    reg [9:0] pointer_x = 0;
    reg [8:0] pointer_y = 0;
    reg pointer_visible = 0;
    always @(posedge clk) if(frame) begin
        pointer_x<=mouse_x; pointer_y<=mouse_y; pointer_visible<=mouse_visible;
    end
    always @(posedge clk) if (frame) paper_head_view <= paper_head;
    wire [8:0] paper_y = paper_head_view + py - 9'd264;
    wire [6:0] paper_x = 7'(hc - 10'd108);
    assign paper_read_addr = {paper_y,paper_x};
    wire paper_area = hc>=108 && hc<236 && py>=12 && py<264;
    reg paper_area_q, ink_qq;
    wire [9:0] sprite_x = hc - card_x;
    wire [8:0] sprite_y = py - (card_front ? 9'd134 : 9'd118);
    // Transport runs behind the calculator; the cue-card recess is in front.
    wire card_area = card_visible && sprite_x < 160 && sprite_y < 24 &&
                     (card_front || hc < 410 || hc >= 600);
    wire [12:0] card_address = {sprite_y[4:0],sprite_x[7:0]};
    reg [7:0] pixel_q;
    reg [3:0] card_q,card_qq;
    reg [9:0] xq,xqq;
    reg [8:0] yq,yqq;
    reg active_q,hs_q,vs_q,ce_q,hblank_q,vblank_q;
    reg active_qq,hs_qq,vs_qq,ce_qq,hblank_qq,vblank_qq;
    reg [23:0] base_rgb;
    always @(posedge clk) begin
        divider <= divider + 2'd1;
        frame <= 0;
        if (tick) begin
            if (hc == 799) begin
                hc <= 0;
                if (vc == (native_480p ? 524 : 261)) begin
                    // Normal HDMI always gets the full-detail 480p panel.
                    // The resolution option applies only to Direct Video.
                    vc <= 0; native_480p <= !direct_video || mode_480p; frame <= 1;
                end else vc <= vc + 10'd1;
            end else hc <= hc + 10'd1;
        end
        paper_area_q <= paper_area;
        ink_qq <= paper_area_q && paper_pixel;
        pixel_q <= panel[active ? address : 19'd0];
        card_q <= card_area ? card_rom[card_address] : 4'd0;
        xq <= hc; yq <= py;
        active_q <= active; hs_q <= hsync; vs_q <= vsync; ce_q <= tick;
        hblank_q <= hc >= 640; vblank_q <= vc >= (native_480p ? 480 : 240);
        base_rgb <= palette[pixel_q];
        xqq <= xq; yqq <= yq; card_qq <= card_q;
        active_qq <= active_q; hs_qq <= hs_q; vs_qq <= vs_q; ce_qq <= ce_q;
        hblank_qq <= hblank_q; vblank_qq <= vblank_q;
    end
    // 12x20 LEDs, with two-row horizontal strokes visible in both rasters.
    function automatic [1:0] led_pixel(input integer dx,dy,input [7:0] leds);
        begin
            led_pixel=0;
            if (dx>=2 && dx<=5 && dy>=0 && dy<=1) led_pixel={1'b1,leds[0]};
            if (dx>=6 && dx<=7 && dy>=2 && dy<=7) led_pixel={1'b1,leds[1]};
            if (dx>=6 && dx<=7 && dy>=11 && dy<=17) led_pixel={1'b1,leds[2]};
            if (dx>=2 && dx<=5 && dy>=18 && dy<=19) led_pixel={1'b1,leds[3]};
            if (dx>=0 && dx<=1 && dy>=11 && dy<=17) led_pixel={1'b1,leds[4]};
            if (dx>=0 && dx<=1 && dy>=2 && dy<=7) led_pixel={1'b1,leds[5]};
            if (dx>=2 && dx<=5 && dy>=8 && dy<=9) led_pixel={1'b1,leds[6]};
            if (dx>=9 && dx<=10 && dy>=18 && dy<=19) led_pixel={1'b1,leds[7]};
        end
    endfunction
    reg [23:0] rgb;
    integer j,bx,by,bw,bh,px,py_cursor;
    reg [7:0] leds;
    reg [1:0] stroke;
    always @* begin
        rgb = ink_qq ? 24'h353432 : base_rgb;
        leds=0;stroke=0;
        for(j=0;j<12;j=j+1) begin
            leds = segments[(11-j)*8 +: 8];
            if (j==0 && calc) leds = leds | 8'h39;
            stroke = led_pixel(int'(xqq)-(430+j*12),int'(yqq)-104,leds);
            if (stroke[1]) rgb = stroke[0] ? 24'hff4936 : 24'h291514;
        end
        case (card_qq)
            1: rgb=24'h6b502b;
            2: rgb=card_error ? 24'hd16c50 : 24'hd2b16f;
            3: rgb=24'h27251d;
            4: rgb=24'h806438;
            default: begin end
        endcase
        if (trace_on && xqq>=130 && xqq<174 && yqq>=399 && yqq<423 &&
            (xqq==130 || xqq==173 || yqq==399 || yqq==422)) rgb=24'hf4bf5b;
        if (printer_busy && xqq>=255 && xqq<261 && yqq>=409 && yqq<415) rgb=24'hff4936;
        bx=panel_key_x(int'(selected)); by=panel_key_y(int'(selected));
        bw=panel_key_w(int'(selected)); bh=panel_key_h(int'(selected));
        if (selected < 48 && int'(xqq)>=bx && int'(xqq)<bx+bw && int'(yqq)>=by && int'(yqq)<by+bh &&
            (int'(xqq)==bx || int'(xqq)==bx+bw-1 || int'(yqq)==by || int'(yqq)==by+bh-1))
            rgb = pressed ? 24'hff4936 : (selected==46 && trace_on ? 24'hf4bf5b : 24'h87c6d7);
        // Black-edged white arrow, drawn last and tall enough for 240p.
        // Both cursor position and artwork use the same 640x480 coordinates.
        px=int'(xqq)-int'(pointer_x); py_cursor=int'(yqq)-int'(pointer_y);
        if(pointer_visible && px>=0 && px<10 && py_cursor>=0 && py_cursor<20 && px<=py_cursor/2) begin
            rgb=(px<2 || py_cursor>=18 || px>=py_cursor/2-1) ? 24'h11151a : 24'hffffff;
        end
    end
    always @(posedge clk) begin
        ce_pixel <= ce_qq;
        hs <= hs_qq; vs <= vs_qq; de <= active_qq;
        hblank <= hblank_qq; vblank <= vblank_qq;
        {r,g,b} <= active_qq ? rgb : 24'd0;
    end
endmodule

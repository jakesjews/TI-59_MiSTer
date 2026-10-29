// SPDX-License-Identifier: GPL-2.0-or-later
// Shared Direct Video/analog pipeline, using unmodified upstream modules.
module ti59_video_out (
    input wire clk, origin, native_480p,
    input wire [1:0] aspect,
    input wire forced_scandoubler,
    input wire [2:0] scale,
    input wire [11:0] hdmi_width, hdmi_height,
    inout wire [21:0] gamma_bus,
    input wire ce_in, hs_in, vs_in, hblank, vblank,
    input wire [7:0] r_in, g_in, b_in,
    output wire ce_pixel, hs, vs, de,
    output wire [7:0] r, g, b,
    output wire [12:0] arx, ary
);
    reg forced = 0;
    always @(posedge clk) if (origin) forced <= forced_scandoubler;
    // MiSTer's global request applies to 240p. Native 480p is never doubled.
    wire doubled = forced && !native_480p;
    wire gamma_hs,gamma_vs,gamma_hb,gamma_vb;
    wire [23:0] gamma_rgb;
    // Parallel LUTs support the two system clocks available per native 480p pixel.
    gamma_fast gamma (
        .clk_vid(clk), .ce_pix(ce_in), .gamma_bus(gamma_bus),
        .HSync(~hs_in), .VSync(~vs_in), .HBlank(hblank), .VBlank(vblank),
        .DE(~(hblank | vblank)), .RGB_in({r_in,g_in,b_in}),
        .HSync_out(gamma_hs), .VSync_out(gamma_vs),
        .HBlank_out(gamma_hb), .VBlank_out(gamma_vb), .DE_out(), .RGB_out(gamma_rgb)
    );

    wire mixer_de;
    video_mixer #(.LINE_LENGTH(640), .GAMMA(0)) mixer (
        .CLK_VIDEO(clk), .CE_PIXEL(ce_pixel), .ce_pix(ce_in),
        .scandoubler(doubled), .hq2x(1'b0), .gamma_bus(),
        .R(gamma_rgb[23:16]), .G(gamma_rgb[15:8]), .B(gamma_rgb[7:0]),
        // gamma_fast preserves the positive sync expected by video_mixer.
        .HSync(gamma_hs), .VSync(gamma_vs), .HBlank(gamma_hb), .VBlank(gamma_vb),
        .HDMI_FREEZE(1'b0), .freeze_sync(),
        .VGA_R(r), .VGA_G(g), .VGA_B(b), .VGA_HS(hs), .VGA_VS(vs),
        .VGA_DE(mixer_de)
    );

    video_freak geometry (
        .CLK_VIDEO(clk), .CE_PIXEL(ce_pixel), .VGA_VS(vs),
        .HDMI_WIDTH(hdmi_width), .HDMI_HEIGHT(hdmi_height),
        .VGA_DE_IN(mixer_de), .VGA_DE(de), .VIDEO_ARX(arx), .VIDEO_ARY(ary),
        .ARX(aspect == 0 ? 12'd4 : {10'd0, aspect - 2'd1}),
        .ARY(aspect == 0 ? 12'd3 : 12'd0),
        .CROP_SIZE(12'd0), .CROP_OFF(5'd0), .SCALE(scale)
    );
endmodule

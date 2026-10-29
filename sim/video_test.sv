// SPDX-License-Identifier: GPL-2.0-or-later
module video_test (
    input wire clk,
    input wire paper_ink, trace_on, printer_busy, pressed,
    input wire [5:0] selected,
    input wire mode_480p,
    input wire [9:0] card_x,
    input wire card_visible, card_front, card_error,
    input wire [1:0] aspect,
    input wire forced_scandoubler,
    input wire [2:0] scale,
    input wire [11:0] hdmi_width, hdmi_height,
    input wire gamma_en, gamma_wr,
    input wire [9:0] gamma_addr,
    input wire [7:0] gamma_value,
    output wire gamma_supported,
    output wire ce_pixel, hs, vs, de,
    output wire [7:0] r,g,b,
    output wire [12:0] arx,ary
);
    wire native_480p, origin, ce_in, hs_in, vs_in, hblank, vblank;
    wire [7:0] r_in, g_in, b_in;
    wire [21:0] gamma_bus;
    assign gamma_bus[20:0] = {clk,gamma_en,gamma_wr,gamma_addr,gamma_value};
    assign gamma_supported = gamma_bus[21];

    ti59_video renderer (
        .clk(clk), .mode_480p(mode_480p), .native_480p(native_480p), .segments(96'h00063f5b4f666d7d077f6f40), .calc(1'b0),
        .card_x(card_x),.card_visible(card_visible),.card_front(card_front),.card_error(card_error),
        .printer_busy(printer_busy),.trace_on(trace_on),.paper_pixel(paper_ink),.paper_head(9'd0),.paper_read_addr(),
        .selected(selected), .pressed(pressed), .origin(origin), .frame(),
        .ce_pixel(ce_in), .hs(hs_in), .vs(vs_in), .de(),
        .hblank(hblank), .vblank(vblank), .r(r_in), .g(g_in), .b(b_in)
    );
    ti59_video_out output_path (.*);
`ifdef VERILATOR
    // Quartus exports names from unnamed generate scopes; standard Verilator
    // instead creates undriven implicit one-bit R_in/G_in/B_in nets in mixer.
    // Model ONLY that scope resolution for our GAMMA=0, HALF_DEPTH=0 instance.
    // RGB still traverses the real gamma, freezer, scandoubler and mixer stages.
    // No synthesized sources or upstream files are changed by this test shim.
    initial begin
        force output_path.mixer.R_gamma = output_path.mixer.genblk1.R_in;
        force output_path.mixer.G_gamma = output_path.mixer.genblk1.G_in;
        force output_path.mixer.B_gamma = output_path.mixer.genblk1.B_in;
    end
`endif
endmodule

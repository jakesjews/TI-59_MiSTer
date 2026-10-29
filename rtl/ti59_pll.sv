// SPDX-License-Identifier: GPL-2.0-or-later
module ti59_pll(input wire refclk, output wire clk, output wire locked);
    // Keep the hierarchy expected by the unmodified MiSTer clock groups.
    ti59_pll_clock pll_inst (.*);
endmodule

module ti59_pll_clock(input wire refclk, output wire clk, output wire locked);
    // Native pixels at 12.6 MHz (240p) or 25.2 MHz (480p).
    altera_pll #(
        .reference_clock_frequency("50.0 MHz"),
        .operation_mode("direct"), .number_of_clocks(1),
        .output_clock_frequency0("50.400000 MHz"),
        .phase_shift0("0 ps"), .duty_cycle0(50),
        .pll_type("General"), .pll_subtype("General")
    ) altera_pll_i (.refclk(refclk), .rst(1'b0), .outclk(clk),
             .locked(locked), .fbclk(1'b0), .fboutclk());
endmodule

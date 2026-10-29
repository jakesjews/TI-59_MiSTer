// SPDX-License-Identifier: GPL-2.0-or-later
// Synthesized mechanical effects, not recordings of original hardware.
// 50.4 MHz / 1050 = 48 kHz. All oscillators/envelopes use this sample enable,
// independent of the selected video mode and calculator instruction speed.
module ti59_audio (
    input wire clk, reset, key_click, card_motor, printer_motor,
    input wire [1:0] level, // 0 normal, 1 quiet, 2/3 off
    output reg sample_ce,
    output reg signed [15:0] audio
);
    reg [10:0] divider;
    reg click_pending;
    reg [22:0] noise;
    reg signed [15:0] filtered;
    wire signed [15:0] white = $signed(noise[15:0]);
    wire signed [16:0] noise_delta = {white[15],white} - {filtered[15],filtered};
    reg [11:0] click_env, card_env, printer_env;
    reg [15:0] card_phase, gear_phase, print_phase, feed_phase;

    function automatic signed [15:0] triangle(input [15:0] phase);
        triangle = $signed({1'b0,phase[15] ? ~phase[14:0] : phase[14:0]}) - 16'sd16384;
    endfunction
    // Soft filtered-noise key tap, a smooth card-drive whirr, and a rougher
    // pulsed printer/feed motor. Smooth attack/release avoids hard audio edges.
    wire signed [17:0] card_wave = (18'(triangle(card_phase)) >>> 2) +
                                   (18'(triangle(gear_phase)) >>> 4) +
                                   (18'(filtered) >>> 4);
    wire signed [17:0] printer_wave = (18'(triangle(feed_phase)) >>> 2) +
        (18'(filtered) >>> (print_phase[15:13] == 0 ? 2 : 4));
    wire signed [28:0] key_product = $signed({1'b0,click_env}) * filtered;
    wire signed [30:0] card_product = $signed({1'b0,card_env}) * card_wave;
    wire signed [30:0] printer_product = $signed({1'b0,printer_env}) * printer_wave;
    // Halve the sum at the output: worst case < 14,000, over 6 dB headroom.
    wire signed [17:0] mixed = 18'(key_product >>> 14) +
                               18'(card_product >>> 12) + 18'(printer_product >>> 12);
    always @(posedge clk) begin
        sample_ce <= 0;
        if (reset) begin
            divider<=0; click_pending<=0; noise<=23'h5a17c9; filtered<=0;
            click_env<=0; card_env<=0; printer_env<=0;
            card_phase<=0; gear_phase<=0; print_phase<=0; feed_phase<=0;
            audio<=0;
        end else begin
            if (key_click) click_pending<=1;
            if (divider==1049) begin
                divider<=0; sample_ce<=1; click_pending<=0;
                noise<={noise[21:0],noise[22]^noise[17]};
                filtered<=16'(17'(filtered)+(noise_delta >>> 2));
                if (click_pending || key_click) click_env<=4095;
                else if (click_env!=0) click_env<=click_env-(click_env >> 6)-12'd1;
                if (card_motor) card_env<=card_env>4079 ? 12'd4095 : card_env+12'd16;
                else card_env<=card_env<32 ? 12'd0 : card_env-12'd32;
                if (printer_motor) printer_env<=printer_env>4063 ? 12'd4095 : printer_env+12'd32;
                else printer_env<=printer_env<32 ? 12'd0 : printer_env-12'd32;
                card_phase<=card_phase+16'd260; // 190 Hz drive
                gear_phase<=gear_phase+16'd1393; // 1.02 kHz gear texture
                print_phase<=print_phase+16'd819; // 600 Hz head chatter
                feed_phase<=feed_phase+16'd137; // 100 Hz paper feed
                case (level)
                    0: audio<=16'(mixed >>> 1);
                    1: audio<=16'(mixed >>> 3);
                    default: audio<=0;
                endcase
            end else divider<=divider+11'd1;
        end
    end
endmodule

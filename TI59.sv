//============================================================================
//
//  This program is free software; you can redistribute it and/or modify it
//  under the terms of the GNU General Public License as published by the Free
//  Software Foundation; either version 2 of the License, or (at your option)
//  any later version.
//
//  This program is distributed in the hope that it will be useful, but WITHOUT
//  ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
//  FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for
//  more details.
//
//  You should have received a copy of the GNU General Public License along
//  with this program; if not, write to the Free Software Foundation, Inc.,
//  51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
//
//============================================================================

module emu
(
	`include "sys/emu_ports.vh"
);

///////// Default values for ports not used in this core /////////

assign ADC_BUS  = 'Z;
assign USER_OUT = '1;
assign {UART_RTS, UART_TXD, UART_DTR} = 0;
assign {SD_SCK, SD_MOSI, SD_CS} = 'Z;
assign {SDRAM_DQ, SDRAM_A, SDRAM_BA, SDRAM_CLK, SDRAM_CKE, SDRAM_DQML, SDRAM_DQMH, SDRAM_nWE, SDRAM_nCAS, SDRAM_nRAS, SDRAM_nCS} = 'Z;
assign {DDRAM_CLK, DDRAM_BURSTCNT, DDRAM_ADDR, DDRAM_DIN, DDRAM_BE, DDRAM_RD, DDRAM_WE} = '0;  

assign VGA_SL = 0;
assign VGA_F1 = 0;
assign VGA_SCALER  = 0;
assign VGA_DISABLE = 0;
assign HDMI_FREEZE = 0;
assign HDMI_BLACKOUT = 0;
assign HDMI_BOB_DEINT = 0;

assign AUDIO_S = 1;
assign AUDIO_L = audio;
assign AUDIO_R = audio;
assign AUDIO_MIX = 0;

assign LED_DISK = 0;
assign LED_POWER = 0;
assign BUTTONS = 0;

//////////////////////////////////////////////////////////////////

`include "build_id.v" 
localparam CONF_STR = {
	"TI59;;",
	"F1,ROM,Load library module;",
	"F2,CRDBIN,Load magnetic card;",
	"-;",
	"O[122:121],Aspect ratio,Original,Full Screen,[ARC1],[ARC2];",
	"H0O[2],Direct Video GUI,240p,480p;",
	"O[6:4],HDMI scaling,Normal,V-Integer,HV-Integer-,HV-Integer+,HV-Integer;",
	"-;",
	"T[7],Clear printer paper;",
	"O[9:8],Sound effects,Normal,Quiet,Off;",
	"J,Press key,2nd,INV,Clear;",
	"T[0],Power cycle;",
	"R[0],Power cycle and close OSD;",
	"v,0;",
	"V,v",`BUILD_DATE
};

wire forced_scandoubler;
wire direct_video;
wire   [1:0] buttons;
wire [127:0] status;
wire  [10:0] ps2_key;
wire  [24:0] ps2_mouse;
wire [31:0] joystick;
wire [21:0] gamma_bus;
wire ioctl_download, ioctl_wr, card_busy;
wire [15:0] ioctl_index;
wire [26:0] ioctl_addr;
wire [7:0] ioctl_dout;

hps_io #(.CONF_STR(CONF_STR)) hps_io
(
	.clk_sys(clk_sys),
	.HPS_BUS(HPS_BUS),
	.EXT_BUS(),
	.gamma_bus(gamma_bus),

	.forced_scandoubler(forced_scandoubler),
	.direct_video(direct_video),

	.buttons(buttons),
	.status(status),
	.status_menumask({15'd0,!direct_video}),
	
	.ps2_key(ps2_key),
	.ps2_mouse(ps2_mouse),
	.joystick_0(joystick),
	.ioctl_download(ioctl_download),
	.ioctl_wr(ioctl_wr),
	.ioctl_index(ioctl_index),
	.ioctl_addr(ioctl_addr),
	.ioctl_dout(ioctl_dout),
	.ioctl_wait(ioctl_index == 2 && card_busy)
);

///////////////////////   CLOCKS   ///////////////////////////////

wire clk_sys, pll_locked;
ti59_pll pll
(
	.refclk(CLK_50M),
	.clk(clk_sys),
	.locked(pll_locked)
);

wire reset = RESET | status[0] | buttons[1] | !pll_locked | (ioctl_download && ioctl_index == 1);
wire hvcnt_atzero;
wire native_480p;
wire ce_raw, hs_raw, vs_raw, hblank_raw, vblank_raw;
wire [7:0] r_raw, g_raw, b_raw;
wire signed [15:0] audio;

// Leave H/V sync always on. This stabilizes the video output while the core
// is in reset. This example releases the reset when H/V counters are at zero.
reg reset_core = 1;
always @(posedge clk_sys) begin
	if(reset) reset_core <= 1;
	else if(hvcnt_atzero) reset_core <= 0;
end

ti59_system calculator
(
	.clk(clk_sys),
	.reset(reset_core),
	.osd_open(OSD_STATUS),
	.mode_480p(status[2]),
	.direct_video(direct_video),
	.clear_paper(status[7]),
	.sound_level(status[9:8]),
	.audio(audio),
	.audio_ce(),
	.native_480p(native_480p),
	.ps2_key(ps2_key),
	.ps2_mouse(ps2_mouse),
	.joystick(joystick[7:0]),
	.lib_wr(ioctl_wr && ioctl_download && ioctl_index == 1 && ioctl_addr < 5000),
	.lib_waddr(ioctl_addr[12:0]),
	.lib_wdata(ioctl_dout),
	.card_download(ioctl_download && ioctl_index == 2),
	.card_wr(ioctl_wr && ioctl_download && ioctl_index == 2),
	.card_addr(ioctl_addr),
	.card_dout(ioctl_dout),
	.card_busy(card_busy),
	.origin(hvcnt_atzero),
	.ce_pixel(ce_raw),
	.hs(hs_raw),
	.vs(vs_raw),
	.de(),
	.hblank(hblank_raw),
	.vblank(vblank_raw),
	.r(r_raw),
	.g(g_raw),
	.b(b_raw),
	.running(LED_USER)
);

ti59_video_out video_output
(
	.clk(clk_sys), .origin(hvcnt_atzero),
	.native_480p(native_480p), .forced_scandoubler(forced_scandoubler),
	.aspect(status[122:121]), .scale(status[6:4]),
	.hdmi_width(HDMI_WIDTH), .hdmi_height(HDMI_HEIGHT), .gamma_bus(gamma_bus),
	.ce_in(ce_raw), .hs_in(hs_raw), .vs_in(vs_raw),
	.hblank(hblank_raw), .vblank(vblank_raw),
	.r_in(r_raw), .g_in(g_raw), .b_in(b_raw),
	.ce_pixel(CE_PIXEL), .hs(VGA_HS), .vs(VGA_VS), .de(VGA_DE),
	.r(VGA_R), .g(VGA_G), .b(VGA_B), .arx(VIDEO_ARX), .ary(VIDEO_ARY)
);

assign CLK_VIDEO = clk_sys;

endmodule

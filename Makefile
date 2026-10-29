SHELL := /bin/bash
RTL := rtl/ti59_audio.sv rtl/ti59_printer.sv rtl/ti59_card.sv rtl/tmc0501.sv rtl/ti59_input.sv rtl/ti59_display.sv rtl/ti59_video.sv rtl/ti59_system.sv
VIDEO_RTL := rtl/ti59_video.sv rtl/ti59_video_out.sv sys/video_mixer.sv sys/video_freak.sv \
  sys/video_freezer.sv sys/gamma_corr.sv sys/scandoubler.v sys/hq2x.sv sys/math.sv
VFLAGS := -Wall -Wno-PINCONNECTEMPTY -Wno-PROCASSINIT
ORACLE := $(CURDIR)/research/sources/Calc-U-59

.PHONY: all prepare lint test test-cpu test-system test-video test-card test-printer test-audio demo framework-check build
.NOTPARALLEL: test
all: lint test
prepare: roms/firmware.hex roms/firmware.bin roms/constants.hex roms/library.hex roms/panel.hex roms/panel_palette.hex roms/card.hex roms/printer_font.hex
roms/firmware.hex roms/firmware.bin roms/constants.hex roms/library.hex: tools/prepare_roms.py
	python3 tools/prepare_roms.py
roms/panel.hex roms/panel_palette.hex roms/card.hex roms/printer_font.hex: tools/make_panel.py assets/ti59-printer.png
	uv run tools/make_panel.py
lint: prepare
	verilator --lint-only $(VFLAGS) --top-module ti59_system $(RTL)
	verilator --lint-only $(VFLAGS) -Wno-TIMESCALEMOD sim/framework.vlt --top-module video_test \
	  $(VIDEO_RTL) sim/video_test.sv
test: test-cpu test-printer test-audio test-system test-video test-card
test-cpu: prepare
	test -f $(ORACLE)/Core/TMC0501.cpp
	mkdir -p build/cpu
	verilator --cc --exe --build -j 4 -Wall --top-module tmc0501 --Mdir build/cpu \
	  rtl/tmc0501.sv $(CURDIR)/sim/cpu_test.cpp \
	  $(ORACLE)/Core/TMC0501.cpp $(ORACLE)/Core/ROM.cpp $(ORACLE)/Core/RAM.cpp \
	  -CFLAGS '-std=c++17 -I$(ORACLE)/Core' >build/cpu-build.log 2>&1
	build/cpu/Vtmc0501
test-system: prepare
	mkdir -p build/system build/card-animation
	verilator --cc --exe --build -j 4 $(VFLAGS) --top-module ti59_system --Mdir build/system \
	  $(RTL) $(CURDIR)/sim/system_test.cpp >build/system-build.log 2>&1
	build/system/Vti59_system
test-video: prepare
	mkdir -p build/video
	verilator --cc --exe --build -j 4 $(VFLAGS) -Wno-TIMESCALEMOD sim/framework.vlt \
	  --top-module video_test --Mdir build/video $(VIDEO_RTL) sim/video_test.sv \
	  $(CURDIR)/sim/video_test.cpp >build/video-build.log 2>&1
	build/video/Vvideo_test
framework-check:
	python3 tools/check_framework.py
build:
	bash build.sh remote

test-card: prepare
	mkdir -p build/card
	verilator --cc --exe --build -j 4 $(VFLAGS) --top-module ti59_card --Mdir build/card \
	  rtl/ti59_card.sv $(CURDIR)/sim/card_test.cpp >build/card-build.log 2>&1
	build/card/Vti59_card

test-printer: prepare
	mkdir -p build/printer
	verilator --cc --exe --build -j 4 $(VFLAGS) --top-module ti59_printer --Mdir build/printer \
	  rtl/ti59_printer.sv $(CURDIR)/sim/printer_test.cpp >build/printer-build.log 2>&1
	build/printer/Vti59_printer

test-audio:
	mkdir -p build/audio
	verilator --cc --exe --build -j 4 $(VFLAGS) --top-module ti59_audio --Mdir build/audio \
	  rtl/ti59_audio.sv $(CURDIR)/sim/audio_test.cpp >build/audio-build.log 2>&1
	build/audio/Vti59_audio

# A real-time recording of the simulated core, including its signed audio.
demo: prepare
	mkdir -p build/demo
	verilator --cc --exe --build -j 4 $(VFLAGS) --top-module ti59_system --Mdir build/demo/obj \
	  $(RTL) $(CURDIR)/sim/demo.cpp >build/demo/build.log 2>&1
	build/demo/obj/Vti59_system
	ffmpeg -hide_banner -loglevel error -y -i build/demo/ti59-card-and-printer-silent.mp4 \
	  -f s16le -ar 48000 -ac 1 -i build/demo/audio.s16le -c:v copy -c:a aac -b:a 128k \
	  -shortest -movflags +faststart build/demo/ti59-card-and-printer-with-sound.mp4

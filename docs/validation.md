# Validation — sound-effects update, October 28, 2026

Current RBF: `releases/TI59_20261028.rbf`, 3,371,500 bytes.
SHA-256: `1c31b41687036feeda1087348ea6a3e866994fe788d5326fec5bd04a5716b043`.
Installed by checksum-verified staged replacement and booted on physical MiSTer.
The preceding silent printer release is retained in `build/before-sound/`.

## Audio and regression checks

Verilator 5.052 on Mac: lint, audio, printer, card and full-system tests pass.
All 57 framework files still match the pinned Template_MiSTer revision.
The core produces signed 16-bit samples at exactly 48 kHz, connected to both
MiSTer audio channels with signed mode enabled. No framework sources changed.

- Audio test: 171,361 samples; exact 1,050-clock sample spacing; stable output
  between samples; silent reset/idle/Off; single-clock and sample-boundary key
  events; motor release; overlapping effects; and both reserved/mute values.
  Quiet measured 0.249513 times Normal RMS. Maximum combined sample magnitude
  was 5,383; the arithmetic also bounds all possible combinations below 14,000.
- Printer tests additionally verify motor activity during printing and paper
  feed, and silence during RAM initialization, clear and after completion.
- Card tests verify that the motor stops halfway out, remains off during front
  seating, and never starts for a malformed file, across one to four banks.
- Full system: 1,213,107,200 clocks / 1,443 native-240p source frames. Real
  firmware card and printer events produce audio. Keyboard presses click once;
  typematic repeats, releases and OSD keys do not retrigger. Arithmetic,
  PRINT/TRACE/ADV, stored 17, two card passes, program result 6, reload and reset
  continuity all pass with audio connected.
- `make demo` captures the native-480p RTL and original firmware, including its
  audio output, through ordinary keyboard/file inputs. No registers are patched.
  The 13.366667-second MP4 contains 401 video frames and 641,600 PCM source samples.
  Two card passes consume 490 bytes, the program produces 6, six lines print,
  and ADV feeds a blank line. Independent dot decoding confirms the printed 6.
  Card-pause and final-idle intervals are exactly silent in the source PCM;
  the demo peak is 3,399. H.264/AAC decoding and stream durations were checked.

Evidence: `build/sound-focused.log`, `build/sound-system-demo.log`,
`build/audio/effects.wav`, and `build/demo/ti59-card-and-printer-with-sound.mp4`.
The separate CPU-oracle and full mixer/freak tests below were run on the preceding
printer release; those implementations were unchanged by the sound update.

## Quartus and installation

Ubuntu Quartus 17.0.2 Lite, DE10-Nano, seed 1, 5m43s full compile. All 33 reported
STA checks have positive slack and zero total negative slack: setup +0.326 ns,
calculator setup +2.723, hold +0.247, recovery +3.915, removal +0.829 and pulse
width +0.396 ns. 11,137 ALMs, 15,344 registers, 3,265,458 memory bits, 423/553 RAM
blocks, 41 DSPs and 3 PLLs. Sound adds no ROM or block RAM.

Zero errors and zero critical warnings; 48 warnings. The one new warning is
Quartus converting the positive constant printer shift counts (2/4) to an
unsigned shift amount; it does not change their values. Other warnings are the
previously documented ROM/font/PLL/I/O messages. All 80 local synthesized source
and ROM inputs match the Ubuntu build. Reports: `output_files/`, `build/quartus.log`
and `build/hardware/sound/timing.json`.

On physical MiSTer, the new RBF accepts keyboard input, loads the two-pass card,
runs the imported program to 6, prints 6 and advances the paper in Direct Video.
The live 240p result is captured in `build/hardware/sound/card-result-print.png`.
Audio waveform/event timing is verified in simulation; physical HDMI/analog
sound has not been listened to or recorded. The synthesized effects are an
approximation of mechanical sounds, not original-hardware recordings.

The OSD sound setting was cycled through Quiet/Off/Normal, then left at Normal.
Original aspect was restored and native 480p was selected. RetroTINK's final
measurement reports a 1,600x525 total / 1,280x480 active HDMI wire raster,
confirming native 480p Direct Video (`build/hardware/sound/vmeas-final.json`).
MiSTer.ini was not modified; its SHA-256 remains
`3e0e5f729433aea4646cad1dc3fdb133824b485c1d692e9166b8e517414999cb`.
Temporary input/MGL helpers were removed and Zaparoo returned to its original
stopped state. No simulation, encoder or Quartus container remains running.

The earlier printer/video results below are retained as historical evidence for
the unchanged calculator, printer and video implementations.

## Previous thermal-printer validation, October 28, 2026

RBF: `releases/TI59_20261028.rbf`, 3,367,592 bytes.
SHA-256: `2a735940915c4aa6619a316d046471d4d529a42f607347a5737df3a989c14e35`.
Installed by checksum-verified staged replacement and booted on physical MiSTer.
The preceding magnetic-card release is retained in `build/before-printer/`.

### Simulation and framework

Verilator 5.052 on Mac. Lint and CPU/printer/card/system/video tests pass.
All 57 sys files match Template_MiSTer 5dda37366d02b04b8448da7b322235c1831af811.

- 2,800,000 instructions compared to unmodified Calc-U-59, including a card
  program returning 6. Oracle code is not synthesized.
- Printer: character and function codes, right-to-left input and buffer wrap,
  all raster dots of a numeric/mnemonic line, 4,165-instruction line BUSY and
  1,370-instruction half-line feed, blank paper, ring wrap, GO abort and clear.
- Full calculator with printer attached: 1,187,955,200 clocks / 1,413 source
  frames. PRINT produces 17; ADV sends two half-line feeds; TRACE prints CLR,
  2 +, 3 =, and 5. Two firmware card passes consume 490 bytes, the imported
  program returns 6, stored 17 survives, repeated loads work, and reset
  preserves video sync. Input tests wait for printer completion between keys.
- Card peripheral: 1–4 banks, streamed bytes, repeated CRD_READ, exact half-out
  position and hold for every bank, front seating, malformed sizes/addresses/
  checksums, OSD deferral/replacement, timeout, unsupported writes and reset.
- Video: 50,324,808 clocks. Native 240p/480p and both forced-scandoubler values,
  geometry, RGB doubling and native detail, gamma LUTs, aspect and integer
  metadata, plus Trace on/off colors while selected. Ink is confined to the 128x252 paper window; exactly 80x24 pixels
  of the half-ejected card are visible in the gap, clear of the printer.
- LED capture decoder checked at 320x240, 640x480 and 1280x960.

Tests use the real upstream video modules with a Verilator-only scope shim for
Quartus unnamed-generate visibility. No synthesized framework changes. The two
right-edge guard pixels of the upstream scandoubler are checked separately.
Logs: `build/printer-final-system.log`, `build/printer-regression.log`,
`build/printer-ram-test.log`, `build/printer-final-video.log`. `build/ti59-printer-preview.png` and
`build/card-animation/ti59-card-loading.mp4` are simulated previews.

### Quartus

A focused Quartus synthesis of the printer confirms 68,096 block-memory bits,
350 registers and 702 logic cells before integration. The paper uses a standard
synchronous two-port RAM template; all dot and feed tests pass with this version.
Its log and summary are in `build/printer/quartus-check/`.

Ubuntu Quartus 17.0.2 Lite, DE10-Nano, seed 1; final full compile 5m43s.
All 33 reported STA checks have positive slack and zero total negative slack.
Worst setup +0.579 ns; calculator setup +2.970; hold +0.245; recovery +3.953;
removal +0.393; minimum pulse width +0.396 ns.
10,902 ALMs, 15,014 registers, 3,265,458 memory bits, 423/553 RAM blocks,
38 DSPs, 3 PLLs. Zero errors, zero critical warnings, 47 warnings. Warnings
cover unused ROM write ports, removal of the three constant-zero upper font
bits, and upstream PLL/I/O assignments. The paper buffer is inferred RAM.
All 79 local synthesized source/ROM files match Ubuntu's inputs; the QSF
matches apart from compiler-updated LAST_QUARTUS_VERSION metadata.
Reports are in `output_files/`; full log is `build/quartus.log`.

### Physical MiSTer

The final RBF boots on physical MiSTer. In Direct Video 240p, PRINT emits 17,
TRACE prints the 2 + 3 = 5 calculation, and ADV moves the printed rows upward.
Native 480p with temporary normal HDMI provides clear 1280x960 screenshots:
the printed 17, CLR, 2 +, 3 = and 5 are decoded directly from the paper's dots.
Clear printer paper in the OSD produces an empty page; RCL 00 still returns 17.

RetroTINK measured this RBF's Direct Video:

| Mode | H / V | HDMI wire total / active |
| --- | --- | --- |
| 240p | 15.75 kHz / 60.11 Hz | 3200x262 / 2560x240 |
| Native 480p | 31.50 kHz / 60.00 Hz | 1600x525 / 1280x480 |

Horizontal repetition explains the wire widths; the core raster width is 640.
The RetroTINK output remained 3840x2160p60. Both forced-scandoubler combinations
were checked in simulation. Separate analog VGA hardware was not tested.
Native-480p Direct Video screenshot APIs can return partial frames; temporary
normal HDMI was used for clear GUI captures. Evidence is under
`build/hardware/printer/`.

With the printer attached, the OSD loads the two-pass card, RCL 00 still
returns the stored 17, and RST/R/S runs the imported program to 6. PRINT then
adds 6 to the existing page. The screenshot in `docs/ti59-hardware.png` is a
real 1280x960 hardware capture. Half-out geometry/hold is verified in simulation;
the live screenshot polling did not catch that brief animation phase.

MiSTer.ini was restored byte-for-byte, SHA-256
`3e0e5f729433aea4646cad1dc3fdb133824b485c1d692e9166b8e517414999cb`.
The restored Direct Video configuration was used to reload the card, run and
print 6 again. The core is left in native 480p with the sample card and paper
output present, Trace off. Temporary input helpers were removed, Zaparoo was
returned to its original stopped state, and the diagnostic tab was closed.
No Quartus containers or local simulation processes remain running.

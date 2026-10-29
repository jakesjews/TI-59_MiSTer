# Building and testing

[Back to the README](../README.md)

## Implementation

The TMC0501 state machine executes the original TI firmware. The implementation
models instruction-visible CPU behavior, rather than the original PMOS chip
pins and every sub-instruction timing detail. The PC-100 printer uses the
firmware's commands, instruction-based BUSY timing, a custom bitmap font and
a circular paper bitmap. Magnetic cards are read through the firmware's card
interface; magnetic flux timing and writing are not modeled.

The panel is a generated reconstruction of the calculator and PC-100A docking
station. LED digits, selected keys, paper output and moving cards are live FPGA
overlays. See [artwork provenance](../assets/README.md). Mechanical sounds are
synthesized approximations, not recordings of the original hardware.

## Framework and video

The `sys/` directory is an unchanged copy of Template_MiSTer revision
`5dda37366d02b04b8448da7b322235c1831af811`, checked October 28, 2026.
`make framework-check` verifies every upstream file against its hash manifest.

| GUI mode | Native raster and timing | Global forced scandoubler |
| --- | --- | --- |
| 240p | 640×240; 800×262 total; 12.6 MHz; 15.750 kHz / 60.115 Hz | Doubles to 640×480, 800×524 total; 31.500 kHz / 60.115 Hz |
| 480p | 640×480; 800×525 total; 25.2 MHz; 31.500 kHz / 60.000 Hz | Native output; never doubled again |

Normal HDMI always renders native 480p, regardless of the saved Direct Video
choice. `hps_io.direct_video` enables the 240p/480p selection, which is hidden
from the OSD during normal HDMI. 480p displays every row of the panel artwork.
240p samples alternate rows and honors MiSTer's `forced_scandoubler` setting.
Resolution changes take effect at a frame boundary; calculator reset never
stops sync.

Both modes use unmodified upstream `gamma_fast`, `video_mixer` and `video_freak`
modules. Parallel gamma LUTs support the native 480p pixel rate. The mixer
handles optional 240p scandoubling, and video_freak supplies aspect and integer
scaling metadata. HDMI scaling offers Normal, V-Integer, HV-Integer-,
HV-Integer+ and HV-Integer. Gamma is available in MiSTer's video settings.

Native RGB/sync serves Direct Video and analog output. Normal HDMI, and analog
with `vga_scaler=1`, use MiSTer's configured scaler output. Native analog shares
the source raster, so it also runs at 480p while normal HDMI is active. Aspect
and integer scaling affect the scaler, not native raster timing.

Audio is signed 16-bit PCM at 48 kHz on both channels, independent of video mode.
Quiet is one-quarter amplitude; Off is silent. Key taps do not repeat while
held, and motor sounds follow card transport and printer activity.

The mouse uses the existing `hps_io.ps2_mouse` packet interface. Pointer motion
accumulates half pixels on the same 640×480 logical panel in both video modes.
Hit testing and key highlights share `rtl/ti59_panel.vh`. A left press captures
one target, with an 80 ms minimum duration for firmware scanning. OSD/card-loader
ownership cancels capture and requires a fresh button-up report to rearm.

## Local checks

Use recent Python 3, GNU Make, Verilator and `uv`. The preparation scripts fetch
pinned chip dumps and record their hashes separately from the HDL. Generated
ROM images and build outputs are ignored by Git.

```sh
make prepare
make lint framework-check
bash tools/fetch_oracle.sh
make test
```

The optional differential oracle is Calc-U-59 under PolyForm Noncommercial
1.0.0, fetched into ignored `research/sources/`. Its unmodified C++ is used only
for local tests and is not synthesized.

`make test` runs CPU, printer, audio, mouse, calculator-system, video and
card-loader tests sequentially. The video test uses the real upstream mixer/freak modules
and checks both resolutions, forced scandoubling, artwork detail, gamma,
aspect ratios and integer scaling. A simulation-only scope shim models
Quartus name lookup for the mixer's unnamed generate block; no upstream
source is modified. Captures are written to `build/ti59-*.ppm`.

## Quartus build

The project targets the DE10-Nano using Quartus 17.0.2 Lite. The remote helper
is configured for the original development environment: SSH host `ubuntu`,
directory `~/dev/mister/TI59`, and Docker image
`theypsilon/quartus-lite-c5:17.0.2.docker0`.

```sh
bash build.sh remote
```

It copies reports and the RBF back to `output_files/`. On a Linux host with
Docker and the project files, `bash build.sh docker` runs the compile locally.
`QUARTUS_IMAGE` selects another compatible installed image. Check the timing
reports before deploying a build; successful compilation alone is not timing
closure. See [validation](validation.md) for the shipped build's evidence.

## Demo recording and hardware capture

`make demo` also requires FFmpeg. It records the simulated core loading a
two-pass card, running the imported program, printing its result and advancing
paper, with the core's actual synthesized audio. The MP4 is written to
`build/demo/ti59-card-and-printer-with-sound.mp4`.

For live screenshots with Zaparoo running on a MiSTer reachable through SSH:

```sh
uv run tools/mister_capture.py build/hardware/add.png \
  --keys '{esc}2+3{enter}' --expect '5.'
```

The helper reads the LED segments from the screenshot and can assert the
displayed value. It does not change video settings. Direct Video screenshots
may be low resolution or partial; temporarily disable Direct Video for larger
captures and restore the original `MiSTer.ini` afterward.

Further references: [research](research.md), [validation](validation.md) and
[firmware provenance](../roms/provenance.json).

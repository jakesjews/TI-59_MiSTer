# TI-59 source and implementation notes

Research and source collection: October 28, 2026.

## Hardware sources

* [Hynek Sladky, TI-58/59 HW Programming Guide (2014)](https://github.com/DennisD2/sigrok-ti5x-decoder/blob/12577e36397b1faee94d337f279129df153a8a60/docs/TI_58_59-HW-manual.pdf).
  The main instruction-set reference: CPU fields, BCD correction, SCOM and
  RAM protocols, keyboard connections, LED scan, and library interface.
  This is a reverse-engineered hardware guide, not a TI datasheet. In particular,
  its discussion of out-of-field IO digits and hexadecimal display patterns
  has qualifications; do not treat those edge cases as established silicon tests.
* [TI patent US4153937A](https://patents.google.com/patent/US4153937A/en),
  *Microprocessor system having high order capability*. Original manufacturer
  architecture, program/constant tables, register organization, and library
  organization. Cross-checked the SCOM/RAM/ROM capacities and interface against
  the hardware guide. It is not a timing-complete model of every peripheral.
* [TI PC-100A interface description (1978)](https://github.com/DennisD2/sigrok-ti5x-decoder/blob/12577e36397b1faee94d337f279129df153a8a60/docs/TI_Calculator_Printer_Interface.pdf).
  Printer-interface reference, together with the hardware guide and the
  original TI patent character tables.
* [TI-58/59 service manual](https://manualzz.com/doc/6324403/texas-instruments-ti-58--ti-59-calculator-service-manual).
  Manufacturer theory of operation and factory diagnostic keystrokes. The
  searchable mirror corroborates the 12-digit display, extra TI-59 RAM chips,
  card electronics and printer instruction family.
* [Internet Archive: TI Programmable 58-59 Quick Reference Guide (1977)](https://archive.org/details/TI58-59QuickReferenceGuideTexasInstruments1977).
  Located through Archive.org's metadata search, along with user newsletters
  and the 1983 TI-59 BASIC cross-compiler thesis. The browser could not open
  this item's detail page; no claim that its complete scan was read.

## Implementations examined

| Source | Revision / date | Use and limitations |
| --- | --- | --- |
| [Calc-U-59](https://github.com/tinue/Calc-U-59) | `e6325e955dff61aa51b596317436fae34249cb0c`, October 25, 2026 | Original-ROM CPU emulator, ROM dumps, register traces and detailed firmware annotations. Unmodified C++ CPU used only as a separately downloaded local differential-test oracle. PolyForm Noncommercial 1.0.0; not included in the synthesized HDL or vendored into this project. Issues list was empty when inspected. |
| [DennisD2/sigrok-ti5x-decoder](https://github.com/DennisD2/sigrok-ti5x-decoder) | `12577e36397b1faee94d337f279129df153a8a60`, December 12, 2024 | Hardware guide, printer documentation and a four-second power-on logic-analyzer recording from a working TI-59. README explicitly warns that decoding is incomplete. Recording collected, not yet used as a pin-level validation oracle. |
| [HrastProgrammer TI-59E](https://www.hrastprogrammer.com/ti59e/) | Retired project, inspected October 28, 2026 | Earlier original-ROM emulator; describes Hynek Sladky's ROM extraction and comparison with the patent. Distribution page forbids mirroring its files. No binaries or source copied into this project. |
| [TI5x Android](https://github.com/ldo/ti5x_android) | Discovered October 28, 2026 | Calculator-level alternative rather than a reusable TMC0501 HDL implementation. Not used. |
| [TI59R revival](https://breatharian.eu/hw/ti59/index_en.html) / [ET58](https://github.com/Panda381/ET58) | Discovered October 28, 2026 | Modern calculator recreations with extensions; not selected as hardware behavior references. |
| [jhallen/calculator TI-59 wiki](https://github.com/jhallen/calculator/wiki/TI-59) | August 21, 2021 wiki revision | Actual programming examples and explanations of Learn mode, program steps and AOS entry behavior. Wiki cloned and read. |

Searches included GitHub repositories/code for TI-59, TI59, TMC0501, Verilog,
VHDL and FPGA, general web searches, calculator community sites and Archive.org.
No reusable TI-59 HDL implementation was found in these searches. This is not
proof that none exists.

## Framework and implementation decisions

[Template_MiSTer](https://github.com/MiSTer-devel/Template_MiSTer) HEAD was
`5dda37366d02b04b8448da7b322235c1831af811` (October 16, 2026), verified live
before copying. All `sys/` files are byte-for-byte copies; `framework.sha256`
was generated from that upstream checkout, not from edited project files.
The top-level module follows the current template ports and frame-boundary reset
pattern. The calculator's PLL hierarchy matches the template's clock-group
constraints without modifying those constraints.

The calculator is a dedicated FPGA state machine, not a software emulator on a
soft CPU. A single-nibble datapath performs each 16-digit instruction, with a
fractional clock enable for 14,218.75 instructions/second and the original
fourfold slowdown in IDLE. This reproduces instruction-visible state; it does
not recreate the PMOS two-phase electrical interface or every sub-instruction
timing effect. Five CPU registers, the flag/KR/SR registers, SCOM constants and
data registers, 120 RAM registers and the library pointer are implemented.

The keyboard is the real KO/KP/KQ/KS/KT matrix. The display samples scanned
register values and leading-zero suppression rather than formatting a host
floating-point result. Independent 640x240 and 640x480 raster timings provide
native 240p and 480p. The unchanged upstream `gamma_fast` runs parallel RGB LUTs
at both pixel rates, then `video_mixer` optionally scandoubles 240p and
`video_freak` supplies display-enable and aspect/integer-scale metadata.
Native 480p bypasses the scandoubler even when the global force flag is set.
Resets never stop sync. The 640x480 indexed panel uses photo-reference imagegen
artwork; 240p samples alternate rows. Live LEDs and key highlights are rendered
by HDL. See `../assets/README.md` for the retained image and exact prompt.

Firmware is from the 2023 Datamath chip dumps preserved in Calc-U-59. Headers
identify the chips and original TI copyright. `roms/provenance.json` records
the pinned source URL and input/output hashes. Firmware is separate from the
GPL HDL license and generated ROM initialization files are ignored by Git. No claim is made that
the emulator's license relicenses TI's ROMs.

## Verification boundaries

Local Verilator compares instruction-visible CPU state with the separately
downloaded oracle. Whole-system tests exercise actual keyboard scan timing,
LED segments, arithmetic and memory, and count native video pixels/lines in
both modes, including reset continuity. Quartus synthesis, fit, assembly and
STA run on Ubuntu. See `validation.md` for completed checks and artifact hashes.

Card writing/export and persistent RAM remain unimplemented. Card loading and
the instruction-visible PC-100 printer are described below.
Unusual fractured-digit patterns, intentionally misphased IDLE/WAIT programs,
and undocumented out-of-field IO behavior need further comparisons with silicon.

## Magnetic-card extension (October 28, 2026)

Read-side TMC0594 support follows the card-reader section (pp. 20–21) of
Hynek Sladky's hardware guide and TI [US4006455](https://patents.google.com/patent/US4006455A/en).
The existing unmodified Calc-U-59 oracle and ROM annotations were used to
cross-check byte ordering, checksum rules and instruction-visible behavior;
none of its card implementation or artwork is compiled into this core.
The core implements already-decoded card bytes, not analog flux recovery.

The GUI motion was observed in [D. Meyer's 2007 reader video](https://commons.wikimedia.org/wiki/File:TI-59_Cardreader.ogv):
right-to-left feed behind the calculator, repeat for the second bank, then
slide into the front cue-card recess. The implementation uses newly drawn
card artwork and contains no video pixels. One pass is shown per loaded bank.
The user supplied a PC-100 docking photograph establishing the printer on the
left and calculator on the right. The card now pauses with exactly half its
length exposed in the gap before another pass or seating.


## Thermal-printer extension (October 28, 2026)

The TMC0251-facing interface implements OUT PRT, OUT PRT_FUNC, PRT_CLEAR,
PRT_STEP, PRT_PRINT and PRT_FEED, with the printer-present, Print, Advance and
Trace keyboard lines connected at their TI-59 positions. The calculator's own
firmware performs number formatting, trace decisions and program listing.
[Thermal printer patent US4020465A](https://patents.google.com/patent/US4020465A/en)
describes the 20-column, 5x7-dot character printer and reverse character-buffer
ordering. Table VII in US4153937 supplies the 64-character code assignment;
the glyph bitmaps in this project are independently drawn.

The unmodified Calc-U-59 oracle was consulted for behavioral cross-checks,
including its recording-derived 4,165-instruction line and 1,370-instruction
half-line feed durations. These durations count retired calculator instructions,
including the CPU's idle rate. They are not a claim of independently measured
printer electronics. No oracle printer implementation, font or artwork is
incorporated into the HDL or assets. The display uses a 128x512 circular dot
bitmap and frame-latched paper feed; it does not simulate electrical heating,
exact thermal dot intensity or physical paper mechanics. Printer output cannot
yet be exported, and paper that has left the screen cannot be browsed.

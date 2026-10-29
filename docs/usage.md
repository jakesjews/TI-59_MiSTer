# TI-59 user guide

[Back to the README](../README.md)

## Controls

Move a connected mouse to show the pointer, then **left-click** a calculator
key or one of the three printer buttons. Hovering highlights the target.
Hold **ADV** to keep feeding paper. Dragging while held keeps the original
button pressed until release; it does not press neighboring keys.
The pointer works in both 240p and 480p, including Direct Video and analog.
Mouse input is suspended while the MiSTer menu is open or a card is loading;
release the button before clicking again. Right-click and the wheel have no
calculator action. Keyboard and gamepad controls remain available.

Use arrows or the gamepad D-pad to move the blue highlight. **Space** or the
gamepad's **Press key** button presses the selected calculator key or printer
button. The right arrow moves from `=` to the three printer buttons; the left
arrow returns to the calculator. Configure the four gamepad actions in MiSTer's
button mapping: **Press key**, **2nd**, **INV**, **Clear**.

| Keyboard | Calculator |
| --- | --- |
| Number row / numeric keypad | 0–9 |
| `+ - * /`, keypad operators | Arithmetic |
| Enter or `=` | `=` |
| `.` | Decimal point |
| Tab or Y | 2nd |
| I | INV |
| Backspace or Escape | CLR |
| Z or Delete | CE |
| A–E or F1–F5 | User keys A–E |
| L | ln x |
| U | LRN |
| V | x↔t |
| K | x² |
| F | √x |
| Q | 1/x |
| H | SST |
| P / O / M | STO / RCL / SUM |
| W | yˣ |
| J | BST |
| X | EE |
| `[` / `]` or `(` / `)` | Parentheses |
| G / S | GTO / SBR |
| T / R | RST / R/S |
| N | +/− |
| F6 | Printer PRINT |
| F7 | Printer ADV |
| F8 | Toggle printer TRACE |

Secondary functions use **2nd**, then the key with the upper legend. For example,
`30`, 2nd, x² evaluates sin(30°). The firmware defaults to degrees.

**F12** opens the MiSTer menu and releases calculator keys while it is open.
**Power cycle** resets the calculator and clears its memory and printer paper.

### Try a program

Press these calculator keys in order:

1. **2nd**, **CE** to clear the program.
2. **LRN** to enter Learn mode.
3. **2**, **×**, **3**, **=**, **R/S** to record the program.
4. **LRN** to leave Learn mode.
5. **RST**, **R/S** to run it. The display should show `6.`.

## Thermal printer

**PRINT** (F6) prints the displayed value. **ADV** (F7) feeds one blank line;
holding the button continues feeding. **TRACE** (F8) toggles automatic printing
of calculations, with a gold outline when enabled. You can also use the three
highlighted buttons below the printer. The calculator's Prt, Adv, List and
alphanumeric printing operations use the same printer.

New lines emerge at the bottom and scroll upward. The red indicator lights
while the printer is busy. In Trace mode, let each line finish before entering
the next operation.

**Clear printer paper** in the menu clears the page and printer buffer without
clearing calculator memory. Old output scrolls out of view; saving paper or
browsing earlier output is not supported.

## Magnetic cards

Copy the [example card files](../examples/cards) to `games/TI59/` on MiSTer,
then choose **Load magnetic card** in the menu. Both examples use the default
memory partition. Load `multiply.crd`, then press **RST**, **R/S** (keyboard
**T**, **R**) to calculate `2 × 3 = 6`. `two-pass.crd` contains the same program
with two banks and two animated passes.

Load while the calculator is stopped and outside Learn mode. Each pass clears
the current calculation but retains stored memory outside the banks being
loaded. The file's memory partition must match the calculator's partition.
The default is 479 program steps / 60 data registers (partition byte `16`).
Use the TI's normal **2nd Op 17** partition operation before loading a card
that requires a different partition.

The card travels right to left, pauses halfway out, then makes its next pass
or moves into the front legend slot. A red card indicates a rejected file or
failed read and disappears after three seconds. If a later bank fails, earlier
successful banks remain loaded. Calculator input is disabled during loading.
Card writing is not supported.

### File formats

`.CRD` and `.BIN` files contain one to four raw 246-byte banks: 246, 492, 738
or 984 bytes in total. Each bank holds 240 program steps or 30 registers and
retains its bank number, program/data flag and protection header. Two banks
represent two passes of a card. The loader checks file size, headers and
checksums before insertion; the TI firmware then reads the card into memory.

The converter accepts headerless binary, `Calc-U-59-CRD` binary and the
`Calc-U-59 Card 1.0` text format. Cue-card artwork is not imported; the GUI uses
a generic TI card. Run these commands from the repository with Python 3:

```sh
python3 tools/card_image.py convert converted.crd original.u59
python3 tools/card_image.py convert combined.crd bank1.crd bank2.crd
python3 tools/card_image.py program multiply.crd 02 65 03 95 91
python3 tools/card_image.py inspect multiply.crd
```

Program arguments are hexadecimal bytes containing TI keycodes. The converter
packs them in physical card register/nibble order and generates both checksums.

## Library modules

The Master Library is present at power-on. Select a program with **2nd LRN**
(Pgm), followed by its two-digit number. For its diagnostic, select **01** and
press **SBR**, **=**; allow the program to finish.

**Load library module** accepts a `.ROM` file containing exactly 5,000 raw bytes
in TI library address order, with two packed BCD nibbles per byte. Textual hex
dumps are not accepted. Loading resets the calculator and replaces the library
until the core is reloaded. The loader does not reject short files, so verify
that the image is complete before loading it.

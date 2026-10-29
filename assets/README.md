# GUI artwork

`ti59-panel.png` was generated with the built-in imagegen tool on October 28,
2026, using the calculator photograph supplied by the user in this chat as a
visual reference. It is a generated reconstruction, not an original TI product
photograph or a pixel-exact scan. The calculator's trademarks and markings
identify the hardware being reproduced.

The current GUI uses `ti59-printer.png`, generated with the built-in imagegen
on October 28, 2026 from the user's PC-100A docking-station photo and the approved
`ti59-panel.png` calculator. The 1448x1086 generated asset is retained unchanged.
Its [complete generation prompt](printer-prompt.txt) records the intended layout.
Printer output, LED digits, highlights and moving cards are rendered by HDL.
The printer font is an original 5x7 bitmap design using the documented TI code
ordering. The card is original geometric art; no video frames are embedded.

The earlier calculator-only generated image is also retained unchanged. `tools/make_panel.py` resamples it
for a 640x480 GUI, converts it to a 256-color indexed ROM, and generates an original geometric magnetic-card sprite. Native 240p samples every
other artwork row; native 480p displays every row. LED digits and key selection
are live HDL overlays inside the calculator. The card moves behind the case
during a reader pass and in front when sliding into the legend slot. The current full-station image places the printer on the left. No frames from the reference video are
embedded in the artwork.

## Generation prompt

Use case: precise-object-edit. Asset type: photorealistic TI-59 calculator front panel texture for a working FPGA calculator UI. Edit the reference photograph into a clean, straight-on orthographic product photograph of this exact Texas Instruments TI Programmable 59 calculator. Preserve its tall roughly 1:2 body proportions, bronze and black materials, subtle real wear, all 45 keys in exactly five columns and nine rows, all exact original primary and secondary key labels, Texas Instruments logo and lettering, and lower TI Programmable 59 / Solid State Software lettering. Correct perspective so key centers form a straight evenly spaced grid. Show entire body, large and centered, with narrow even margins on a solid near-black background #11151a. REMOVE the loose magnetic card projecting to the right. REMOVE the TRIANGLE SOLUTION paper card from the inset above the keys: leave a realistic blank dark brown card recess. Make the upper LED glass window completely blank/unlit, a smooth dark smoked brown-red glass surface, NO lit numbers or faint digit shapes (live digits will be drawn by hardware). Soft even studio lighting with realistic plastic texture and subtle key shadows, no glare that obscures labels. No invented keys, no changed labels, no UI widgets, no captions outside the calculator. High resolution portrait image. Key rows must match reference exactly: A B C D E / 2nd INV lnx CE CLR / LRN x-exchange-t x-squared square-root-x 1/x / SST STO RCL SUM y-power-x / BST EE ( ) divide / GTO 7 8 9 multiply / SBR 4 5 6 minus / RST 1 2 3 plus / R/S 0 decimal plus-minus equals. Use the photo's exact mathematical glyphs.

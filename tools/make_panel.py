#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# dependencies = ["pillow>=12"]
# ///
"""Convert the generated photograph to an indexed FPGA ROM and magnetic-card sprite."""
from pathlib import Path
from PIL import Image, ImageDraw
ROOT = Path(__file__).resolve().parents[1]
FONT = {
 'A':[14,17,17,31,17,17,17], 'B':[30,17,17,30,17,17,30],
 'C':[14,17,16,16,16,17,14], 'D':[30,17,17,17,17,17,30],
 'E':[31,16,16,30,16,16,31], 'F':[31,16,16,30,16,16,16],
 'G':[14,17,16,23,17,17,15], 'H':[17,17,17,31,17,17,17],
 'I':[14,4,4,4,4,4,14], 'J':[7,2,2,2,2,18,12],
 'K':[17,18,20,24,20,18,17], 'L':[16,16,16,16,16,16,31],
 'M':[17,27,21,21,17,17,17], 'N':[17,25,21,19,17,17,17],
 'O':[14,17,17,17,17,17,14], 'P':[30,17,17,30,16,16,16],
 'Q':[14,17,17,17,21,18,13], 'R':[30,17,17,30,20,18,17],
 'S':[15,16,16,14,1,1,30], 'T':[31,4,4,4,4,4,4],
 'U':[17,17,17,17,17,17,14], 'V':[17,17,17,17,17,10,4],
 'W':[17,17,17,21,21,21,10], 'X':[17,17,10,4,10,17,17],
 'Y':[17,17,10,4,4,4,4], 'Z':[31,1,2,4,8,16,31],
 '0':[14,17,19,21,25,17,14], '1':[4,12,4,4,4,4,14],
 '2':[14,17,1,2,4,8,31], '3':[30,1,1,14,1,1,30],
 '4':[2,6,10,18,31,2,2], '5':[31,16,16,30,1,1,30],
 '6':[14,16,16,30,17,17,14], '7':[31,1,2,4,8,8,8],
 '8':[14,17,17,14,17,17,14], '9':[14,17,17,15,1,1,14],
 '+':[0,4,4,31,4,4,0], '-':[0,0,0,31,0,0,0],
 '=':[0,0,31,0,31,0,0], '/':[1,2,2,4,8,8,16],
 '*':[0,21,14,31,14,21,0], '.':[0,0,0,0,0,6,6],
 '(':[2,4,8,8,8,4,2], ')':[8,4,2,2,2,4,8],
 '<':[1,2,4,8,4,2,1], '>':[16,8,4,2,4,8,16],
 '^':[4,10,17,0,0,0,0], "'":[4,4,8,0,0,0,0],
 '|':[4,4,4,4,4,4,4], ':':[0,6,6,0,6,6,0],
}
def main():
    artwork = Image.open(ROOT / "assets/ti59-printer.png").convert("RGB")
    panel = artwork.resize((640,480), Image.Resampling.LANCZOS)
    def text(image, x, y, s, color, scale=1):
        draw = ImageDraw.Draw(image)
        for ch in s.upper():
            for py, bits in enumerate(FONT.get(ch, [0]*7)):
                for px in range(5):
                    if bits & (16 >> px):
                        draw.rectangle((x+px*scale, y+py*scale,
                                        x+(px+1)*scale-1, y+(py+1)*scale-1), fill=color)
            x += 6*scale
    indexed=panel.quantize(colors=256,method=Image.Quantize.MEDIANCUT,dither=Image.Dither.NONE)
    roms=ROOT/'roms';roms.mkdir(exist_ok=True)
    (roms/'panel.hex').write_text(''.join(f'{v:02x}\n' for v in indexed.tobytes()))
    palette=indexed.getpalette()
    (roms/'panel_palette.hex').write_text(''.join(bytes(palette[i:i+3]).hex()+'\n' for i in range(0,768,3)))
    # Original geometric card art, not a frame or asset copied from the video.
    card=Image.new('L',(256,32),0)
    draw=ImageDraw.Draw(card)
    draw.rectangle((0,0,159,23),fill=1)
    draw.rectangle((1,1,158,22),fill=2)
    draw.rectangle((2,2,157,10),fill=3)
    text(card,6,3,"TI PROGRAMMABLE 59",2)
    for x in (2,33,64,95,126,157): draw.line((x,13,x,22),fill=4)
    draw.line((2,12,157,12),fill=4)
    draw.line((2,22,157,22),fill=4)
    for i,ch in enumerate("ABCDE"): text(card,14+i*31,14,ch,3)
    (roms/'card.hex').write_text(''.join(f'{v:x}\n' for v in card.tobytes()))
    # Original 5x7 bitmap drawings; character ordering follows TI US4153937,
    # Table VII. No emulator font or printer assets are incorporated.
    symbols = {
      ' ': [0]*7, 'x':[0,0,17,10,4,10,17], 'e':[0,0,14,17,31,16,14],
      '√':[0,3,2,18,10,6,2], 'π':[0,0,31,10,10,10,19],
      ',':[0,0,0,0,6,4,8], '↑':[4,14,21,4,4,4,4],
      '%':[25,26,2,4,8,11,19], '↔':[0,10,27,31,27,10,0],
      'ˣ':[17,10,4,10,17,0,0], 'x̄':[31,0,17,10,4,10,17],
      '²':[12,18,4,8,30,0,0], '?':[14,17,1,2,4,0,4],
      '÷':[0,4,0,31,0,4,0], '!':[4,4,4,4,4,0,4],
      'Ⅱ':[27,10,10,10,10,10,27], '△':[0,4,4,10,10,17,31],
      'Π':[31,10,10,10,10,10,27], 'Σ':[31,16,8,4,8,16,31],
    }
    glyphs = list(' 0123456789ABCDE-FGHIJKLMNOPQRST.UVWXYZ+') + [
        'x','*','√','π','e','(',')',',','↑','%','↔','/','=',"'",'ˣ','x̄','²','?','÷','!','Ⅱ','△','Π','Σ']
    assert len(glyphs)==64
    font = {**FONT,**symbols}
    (roms/'printer_font.hex').write_text(''.join(f'{row:02x}\n' for ch in glyphs for row in [*font[ch],0]))
    build=ROOT/'build';build.mkdir(exist_ok=True)
    indexed.convert('RGB').save(build/'panel.png')
    print('Generated 640x480 indexed photographic panel, 256-color palette and magnetic-card sprite')

if __name__=='__main__':main()

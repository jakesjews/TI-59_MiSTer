#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# dependencies = ["pillow>=12"]
# ///
"""Capture a running TI59 through Zaparoo; optionally send keyboard macros.

Example: uv run tools/mister_capture.py build/hardware/add.png --keys '2+3{enter}'
This never changes MiSTer.ini. Disable Direct Video temporarily for larger captures.
"""
import argparse
import base64
import io
import json
import math
import shlex
import subprocess
import time
from pathlib import Path
from PIL import Image


def rpc(host, method, params=None):
    request = method if params is None else method + ":" + json.dumps(params)
    command = shlex.join(["/media/fat/Scripts/zaparoo.sh", "-api", request])
    response = subprocess.run(["ssh", "-o", "BatchMode=yes", "-o", "LogLevel=ERROR",
                               f"root@{host}", command], capture_output=True,
                              text=True, timeout=60, check=True)
    result = json.loads(response.stdout)
    if isinstance(result, dict) and "error" in result:
        raise RuntimeError(result["error"])
    return result


def read_leds(image):
    # Sample segment centers in the calculator glass on the 640x480 logical panel.
    # Small interior rectangles tolerate either capture/downsampling pixel phase.
    samples = [(2,0,5,1), (6,3,7,6), (6,12,7,16), (2,18,5,19),
               (0,12,1,16), (0,3,1,6), (2,8,5,9), (9,18,10,19)]
    glyphs = {0: " ", 0x3f: "0", 6: "1", 0x5b: "2", 0x4f: "3", 0x66: "4",
              0x6d: "5", 0x7d: "6", 7: "7", 0x7f: "8", 0x6f: "9", 0x40: "-", 0x39: "C"}
    if image.width * 3 != image.height * 4:
        raise ValueError(f"Incomplete or unexpected capture size: {image.size}")
    out = ""
    for digit in range(12):
        bits = 0
        for bit, (x0,y0,x1,y1) in enumerate(samples):
            left=math.floor((430+12*digit+x0)*image.width/640)
            right=math.ceil((431+12*digit+x1)*image.width/640)
            top=math.floor((104+y0)*image.height/480)
            bottom=math.ceil((105+y1)*image.height/480)
            pixels=(image.getpixel((x,y))[:3] for y in range(top,bottom) for x in range(left,right))
            lit=any(red>80 and red>green*1.5 and red>blue*1.5 for red,green,blue in pixels)
            bits |= int(lit) << bit
        out += glyphs.get(bits & 0x7f, "?") + ("." if bits & 0x80 else "")
    return out.strip()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("output", type=Path)
    parser.add_argument("--host", default="mister")
    parser.add_argument("--keys")
    parser.add_argument("--settle", type=float, default=1)
    parser.add_argument("--expect", help="fail if the captured LED text differs")
    args = parser.parse_args()
    if args.keys:
        rpc(args.host, "input.keyboard", {"keys": args.keys})
        time.sleep(args.settle)
    # The first capture after a raster change can contain stale dimensions.
    # Reject partial frames instead of interpreting their pixels as LED state.
    for attempt in range(3):
        shot = rpc(args.host, "screenshot")
        data = base64.b64decode(shot["data"])
        image = Image.open(io.BytesIO(data)).convert("RGB")
        if image.width * 3 == image.height * 4:
            break
        if attempt == 2:
            raise ValueError(f"Incomplete capture after three attempts: {image.size}")
        time.sleep(0.5)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_bytes(data)
    display = read_leds(image)
    print(json.dumps({"image": str(args.output), "size": image.size, "display": display}))
    if args.expect is not None and display != args.expect:
        raise SystemExit(f"Expected {args.expect!r}, captured {display!r}")


if __name__ == "__main__":
    main()

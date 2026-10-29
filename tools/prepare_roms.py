#!/usr/bin/env python3
"""Convert the archived Datamath TI-59 chip dumps; keep ROMs separate from HDL.

Pass a Calc-U-59 checkout or use the pinned public archive. No emulator code
is embedded in the FPGA. Input headers identify Texas Instruments copyright.
"""
import argparse
import hashlib
import json
import re
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
REV = "e6325e955dff61aa51b596317436fae34249cb0c"
URL = f"https://raw.githubusercontent.com/tinue/Calc-U-59/{REV}/roms/"

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, help="local Calc-U-59 checkout")
    args = parser.parse_args()
    hashes = {}
    def read(name):
        data = ((args.source / "roms" / name).read_bytes() if args.source else
                urllib.request.urlopen(URL + name, timeout=30).read())
        hashes[name] = hashlib.sha256(data).hexdigest()
        return data.decode("utf-8-sig")
    words = []
    for name, count in [("TMC0582", 2560), ("TMC0583", 2560), ("TMC0571B", 1024)]:
        values = []
        for line in read(f"calculator/{name}.txt").splitlines():
            if re.match(r"^[0-9A-F]{4}: ", line):
                values.extend(int(x, 16) for x in line.split(":", 1)[1].split())
        assert len(values) == count and max(values) < 8192, name
        words.extend(values)
    constants = []
    for name in ["TMC0582", "TMC0583"]:
        data = read(f"calculator/{name}-CONST-K.txt")
        values = re.findall(r"^\d{3}: ([0-9A-F]{16})\s*$", data, re.M)
        assert len(values) == 32, name
        constants.extend(values)
    lib = []
    for line in read("solid-state/TMC0541.txt").splitlines():
        if re.match(r"^\d{4}: ", line):
            lib.extend(int(x, 16) for x in line.split(":", 1)[1].split())
    assert len(lib) == 5000, len(lib)
    out = ROOT / "roms"
    out.mkdir(exist_ok=True)
    images = {
        "firmware.hex": "".join(f"{x:04x}\n" for x in words + [0] * 2048),
        "firmware.bin": "".join(f"{x:013b}\n" for x in words + [0] * 2048),
        "constants.hex": "\n".join(constants) + "\n",
        "library.hex": "".join(f"{x:02x}\n" for x in lib + [0] * (8192 - 5000)),
    }
    for name, data in images.items():
        (out / name).write_text(data)
    (out / "provenance.json").write_text(json.dumps({
        "source": URL, "sha256_inputs": hashes,
        "sha256_outputs": {k: hashlib.sha256(v.encode()).hexdigest() for k, v in images.items()},
        "copyright": "Original firmware and data: Texas Instruments, 1977. Not covered by the HDL license."
    }, indent=2) + "\n")
    print("Prepared 6144 instruction words, 64 constants, 5000 Master Library bytes")

if __name__ == "__main__":
    main()

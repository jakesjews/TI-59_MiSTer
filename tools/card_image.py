#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
"""Create, convert, combine and validate raw TI-59 magnetic-card bank images.

Each 246-byte bank contains the hardware header, 240 payload bytes and two
checksum bytes. This format is also the legacy headerless Calc-U-59 format.
"""
import argparse
from pathlib import Path
import re


def checksum(bank):
    return (sum(v & 15 for v in bank[:3]) +
            sum((v >> 4) + (v & 15) for v in bank[4:244])) & 15


def validate(raw):
    if len(raw) not in (246, 492, 738, 984):
        raise ValueError('Expected 1–4 complete 246-byte banks')
    for offset in range(0, len(raw), 246):
        b = raw[offset:offset+246]
        if not (2 <= (b[0] & 15) <= 12 and (b[1] & 15) <= 1 and
                (b[2] & 15) in (0, 3, 6, 9)):
            raise ValueError(f'Invalid header at offset {offset}')
        if any((v & 15) != checksum(b) for v in b[244:]):
            raise ValueError(f'Invalid checksum at offset {offset}')
    return raw


def read(path):
    raw = Path(path).read_bytes()
    if raw.startswith(b'Calc-U-59-CRD'):
        raw = raw[len(b'Calc-U-59-CRD'):]
    elif raw.startswith(b'Calc-U-59 Card 1.0'):
        # Independently parse the documented interchange format. Cue-card
        # metadata is optional and has no counterpart in the magnetic bytes.
        fields, rows, section, has_data = {}, [], '', False
        for line in raw.decode().splitlines()[1:]:
            line = line.split('#', 1)[0].strip()
            if not line:
                continue
            if line.endswith(':'):
                section = line[:-1].upper()
                has_data |= section == 'DATA'
                continue
            if section == 'HEADER':
                key, value = line.split(':', 1)
                fields[key.strip().lower()] = value.strip()
            elif section == 'DATA':
                match = re.fullmatch(r'R(\d{3}):\s*((?:[0-9a-fA-F]{2}\s*){8})', line)
                if not match or len(rows) >= 30:
                    raise ValueError(f'Invalid register row: {line}')
                # Labels are informational; bank 2 normally starts at R030.
                rows.append(bytes.fromhex(match[2]))
        if not has_data:
            raise ValueError('Missing DATA section')
        b = bytearray(246)
        partition = int(fields['partition'], 16)
        bank = int(fields['bank'])
        kind = fields['datatype'].lower()
        protection = fields['protection'].lower()
        if bank not in range(1, 5) or kind not in ('program', 'data') or protection not in ('yes', 'no'):
            raise ValueError('Invalid text card header')
        b[:4] = bytes((partition, 0x11 if kind == 'program' else 0x10,
                       0x10 + 3*(bank-1), 0x10 if protection == 'yes' else 0))
        for index, row in enumerate(rows):
            b[4+index*8:12+index*8] = row
        b[244:] = bytes((int(fields['checksum'], 16),))*2
        raw = bytes(b)
    return validate(raw)


def program(codes, bank=1, partition=6):
    if len(codes)>240 or bank not in range(1,5) or partition not in range(2,13):
        raise ValueError('A bank holds at most 240 steps; bank 1–4; partition 2–12')
    b = bytearray(246)
    b[:4] = bytes((0x10+partition, 0x11 if partition >= bank*3 else 0x10, 0x10+(bank-1)*3, 0))
    for step, value in enumerate(codes):
        if not 0 <= value <= 255:
            raise ValueError('Program codes must be bytes')
        b[4+(step//8)*8+7-step%8] = ((value & 15)<<4)|(value>>4)
    b[244:] = bytes((checksum(b),))*2
    return validate(b)


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    sub=parser.add_subparsers(dest='command', required=True)
    p=sub.add_parser('program', help='Pack hexadecimal TI keycodes (e.g. 02 65 03 95 91)')
    p.add_argument('output',type=Path);p.add_argument('codes',nargs='+')
    p.add_argument('--bank',type=int,default=1);p.add_argument('--partition',type=int,default=6)
    p=sub.add_parser('convert', help='Convert raw/headered/text cards, or concatenate banks')
    p.add_argument('output',type=Path);p.add_argument('inputs',nargs='+',type=Path)
    p=sub.add_parser('inspect');p.add_argument('input',type=Path)
    args=parser.parse_args()
    try:
        if args.command=='program':
            raw=program([int(c,16) for c in args.codes],args.bank,args.partition)
        elif args.command=='convert':
            raw=validate(b''.join(read(p) for p in args.inputs))
        else:
            raw=read(args.input)
        if args.command!='inspect':
            args.output.write_bytes(raw)
        for offset in range(0,len(raw),246):
            b=raw[offset:offset+246]
            print(f'Bank {(b[2]&15)//3+1}: partition {(b[0]&15)*80-1} steps, '
                  f'{"program" if b[1]&1 else "data/mixed"}, checksum {checksum(b):X}')
    except (ValueError,KeyError,OSError) as error:
        parser.error(str(error))

if __name__=='__main__': main()

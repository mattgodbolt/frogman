#!/usr/bin/env python3
"""Analyze game.asm to find all addresses needing labels."""

import re

with open('game.asm') as f:
    lines = f.readlines()

# Compute address for each line
addr = 0x4800
addr_at_line = {}  # line_index -> address at start of that line
label_at_addr = {}  # address -> label_name

for i, line in enumerate(lines):
    stripped = line.strip()
    s = stripped.split(';')[0].strip()

    addr_at_line[i] = addr

    # Labels
    m = re.match(r'^\.(\w+)', s)
    if m:
        label_at_addr[addr] = m.group(1)
        continue

    if not s or s.startswith(';'):
        continue

    if s.startswith('ORG'):
        addr = int(re.search(r'&([0-9A-Fa-f]+)', s).group(1), 16)
        addr_at_line[i] = addr
        continue

    # Handle chained instructions with ':'
    if ':' in s:
        parts = [p.strip() for p in s.split(':')]
        for part in parts:
            if not part:
                continue
            part_clean = part.split(';')[0].strip()
            if not part_clean:
                continue
            if part_clean in ['PHA','PLA','TXA','TAX','TYA','TAY','INX','INY',
                              'DEX','DEY','CLC','SEC','SEI','CLI','RTS','RTI',
                              'NOP','BRK','TSX','TXS']:
                addr += 1
            elif (part_clean.startswith('ASL A') or part_clean.startswith('LSR A') or
                  part_clean.startswith('ROL A') or part_clean.startswith('ROR A')):
                addr += 1
            elif re.match(r'\w+\s+&[0-9A-Fa-f]{3,4}', part_clean):
                addr += 3
            elif re.match(r'\w+\s+&[0-9A-Fa-f]{1,2}(,[XY])?$', part_clean):
                addr += 2
            elif re.match(r'\w+\s+#', part_clean):
                addr += 2
            elif re.match(r'\w+\s+\w+', part_clean):
                addr += 3
            else:
                addr += 1
        continue

    if s.startswith('EQUB'):
        equb_part = s[4:].strip()
        count = len([x.strip() for x in equb_part.split(',') if x.strip()])
        addr += count
        continue

    # Single instruction
    instr = s
    if instr in ['RTS','RTI','SEI','CLI','PHA','PLA','TXA','TAX','TYA','TAY',
                 'TXS','TSX','INX','INY','DEX','DEY','CLC','SEC','NOP','BRK']:
        addr += 1
    elif (instr.startswith('ASL A') or instr.startswith('LSR A') or
          instr.startswith('ROL A') or instr.startswith('ROR A')):
        addr += 1
    elif re.match(r'(BCC|BCS|BEQ|BNE|BPL|BMI|BVC|BVS)\s+', instr):
        addr += 2
    elif '#' in instr:
        addr += 2
    elif re.match(r'\w+\s+\((&[0-9A-Fa-f]{2}|&[0-9A-Fa-f]{2})\)', instr):
        addr += 2
    elif re.match(r'\w+\s+\(&[0-9A-Fa-f]{2},[XY]\)', instr):
        addr += 2
    elif re.match(r'\w+\s+\(&[0-9A-Fa-f]{2}\),[XY]', instr):
        addr += 2
    elif re.match(r'\w+\s+&[0-9A-Fa-f]{3,4}', instr):
        addr += 3
    elif re.match(r'\w+\s+&[0-9A-Fa-f]{1,2}(,[XY])?$', instr):
        addr += 2
    elif re.match(r'\w+\s+\w+', instr):
        # label reference
        addr += 3
    else:
        addr += 1

print(f'Final address: &{addr:04X} (expected &5800)')

# Build reverse map: address -> line_index for lines that START at that address
line_for_addr = {}
for li, a in addr_at_line.items():
    if a not in line_for_addr:
        line_for_addr[a] = li

# Now find all references
refs = set()
for i, line in enumerate(lines):
    if 'EQUB' in line:
        continue
    for m in re.finditer(r'&(4[89A-Fa-f][0-9A-Fa-f]{2}|5[0-7][0-9A-Fa-f]{2})', line):
        a = int(m.group(1), 16)
        if 0x4800 <= a <= 0x57FF:
            refs.add(a)

unlabeled = sorted(refs - set(label_at_addr.keys()))
print(f'\nUnlabeled addresses needing labels: {len(unlabeled)}')
for a in unlabeled:
    if a in line_for_addr:
        li = line_for_addr[a]
        print(f'  &{a:04X} -> line {li+1}: {lines[li].rstrip()[:70]}')
    else:
        print(f'  &{a:04X} -> NOT FOUND as line start! (self-mod target?)')

labeled = sorted(refs & set(label_at_addr.keys()))
print(f'\nAlready labeled: {len(labeled)}')
for a in labeled:
    print(f'  &{a:04X} = {label_at_addr[a]}')

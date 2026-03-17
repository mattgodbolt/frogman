#!/usr/bin/env python3
"""
Transform game.asm: replace all hard-coded &4800-&57FF addresses with symbolic labels.

Strategy:
1. Compute exact byte address of every line
2. For each referenced address, determine if it's:
   a. A line start -> add label before that line
   b. Inside an instruction operand (self-mod) -> label parent + offset
   c. Inside EQUB data -> add label before that EQUB line
3. Handle LDX #lo / LDY #hi OSCLI pointer pairs
4. Replace all references with label names
"""

import re
import copy

with open('game.asm') as f:
    orig_lines = f.read().split('\n')

# ============================================================
# Address computation
# ============================================================

def compute_instr_size(s):
    s = s.strip()
    if not s:
        return 0
    if s in ['RTS','RTI','SEI','CLI','PHA','PLA','TXA','TAX','TYA','TAY',
             'TXS','TSX','INX','INY','DEX','DEY','CLC','SEC','NOP','BRK']:
        return 1
    if s.startswith(('ASL A','LSR A','ROL A','ROR A')):
        return 1
    if re.match(r'(BCC|BCS|BEQ|BNE|BPL|BMI|BVC|BVS)\s+', s):
        return 2
    if '#' in s:
        return 2
    if re.match(r'\w+\s+\(&[0-9A-Fa-f]{2}\)', s):
        return 2
    if re.match(r'\w+\s+\(&[0-9A-Fa-f]{2},[XY]\)', s):
        return 2
    if re.match(r'\w+\s+\(&[0-9A-Fa-f]{2}\),[XY]', s):
        return 2
    if re.match(r'\w+\s+&[0-9A-Fa-f]{3,4}', s):
        return 3
    if re.match(r'\w+\s+&[0-9A-Fa-f]{1,2}(,[XY])?$', s):
        return 2
    if re.match(r'\w+\s+\w+', s):
        return 3
    return 1

def line_bytes(line):
    """Compute number of bytes a line emits."""
    stripped = line.strip()
    s = stripped.split(';')[0].strip()
    if not s or s.startswith(';') or s.startswith('.') or s.startswith('ORG'):
        return 0
    if ':' in s:
        total = 0
        for part in s.split(':'):
            pc = part.split(';')[0].strip()
            if pc:
                total += compute_instr_size(pc)
        return total
    if s.startswith('EQUB'):
        equb_part = s[4:].strip()
        return len([x.strip() for x in equb_part.split(',') if x.strip()])
    return compute_instr_size(s)

# Compute addresses
addr = 0x4800
line_addr = []  # index -> address at start of line
for i, line in enumerate(lines := orig_lines):
    stripped = line.strip()
    s = stripped.split(';')[0].strip()
    line_addr.append(addr)
    if s.startswith('ORG'):
        addr = int(re.search(r'&([0-9A-Fa-f]+)', s).group(1), 16)
        line_addr[i] = addr
        continue
    addr += line_bytes(line)

assert addr == 0x5800, f"Final address &{addr:04X} != &5800"

# Build maps
addr_to_first_line = {}
for i, a in enumerate(line_addr):
    if a not in addr_to_first_line:
        addr_to_first_line[a] = i

existing_labels = {}  # addr -> name
for i, line in enumerate(lines):
    m = re.match(r'^\s*\.(\w+)', line)
    if m:
        existing_labels[line_addr[i]] = m.group(1)

# ============================================================
# Collect all &4800-&57FF references (not in EQUB lines)
# ============================================================

all_refs = set()
for i, line in enumerate(lines):
    if 'EQUB' in line:
        continue
    for m in re.finditer(r'&(4[89A-Fa-f][0-9A-Fa-f]{2}|5[0-7][0-9A-Fa-f]{2})', line):
        a = int(m.group(1), 16)
        if 0x4800 <= a <= 0x57FF:
            all_refs.add(a)

# ============================================================
# For self-mod: find parent instruction
# ============================================================

# Build instruction map: list of (addr, size, line_index)
instrs = []
a2 = 0x4800
for i, line in enumerate(lines):
    stripped = line.strip()
    s = stripped.split(';')[0].strip()
    if not s or s.startswith(';') or s.startswith('.') or s.startswith('ORG'):
        if s.startswith('ORG'):
            a2 = int(re.search(r'&([0-9A-Fa-f]+)', s).group(1), 16)
        continue
    if ':' in s:
        for part in s.split(':'):
            pc = part.split(';')[0].strip()
            if pc:
                sz = compute_instr_size(pc)
                instrs.append((a2, sz, i))
                a2 += sz
        continue
    if s.startswith('EQUB'):
        equb_part = s[4:].strip()
        count = len([x.strip() for x in equb_part.split(',') if x.strip()])
        # Each EQUB byte is 1 "instruction" of size 1 (for data)
        instrs.append((a2, count, i))
        a2 += count
        continue
    sz = compute_instr_size(s)
    instrs.append((a2, sz, i))
    a2 += sz

def find_parent(target):
    """Find instruction containing address 'target' as operand."""
    for ia, isz, ili in instrs:
        if ia < target < ia + isz:
            return ia, isz, ili, target - ia
    return None, None, None, None

# ============================================================
# Assign names
# ============================================================

# Descriptive names for known addresses
descriptive = {
    0x4800: 'tile_source_lut',
    0x4880: 'collision_flags',
    0x4A28: 'wait_for_space_done',
    0x4AD6: 'check_passthrough',
    0x4BE2: 'fall_step_table',
    0x4BEA: 'fall_loop',
    0x4C12: 'get_tile_at_frog',
    0x4C29: 'check_tile_solid',
    0x4C52: 'tile_type_table',
    0x4C5F: 'get_tile_at_pos',
    0x4C79: 'set_tile_at_pos',
    0x4C97: 'crtc_table',
    0x4D8F: 'move_down',
    0x4E58: 'scroll_step_table_8',
    0x4E60: 'scroll_step_table_4',
    0x4E64: 'read_key',
    0x4E6B: 'get_tile_type',
    0x4E80: 'move_right',
    0x4FA5: 'move_up_check',
    0x5160: 'check_tile_effect',
    0x51C7: 'move_right_check',
    0x5212: 'move_left_check',
    0x52C7: 'scroll_obj_index',
    0x52EF: 'collision_check_table',
    0x536C: 'collect_item',
    0x5386: 'clear_tile_pickup',
    0x539C: 'drop_item',
    0x53F9: 'place_tile_1c',
    0x540C: 'place_tile_1d',
    0x5411: 'place_tile_00',
    0x5416: 'draw_digit',
    0x544E: 'digit_mask_table',
    0x5456: 'str_title',
    0x546F: 'str_press_space',
    0x5488: 'draw_string',
    0x549E: 'handle_map_reveal',
    0x5538: 'palette_fade_table',
    0x553F: 'palette_fade_last',
    0x55E1: 'handle_special_tile',
    0x564F: 'load_level_data',
}

# Rename existing l_XXXX labels where we have better names
renames = {}
for addr_val, new_name in descriptive.items():
    if addr_val in existing_labels:
        old_name = existing_labels[addr_val]
        if old_name != new_name and old_name.startswith('l_'):
            renames[old_name] = new_name

# Build the complete label map
# Start with existing labels (applying renames)
label_map = {}
for a, name in existing_labels.items():
    label_map[a] = renames.get(name, name)

# For self-mod targets, we need to label the parent instruction
selfmod = {}  # target_addr -> (parent_addr, offset)
labels_to_insert = {}  # addr -> name (new labels to insert before a line)

for a in sorted(all_refs):
    if a in label_map:
        continue  # Already labeled

    if a in addr_to_first_line:
        # Address starts a line - add a label
        name = descriptive.get(a, f'l_{a:04X}')
        label_map[a] = name
        labels_to_insert[a] = name
    else:
        # Self-mod target
        parent, sz, li, offset = find_parent(a)
        if parent is not None:
            selfmod[a] = (parent, offset)
            # Ensure parent has a label
            if parent not in label_map:
                name = descriptive.get(parent, f'l_{parent:04X}')
                label_map[parent] = name
                labels_to_insert[parent] = name
        else:
            print(f"WARNING: &{a:04X} not found!")

# ============================================================
# Handle OSCLI LDX #lo / LDY #hi pairs
# ============================================================
# Pattern: LDX #&XX followed by LDY #&YY where &YYXX is in range
# These need to become LDX #LO(label) / LDY #HI(label)

oscli_pairs = []  # list of (ldx_line, ldy_line, target_addr)
for i in range(len(lines) - 1):
    s1 = lines[i].strip().split(';')[0].strip()
    s2 = lines[i+1].strip().split(';')[0].strip()
    m1 = re.match(r'LDX #&([0-9A-Fa-f]{2})', s1)
    m2 = re.match(r'LDY #&([0-9A-Fa-f]{2})', s2)
    if m1 and m2:
        lo = int(m1.group(1), 16)
        hi = int(m2.group(1), 16)
        addr_val = (hi << 8) | lo
        if 0x4800 <= addr_val <= 0x57FF:
            oscli_pairs.append((i, i+1, addr_val))

# OSCLI string labels
oscli_names = {
    0x48CB: 'oscli_load_level_g',
    0x48E2: 'oscli_load_fastio',
    0x4903: 'oscli_load_level_t',
    0x4924: 'oscli_load_level_s',
    0x493F: 'oscli_load_tabs',
    0x5660: 'oscli_disc',
    0x5674: 'oscli_load_level_m',
    0x56B2: 'oscli_load_level_t2',
    0x56CE: 'oscli_load_tbar',
}

for ldx_li, ldy_li, target in oscli_pairs:
    if target not in label_map:
        name = oscli_names.get(target, f'oscli_{target:04X}')
        label_map[target] = name
        if target not in existing_labels:
            labels_to_insert[target] = name

print(f"OSCLI pairs found: {len(oscli_pairs)}")
for ldx_li, ldy_li, target in oscli_pairs:
    name = label_map.get(target, f'???')
    print(f"  lines {ldx_li+1}-{ldy_li+1}: &{target:04X} = {name}")

# Also handle standalone LDX / LDY with string pointers where they're not adjacent
# e.g. line 194: LDX #&56, line 195: LDY #&54 -> &5456
# line 203: LDX #&6F, line 204: LDY #&54 -> &546F

# Check for LDY-only lines that reference hi-byte of in-range addresses
# These are the string pointer pairs with comments
more_pairs = []
for i in range(len(lines) - 1):
    s1 = lines[i].strip().split(';')[0].strip()
    s2 = lines[i+1].strip().split(';')[0].strip()
    # LDX #&XX (string pointer low)
    m1 = re.match(r'LDX #&([0-9A-Fa-f]{2})', s1)
    if m1 and 'String pointer' in lines[i]:
        m2 = re.match(r'LDY #&([0-9A-Fa-f]{2})', s2)
        if m2:
            lo = int(m1.group(1), 16)
            hi = int(m2.group(1), 16)
            addr_val = (hi << 8) | lo
            if 0x4800 <= addr_val <= 0x57FF and (i, i+1, addr_val) not in oscli_pairs:
                more_pairs.append((i, i+1, addr_val))

oscli_pairs.extend(more_pairs)

# Also find more patterns by looking for any LDX #lo / LDY #hi where
# the combined address matches a known label
extra_pairs = []
for i in range(len(lines) - 3):
    for j in range(i+1, min(i+4, len(lines))):
        s1 = lines[i].strip().split(';')[0].strip()
        s2 = lines[j].strip().split(';')[0].strip()
        m1 = re.match(r'LDX #&([0-9A-Fa-f]{2})', s1)
        m2 = re.match(r'LDY #&([0-9A-Fa-f]{2})', s2)
        if m1 and m2:
            lo = int(m1.group(1), 16)
            hi = int(m2.group(1), 16)
            addr_val = (hi << 8) | lo
            if 0x4800 <= addr_val <= 0x57FF:
                if (i, j, addr_val) not in oscli_pairs:
                    existing = [(a,b) for a,b,c in oscli_pairs if a == i or b == j]
                    if not existing:
                        extra_pairs.append((i, j, addr_val))

for ldx_li, ldy_li, target in extra_pairs:
    if target not in label_map:
        name = oscli_names.get(target, f'l_{target:04X}')
        label_map[target] = name
        if target not in existing_labels:
            labels_to_insert[target] = name

oscli_pairs.extend(extra_pairs)

print(f"\nAll LDX/LDY pairs: {len(oscli_pairs)}")
for ldx_li, ldy_li, target in oscli_pairs:
    name = label_map.get(target, f'???')
    print(f"  lines {ldx_li+1}-{ldy_li+1}: &{target:04X} = {name}")

# ============================================================
# Now generate output
# ============================================================

# Determine which lines need label insertions before them
insert_at_line = {}  # line_index -> label_name
for a, name in labels_to_insert.items():
    if a in addr_to_first_line:
        li = addr_to_first_line[a]
        insert_at_line[li] = name

# Build output
output_lines = []
oscli_ldx_lines = {t[0] for t in oscli_pairs}
oscli_ldy_lines = {t[1] for t in oscli_pairs}
oscli_addr_by_ldx = {t[0]: t[2] for t in oscli_pairs}
oscli_addr_by_ldy = {t[1]: t[2] for t in oscli_pairs}

for i, line in enumerate(lines):
    # Insert label if needed
    if i in insert_at_line:
        output_lines.append(f'.{insert_at_line[i]}')

    stripped = line.strip()

    # Handle label renames
    m = re.match(r'^(\s*)\.(\w+)(.*)', line)
    if m:
        indent, name, rest = m.groups()
        if name in renames:
            line = f'{indent}.{renames[name]}{rest}'

    # Skip EQUB lines
    if 'EQUB' in line:
        output_lines.append(line)
        continue

    # Handle OSCLI LDX #lo lines
    if i in oscli_ldx_lines:
        target = oscli_addr_by_ldx[i]
        name = label_map.get(target)
        if name:
            # Replace LDX #&XX with LDX #LO(name)
            line = re.sub(r'LDX #&[0-9A-Fa-f]{2}',
                         f'LDX #LO({name})', line)

    # Handle OSCLI LDY #hi lines
    if i in oscli_ldy_lines:
        target = oscli_addr_by_ldy[i]
        name = label_map.get(target)
        if name:
            line = re.sub(r'LDY #&[0-9A-Fa-f]{2}',
                         f'LDY #HI({name})', line)

    # Replace absolute address references
    # Process from right to left to preserve positions
    replacements = []
    for m in re.finditer(
        r'(JSR|JMP|LDA|STA|INC|DEC|LDX|LDY|ADC|SBC|CMP|BIT|ORA|AND|EOR|STX|STY|CPX|CPY|ASL|LSR|ROL|ROR)'
        r'\s+&(4[89A-Fa-f][0-9A-Fa-f]{2}|5[0-7][0-9A-Fa-f]{2})'
        r'(,([XY]))?',
        line
    ):
        a = int(m.group(2), 16)
        if a < 0x4800 or a > 0x57FF:
            continue
        idx_reg = m.group(4)
        opcode = m.group(1)

        # Check self-mod
        if a in selfmod:
            parent, offset = selfmod[a]
            parent_label = label_map.get(parent)
            if parent_label:
                suffix = f',{idx_reg}' if idx_reg else ''
                new_text = f'{opcode} {parent_label} + {offset}{suffix}'
                replacements.append((m.start(), m.end(), new_text))
                continue

        # Regular reference
        label = label_map.get(a)
        if label:
            suffix = f',{idx_reg}' if idx_reg else ''
            new_text = f'{opcode} {label}{suffix}'
            replacements.append((m.start(), m.end(), new_text))

    # Apply replacements right-to-left
    for start, end, new_text in reversed(replacements):
        line = line[:start] + new_text + line[end:]

    output_lines.append(line)

# Apply renames throughout (for branch targets etc.)
output = '\n'.join(output_lines)
for old, new in renames.items():
    output = re.sub(r'\b' + re.escape(old) + r'\b', new, output)

with open('game.asm', 'w') as f:
    f.write(output)

print(f"\nLabels inserted: {len(insert_at_line)}")
print(f"Renames applied: {len(renames)}")
print(f"Self-mod references: {len(selfmod)}")
print("Written to game.asm")

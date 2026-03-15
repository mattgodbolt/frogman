#!/usr/bin/env python3
"""Disassemble FROGMAN binary dumps into annotated 6502 assembly."""

import sys

# 6502 opcode table: (mnemonic, addressing_mode, bytes)
# Modes: imp=0, imm=1, zp=2, zpx=3, zpy=4, abs=5, absx=6, absy=7,
#        indx=8, indy=9, rel=10, acc=11, ind=12
OPCODES = {
    0x00: ('BRK', 0, 1), 0x01: ('ORA', 8, 2), 0x05: ('ORA', 2, 2),
    0x06: ('ASL', 2, 2), 0x08: ('PHP', 0, 1), 0x09: ('ORA', 1, 2),
    0x0A: ('ASL', 11, 1), 0x0D: ('ORA', 5, 3), 0x0E: ('ASL', 5, 3),
    0x10: ('BPL', 10, 2), 0x11: ('ORA', 9, 2), 0x15: ('ORA', 3, 2),
    0x16: ('ASL', 3, 2), 0x18: ('CLC', 0, 1), 0x19: ('ORA', 7, 3),
    0x1D: ('ORA', 6, 3),
    0x20: ('JSR', 5, 3), 0x21: ('AND', 8, 2), 0x24: ('BIT', 2, 2),
    0x25: ('AND', 2, 2), 0x26: ('ROL', 2, 2), 0x28: ('PLP', 0, 1),
    0x29: ('AND', 1, 2), 0x2A: ('ROL', 11, 1), 0x2C: ('BIT', 5, 3),
    0x2D: ('AND', 5, 3), 0x2E: ('ROL', 5, 3),
    0x30: ('BMI', 10, 2), 0x31: ('AND', 9, 2), 0x35: ('AND', 3, 2),
    0x36: ('ROL', 3, 2), 0x38: ('SEC', 0, 1), 0x39: ('AND', 7, 3),
    0x3D: ('AND', 6, 3),
    0x40: ('RTI', 0, 1), 0x41: ('EOR', 8, 2), 0x45: ('EOR', 2, 2),
    0x46: ('LSR', 2, 2), 0x48: ('PHA', 0, 1), 0x49: ('EOR', 1, 2),
    0x4A: ('LSR', 11, 1), 0x4C: ('JMP', 5, 3), 0x4D: ('EOR', 5, 3),
    0x4E: ('LSR', 5, 3),
    0x50: ('BVC', 10, 2), 0x51: ('EOR', 9, 2), 0x55: ('EOR', 3, 2),
    0x56: ('LSR', 3, 2), 0x58: ('CLI', 0, 1), 0x59: ('EOR', 7, 3),
    0x5D: ('EOR', 6, 3),
    0x60: ('RTS', 0, 1), 0x61: ('ADC', 8, 2), 0x65: ('ADC', 2, 2),
    0x66: ('ROR', 2, 2), 0x68: ('PLA', 0, 1), 0x69: ('ADC', 1, 2),
    0x6A: ('ROR', 11, 1), 0x6C: ('JMP', 12, 3), 0x6D: ('ADC', 5, 3),
    0x6E: ('ROR', 5, 3),
    0x70: ('BVS', 10, 2), 0x71: ('ADC', 9, 2), 0x75: ('ADC', 3, 2),
    0x76: ('ROR', 3, 2), 0x78: ('SEI', 0, 1), 0x79: ('ADC', 7, 3),
    0x7D: ('ADC', 6, 3),
    0x81: ('STA', 8, 2), 0x84: ('STY', 2, 2), 0x85: ('STA', 2, 2),
    0x86: ('STX', 2, 2), 0x88: ('DEY', 0, 1), 0x8A: ('TXA', 0, 1),
    0x8C: ('STY', 5, 3), 0x8D: ('STA', 5, 3), 0x8E: ('STX', 5, 3),
    0x90: ('BCC', 10, 2), 0x91: ('STA', 9, 2), 0x94: ('STY', 3, 2),
    0x95: ('STA', 3, 2), 0x96: ('STX', 4, 2), 0x98: ('TYA', 0, 1),
    0x99: ('STA', 7, 3), 0x9D: ('STA', 6, 3),
    0xA0: ('LDY', 1, 2), 0xA1: ('LDA', 8, 2), 0xA2: ('LDX', 1, 2),
    0xA4: ('LDY', 2, 2), 0xA5: ('LDA', 2, 2), 0xA6: ('LDX', 2, 2),
    0xA8: ('TAY', 0, 1), 0xA9: ('LDA', 1, 2), 0xAA: ('TAX', 0, 1),
    0xAC: ('LDY', 5, 3), 0xAD: ('LDA', 5, 3), 0xAE: ('LDX', 5, 3),
    0xB0: ('BCS', 10, 2), 0xB1: ('LDA', 9, 2), 0xB4: ('LDY', 3, 2),
    0xB5: ('LDA', 3, 2), 0xB6: ('LDX', 4, 2), 0xB8: ('CLV', 0, 1),
    0xB9: ('LDA', 7, 3), 0xBC: ('LDY', 6, 3), 0xBD: ('LDA', 6, 3),
    0xBE: ('LDX', 7, 3),
    0xC0: ('CPY', 1, 2), 0xC1: ('CMP', 8, 2), 0xC4: ('CPY', 2, 2),
    0xC5: ('CMP', 2, 2), 0xC6: ('DEC', 2, 2), 0xC8: ('INY', 0, 1),
    0xC9: ('CMP', 1, 2), 0xCA: ('DEX', 0, 1), 0xCC: ('CPY', 5, 3),
    0xCD: ('CMP', 5, 3), 0xCE: ('DEC', 5, 3),
    0xD0: ('BNE', 10, 2), 0xD1: ('CMP', 9, 2), 0xD5: ('CMP', 3, 2),
    0xD6: ('DEC', 3, 2), 0xD8: ('CLD', 0, 1), 0xD9: ('CMP', 7, 3),
    0xDD: ('CMP', 6, 3), 0xDE: ('DEC', 6, 3),
    0xE0: ('CPX', 1, 2), 0xE1: ('SBC', 8, 2), 0xE4: ('CPX', 2, 2),
    0xE5: ('SBC', 2, 2), 0xE6: ('INC', 2, 2), 0xE8: ('INX', 0, 1),
    0xE9: ('SBC', 1, 2), 0xEA: ('NOP', 0, 1), 0xEC: ('CPX', 5, 3),
    0xED: ('SBC', 5, 3), 0xEE: ('INC', 5, 3),
    0xF0: ('BEQ', 10, 2), 0xF1: ('SBC', 9, 2), 0xF5: ('SBC', 3, 2),
    0xF6: ('INC', 3, 2), 0xF8: ('SED', 0, 1), 0xF9: ('SBC', 7, 3),
    0xFD: ('SBC', 6, 3), 0xFE: ('INC', 6, 3),
}

def format_operand(mode, lo, hi, addr):
    if mode == 0: return ""        # implied
    if mode == 11: return "A"      # accumulator
    if mode == 1: return f"#&{lo:02X}"  # immediate
    if mode == 2: return f"&{lo:02X}"   # zero page
    if mode == 3: return f"&{lo:02X},X" # zp,X
    if mode == 4: return f"&{lo:02X},Y" # zp,Y
    if mode == 5: return f"&{hi:02X}{lo:02X}" # absolute
    if mode == 6: return f"&{hi:02X}{lo:02X},X" # abs,X
    if mode == 7: return f"&{hi:02X}{lo:02X},Y" # abs,Y
    if mode == 8: return f"(&{lo:02X},X)" # (zp,X)
    if mode == 9: return f"(&{lo:02X}),Y" # (zp),Y
    if mode == 10:  # relative
        offset = lo if lo < 128 else lo - 256
        target = addr + 2 + offset
        return f"&{target:04X}"
    if mode == 12: return f"(&{hi:02X}{lo:02X})" # indirect
    return "?"

def disassemble(data, base, end=None):
    if end is None:
        end = base + len(data)
    lines = []
    i = 0
    while i < len(data) and base + i < end:
        addr = base + i
        b = data[i]
        if b in OPCODES:
            mnem, mode, nbytes = OPCODES[b]
            if i + nbytes > len(data):
                lines.append(f"    EQUB &{b:02X}")
                i += 1
                continue
            lo = data[i+1] if nbytes > 1 else 0
            hi = data[i+2] if nbytes > 2 else 0
            operand = format_operand(mode, lo, hi, addr)
            hexbytes = ' '.join(f'{data[i+j]:02X}' for j in range(nbytes))
            if operand:
                lines.append((addr, f"    {mnem} {operand}", hexbytes))
            else:
                lines.append((addr, f"    {mnem}", hexbytes))
            i += nbytes
        else:
            lines.append((addr, f"    EQUB &{b:02X}", f'{b:02X}'))
            i += 1
    return lines


def main():
    # Load all binaries
    with open("extracted/decrypted/irq_handler.bin", "rb") as f:
        irq_data = list(f.read())
    with open("extracted/decrypted/game_engine.bin", "rb") as f:
        engine_data = list(f.read())

    print("; === IRQ Handler (&0600-&065B) ===")
    print("ORG &0600")
    for item in disassemble(irq_data, 0x0600):
        if isinstance(item, tuple):
            addr, asm, hexb = item
            print(f"    ; {addr:04X}: {hexb}")
            print(asm)
        else:
            print(item)

    print()
    print("; === Game Engine (&0880-&0C77) ===")
    print("ORG &0880")
    for item in disassemble(engine_data, 0x0880):
        if isinstance(item, tuple):
            addr, asm, hexb = item
            print(f"    ; {addr:04X}: {hexb}")
            print(asm)
        else:
            print(item)


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
"""Collect memory dumps from jsbeeb read_memory output and save as binary files.

Usage: Run this script after populating the `dumps` dict below with byte arrays
from jsbeeb read_memory calls. It writes binary files to extracted/decrypted/.
"""

import os
import struct

OUTPUT_DIR = "extracted/decrypted"
os.makedirs(OUTPUT_DIR, exist_ok=True)

# Memory dumps keyed by start address (decimal)
# Each value is a list of byte values (0-255)
dumps = {}

# Regions to save as files, with (start_addr, end_addr_exclusive, filename)
REGIONS = [
    (0x0000, 0x0100, "zeropage.bin"),
    (0x0100, 0x0300, "stack_and_page2.bin"),
    (0x0300, 0x0400, "level_header.bin"),
    (0x0400, 0x0600, "page4_5.bin"),
    (0x0600, 0x0660, "irq_handler.bin"),
    (0x06BA, 0x06C8, "sprite_ptr_table.bin"),
    (0x0700, 0x0740, "screen_col_lut.bin"),
    (0x0740, 0x0780, "screen_row_lut.bin"),
    (0x0780, 0x0800, "palette_tables.bin"),
    (0x0800, 0x0880, "physics_table.bin"),
    (0x0880, 0x0C78, "game_engine.bin"),
    (0x0C78, 0x0F00, "music_data.bin"),
    (0x0F00, 0x1300, "level_map_part1.bin"),
    (0x1300, 0x2200, "titlescreen_data.bin"),
    (0x2800, 0x3700, "level_map_part2.bin"),
    (0x3700, 0x4800, "tile_graphics.bin"),
    (0x4800, 0x5800, "sprite_graphics.bin"),
    (0x7800, 0x8000, "status_bar.bin"),
    # Combined files for convenience
    (0x0600, 0x0700, "page6_irq.bin"),
    (0x0700, 0x0800, "page7_luts.bin"),
    (0x0800, 0x0D00, "engine_full.bin"),
    (0x0D00, 0x0F00, "music_and_encrypted.bin"),
]


def save_regions():
    """Save all defined regions from the dumps dict."""
    # Build a flat memory image from all dumps
    mem = bytearray(0x10000)  # 64KB
    for addr, data in sorted(dumps.items()):
        for i, b in enumerate(data):
            mem[addr + i] = b

    for start, end, filename in REGIONS:
        filepath = os.path.join(OUTPUT_DIR, filename)
        with open(filepath, "wb") as f:
            f.write(bytes(mem[start:end]))
        print(f"  {filepath}: ${start:04X}-${end-1:04X} ({end-start} bytes)")

    # Also save the full memory image for reference
    filepath = os.path.join(OUTPUT_DIR, "full_memory.bin")
    with open(filepath, "wb") as f:
        f.write(bytes(mem))
    print(f"  {filepath}: full 64KB memory image")


if __name__ == "__main__":
    # Check if we have data
    if not dumps:
        print("No dumps loaded. Populate the dumps dict first.")
    else:
        print(f"Saving {len(dumps)} memory pages...")
        save_regions()
        print("Done!")

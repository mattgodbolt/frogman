#!/usr/bin/env python3
"""Import a Tiled .tmx map back into FROGMAN Level?M binary format.

Reads the CSV tile data from a .tmx file and writes the corresponding
Level?M binary. Tiled GIDs are 1-based (GID 1 = tile 0), GID 0 = empty
(written as tile 0).

Usage:
  python3 import_tiled.py tiled/level1.tmx extracted/Level1M
  python3 import_tiled.py tiled/level2.tmx extracted/Level2M
"""

import sys
import xml.etree.ElementTree as ET

SCREENS_X = 8
SCREENS_Y = 10
TILES_PER_SCREEN_X = 16
TILES_PER_SCREEN_Y = 8
MAP_W = SCREENS_X * TILES_PER_SCREEN_X    # 128
MAP_H = SCREENS_Y * TILES_PER_SCREEN_Y    # 80


def import_tmx(tmx_path, output_path):
    tree = ET.parse(tmx_path)
    root = tree.getroot()

    # Verify dimensions
    width = int(root.get("width"))
    height = int(root.get("height"))
    if width != MAP_W or height != MAP_H:
        print(f"Warning: map is {width}x{height}, expected {MAP_W}x{MAP_H}")

    # Find the tile layer
    layer = root.find(".//layer[@name='Map']")
    if layer is None:
        layer = root.find(".//layer")
    if layer is None:
        print("Error: no tile layer found")
        sys.exit(1)

    data = layer.find("data")
    if data is None or data.get("encoding") != "csv":
        print("Error: expected CSV-encoded tile data")
        sys.exit(1)

    # Parse CSV tile IDs
    csv_text = data.text.strip()
    rows = []
    for line in csv_text.split("\n"):
        line = line.strip().rstrip(",")
        if line:
            rows.append([int(x) for x in line.split(",")])

    if len(rows) != MAP_H:
        print(f"Warning: got {len(rows)} rows, expected {MAP_H}")

    # Convert back to screen-based binary format
    # map_ptr = screen_y * &400 + screen_x * &80
    # Each screen = 128 bytes = 16 tiles × 8 rows
    map_data = bytearray(SCREENS_X * SCREENS_Y * 0x80)

    for screen_y in range(SCREENS_Y):
        for screen_x in range(SCREENS_X):
            screen_offset = screen_y * 0x400 + screen_x * 0x80
            for tile_y in range(TILES_PER_SCREEN_Y):
                for tile_x in range(TILES_PER_SCREEN_X):
                    row = screen_y * TILES_PER_SCREEN_Y + tile_y
                    col = screen_x * TILES_PER_SCREEN_X + tile_x
                    if row < len(rows) and col < len(rows[row]):
                        gid = rows[row][col]
                        tile_idx = max(0, gid - 1)  # 1-based to 0-based
                    else:
                        tile_idx = 0
                    map_data[screen_offset + tile_y * TILES_PER_SCREEN_X + tile_x] = tile_idx

    # Verify size matches
    expected_size = SCREENS_X * SCREENS_Y * 128  # 10240
    assert len(map_data) == expected_size, f"Size mismatch: {len(map_data)} != {expected_size}"

    with open(output_path, "wb") as f:
        f.write(map_data)

    print(f"Wrote {len(map_data)} bytes to {output_path}")

    # Show stats
    non_empty = sum(1 for b in map_data if b != 0)
    print(f"  Non-empty tiles: {non_empty}")
    print(f"  Empty tiles: {len(map_data) - non_empty}")


def main():
    if len(sys.argv) != 3:
        print(f"Usage: {sys.argv[0]} <input.tmx> <output_levelM>")
        print(f"  e.g.: {sys.argv[0]} tiled/level1.tmx extracted/Level1M")
        sys.exit(1)

    import_tmx(sys.argv[1], sys.argv[2])


if __name__ == "__main__":
    main()

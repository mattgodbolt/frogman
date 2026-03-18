#!/usr/bin/env python3
"""Export FROGMAN level data to Tiled Map Editor format.

Generates:
  - tiled/level{N}_tileset.png  — tileset image (all tiles rendered)
  - tiled/level{N}_tileset.tsx  — Tiled tileset file
  - tiled/level{N}.tmx          — Tiled map file

Usage:
  python3 export_tiled.py          # Export both levels
  python3 export_tiled.py 1        # Export level 1 only
"""

import os
import sys
import xml.etree.ElementTree as ET
from PIL import Image

# --- Constants (matching render_map.py) ---

BBC_PALETTE = [
    (0, 0, 0), (255, 0, 0), (0, 255, 0), (255, 255, 0),
    (0, 0, 255), (255, 0, 255), (0, 255, 255), (255, 255, 255),
    (0, 0, 0), (255, 0, 0), (0, 255, 0), (255, 255, 0),
    (0, 0, 255), (255, 0, 255), (0, 255, 255), (255, 255, 255),
]

SCREENS_X = 8
SCREENS_Y = 10
TILES_PER_SCREEN_X = 16
TILES_PER_SCREEN_Y = 8
TILE_W = 8      # pixels
TILE_H = 16     # pixels
TILE_GFX_OFFSET = 0x100
NUM_TILES = 32  # map tiles 0-31

# Collision flags from game.asm
COLLISION_FLAGS = [
    0xFF, 0x00, 0x00, 0x00, 0xFF, 0x00, 0xFF, 0xFF,
    0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
    0x00, 0x00, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF,
    0xFF, 0xFF, 0xFF, 0xFF, 0x00, 0x00, 0x00, 0xFF,
]


def decode_mode2_byte(byte):
    left = ((byte >> 7) & 1) * 8 + ((byte >> 5) & 1) * 4 + \
           ((byte >> 3) & 1) * 2 + ((byte >> 1) & 1)
    right = ((byte >> 6) & 1) * 8 + ((byte >> 4) & 1) * 4 + \
            ((byte >> 2) & 1) * 2 + (byte & 1)
    return left, right


def render_tile(gfx_data, tile_idx):
    """Render a single tile as an 8x16 pixel list."""
    offset = TILE_GFX_OFFSET + (tile_idx // 4) * 0x100 + (tile_idx % 4) * 0x40
    pixels = []
    if offset + 64 > len(gfx_data):
        return [(0, 0, 0)] * (TILE_W * TILE_H)
    for char_row in range(2):
        for scanline in range(8):
            for cell in range(4):
                byte = gfx_data[offset + char_row * 32 + cell * 8 + scanline]
                left, right = decode_mode2_byte(byte)
                pixels.append(BBC_PALETTE[left])
                pixels.append(BBC_PALETTE[right])
    return pixels


def generate_tileset_image(gfx_data, num_tiles=NUM_TILES):
    """Generate a tileset PNG with all tiles in a horizontal strip."""
    # Lay out tiles in a grid: 8 columns × 4 rows for 32 tiles
    cols = 8
    rows = (num_tiles + cols - 1) // cols
    img = Image.new("RGB", (cols * TILE_W, rows * TILE_H), (0, 0, 0))

    for idx in range(num_tiles):
        pixels = render_tile(gfx_data, idx)
        col = idx % cols
        row = idx // cols
        for py in range(TILE_H):
            for px in range(TILE_W):
                img.putpixel(
                    (col * TILE_W + px, row * TILE_H + py),
                    pixels[py * TILE_W + px]
                )
    return img


def generate_tsx(tileset_image_file, num_tiles=NUM_TILES, scale_x=8, scale_y=4):
    """Generate a Tiled tileset (.tsx) XML."""
    cols = 8
    tw = TILE_W * scale_x
    th = TILE_H * scale_y
    rows = (num_tiles + cols - 1) // cols
    tileset = ET.Element("tileset", {
        "version": "1.10",
        "tiledversion": "1.12.0",
        "name": "frogman_tiles",
        "tilewidth": str(tw),
        "tileheight": str(th),
        "tilecount": str(num_tiles),
        "columns": str(cols),
    })
    ET.SubElement(tileset, "image", {
        "source": tileset_image_file,
        "width": str(cols * tw),
        "height": str(rows * th),
    })

    # Add collision property to each tile
    for idx in range(num_tiles):
        tile_el = ET.SubElement(tileset, "tile", {"id": str(idx)})
        props = ET.SubElement(tile_el, "properties")
        passable = COLLISION_FLAGS[idx] == 0xFF if idx < len(COLLISION_FLAGS) else True
        ET.SubElement(props, "property", {
            "name": "passable",
            "type": "bool",
            "value": "true" if passable else "false",
        })

    return tileset


def generate_tmx(level_num, map_data, tileset_file, scale_x=8, scale_y=4):
    """Generate a Tiled map (.tmx) XML from map data."""
    map_w = SCREENS_X * TILES_PER_SCREEN_X   # 128
    map_h = SCREENS_Y * TILES_PER_SCREEN_Y   # 80

    tiled_map = ET.Element("map", {
        "version": "1.10",
        "tiledversion": "1.12.0",
        "orientation": "orthogonal",
        "renderorder": "right-down",
        "width": str(map_w),
        "height": str(map_h),
        "tilewidth": str(TILE_W * scale_x),
        "tileheight": str(TILE_H * scale_y),
        "infinite": "0",
    })

    ET.SubElement(tiled_map, "tileset", {
        "firstgid": "1",
        "source": tileset_file,
    })

    # Build tile data — Tiled uses 1-based IDs (0 = empty)
    # Our tile 0 maps to Tiled GID 1, etc.
    tile_ids = []
    for screen_row in range(SCREENS_Y):
        for tile_row in range(TILES_PER_SCREEN_Y):
            row_ids = []
            for screen_col in range(SCREENS_X):
                screen_offset = screen_row * 0x400 + screen_col * 0x80
                for tile_col in range(TILES_PER_SCREEN_X):
                    if screen_offset + 128 <= len(map_data):
                        tile_idx = map_data[screen_offset + tile_row * TILES_PER_SCREEN_X + tile_col]
                        row_ids.append(tile_idx + 1)  # 1-based
                    else:
                        row_ids.append(0)
            tile_ids.append(row_ids)

    layer = ET.SubElement(tiled_map, "layer", {
        "id": "1",
        "name": "Map",
        "width": str(map_w),
        "height": str(map_h),
    })

    # CSV format — each row ends with comma except the last
    csv_lines = []
    for i, row in enumerate(tile_ids):
        line = ",".join(str(tid) for tid in row)
        if i < len(tile_ids) - 1:
            line += ","
        csv_lines.append(line)
    data_el = ET.SubElement(layer, "data", {"encoding": "csv"})
    data_el.text = "\n" + "\n".join(csv_lines) + "\n"

    return tiled_map


def write_xml(element, filename):
    """Write XML with proper formatting. Avoids minidom mangling CSV data."""
    tree = ET.ElementTree(element)
    ET.indent(tree, space="  ")
    tree.write(filename, encoding="unicode", xml_declaration=True)


def export_level(level_num):
    """Export a single level to Tiled format."""
    os.makedirs("tiled", exist_ok=True)

    gfx_file = f"extracted/Level{level_num}G"
    map_file = f"extracted/Level{level_num}M"

    with open(gfx_file, "rb") as f:
        gfx_data = f.read()
    with open(map_file, "rb") as f:
        map_data = f.read()

    # Generate tileset image
    tileset_img = generate_tileset_image(gfx_data)
    # Scale with BBC MODE 2 pixel aspect ratio (2:1 width:height)
    # 8x horizontal (2x aspect × 4x size), 4x vertical
    scale_x = 8
    scale_y = 4
    tileset_img_scaled = tileset_img.resize(
        (tileset_img.width * scale_x, tileset_img.height * scale_y), Image.NEAREST
    )
    img_filename = f"level{level_num}_tileset.png"
    tileset_img_scaled.save(f"tiled/{img_filename}")
    print(f"  Tileset image: tiled/{img_filename}")

    # Generate .tsx
    tsx = generate_tsx(img_filename)
    tsx_filename = f"level{level_num}_tileset.tsx"
    write_xml(tsx, f"tiled/{tsx_filename}")
    print(f"  Tileset file:  tiled/{tsx_filename}")

    # Generate .tmx
    tmx = generate_tmx(level_num, map_data, tsx_filename)
    tmx_filename = f"level{level_num}.tmx"
    write_xml(tmx, f"tiled/{tmx_filename}")
    print(f"  Map file:      tiled/{tmx_filename}")


def main():
    levels = [int(a) for a in sys.argv[1:]] if len(sys.argv) > 1 else [1, 2]
    for level in levels:
        print(f"Exporting Level {level}...")
        export_level(level)
    print("Done! Open the .tmx files in Tiled.")


if __name__ == "__main__":
    main()

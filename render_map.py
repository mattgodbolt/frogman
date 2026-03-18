#!/usr/bin/env python3
"""Render FROGMAN level maps as PNG images.

Reads Level?M (map data) and Level?G (tile graphics) files from the
extracted/ directory and composites every screen into a single large
PNG showing the entire game world.

Map format (from setup_map_render in engine.asm):
  map_ptr = &0F00 + scroll_y * &400 + scroll_x * &80
  Each screen = 128 bytes = 16 tiles × 8 rows
  Map grid = 8 screens wide × 10 screens tall

Tile format (from block_copy in engine.asm):
  Each tile = 64 bytes = 4 character cells × 2 character rows
  Tile = 8 pixels wide × 16 pixels tall (MODE 2)
  In MODE 2: 2 pixels per byte, 4 bits per pixel

BBC Micro MODE 2 pixel layout:
  Left pixel:  bit7*8 + bit5*4 + bit3*2 + bit1
  Right pixel: bit6*8 + bit4*4 + bit2*2 + bit0
"""

from PIL import Image, ImageDraw, ImageFont

# BBC Micro physical colour palette (MODE 2)
BBC_PALETTE = [
    (0, 0, 0),         # 0: black
    (255, 0, 0),       # 1: red
    (0, 255, 0),       # 2: green
    (255, 255, 0),     # 3: yellow
    (0, 0, 255),       # 4: blue
    (255, 0, 255),     # 5: magenta
    (0, 255, 255),     # 6: cyan
    (255, 255, 255),   # 7: white
    # 8-15: flashing versions — show as base colour
    (0, 0, 0), (255, 0, 0), (0, 255, 0), (255, 255, 0),
    (0, 0, 255), (255, 0, 255), (0, 255, 255), (255, 255, 255),
]

# Map dimensions
SCREENS_X = 8       # Screens per row
SCREENS_Y = 10      # Screen rows
TILES_X = 16        # Tiles per screen (horizontal)
TILES_Y = 8         # Tiles per screen (vertical)
TILE_W = 8          # Tile width in pixels (4 bytes × 2 px/byte)
TILE_H = 16         # Tile height in pixels (2 char rows × 8 scanlines)
SCREEN_W = TILES_X * TILE_W    # 128 pixels
SCREEN_H = TILES_Y * TILE_H    # 128 pixels

# Tile graphics layout
TILE_GFX_OFFSET = 0x100    # Offset into Level?G file for tile 0

# Frog start position (from wait_for_space_done in game.asm)
FROG_START_SX = 0   # Screen X
FROG_START_SY = 0   # Screen Y
FROG_START_COL = 5  # Tile column within screen
FROG_START_ROW = 1  # Tile row within screen

# Scale factor for final image
SCALE = 4


def decode_mode2_byte(byte):
    """Decode a MODE 2 byte into two 4-bit colour values (left, right)."""
    left = ((byte >> 7) & 1) * 8 + ((byte >> 5) & 1) * 4 + \
           ((byte >> 3) & 1) * 2 + ((byte >> 1) & 1)
    right = ((byte >> 6) & 1) * 8 + ((byte >> 4) & 1) * 4 + \
            ((byte >> 2) & 1) * 2 + (byte & 1)
    return left, right


def get_tile_pixels(gfx_data, tile_idx):
    """Extract an 8×16 pixel tile from graphics data."""
    offset = TILE_GFX_OFFSET + (tile_idx // 4) * 0x100 + (tile_idx % 4) * 0x40

    if offset + 64 > len(gfx_data):
        return [[(0, 0, 0)] * TILE_W for _ in range(TILE_H)]

    pixels = []
    for char_row in range(2):
        for scanline in range(8):
            row_pixels = []
            for cell in range(4):
                byte_offset = offset + char_row * 32 + cell * 8 + scanline
                byte = gfx_data[byte_offset]
                left, right = decode_mode2_byte(byte)
                row_pixels.append(BBC_PALETTE[left])
                row_pixels.append(BBC_PALETTE[right])
            pixels.append(row_pixels)

    return pixels


def find_used_bounds(map_data):
    """Find the bounding box of non-empty screens."""
    min_sx, min_sy = SCREENS_X, SCREENS_Y
    max_sx, max_sy = 0, 0

    for sy in range(SCREENS_Y):
        for sx in range(SCREENS_X):
            screen_offset = sy * 0x400 + sx * 0x80
            if screen_offset + 128 > len(map_data):
                continue
            screen_data = map_data[screen_offset:screen_offset + 128]
            if not all(b == 0 for b in screen_data):
                min_sx = min(min_sx, sx)
                min_sy = min(min_sy, sy)
                max_sx = max(max_sx, sx)
                max_sy = max(max_sy, sy)

    return min_sx, min_sy, max_sx, max_sy


def find_items(map_data):
    """Find all item/special tile positions (tile index >= 0x20)."""
    items = []
    for sy in range(SCREENS_Y):
        for sx in range(SCREENS_X):
            screen_offset = sy * 0x400 + sx * 0x80
            if screen_offset + 128 > len(map_data):
                continue
            screen_data = map_data[screen_offset:screen_offset + 128]
            if all(b == 0 for b in screen_data):
                continue
            for ty in range(TILES_Y):
                for tx in range(TILES_X):
                    tile_idx = screen_data[ty * TILES_X + tx]
                    if tile_idx >= 0x20:
                        items.append((sx, sy, tx, ty, tile_idx))
    return items


def render_level(level_num):
    """Render a complete level map as a PIL Image with annotations."""
    map_file = f"extracted/Level{level_num}M"
    gfx_file = f"extracted/Level{level_num}G"

    with open(map_file, "rb") as f:
        map_data = f.read()
    with open(gfx_file, "rb") as f:
        gfx_data = f.read()

    # Find used area
    min_sx, min_sy, max_sx, max_sy = find_used_bounds(map_data)
    used_w = max_sx - min_sx + 1
    used_h = max_sy - min_sy + 1
    print(f"Level {level_num}: {used_w}×{used_h} screens "
          f"(x={min_sx}-{max_sx}, y={min_sy}-{max_sy})")

    # Create output image (just the used area)
    img_w = used_w * SCREEN_W
    img_h = used_h * SCREEN_H
    img = Image.new("RGB", (img_w, img_h), (32, 32, 32))

    # Render each screen
    for sy in range(min_sy, max_sy + 1):
        for sx in range(min_sx, max_sx + 1):
            screen_offset = sy * 0x400 + sx * 0x80
            if screen_offset + 128 > len(map_data):
                continue
            screen_data = map_data[screen_offset:screen_offset + 128]
            if all(b == 0 for b in screen_data):
                continue

            for ty in range(TILES_Y):
                for tx in range(TILES_X):
                    tile_idx = screen_data[ty * TILES_X + tx]
                    tile_pixels = get_tile_pixels(gfx_data, tile_idx)

                    px = (sx - min_sx) * SCREEN_W + tx * TILE_W
                    py = (sy - min_sy) * SCREEN_H + ty * TILE_H
                    for row_idx, row in enumerate(tile_pixels):
                        for col_idx, rgb in enumerate(row):
                            img.putpixel((px + col_idx, py + row_idx), rgb)

    # Scale up with MODE 2 pixel aspect ratio correction
    # MODE 2 pixels are ~2:1 (wider than tall) on a 4:3 PAL display
    # Standard: 160px across 4:3 width, 256px across height → ratio 32:15 ≈ 2.13
    aspect_x = SCALE * 2   # Double width to approximate BBC pixel shape
    aspect_y = SCALE
    img_scaled = img.resize(
        (img.width * aspect_x, img.height * aspect_y), Image.NEAREST
    )
    draw = ImageDraw.Draw(img_scaled)

    # Draw screen grid lines
    for sx in range(used_w + 1):
        x = sx * SCREEN_W * aspect_x
        draw.line([(x, 0), (x, img_scaled.height)], fill=(80, 80, 80), width=1)
    for sy in range(used_h + 1):
        y = sy * SCREEN_H * aspect_y
        draw.line([(0, y), (img_scaled.width, y)], fill=(80, 80, 80), width=1)

    # Mark frog start position
    frog_px = ((FROG_START_SX - min_sx) * SCREEN_W + FROG_START_COL * TILE_W) * aspect_x
    frog_py = ((FROG_START_SY - min_sy) * SCREEN_H + FROG_START_ROW * TILE_H) * aspect_y
    frog_w = TILE_W * aspect_x
    frog_h = TILE_H * aspect_y
    for i in range(3):
        draw.rectangle(
            [frog_px - i, frog_py - i, frog_px + frog_w + i, frog_py + frog_h + i],
            outline=(0, 255, 0)
        )
    draw.text((frog_px, frog_py - 14), "START", fill=(0, 255, 0))

    # Mark items with small yellow dots
    items = find_items(map_data)
    print(f"  Found {len(items)} item/special tiles")
    for sx, sy, tx, ty, tile_idx in items:
        cx = ((sx - min_sx) * SCREEN_W + tx * TILE_W + TILE_W // 2) * aspect_x
        cy = ((sy - min_sy) * SCREEN_H + ty * TILE_H + TILE_H // 2) * aspect_y
        r = 4
        draw.ellipse([cx - r, cy - r, cx + r, cy + r], fill=(255, 255, 0))

    # Add screen coordinates
    for sy in range(used_h):
        for sx in range(used_w):
            screen_offset = (sy + min_sy) * 0x400 + (sx + min_sx) * 0x80
            screen_data = map_data[screen_offset:screen_offset + 128]
            if all(b == 0 for b in screen_data):
                continue
            label_x = sx * SCREEN_W * aspect_x + 4
            label_y = sy * SCREEN_H * aspect_y + 4
            draw.text((label_x, label_y),
                      f"({sx + min_sx},{sy + min_sy})",
                      fill=(128, 128, 128))

    return img_scaled


def main():
    for level in [1, 2]:
        img = render_level(level)
        out = f"map_level{level}.png"
        img.save(out)
        print(f"  Saved {out} ({img.width}×{img.height})")


if __name__ == "__main__":
    main()

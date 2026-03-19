# FROGMAN Data Formats

Technical documentation of the graphics, tile map, and object system formats.

## Tile Graphics (Level?G)

Each level has 64 tiles. A tile is 32×16 pixels in Mode 2 (4 character cells
wide × 2 character rows tall). Each tile occupies 64 bytes.

**File layout:** 4352 bytes loaded at &3700.
- &3700-&37FF: First 256 bytes (purpose unclear; possibly padding or extra data)
- &3800-&47FF: 64 tiles in 16 pages of 256 bytes each

**Tile addressing:** 4 tiles share each 256-byte page:
```
Tile N → page &38 + (N DIV 4), offset (N MOD 4) × &40
```

**Tile 32 (&20) special case:** The first 64 bytes of the page containing
tile 32 (at &4000-&403F) double as the **tile type lookup table**. The game's
`get_tile_type` reads pairs of bytes from &4000 indexed by `(tile - &20) * 2`.
This means tile 32's visual appearance is determined by its gameplay properties
— a clever memory-saving trick that embeds type data in pixel data.

**Mode 2 pixel encoding:** Each byte represents 2 pixels. Bits 0,2,4,6 form
one pixel's colour; bits 1,3,5,7 form the other. Colours 0-15 (4-bit).

## Tile Map (Level?M)

The level map is an 8×10 grid of screens (Level 1) or 6×5 (Level 2).
Each screen is 16 tiles wide × 8 tiles tall = 128 bytes. Total: 10240 bytes.

**File:** Loaded at &5800, then relocated to &0F00-&36FF.

**Screen addressing:**
```
screen_addr = &0F00 + (screen_Y × &400) + (screen_X × &80)
tile_addr   = screen_addr + (tile_Y × &10) + tile_X
```

**Tile indices:** Each byte is a tile index 0-63:
- **&00-&1F (0-31):** Simple tiles with collision defined by `collision_flags`
- **&20-&3F (32-63):** Indexed tiles with type data from `get_tile_type`

## Collision System

### Simple tiles (&00-&1F)

The `collision_flags` table maps each tile to a collision byte:
- **&00** = solid ground (frog lands on it)
- **&FF** = passable (frog falls through / walks through)

| Tile | Hex  | Collision | Description                     |
|------|------|-----------|----------------------------------|
| 0    | &00  | passable  | Empty space                      |
| 1    | &01  | solid     | Standard brick                   |
| 2    | &02  | solid     | Conveyor belt (moves left)       |
| 3    | &03  | solid     | Conveyor belt (moves right)      |
| 4    | &04  | passable  | Map reveal terminal              |
| 5    | &05  | solid     | Climbable slope (rightward)      |
| 6    | &06  | passable  | Ladder (walkable, gravity check)  |
| 7    | &07  | passable  | Ladder frame (animated climbing) |
| 8-17 | &08-&11 | solid  | Brick variants, locked door (&11)|
| 18   | &12  | passable  | Lethal hazard (instant death)    |
| 19-27| &13-&1B | passable | Decoration tiles               |
| 28-29| &1C-&1D | solid  | Crumbling platform stages        |
| 30   | &1E  | solid     | Climbable slope (leftward)       |
| 31   | &1F  | passable  | Power control terminal (final)   |

### Indexed tiles (&20-&3F)

For tiles >= &20, `get_tile_type` reads a 2-byte descriptor from &4000:
- **Byte 0:** Type code (returned in A)
- **Byte 1:** Associated data value (stored in `zp_tile_data`)

Type codes and their effects:

| Type | Collision | Pickup | Behaviour                                    |
|------|-----------|--------|----------------------------------------------|
| 0    | solid     | yes    | Standard pickupable item                     |
| 1    | solid     | yes    | Key — unlocks tile &11 (locked doors)        |
| 3    | passable  | no     | Solid decoration (blocks falling)            |
| 4    | passable  | no     | Placeable surface                            |
| 5    | solid     | no     | Platform-when-held: solid if carrying matching data |
| 7    | solid     | no     | Platform-when-held: solid if carrying matching data |
| 8    | passable  | no     | Solid block (can't pick up, blocks falling)  |
| 9    | passable  | no     | Auto-collect: transforms held item (INC slot)|
| 11   | solid     | no     | Drop trigger: consumes held item (clears slot)|

**"Platform-when-held" mechanic (types 5, 7):** When `check_tile_solid` evaluates
these tiles, it compares `zp_tile_data` (the tile's associated data value)
against `zp_item_0` and `zp_item_1`. If either item slot matches, the tile
counts as solid ground — effectively creating platforms by carrying the right item.

## Item System

The frog has 2 inventory slots (`zp_item_0`, `zp_item_1`). Items are tile indices.

**Picking up (f0/f1 keys):** `use_item_slot` checks tiles at the frog position,
adjacent tile (based on facing direction), and below. If the tile's type has
`collision_check_table[type] == 0`, the tile is picked up (stored in the slot)
and replaced with empty space.

**Placing (f0/f1 with item held):** If the frog's current tile is empty, the
item is placed there. Types 3 and 4 allow placement at the frog's position;
other types require an empty tile above with solid ground.

**Auto-collect (type 9):** When the frog walks onto a type-9 tile, `collect_item`
checks if either slot matches the tile's data value. If so, the slot is
**incremented** (the item "evolves" to the next tile index). This creates
item transformation chains.

**Drop trigger (type 11):** When the frog steps below a type-11 tile, `drop_item`
checks if either slot matches the tile's data value. If so, the slot is
**cleared** (item consumed), with a palette flash animation.

## Sprite Definitions (Level?S)

768 bytes loaded at &0300-&05FF. Contains two distinct sections:

**Map overview (&0300-&037F, 128 bytes):** A 16×8 tile grid used as the overview
map shown when the frog visits a map terminal (tile &04). Rendered by the
`handle_map_reveal` routine using the engine's `render_map`.

**Frog graphics (&0380-&05FF, 640 bytes):** Tile graphics data for the frog
in 4 orientations (right, right-hopping, left, left-hopping). Loaded by
`tile_addr_setup` using `zp_direction` as an index into `tile_col_lut` to
select the column offset (0, &40, &80, &C0) within the graphics page.

## Tile Mask Table (Tabs)

64 bytes loaded at &0100 (stack page). Used by the `tile_render` routine
for AND masking during frog overlay compositing. Each byte is an AND mask:
screen pixels AND mask, then OR with frog graphics. This creates the
frog's silhouette by masking out background where the frog should appear.

## Status Bar (Tbar)

2048 bytes loaded at &7800. Contains the pre-rendered status bar graphic
(yellow border, "FROGMAN" title, item slot frames, frog icon, lives counter
area). Displayed below the main game area via the custom CRTC layout.

## Sound Data (Level?T)

640 bytes loaded at &5D80. After the engine copy (&5800→&0700), this maps
to &0C80-&0EFF, overwriting all three music channel data streams:
- Channel 1: &0C80-&0CFF (128 bytes)
- Channel 2: &0D80-&0DFF (128 bytes)
- Channel 3: &0E80-&0EFF (128 bytes)

Includes the `anim_timing_const` value (note duration base), making the
music timing level-specific. Format is interleaved note/duration pairs
with control tokens (&FC=set loop, &FA=loop back, &FE=end of channel).

## Crumbling Platform Cycle

Tiles &10, &1C, &1D form a disappearing platform sequence:
```
&10 (crumble) → places &1C below → &1C → places &1D below → &1D → places &00 below
```
Standing on each stage triggers the next. The platform crumbles under the
frog's weight over 3 frames, creating time-pressure platforming challenges.

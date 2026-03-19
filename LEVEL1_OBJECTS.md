# Level 1 Object Map and Dependency Graph

Object identifications confirmed by the original artist (Matt Godbolt, 2026).

## Complete Tile Index (&20-&3F)

All indexed tiles in order, rendered with correct Mode 2 aspect ratio:

| Tile | Sprite | Identity | Type | Notes |
|------|--------|----------|------|-------|
| &20 | *(n/a)* | *(type table data)* | — | Not a visible tile; pixel data encodes type lookup |
| &21 | ![](docs/tile_21.png) | **White Key** | 0 | Pickupable. Hold → pass through White Door (&23) |
| &22 | ![](docs/tile_22.png) | *(barrier)* | 5 | Passable when holding Rabbit (&35) |
| &23 | ![](docs/tile_23.png) | **White Door** | 7 | Barrier → passable when holding White Key (&21) |
| &24 | ![](docs/tile_24.png) | **Carrot** | 0 | Pickupable decoration |
| &25 | ![](docs/tile_25.png) | *(decoration)* | 0 | |
| &26 | ![](docs/tile_26.png) | *(decoration)* | 0 | |
| &27 | ![](docs/tile_27.png) | *(decoration)* | 0 | |
| &28 | ![](docs/tile_28.png) | **Yellow Key** | 0 | Pickupable. Hold → pass through Yellow Door (&29) |
| &29 | ![](docs/tile_29.png) | **Yellow Door** | 7 | Barrier → passable when holding Yellow Key (&28) |
| &2A | ![](docs/tile_2a.png) | **Bookshelf** | 8 | Passable decoration (walk-through) |
| &2B | ![](docs/tile_2b.png) | **Library Ticket** | 0 | Pickupable. Evolves via &2D chain |
| &2C | ![](docs/tile_2c.png) | **Bible** | 7 | Barrier → passable when holding evolved item &2C |
| &2D | ![](docs/tile_2d.png) | **Blank / Teleporter?** | 9 | Auto-collect: ticket &2B → &2C (bible) |
| &2E | ![](docs/tile_2e.png) | **Cross** | 7 | Barrier → passable when holding &2C (bible) |
| &2F | ![](docs/tile_2f.png) | **Unlit Candle** | 0 | Pickupable. Evolves via &31 chain |
| &30 | ![](docs/tile_30.png) | **Lit Candle** | — | Evolved from unlit candle. Consumed by TNT (&32) |
| &31 | ![](docs/tile_31.png) | **Fire** | 9 | Auto-collect: candle &2F → &30 (lit candle) |
| &32 | ![](docs/tile_32.png) | **TNT** | 0B | Drop trigger: consumes lit candle &30 |
| &33 | ![](docs/tile_33.png) | *(solid block)* | 8 | Passable decoration |
| &34 | ![](docs/tile_34.png) | **Magic Wand** | 0 | Pickupable. Evolves via &36 chain |
| &35 | ![](docs/tile_35.png) | **Rabbit** | — | Evolved from wand + top hat. Hold → pass through &22 |
| &36 | ![](docs/tile_36.png) | **Top Hat** | 9 | Auto-collect: wand &34 → &35 (rabbit!) |
| &37 | ![](docs/tile_37.png) | **Ring** | 1 | Pickupable. Unlocks locked doors (&11) |
| &38 | ![](docs/tile_38.png) | **Terminal 1** | 0 | Library ticket (collect all 8 to win) |
| &39 | ![](docs/tile_39.png) | **Terminal 2** | 0 | |
| &3A | ![](docs/tile_3a.png) | **Terminal 3** | 0 | |
| &3B | ![](docs/tile_3b.png) | **Terminal 4** | 0 | |
| &3C | ![](docs/tile_3c.png) | **Terminal 5** | 0 | |
| &3D | ![](docs/tile_3d.png) | **Terminal 6** | 0 | |
| &3E | ![](docs/tile_3e.png) | **Terminal 7** | 0 | |
| &3F | ![](docs/tile_3f.png) | **Terminal 8** | 0 | |

## Pickupable Items

| Tile | Sprite | Identity | Location | Purpose |
|------|--------|----------|----------|---------|
| &21 | ![](docs/tile_21.png) | **White Key** | screen(4,9) t(14,1) | Hold → pass through White Door &23 |
| &24 | ![](docs/tile_24.png) | **Carrot** | screen(5,1), screen(6,1) | Decoration / collectible |
| &28 | ![](docs/tile_28.png) | **Yellow Key** | screen(1,3) t(3,2) | Hold → pass through Yellow Door &29 |
| &2B | ![](docs/tile_2b.png) | **Library Ticket** | screen(7,0) t(14,6) | Evolves via &2D chain |
| &2F | ![](docs/tile_2f.png) | **Unlit Candle** | screen(0,6) t(8,5) | Evolves via Fire (&31) chain |
| &34 | ![](docs/tile_34.png) | **Magic Wand** | screen(0,0) t(1,6) | Evolves via Top Hat (&36) chain |
| &37 | ![](docs/tile_37.png) | **Ring** | screen(6,9) t(12,2) | Unlocks locked doors (&11) |

### Terminal Codes (collect all 8 to win)

| Tile | Sprite | Location |
|------|--------|----------|
| &38 | ![](docs/tile_38.png) | screen(1,2) t(5,1) |
| &39 | ![](docs/tile_39.png) | screen(2,5) t(14,6) |
| &3A | ![](docs/tile_3a.png) | screen(1,9) t(15,3) |
| &3B | ![](docs/tile_3b.png) | screen(7,2) t(11,2) |
| &3C | ![](docs/tile_3c.png) | screen(6,0) t(6,6) |
| &3D | ![](docs/tile_3d.png) | screen(7,7) t(9,4) |
| &3E | ![](docs/tile_3e.png) | screen(1,7) t(8,3) |
| &3F | ![](docs/tile_3f.png) | screen(6,9) t(5,2) |

## Barrier and Interaction Tiles

These tiles are **solid by default** and become **passable** when the frog
carries the matching item (types 5, 7), or they trigger item transformations
when walked on (type 9), or consume items (type 0B).

| Tile | Sprite | Identity | Type | Data | Effect | Count |
|------|--------|----------|------|------|--------|-------|
| &22 | ![](docs/tile_22.png) | *(barrier)* | 5 | &35 | Passable when holding Rabbit (&35) | 4 |
| &23 | ![](docs/tile_23.png) | White Door | 7 | &21 | Passable when holding White Key (&21) | 1 |
| &29 | ![](docs/tile_29.png) | Yellow Door | 7 | &28 | Passable when holding Yellow Key (&28) | 1 |
| &2A | ![](docs/tile_2a.png) | Bookshelf | 8 | &00 | Passable decoration (walk-through) | 12 |
| &2D | ![](docs/tile_2d.png) | Blank/Teleporter? | 9 | &2B | Auto-collect: ticket &2B → &2C | 4 |
| &2E | ![](docs/tile_2e.png) | Cross | 7 | &2C | Passable when holding Bible (&2C) | 5 |
| &31 | ![](docs/tile_31.png) | Fire | 9 | &2F | Auto-collect: candle &2F → lit candle &30 | 2 |
| &32 | ![](docs/tile_32.png) | TNT | 0B | &30 | Drop trigger: consumes lit candle &30 | 1 |
| &36 | ![](docs/tile_36.png) | Top Hat | 9 | &34 | Auto-collect: wand &34 → rabbit &35 | 1 |

## Item Evolution Chains

### Chain 1: Magic Trick — Wand + Top Hat → Rabbit
```
Pick up Magic Wand (&34) at screen(0,0)
    │
    ▼
Walk on Top Hat (&36, type 9) at screen(0,9)
    │  wand goes INTO the hat → Rabbit (&35) comes out!
    ▼
Holding Rabbit makes barrier tiles (&22) PASSABLE
    → 4 barrier tiles at screen(4,9) can be walked through
```
*The classic magic trick: put the wand in the hat, pull out a rabbit.*

### Chain 2: Library Ticket → Bible → Cross barriers
```
Pick up Library Ticket (&2B) at screen(7,0)
    │
    ▼
Walk on Blank/Teleporter (&2D, type 9) at screen(6,1)
    │  ticket transforms → Bible (&2C)
    ▼
Holding Bible makes Cross tiles (&2E) PASSABLE
    → 5 barrier tiles at screens (0,4), (0,5), (0,6)
```
*The library ticket becomes a bible, which lets you pass through crosses.*

### Chain 3: Candle + Fire → Lit Candle → TNT
```
Pick up Unlit Candle (&2F) at screen(0,6)
    │
    ▼
Walk on Fire (&31, type 9) at screen(7,3)
    │  candle is lit → Lit Candle (&30)
    ▼
Walk on TNT (&32, type 0B) at screen(3,3)
    │  lit candle consumed! (flash animation)
    ▼
Demolition effect triggered
```
*Light the candle in the fire, then use it to ignite the TNT.*

### Chain 4: White Key → White Door
```
Pick up White Key (&21) at screen(4,9)
    │
    ▼
Holding White Key makes White Door (&23) PASSABLE
    → 1 barrier at screen(3,3) can be walked through
```

### Chain 5: Yellow Key → Yellow Door
```
Pick up Yellow Key (&28) at screen(1,3)
    │
    ▼
Holding Yellow Key makes Yellow Door (&29) PASSABLE
    → 1 barrier at screen(0,0) can be walked through
```

### Chain 6: Ring → Locked Doors
```
Pick up Ring (&37) at screen(6,9)
    │
    ▼
Holding Ring (type 1) allows passing through tile &11
    → All locked doors become passable
```

## Terminal Collection (Win Condition)

The 8 terminal codes (&38-&3F, numbered 1-8) must all be collected and
placed on the map overview screen:

1. Explore the 8×10 screen map to find all 8 numbered terminals
2. Visit a map terminal (tile &04) — displays the overview map
3. Collected terminals (slot value >= &38) are automatically placed on
   the overview at row 6, with X position = tile_index - &31
4. Each placement increments `zp_terminal_ctr` and clears the slot
5. When `zp_terminal_ctr >= 8`, visiting tile &1F shows "LOGGED ON"

Since the frog only has 2 inventory slots, completing the game requires
multiple trips between terminals and the map overview.

## Dependency DAG (Mermaid)

```mermaid
graph TD
    subgraph "Magic Trick"
        WAND["&34 Magic Wand<br/>screen(0,0)"]
        WAND --> |"walk on &36 Top Hat<br/>screen(0,9)"| RABBIT["Hold &35 Rabbit"]
        RABBIT --> |"pass through"| BARRIER22["&22 barriers x4<br/>screen(4,9)"]
    end

    subgraph "Library Chain"
        TICKET["&2B Library Ticket<br/>screen(7,0)"]
        TICKET --> |"walk on &2D<br/>screen(6,1)"| BIBLE["Hold &2C Bible"]
        BIBLE --> |"pass through"| CROSSES["&2E Cross barriers x5<br/>screens(0,4-6)"]
    end

    subgraph "Demolition"
        CANDLE["&2F Unlit Candle<br/>screen(0,6)"]
        CANDLE --> |"walk on &31 Fire<br/>screen(7,3)"| LITCANDLE["Hold &30 Lit Candle"]
        LITCANDLE --> |"consumed by &32 TNT<br/>screen(3,3)"| BOOM["Demolition!"]
    end

    subgraph "Keys and Doors"
        WKEY["&21 White Key<br/>screen(4,9)"]
        WKEY --> |"pass through"| WDOOR["&23 White Door<br/>screen(3,3)"]

        YKEY["&28 Yellow Key<br/>screen(1,3)"]
        YKEY --> |"pass through"| YDOOR["&29 Yellow Door<br/>screen(0,0)"]

        RING["&37 Ring<br/>screen(6,9)"]
        RING --> |"pass through"| DOORS["&11 Locked doors"]
    end

    subgraph "Terminal Codes (Win Condition)"
        T1["&38 Terminal 1"] --> MAP["Map Overview"]
        T2["&39 Terminal 2"] --> MAP
        T3["&3A Terminal 3"] --> MAP
        T4["&3B Terminal 4"] --> MAP
        T5["&3C Terminal 5"] --> MAP
        T6["&3D Terminal 6"] --> MAP
        T7["&3E Terminal 7"] --> MAP
        T8["&3F Terminal 8"] --> MAP
        MAP --> |"all 8 placed"| WIN["LOGGED ON"]
    end

    BARRIER22 -.-> |"may block<br/>access to"| T1
    CROSSES -.-> |"may block<br/>access to"| T7
    WDOOR -.-> |"may block<br/>access to"| BOOM
    DOORS -.-> |"may block<br/>access to"| T8
```

## All 64 Tiles

![All 64 Level 1 Tiles](all_tiles_level1.png)

8×8 grid showing every tile in the Level 1 tileset. Rows 0-3 are simple
tiles (&00-&1F): bricks, conveyors, ladders, decorations, hazards. Rows
4-7 are indexed tiles (&20-&3F): game objects and terminal codes.

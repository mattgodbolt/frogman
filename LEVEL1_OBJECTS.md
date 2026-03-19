# Level 1 Object Map and Dependency Graph

## Object Reference

![Object Reference Sheet](docs/object_reference.png)

All indexed tiles rendered from Level 1 graphics with correct Mode 2 aspect
ratio (pixels are ~2:1 width:height).

## Pickupable Items

Items picked up with f0/f1 keys (type 0 or 1 in the tile type table).

| Tile | Sprite | Guess | Location | Purpose |
|------|--------|-------|----------|---------|
| &21 | ![](docs/tile_21.png) | **Top Hat** | screen(4,9) t(14,1) | Hold → pass through &23 barrier |
| &28 | ![](docs/tile_28.png) | **Rabbit** (or Key?) | screen(1,3) t(3,2) | Hold → pass through &29 barrier |
| &2B | ![](docs/tile_2b.png) | **Fire** | screen(7,0) t(14,6) | Evolves via &2D chain |
| &2F | ![](docs/tile_2f.png) | **Candle** (unlit) | screen(0,6) t(8,5) | Evolves via &31 chain |
| &34 | ![](docs/tile_34.png) | **Magic Wand** | screen(0,0) t(1,6) | Evolves via &36 chain |
| &37 | ![](docs/tile_37.png) | **Key** | screen(6,9) t(12,2) | Unlocks locked doors (&11) |

### Library Tickets (Terminal Codes)

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

These tiles are NOT pickupable. They are normally **solid** (blocking) and
become **passable** when the frog carries the matching item, or they trigger
item transformations when walked on.

| Tile | Sprite | Guess | Type | Data | Effect | Count |
|------|--------|-------|------|------|--------|-------|
| &22 | ![](docs/tile_22.png) | Dynamite stick | 5 | &35 | Barrier → passable when holding &35 | 4 |
| &23 | ![](docs/tile_23.png) | Bible | 7 | &21 | Barrier → passable when holding &21 (top hat) | 1 |
| &29 | ![](docs/tile_29.png) | Rabbit hutch | 7 | &28 | Barrier → passable when holding &28 (rabbit) | 1 |
| &2A | ![](docs/tile_2a.png) | Coloured blocks | 8 | &00 | Passable decoration (walk-through) | 12 |
| &2D | ![](docs/tile_2d.png) | Fireplace | 9 | &2B | Auto-collect: fire &2B → &2C (bible) | 4 |
| &2E | ![](docs/tile_2e.png) | Cross | 7 | &2C | Barrier → passable when holding &2C (bible) | 5 |
| &31 | ![](docs/tile_31.png) | Dynamite (lit) | 9 | &2F | Auto-collect: candle &2F → &30 (lit candle) | 2 |
| &32 | ![](docs/tile_32.png) | TNT bundle | 0B | &30 | Drop trigger: consumes &30 (lit candle) | 1 |
| &36 | ![](docs/tile_36.png) | Blue book | 9 | &34 | Auto-collect: wand &34 → &35 | 1 |

### Evolved Items (created by item transformation, not on the map)

| Tile | Sprite | Guess | Created by | Used for |
|------|--------|-------|------------|----------|
| &2C | ![](docs/tile_2c.png) | Bible (red+cross) | Fire &2B + fireplace &2D | Pass through cross barriers &2E |
| &30 | ![](docs/tile_30.png) | Lit candle | Candle &2F + dynamite &31 | Consumed by TNT bundle &32 |
| &35 | ![](docs/tile_35.png) | Magic orb? | Wand &34 + blue book &36 | Pass through dynamite barriers &22 |

### Decoration

| Tile | Sprite | Notes |
|------|--------|-------|
| &24-&27 | ![](docs/tile_24.png)![](docs/tile_25.png)![](docs/tile_26.png)![](docs/tile_27.png) | "LIBRARY" sign (4 tiles) |

## Item Evolution Chains

Items transform through specific tile interactions. Carrying the right item
lets you **pass through** specific barrier tiles that are otherwise solid walls.

### Chain 1: Magic Wand → pass through Dynamite barriers
```
Pick up Magic Wand (&34) at screen(0,0)
    │
    ▼
Walk on Blue Book (&36, type 9) at screen(0,9)
    │  wand transforms → &35 (magic orb?)
    ▼
Holding &35 makes Dynamite tiles (&22) PASSABLE
    → 4 barrier tiles at screen(4,9) can now be walked through
```

### Chain 2: Fire → pass through Cross barriers
```
Pick up Fire (&2B) at screen(7,0)
    │
    ▼
Walk on Fireplace (&2D, type 9) at screen(6,1)
    │  fire transforms → &2C (bible)
    ▼
Holding &2C makes Cross tiles (&2E) PASSABLE
    → 5 barrier tiles at screens (0,4), (0,5), (0,6) can be walked through
```

### Chain 3: Candle → Demolition
```
Pick up Candle (&2F) at screen(0,6)
    │
    ▼
Walk on Dynamite (&31, type 9) at screen(7,3)
    │  candle transforms → &30 (lit candle)
    ▼
Walk on TNT Bundle (&32, type 0B) at screen(3,3)
    │  lit candle consumed! (clears slot, flash animation)
    ▼
Demolition effect triggered
```

### Chain 4: Top Hat → pass through Bible barrier
```
Pick up Top Hat (&21) at screen(4,9)
    │
    ▼
Holding &21 makes Bible tile (&23) PASSABLE
    → 1 barrier tile at screen(3,3) can be walked through
```

### Chain 5: Rabbit → pass through Hutch barrier
```
Pick up Rabbit (&28) at screen(1,3)
    │
    ▼
Holding &28 makes Hutch tile (&29) PASSABLE
    → 1 barrier tile at screen(0,0) can be walked through
```

### Chain 6: Key → Locked Doors
```
Pick up Key (&37) at screen(6,9)
    │
    ▼
Holding Key (type 1) allows passing through tile &11
    → All locked doors become passable
```

## Terminal Collection (Win Condition)

The 8 library tickets (&38-&3F, numbered 1-8) must all be collected and
placed on the map overview screen:

1. Explore the 8×10 screen map to find all 8 numbered tickets
2. Visit a map terminal (tile &04) — displays the overview map
3. Collected tickets (slot value >= &38) are automatically placed on
   the overview at row 6, with X position = tile_index - &31
4. Each placement increments `zp_terminal_ctr` and clears the slot
5. When `zp_terminal_ctr >= 8`, visiting tile &1F shows "LOGGED ON"

Since the frog only has 2 inventory slots, completing the game requires
multiple trips between terminals and the map overview — collecting 2
tickets at a time, placing them, then going back for more.

## Dependency DAG (Mermaid)

```mermaid
graph TD
    subgraph "Magic Wand Chain"
        WAND["&34 Magic Wand<br/>screen(0,0)"]
        WAND --> |"walk on &36 Blue Book<br/>screen(0,9)"| ORB["Hold &35"]
        ORB --> |"pass through"| DYNAMITE["&22 Dynamite barriers x4<br/>screen(4,9)"]
    end

    subgraph "Fire Chain"
        FIRE["&2B Fire<br/>screen(7,0)"]
        FIRE --> |"walk on &2D Fireplace<br/>screen(6,1)"| BIBLE["Hold &2C Bible"]
        BIBLE --> |"pass through"| CROSSES["&2E Cross barriers x5<br/>screens(0,4-6)"]
    end

    subgraph "Demolition Chain"
        CANDLE["&2F Candle<br/>screen(0,6)"]
        CANDLE --> |"walk on &31 Dynamite<br/>screen(7,3)"| LITCANDLE["Hold &30 Lit Candle"]
        LITCANDLE --> |"consumed by &32 TNT<br/>screen(3,3)"| BOOM["Demolition!"]
    end

    subgraph "Direct Items"
        HAT["&21 Top Hat<br/>screen(4,9)"]
        HAT --> |"pass through"| BIBLEBARRIER["&23 Bible barrier<br/>screen(3,3)"]

        RABBIT["&28 Rabbit<br/>screen(1,3)"]
        RABBIT --> |"pass through"| HUTCH["&29 Hutch barrier<br/>screen(0,0)"]
    end

    subgraph "Key"
        KEY["&37 Key<br/>screen(6,9)"]
        KEY --> |"pass through"| DOORS["&11 Locked doors"]
    end

    subgraph "Library Tickets (Win Condition)"
        T1["Ticket 1"] --> MAP["Map Overview"]
        T2["Ticket 2"] --> MAP
        T3["Ticket 3"] --> MAP
        T4["Ticket 4"] --> MAP
        T5["Ticket 5"] --> MAP
        T6["Ticket 6"] --> MAP
        T7["Ticket 7"] --> MAP
        T8["Ticket 8"] --> MAP
        MAP --> |"all 8 placed"| WIN["LOGGED ON"]
    end

    DYNAMITE -.-> |"barriers may<br/>block access to"| T1
    CROSSES -.-> |"barriers may<br/>block access to"| T7
    BIBLEBARRIER -.-> |"barrier may<br/>block access to"| BOOM
    DOORS -.-> |"doors may<br/>block access to"| T8
```

**Note:** Dotted lines show spatial dependencies — certain barriers must
be made passable to physically reach other items or tickets. The exact
routing depends on the player's path through the 8×10 screen grid.

## All 64 Tiles

![All 64 Level 1 Tiles](all_tiles_level1.png)

8×8 grid showing every tile in the Level 1 tileset. Rows 0-3 are simple
tiles (&00-&1F): bricks, conveyors, ladders, decorations, hazards. Rows
4-7 are indexed tiles (&20-&3F): game objects, library sign, and the 8
numbered terminal tickets.

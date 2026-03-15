# FROGMAN

A BBC Master platformer written by Matt Godbolt and Richard Talbot-Watkins in February 1993.

This repository contains a fully annotated, instruction-level disassembly of the game, suitable for reassembly with [BeebASM](https://github.com/stardot/beebasm).

## The Game

FROGMAN is a side-scrolling platformer for the BBC Master. You control a frog navigating brick-walled levels filled with trees, obstacles, and hazards. The game features two levels, sprite animation, scrolling, music, and a lives system — all packed into approximately **1.1KB of 6502 machine code**.

The original game files are heavily encrypted on disk using a 55-stage XOR encryption chain with VIA timer-based PRNG seeds, making static analysis intentionally impossible. This disassembly was produced by booting the game in an emulator and dumping decrypted memory at runtime.

## Building

```bash
make
```

Requires [BeebASM](https://github.com/stardot/beebasm). Produces `frogman_rebuilt.ssd` which can be booted in any BBC Master emulator.

## Repository Structure

```
frogman.ssd               Original disk image (1993)

engine.asm                 Annotated game engine disassembly
                             IRQ handler (92 bytes) + game engine (1016 bytes)
tables.asm                 Lookup tables: screen addressing, palette, physics
music.asm                  Music data: three tunes + encrypted blocks
frogman.asm                Main BeebASM build file
loader.asm                 Clean replacement for the encrypted loader
encryption_appendix.asm    Documentation of original copy protection
ribbit.bas                 Plain-text reconstruction of BASIC title loader
Makefile                   Build system

extracted/                 Raw files from disk image (encrypted)
extracted/decrypted/       Decrypted memory dumps from emulator
save_dumps.py              Memory dump collection tooling
```

## Technical Details

### Memory Map

| Address | Size | Contents |
|---|---|---|
| `&0600-&065D` | 94 bytes | IRQ handler — music playback, sound envelopes, timer interrupts |
| `&06BA-&06C8` | 15 bytes | Sprite data pointer table |
| `&0700-&073F` | 64 bytes | Screen column address lookup table |
| `&0740-&077F` | 64 bytes | Screen row high-byte lookup table |
| `&0780-&07FF` | 128 bytes | Palette/fade tables (also used as volume envelope) |
| `&0800-&087F` | 128 bytes | Physics/gravity curve (also used as sound decay) |
| `&0880-&0C77` | 1016 bytes | **Game engine** — rendering, sprites, physics, sound, collision |
| `&0C78-&0EFF` | 648 bytes | Music data (3 tunes) + encrypted blocks |
| `&0F00-&22FF` | 5120 bytes | Level tile map (part 1) |
| `&2800-&36FF` | 3840 bytes | Level tile map (part 2) |
| `&3700-&47FF` | 4352 bytes | Tile graphics (Mode 2 pixel data) |
| `&4800-&57FF` | 4096 bytes | Sprite graphics |
| `&7800-&7FFF` | 2048 bytes | Status bar graphics |

### Engine Architecture

The game engine at `&0880` exposes a jump table of 7 entry points:

| Entry | Address | Function |
|---|---|---|
| `JMP &0895` | block_copy | Copy 32-byte tile to screen memory |
| `JMP &0967` | calc_screen_addr | Convert tile coordinates to screen address |
| `JMP &0982` | setup_map_render | Set up map rendering from scroll position |
| `JMP &0997` | render_map | Render visible map area |
| `JMP &0B30` | spawn_sprite | Initialize sprite from animation table |
| `JMP &0A2D` | update_sprites | Main sprite update loop (physics + animation) |
| `JMP &09BF` | init_game | Game initialization (VIA timers, clear sprites) |

### Encryption

The original Loader uses a ~55-stage decryption chain. Each stage XORs data with fixed keys, 256-byte block XOR, VIA timer values (timing-dependent), and byte indices. The VIA timer dependency means the XOR keys vary with exact CPU cycle timing, disk motor speed, and interrupt latency — even single-stepping in a debugger produces wrong results. See `encryption_appendix.asm` for details.

## Reverse Engineering Process

1. **Boot in emulator** — jsbeeb with BBC Master model
2. **Wait for decryption** — select level, let the 55-stage loader complete
3. **Dump memory** — read all memory regions from the running game
4. **Disassemble** — radare2 with 6502 architecture
5. **Annotate** — every instruction documented in BeebASM syntax
6. **Verify** — rebuild and compare against original

## Credits

- **Original game**: Matt Godbolt & Richard Talbot-Watkins (1993)
- **Reverse engineering & annotation**: Matt Godbolt & Claude (2026)

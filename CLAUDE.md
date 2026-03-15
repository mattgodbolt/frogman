# FROGMAN Reverse Engineering Project

BBC Master game written by Matt Godbolt & Richard Talbot-Watkins in 1993.
Goal: produce a fully annotated, instruction-level disassembly suitable for
reassembly with BeebASM. Byte-exact match achieved.

## Project Structure

```
frogman.ssd              # Original disk image
extracted/                # Files extracted from disk image
  Boot, Ribbit, Loader, FastIO, Gcode, Level1G, Level2G, ...
extracted/decrypted/      # Decrypted memory dumps from jsbeeb emulator
  game_engine.bin         # Core engine code (&0880-&0C79)
  irq_handler.bin         # IRQ handler (&0600-&065D)
  full_memory.bin         # Complete 64KB memory snapshot
  ...
save_dumps.py             # Memory dump collection script (canonical data source)
engine.asm                # Annotated game engine disassembly (BeebASM)
tables.asm                # Lookup tables (BeebASM)
music.asm                 # Music data (BeebASM)
frogman.asm               # Main build file
loader.asm                # Clean replacement loader
```

## Build

```bash
beebasm -i frogman.asm -do frogman_rebuilt.ssd -title FROGMAN
```

## Key Technical Details

- **Total executable code: ~1.1KB** (94 bytes IRQ + 1018 bytes engine)
- Custom CRTC screen layout (display base &5800, &200-byte row stride)
- Original Loader uses 55-stage XOR encryption with VIA timer PRNG
- SN76489 sound chip via System VIA at &FE40/&FE41
- All game files encrypted on disk — must dump from running emulator
- No enemies — the frog navigates environmental hazards and obstacles

## Memory Map (decrypted, game running)

| Region | Contents |
|---|---|
| &0000-&00FF | Zero page: game state variables |
| &0600-&065D | IRQ handler (music, sound envelopes, VSYNC dispatch) |
| &06BA-&06C8 | Sprite data pointer table |
| &0700-&073F | Tile source low-byte LUT (tile graphics addressing) |
| &0740-&077F | Tile source high-byte LUT (tile graphics addressing) |
| &0780-&07FF | Palette/fade tables (also SN76489 frequency low nibble) |
| &0800-&087F | Descending curve table (SN76489 frequency envelope) |
| &0880-&0C79 | Game engine code |
| &0C7A-&0EFF | Music data (3 tunes) + sound state block |
| &0F00-&22FF | Level map (part 1) |
| &2800-&36FF | Level map (part 2) |
| &3700-&47FF | Tile graphics |
| &4800-&57FF | Sprite graphics |
| &7800-&7FFF | Status bar graphics |

## Conventions

- BeebASM syntax: `&` for hex (not `$`), `.label` for labels
- Comments explain "why" not "what" for non-obvious code
- All internal cross-references use labels (no hard-coded addresses)
- Data tables annotated with structure documentation
- Every instruction in code sections gets a comment

## Workflow

- Dump memory via jsbeeb MCP tools → save_dumps.py → binary files
- Disassemble with radare2: `r2 -a 6502 -b 8 -m 0x0880`
- Annotate as BeebASM assembly
- Verify: build → compare binary output against memory dump (0 mismatches)

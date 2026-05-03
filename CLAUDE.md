# FROGMAN Reverse Engineering Project

BBC Micro game written by Matt Godbolt & Richard Talbot-Watkins in 1993.
Fully annotated, instruction-level disassembly with byte-exact BeebASM
reassembly. Runs on both BBC Master and BBC Model B.

## Build

```bash
make                # Build disc image
./verify.sh         # Verify byte-exact match against original
```

## Key Facts

- **Flip-screen platformer** — no smooth scrolling, screens transition on map edges
- **No visual sprites** — frog rendered via tile overlay system, everything else is map tiles
- **4-channel sound engine** — what the code calls "sprites" are actually SN76489 sound channels driven by a music sequencer with envelope data
- **Music is level-specific** — Level?T files overwrite all 3 channel data streams (&0C80-&0EFF)
- **M key** toggles music on/off (not a debug feature for sprites)
- **Controls**: Z (right), X (down), : (climb), / (short hop), f0/f1 (item slots), SPACE (start), ESCAPE (die)
- **Pure NMOS 6502** — no 65C02 instructions, runs on Model B unchanged
- Custom CRTC layout: display base &5800, 64 chars wide, 20 rows, &200-byte stride

## Conventions

- BeebASM syntax: `&` for hex, `.label` for labels, `{}` for scoping
- `.*label` for globally-visible labels inside scopes (use sparingly)
- Comments explain "why" not "what" for non-obvious code
- All internal cross-references use labels (no hard-coded addresses)
- Zero page variables named in zero_page.asm, hardware in constants.asm
- Sound channel state uses `zp_snd_*` prefix, not "sprite"

## Music data layout

Each music channel lives at a page-aligned address required by the IRQ
read code (`LDA (zp_snd_data_lo),Y` with channel-specific HI byte and a
shared LO byte). music.asm anchors each channel explicitly:

- `music_ch1` at `&0C80`
- `music_ch2` at `&0D80`
- `music_ch3` at `&0E80`
- `anim_timing_const` at `&0EF7` (per-level note timing, slot in Level?T)

Engine and game code reference these by name (`HI(music_ch1)`,
`LO(music_ch1)`, `STA music_ch1,Y`). The Level?T file format is 640 bytes
mapped to `&0C80-&0EFF`: ch1 = bytes 0..255, ch2 = 256..511, ch3 = 512..639,
timing byte at file offset 631. Engine code can grow freely up to `&0C80`
without breaking the music — adding bytes there does not slide the channels.

## Verification

Always run `./verify.sh` after changes to confirm byte-exact match.
The script checks engine (&0700-&0EFF) and game code (&4800-&5800)
against the original decrypted binaries.

## Diary

DIARY.md contains the full reverse engineering diary. Keep it updated
when making significant discoveries or changes — it's the narrative
record of how the project evolved and captures context that isn't
obvious from the code alone.

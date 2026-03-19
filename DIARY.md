# FROGMAN Reverse Engineering Diary

## Entry 1: Discovery and Disk Exploration

Parsed the DFS disk catalog and extracted all 21 files from `frogman.ssd`. Decoded the Ribbit BASIC loader which displays a Mode 7 title screen with teletext graphics (clever trick: using BBC BASIC token values as teletext characters), hardware detection messages (including the hilarious "What on earth is this doing on an Electron?"), level selection (1 or 2), then `*RUN Loader`.

**Key discovery:** The Loader file (8KB) is almost entirely encryption — a chain of ~55 XOR stages using VIA timers as PRNG seeds. The VIA timer dependency makes static analysis impossible because the XOR keys change based on exact CPU cycle timing. Even single-stepping in a debugger produces different decryption results.

**Surprise:** How paranoid the encryption is for a school project. The original ReadMe brags about being "nearly unhackable."

## Entry 2: Emulator Dumping

Booted the game in jsbeeb (BBC Master model), selected level 1, waited for the loader to complete all 55 decryption stages. Dumped all memory regions (256 bytes at a time via jsbeeb's `read_memory` API) — about 120 calls across the full address space. Saved everything to binary files via Python scripts.

**Key discovery:** The total executable code is only ~1.1KB — 94 bytes of IRQ handler plus 1018 bytes of game engine. A complete platformer with scrolling, sprite animation, movement, music, and sound effects in just over a kilobyte.

## Entry 3: Disassembly and First Annotation Pass

Used radare2 (`r2 -a 6502 -b 8`) to produce initial disassembly. Identified the jump table at the engine entry point (7 JMP entries), traced all JSR/JMP targets, found the self-modifying code locations.

Wrote the first annotated BeebASM source. Got it building and assembling, but with 878 byte mismatches — accumulated errors from wrong label placements, an extra data table entry, and incorrect loop structures.

## Entry 4: Byte-Exact Match

Systematically compared the assembled output against the original binary, section by section. Found and fixed:
- `delay_spin` label was on the wrong instruction (INC instead of STA)
- `bc_copy_loop` label included `LDY #&00` inside the loop incorrectly
- `init_silence` label excluded `LDA #&00` from the loop body
- Movement pointer table had a spurious 8th entry that was actually the first sequence's chain terminator
- Music data had a hard-coded ORG that didn't match the engine end address

After fixes: **0 mismatches across 2304 bytes**.

## Entry 5: Cross-Reference Labels

Replaced every hard-coded internal address with symbolic labels. All code cross-references now use labels or `label + offset`, so editing the code won't break references. Added named labels for the four IRQ-handler-patched locations in the sound state block: `music_note_reset`, `music_ptr_lo`, `music_ptr_hi`, `music_env_patch`.

## Entry 6: Five-Agent Parallel Review

Launched 5 review agents in parallel, each scrutinizing a major routine against BBC Micro hardware documentation and the binary dump.

**Critical errors found and fixed:**
- **IRQ dispatch:** CMP #&03 tests CA1+CA2 (VSYNC-related), NOT Timer 1+Timer 2. Bits 0+1 in the VIA IFR are CA2+CA1, not timers.
- **Sound chip access:** The SN76489 is connected to the **System VIA**, not User VIA. &FE40/&FE41 are System VIA registers.
- **Register table swap:** `channel_vol_regs` (&E0,&C0,&A0,&80) actually contains **frequency** register bytes (1 cc 0 dddd), while `channel_freq_regs` (&F0,&D0,&B0,&90) contains **volume** bytes (1 cc 1 dddd). Labels were backwards.
- **Routine name swap:** `set_volume` actually set tone/frequency; `set_attenuation` actually set volume. Both renamed.
- **VIA "timer" setup:** &FE42/&FE43 are DDRB/DDRA (Data Direction Registers), NOT timer registers. Both routines configure the System VIA ports, neither touches timers or the User VIA.
- **Screen LUTs:** The &0700/&0740 tables provide tile **graphics source** addresses, not screen destination addresses. Values &38-&47 are tile source bank high bytes, not screen memory.
- **Screen base:** Display starts at &5800 with &200-byte row stride (custom CRTC), not standard Mode 2 at &3000.
- **No enemies:** The game has no enemies — sprites 1-3 are environmental hazards/objects.
- **Movement data format:** &FD and &FE are signed velocity bytes (-3 and -2), not special command prefixes. &FF,&FF entries are chain terminators, not sequence headers.

## Entry 7: Comment Hygiene

Removed all hard-coded address ranges from comments (they rot when code changes). Marked speculative tune names as "purpose unconfirmed". Renamed remaining misleading sprite state variables. Updated all documentation (README, CLAUDE.md, loader.asm) for consistency.

## Entry 8: Bootable Disc Investigation (parked)

Attempted to build a bootable disc image from the disassembly. Built successfully with BeebASM (PUTFILE for data, PUTBASIC for BASIC loader) but the game doesn't start because the **main game loop is missing**.

The ~1KB engine at &0880 contains only subroutines (render_map, update_sprites, set_tone, etc.) — they all end with RTS. Something external must call them in a loop. This orchestration code is created by the Loader's decryption chain and we haven't captured it.

**What we tried:**
- Patching the running game with JMP-to-self at update_sprites entry — but we can't read registers/SP to find the caller
- Reading the stack to find return addresses — stack is shared with mask table, can't determine SP
- Searching for the decryption chain endpoint — each stage's EOR uses memory being decrypted, so patching memory to set breakpoints corrupts the chain
- IRQ1V at &204/&205 unexpectedly points to &4CA5 (sprite graphics area), not &0600 — the interrupt hookup is more complex than assumed

**What's needed to proceed:**
- jsbeeb MCP needs breakpoint and register-read support to trace the Loader's decryption chain to its endpoint
- Once we can see the decrypted Loader's final stage, we'll find the game startup code that sets up IRQ vectors, calls init_game, renders the initial map, and enters the main loop
- The main loop is likely small (maybe 20-50 bytes) — it just needs to call update_sprites and handle keyboard input in a loop

## Entry 9: Tracing the Loader Decryption Chain

Added breakpoint support to the jsbeeb MCP (set_breakpoint, clear_breakpoint, read_registers, disassemble). Fixed two bugs: the `!first` skip in executeInternal could miss breakpoints, and type() interleaving runFor calls interfered with breakpoint halt/resume. Rewrote type() as a debugInstruction hook that coexists with breakpoints.

**The decryption chain structure:**

The Loader (&2800-&47FF, 8KB) contains ~410 stages of EOR loops, each 28 bytes of code decrypting the next 256 bytes. The code was ORGed at the end of the Loader and stages were prepended backwards until the space was filled. Each stage seeds the User VIA Timer 1 (&FE64/&FE65) with a different value and uses it as a rolling XOR key, making the decryption timing-dependent.

After the EOR chain completes, the decrypted code at &4700 reveals an easter egg:

> "So you've hacked through the 410(ish) little Eor Loops Of Brain Death. Now combat the Evil Timer Eor System Of Doom. (heh heh heh). Honestly, can't you find something better to do?"

The decrypted &4700 code then:
1. `*LOAD Screen` and decrypts &1F00-&21FF
2. &1F70: `*Load Credits 2400` and jumps to &2000
3. &2000: Timer-based EOR using Credits data as key, decrypts &2100
4. &2100: `*Load Data`, XORs &1100-&12FF using Credits data, jumps to &1100
5. &1100: MODE 2, CRTC setup, `*L.Data2` (title screen), RLE decompress to screen, wait for SPACE, `*L.Gcode`, decrypt sprite graphics (nibble swap + EOR), enable interrupts, `JMP &48A0`

## Entry 10: The Hidden Game Code

**The "sprite graphics" at &4800-&57FF is actually ~4KB of executable game code!**

What we labelled as sprite pixel data is in fact the game's main loop, IRQ handler, collision detection, keyboard handling, level loading, and all the orchestration code that calls the engine subroutines. The Gcode file is encrypted on disc and decrypted at &1100 using nibble-swap + double EOR (&4D, &47 — "MG"!).

**Key discoveries:**

- **IRQ handler at &4CA5** (not &0600): `LDA &FC : PHA : TXA : PHA : TYA : PHA : SEI : LDA &FE4D` — proper BBC IRQ1V protocol. Reads System VIA IFR at &FE4D (correct!), checks for CA1 (VSYNC), calls `JSR &088F` (update_sprites). This is the real interrupt handler.

- **IRQ1V setup at &497C**: `LDA #&A5 : STA &0204 : LDA #&4C : STA &0205` — sets IRQ1V to &4CA5, confirming the value we saw earlier.

- **Game main loop at &48A0+**: Loads level-specific files (`Level*G`, `FastI/O`, `Level*T`, `Level*S`, `Tabs`), patches filenames with the level number, copies tables from &5800 to &0700, clears screen memory, sets up sprites, renders initial map via `JSR &0886`/`JSR &0889`, then enters the game loop with keyboard scanning and collision detection.

- **&0600 is the NMI disc handler** (confirmed): used only during loading, not during gameplay.

**The total executable code is much larger than 1.1KB:**
- Engine subroutines: &0880-&0C79 (1018 bytes)
- Game code (Gcode): &4800-&57FF (~4096 bytes, encrypted on disc)
- Setup code: &1100-&12FF (512 bytes, runs once)
- NMI disc handler: &0600-&065D (94 bytes, loading only)

## Entry 11: Disc Build Restructured

Restructured the disc build to use original disc files from `extracted/` directly — the game code at &48A0 loads Level1G, Level1S, Level1T, Tabs, etc. by name via `*LOAD`, so these just need to be on the disc. Removed the stale memory dump files from `data/` that contained runtime state contamination.

The only pre-decrypted file needed is `data/gcode_decrypted.bin` (&4800-&57FF), since our boot loader bypasses the &1100 setup code that normally decrypts Gcode after loading.

**File loading flow discovered:**
- `*Load FastI/O 5800` — engine loaded to &5800 (NOT &0700!)
- Init at &495F copies &5800-&5FFF → &0700-&0EFF and clears screen
- `*Load Level?T 5D80` — level tile table at &5D80, overlaps the &5800 copy range so ends up at &0D80-&0EFF after copying (this is how the music/data region gets populated!)
- `*Load Level?G` — tile graphics, loads at default address from file header
- `*Load Level?S 300` — sprite defs to &0300
- `*Load Tabs 100` — mask table to &0100 (stack page)
- Level1G is unencrypted on disc; Level1S and Tabs have some mismatches vs memory (possibly runtime modifications or stack overwrites for Tabs)

**Boot loader:** MODE 2, load Gcode to &4800, load FastI/O to &5800, set level number at &0430, CALL &48A0.

Disc builds cleanly. Not yet tested in emulator.

## Entry 12: Bootable Disc Achieved

The rebuilt disc boots and plays! The missing piece was `Level1M` — the game code at &564F does `*DISC` then `*Load Level1M 5800` to load the level map. Once that file was added to the disc, everything works.

**Boot sequence:** `!Boot` → `*BASIC` → `CHAIN "Ribbit"` → MODE 2, `*LOAD Gcode` (pre-decrypted to &4800), `*LOAD FastI/O 5800`, set level number at &0430, `CALL &48A0`.

The game code at &48A0 then loads Level1G, FastI/O (to &5800), Level1T (to &5D80), Level1S (to &0300), and Tabs (to &0100). The init at &495F copies &5800-&5FFF → &0700-&0EFF (placing the engine at its runtime address) and clears screen memory. At &564F it does `*DISC` and loads Level1M (to &5800, then relocated). IRQ1V is set to &4CA5, interrupts enabled, game loop runs.

**Key discovery:** the `*DISC` command at &564F suggests the game was designed to work with both DFS and non-DFS filing systems. The original Loader may have switched filing systems during loading.

## Entry 13: Game Code Fully Disassembled and Labelled

Converted game.asm from pure EQUB to proper 6502 instructions with symbolic labels. The mechanical disassembly was done by a Python script that correctly identifies code vs data regions (OSCLI strings, lookup tables). A subagent then replaced all 138 hard-coded absolute addresses with labels.

**Current state:**
- 260 labels with descriptive names
- 0 hard-coded internal addresses
- 30 LO()/HI() usages for OSCLI string pointers
- OS entry points and hardware registers as named constants
- OSCLI strings converted from EQUB to EQUS with readable text
- Level number placeholders have named labels (oscli_level_g_num etc.)
- TILESTR macro defined for the custom tile font (A=&0A..Z=&23)
- Tile font display strings still need converting from wrongly-disassembled instructions to EQUB with TILESTR macro

**Key routines identified:**
- IRQ handler: VSYNC-driven, palette colour cycling, calls update_sprites
- set_palette: self-modifying Video ULA register write
- game_init: copies engine &5800→&0700, sets IRQ1V, VIA config
- main_loop: keyboard scanning → tile collision → movement dispatch
- Movement handlers: move_down, move_right, move_up_check etc.
- Tile operations: get_tile_at_pos, set_tile_at_pos, check_tile_solid
- Item system: collect_item, drop_item, clear_tile_pickup
- Display: draw_digit, draw_string (game_routines_5), draw_status

## Entry 14: Named Zero Page Variables

Replaced all ~500 bare zero page address references in both game.asm and engine.asm with named variables from zero_page.asm. Every `LDA &0C`, `STA &11`, `INC &0B` etc. now reads as `LDA zp_colour_phase`, `STA zp_frog_col`, `INC zp_tile_y`.

Added two new variables discovered during the process:
- `zp_temp_item` (&27) — temporary storage for item tile being placed
- `zp_temp_type` (&28) — temporary storage for item type being placed

Named the four tile renderer temporaries (&15-&18) that were previously anonymous `SKIP 4`:
- `zp_tile_y_ofs` — Y pixel offset within tile
- `zp_tile_width` — width step for tile loop
- `zp_tile_limit` — width limit counter
- `zp_tile_rows` — row counter

Replaced the duplicated zero page usage comment block in game.asm's IRQ handler with a reference to zero_page.asm.

**Issue flagged for investigation:** `&19` (`zp_direction`) is used as movement direction flags throughout game.asm, but the engine's `tile_addr_setup` uses it as a level number index. Likely a double-duty variable (level number set once at init, then reused as direction during gameplay).

**Process note:** After an earlier attempt at bulk replacement went wrong (replacing without verifying), switched to replacing one variable at a time with `./verify.sh` between each. This caught one bug: `STA &0F` replace_all also matched `STA &0F00,X`, mangling it to `STA zp_scroll_x00,X`. Fixed immediately.

## Entry 15: All Labels Named and Scoped

Replaced all 175 `l_XXXX` address-based labels with descriptive names. Applied BeebASM `{}` scoping throughout game.asm to contain internal branch targets as local labels. Key routines now read naturally:

- `move_down` / `move_right` — with `.anim_8`, `.anim_4`, `.scroll_right`/`.scroll_left`
- `move_up_check` — `.climb_left_step`, `.climb_right_step`, `.climb_ladder`, `.jump_up`
- `convey_right` / `convey_left` — conveyor belt movement routines
- `check_gravity` — `.check_fall`, `.start_fall`, `.scroll_down`
- `handle_map_reveal` — `.fade_out`, `.apply_palette`, `.calc_scroll_pos`
- `handle_special_tile` — `.first_visit`, `.show_denied`, `.all_collected`
- `game_state_handlers` — `.sink_loop`, `.check_lives`, `.game_over`
- `scan_keys` — `.not_down`, `.not_right`, `.not_up`, `.no_scroll`
- All utility routines: `get_tile_at_frog`, `check_tile_solid`, `get_tile_at_pos`, `check_tile_passable`, `collect_item`, `drop_item`, `draw_digit`, `draw_string`

Used `.*label` sparingly for labels that need global visibility from within a scope (e.g. `.*check_fall`, `.*scroll_right`, `.*scroll_left`, `.*item_slot_select`, `.*update_frog_tile`).

Engine cross-references now use jump table labels (`jmp_block_copy`, `jmp_render_map`, etc.) and `tile_addr_setup`/`tile_addr_setup_y`. Hardware registers use named constants.

**Final count: 0 unnamed labels, 0 bare zero page references.**

## Entry 16: Cleanup Pass

Sprite state arrays (&70-&91) added to zero_page.asm with named variables (`zp_spr_dir`, `zp_spr_anim_tmr`, `zp_spr_move_lo/hi`, `zp_spr_subctr`, `zp_anim_ptr_lo/hi`, etc.) and all references in engine.asm updated.

Fixed data misidentified as code: `BRK` instructions converted to `EQUB &00` in `tile_type_table` and `palette_fade_table`. `fall_step_table` data decoded from wrongly-disassembled `ORA (&01,X)` to correct `EQUB &01, &01, ...`. The `game_routines_1` code/data overlap resolved — was actually `JSR tile_addr_setup : JMP main_loop`.

Compacted consecutive `ASL A`/`LSR A`/`ROL A` sequences onto single lines with `:` separators throughout game.asm.

Scoped all remaining copy loops with local labels (no `.*` needed — self-modifying `label + 2` refs work fine inside the same scope).

**Resolved TODOs:**
- **&19 double-duty**: Not double-duty at all! `tile_addr_setup` uses `zp_direction` to select which column of tile graphics to render (0→&00, 1→&40, 2→&80, 3→&C0). The direction naturally indexes different visual orientations.
- **`load_level_map`**: `JMP` to itself — an unreachable infinite loop, likely a crash trap. Renamed to `.halt`.
- **`wait_frames` TODO**: Already identified, stale comment removed.

**Unused labels found and handled:**
- `str_power_off` — " POWER DEACTIVATED *" string, never displayed. Marked as unused (cut feature?).
- `jmp_spawn_sprite` — jump table entry never called through the table. Marked unused.
- `str_title_end`, `game_routines_3` — dead labels removed.

**physics_table investigation:** Tested reciprocal, exponential, power curve, and linear formulas against all 128 values. No simple formula produces a byte-exact match — the irregular first-differences suggest original BBC BASIC fixed-point arithmetic or hand-tuning. Keeping hardcoded EQUB.

## Entry 17: Three-Agent Review and Game Mechanics Corrections

Launched three review agents in parallel to audit engine.asm and game.asm for comment accuracy.

**Code recovered from EQUB data:**
- `read_key` was 7 bytes of EQUB — now properly disassembled as `STA VIA_ORA_NH : BIT VIA_ORA_NH : RTS` (direct VIA keyboard scan via no-handshake ORA at &FE4F).
- `get_tile_type` prefix was 4 bytes of EQUB — now `STY get_tile_type_ry + 1 : SEC` (self-modifying Y save).

**Key scan codes verified against BBC Micro keyboard matrix** (row × &10 + column):
- X (&42) = move down, Z (&61) = move right, : (&48) = climb/move up
- / (&68) = short hop modifier (4-step vs 8-step animation)
- f0 (&20) = use item slot 0, f1 (&71) = use item slot 1
- SPACE (&62) = start, ESCAPE (&70) = die/restart
- **M (&65) = toggle sprite display — a debug key!** Previously unknown.

**Critical game mechanics correction — flip-screen, not scrolling:**
The game uses flip-screen transitions, not smooth scrolling. This was a fundamental misunderstanding that cascaded through many labels and comments:
- `scroll_routines` → `use_item_slot` (f0/f1 pick up and place items, not scroll!)
- `scroll_right`/`scroll_left` → `short_hop_right`/`short_hop_left` (/ key shortens hops)
- `game_routines_4` → `place_item`
- `zp_scroll_x`/`zp_scroll_y` are the frog's pixel position within the current screen
- `zp_map_scroll_x`/`zp_map_scroll_y` are which screen the player is on in the map grid
- `INC zp_map_scroll_x` + `JSR jmp_setup_map` = flip to the next screen

**Engine comment fixes from review:**
- Animation loop comments ("Y = 1", "advance past loop body") were factually wrong — fixed
- VIA config routines had misleading "refresh timer" comments — now describe actual purpose
- Self-modifying AND in tile renderer — comment clarified (patches address, not immediate)
- Magic constants (&02, &04) in sprite init — now explain they skip chain terminators

**Other fixes:**
- IRQ entry comment: "Restore A" → "Load A saved by MOS IRQ dispatcher"
- Stale hardcoded address comments removed (IRQ1V hex values, string pointer addresses)
- CRTC register table annotated with per-register descriptions
- `str_power_off` marked as unused cut feature
- `halt` label for unreachable JMP-to-self (was misleadingly called `load_level_map`)

## What Remains

- Full annotation of the setup code at &1100-&12FF
- The relationship between the three tunes and game states
- `game_routines_2` padding bytes between `set_palette` and `wait_vsync`
## Entry 18: "Sprites" Are Sound Channels

Major conceptual correction: what the engine calls "sprites" are actually **sound channels**. The game has no visual sprites in the traditional sense — the frog is rendered by the overlay system (`tile_render` compositing from &3700 via AND/ORA masking onto the background). The engine's `update_sprites` routine is a 4-channel music/sound sequencer:

- Channels 1-3: music voices following scripted note sequences
- Channel 0: sound effects with envelope-driven frequency/volume

The "animation tokens" (&FC=loop, &FA=loop-back, &FE=end) are music sequence commands. The "movement sequences" are frequency/volume envelope data. The "sprite state arrays" are per-channel sound state.

Renamed throughout:
- `update_sprites` → `update_sound`, `spawn_sprite` → `init_channel`
- `sprite_anim_*` → `channel_*`, `sprite_vert_speed` → `channel_freq_param`
- `zp_spr_*` → `zp_snd_*` (freq, vol, timer, seq_lo/hi, etc.)
- `zp_sprite_inhibit` → `zp_music_inhibit`
- `clear_sprite_state` → `clear_sound_state`
- All comments updated: "animation" → "music", "movement" → "envelope", etc.

The M key toggles music (not "sprite display" as previously thought) — it sets `zp_music_inhibit` which prevents the IRQ handler from calling `update_sound`.

## Entry 19: Music and Remaining Cleanup

Documented how Level?T (640 bytes at &5D80) maps to &0C80-&0EFF after the engine copy, overwriting all three sound channel data streams. Each level has completely different music — no channels shared.

Added a simple level select prompt to boot.bas (MODE 7, "Level 1 or 2?").

The `game_routines_2` mystery bytes (`&65 &03` at &4D18-&4D19) are confirmed as dead code: no JSR, JMP, or branch targets them, and they sit after an RTS. Likely a vestigial instruction left behind during development.

## Entry 20: BBC Model B Compatibility

Investigated whether the game could run on a BBC Model B (standard NMOS 6502) instead of the BBC Master (65C12). Found:

- **No 65C02 instructions used** — the entire codebase is pure NMOS 6502. No STZ, PHX/PLX, BRA, TRB/TSB, INC A, or (zp) indirect modes.
- **Same hardware** — System VIA, CRTC, Video ULA, SN76489 are identical between Model B and Master.

Booted `frogman_rebuilt.ssd` on a BBC Model B (DFS 1.2) in jsbeeb. It works perfectly — level select, title screen, gameplay, movement, music, all correct. The frog hops, screens flip, items render, status bar updates.

**The original game's Model B incompatibility was entirely due to the encrypted Loader**, not the game code. The Loader's 55-stage XOR decryption chain likely used Master-specific features (PAGE=&E00 giving more BASIC workspace, or Master-specific memory layout assumptions). By bypassing the encryption with our clean BASIC boot loader, the game just works on a Model B with no code changes needed.

This is a nice side effect of the reverse engineering — the rebuilt disc runs on hardware the original never supported!

## Entry 21: Title Screen Restoration and Remastered Boot Sequence

Reinstated the full original boot experience:

1. **Mode 7 credits screen** — decoded the original Ribbit BASIC loader's teletext graphics (large green block-letter FROGMAN logo, red separator bars, cyan credits, magenta copyright) by reading the tokenized BASIC directly. Added "Remastered 2026" in blue.

2. **Level select** — "Choose level (1 or 2):" with coloured text matching the original.

3. **Mode 2 title screen** — disassembled the original setup code at &1100, extracted the RLE decompressor (3 token types: literal copy, repeat fill, page fill), and wrote `setup.asm` as a clean standalone version at &0900. Loads and decompresses Data2 to display the pixel-art FROG MAN title with the green frog.

4. **Clean transitions** — blanks display via CRTC R1=0 before mode switches, clears screen memory (&3000-&7FFF) manually after SPACE to prevent garbage when the game reconfigures CRTC to its custom layout.

## Entry 22: Comment Audit, Idiomatic BeebASM, and Object System Documentation

Deep review pass over all assembly files, focusing on comment accuracy, idiomatic improvements, and documenting the item/object system.

**Comment fixes across all files:**

- **engine.asm:** Replaced all remaining sprite-era terminology in envelope sequences — "velY/velX" → "vol/freq delta" with proper signed values. Fixed the header to describe subroutines rather than claiming "complete game logic". Clarified the set_tone routine's dual use of palette_tables and renamed `physics_table` → `freq_divider_table` (it provides SN76489 frequency divider high bytes, not physics data).

- **tables.asm:** Rewrote palette table header to explain the dual-use as both colour indices and frequency latch nibbles. Replaced speculative "Bright cycling colours" / "Fade ramp" comments with factual pitch-range descriptions for the frequency divider table.

- **music.asm:** Removed false claim of "encrypted data block" — the data after the tunes is just residual bytes overwritten by Level?T. Removed speculative note annotations ("bass notes", "chord progression"). Documented `anim_timing_const` as level-specific (it lives in the Level?T overwrite region).

- **game.asm:** The most impactful fix — renamed `move_down` → `hop_right` and `move_right` → `hop_left`. The X key hops RIGHT (INC scroll_x, INC frog_col) and Z hops LEFT (DEC scroll_x, DEC frog_col). The original names were backwards, a cascading error from early disassembly. Added per-entry comments to `collision_flags` documenting what each tile is. Documented the inverted collision convention (0=solid, &FF=passable). Added explanatory headers to `check_tile_solid`, `collect_item`, `drop_item`, `handle_map_reveal`, and `handle_special_tile`.

**Key discovery — tile type table is embedded in tile graphics:**

`get_tile_type` reads from &4000, which is tile &20's pixel data. The first 64 bytes of tile 32's graphics serve double duty as the type lookup table for ALL indexed tiles (&20-&3F). Each level's graphics file thus embeds gameplay properties in pixel data — changing Level?G changes both visuals AND item behaviour. This is documented in FORMATS.md.

**Idiomatic BeebASM improvements:**

- Added named constants for all 10 key scan codes (`KEY_X`, `KEY_Z`, `KEY_COLON`, `KEY_SLASH`, `KEY_F0`, `KEY_F1`, `KEY_SPACE`, `KEY_ESCAPE`, `KEY_M`, `KEY_ZERO`) and 17 special tile indices (`TILE_EMPTY` through `TILE_POWER_TERM`).
- Replaced ~30 magic numbers in game.asm with these constants.
- Converted 4 display strings from raw EQUB to `TILESTR` macro (`str_title`, `str_press_space`, `str_special_msg`, `str_continue`, `str_well_done`, `str_power_off`).
- Replaced the 128-byte `tile_source_lut` EQUB block with `FOR/NEXT` loops matching the engine's pattern.
- All changes verified byte-exact against original binaries.

**Item/object system fully documented (FORMATS.md, LEVEL1_OBJECTS.md):**

Traced all 6 item evolution chains in Level 1, the terminal collection win condition (8 terminals → "LOGGED ON"), and the key/door mechanic. Created a Mermaid DAG showing object dependencies. The item system uses a clever INC-based transformation: walking on a type-9 tile while holding the matching data value increments the slot, creating item chains like &34 → &35 (which then makes barrier tiles passable).

**Visual identification confirmed by the original artist:**

Matt Godbolt provided definitive tile identifications: white key (&21), yellow key (&28), white/yellow doors (&23/&29), carrot (&24), bookshelf (&2A), library ticket (&2B), bible (&2C), cross (&2E), unlit/lit candle (&2F/&30), fire (&31), TNT (&32), magic wand (&34), rabbit (&35), top hat (&36), ring (&37). The magic trick chain is confirmed: wand goes into the top hat → rabbit comes out.

**Purged all "scroll" terminology:**

The game has no scrolling — it's flip-screen. Renamed `zp_scroll_x`/`zp_scroll_y` → `zp_frog_x`/`zp_frog_y` (character columns and scanlines within the current screen), `zp_map_scroll_x`/`zp_map_scroll_y` → `zp_screen_x`/`zp_screen_y` (which screen in the level grid). Also renamed labels: `scroll_down` → `screen_down`, `scroll_step_table` → `hop_arc_table`, `calc_scroll_pos` → `calc_frog_pos`. Zero occurrences of "scroll" remain in any .asm file.

**Fixed collision logic (types 5/7):**

The `check_held` routine returns &FF when the item matches, which is *passable* per the codebase convention (&00=solid, &FF=passable). So types 5/7 tiles are barriers that become passable when you hold the matching item — not platforms that appear. Renamed the misleading `.solid` label to `.held_passable`.

## What Remains

- Level 2 object analysis and DAG
- Full annotation of the setup code at &1100-&12FF

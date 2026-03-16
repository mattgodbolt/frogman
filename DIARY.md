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

## What Remains

- **Boot test** the rebuilt disc in jsbeeb
- Disassemble and annotate the &4800-&57FF game code (main loop, IRQ handler, collision)
- Full annotation of the setup code at &1100-&12FF
- The relationship between the three tunes and game states
- Level 2 support (load Level2* files)
- Update encryption_appendix.asm with the full decryption chain structure
- Reconcile the engine assembly comments with the new understanding (game code calls engine via jump table, IRQ at &4CA5 not &0600)

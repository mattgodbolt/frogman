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

## What Remains

- The mask table at &0100-&013F (stack page) is populated at runtime but we haven't captured or documented its contents
- The exact CRTC register configuration isn't documented
- The BASIC loader (Ribbit) reconstruction is a sketch, not byte-accurate
- Level 2 data hasn't been dumped or compared
- The relationship between the three tunes and game states is unknown
- The two "sound data blocks" between tunes contain data whose runtime purpose (beyond the 4 named labels) is unidentified

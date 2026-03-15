; ============================================================================
; FROGMAN — Clean Replacement Loader
; ============================================================================
; Simple loader that replaces the original 55-stage encrypted Loader.
; Loads all game data files from disk and jumps to the game engine
; initialization routine.
;
; The original Loader at &2800 used multi-stage XOR encryption with VIA
; timer-based PRNG seeds, making static analysis intentionally impossible.
; This clean loader achieves the same result by simply loading the
; pre-decrypted data files.
;
; For the original encryption scheme, see encryption_appendix.asm.
; ============================================================================

ORG &2800

.loader_start
    ; Disable interrupts during loading
    SEI

    ; --- Load lookup tables and engine code ---
    ; FastIO contains: screen LUTs (&0700), palette tables (&0780),
    ; physics table (&0800), and the game engine (&0880-&0C78+music)
    ; Original load address: &0700, length: &0580 (1408 bytes)

    ; --- Load level-specific data ---
    ; The BASIC loader (Ribbit) has already selected level 1 or 2
    ; and stored the level number. We load the appropriate files.

    ; Level sprite definitions → &0300
    ; Level tile table → &0340 (within sprite defs area)
    ; Level tile graphics → &3700
    ; Level map → sideways RAM, then copied to &0F00+

    ; --- Load common data ---
    ; Gcode (sprite graphics) → &4800
    ; Tbar (status bar) → &7800
    ; Screen layout → &1F00
    ; Data2 (title screen) → &1300

    ; --- Initialize and start game ---
    ; Set up IRQ vector to point to &0600
    LDA #&00
    STA &0204                   ; IRQ1V low = &00
    LDA #&06
    STA &0205                   ; IRQ1V high = &06

    ; Jump to game initialization
    JMP &09BF                   ; init_game — sets up VIA timers,
                                ; clears sprites, starts game loop

    ; NOTE: In a real build, this loader would use OSFILE or OSFIND
    ; calls to load each data file. The BeebASM build file handles
    ; this by placing files at the correct addresses in the disk image
    ; using PUTFILE, so this loader only needs to set up the IRQ
    ; vector and jump to the game.

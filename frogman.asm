; ============================================================================
; FROGMAN — BBC Micro Game
; Written by Matthew Godbolt & Richard Talbot-Watkins, February 1993
;
; Main build file for BeebASM reassembly.
;
; Boot sequence:
;   !Boot → BASIC → Ribbit (credits, level select) → Setup (title screen,
;   loads Gcode + FastI/O, JMP &48A0) → game_init (copies &5800→&0700,
;   loads level files, sets IRQ, enters main loop).
; ============================================================================

; --- Constants and zero page definitions ---
INCLUDE "constants.asm"
INCLUDE "zero_page.asm"

; === Engine: lookup tables + subroutines + music ===
; Loaded as "FastI/O" to &5800, then copied to &0700 by game_init.
; Level?T (640 bytes at &5D80) overwrites &0C80-&0EFF with music data.
ORG &0700
INCLUDE "tables.asm"
INCLUDE "engine.asm"
INCLUDE "music.asm"

; Original FastI/O was 1408 bytes (&580). The music data (&0C80-&0EFF)
; is always overwritten by Level?T, so we only need to save up to &0C80.
; We save the full range for simplicity; the extra bytes are harmless.
SAVE "FastI/O", &0700, &0F00, &0700

; === Game code ===
; Main game loop, IRQ handler, collision, keyboard, level loading.
; On the original disc this is encrypted as "Gcode".
ORG &4800
INCLUDE "game.asm"
SAVE "Gcode", &4800, &5800, &4800

; === Level data files ===
; Loaded by *LOAD commands in the game code at &48A0.
PUTFILE "extracted/Level1G",  "Level1G", &3700, &3700
PUTFILE "extracted/Level1S",  "Level1S", &0300, &0300
PUTFILE "extracted/Level1T",  "Level1T", &5D80, &5D80
PUTFILE "extracted/Level2G",  "Level2G", &3700, &3700
PUTFILE "extracted/Level2S",  "Level2S", &0300, &0300
PUTFILE "extracted/Level1M",  "Level1M", &5800, &5800
PUTFILE "extracted/Level2T",  "Level2T", &5D80, &5D80
PUTFILE "extracted/Level2M",  "Level2M", &5800, &5800
PUTFILE "extracted/Tabs",     "Tabs",    &0100, &0100
PUTFILE "extracted/Tbar",     "Tbar",    &7800, &7800

; === Title screen setup code ===
; RLE decompressor + title screen display + game launcher.
CLEAR &0900, &0B00
ORG &0900
INCLUDE "setup.asm"
SAVE "Setup", setup_entry, P%, setup_entry

; Data2 is the RLE-compressed title screen graphic.
PUTFILE "extracted/Data2",   "Data2",   &1300, &1300

; === Boot loader ===
; Ribbit is the tokenized BASIC program (Mode 7 credits + level select).
; !Boot is the DFS auto-boot command.
PUTBASIC "boot.bas", "Ribbit"
PUTTEXT "bootcmd.txt", "!Boot", 0

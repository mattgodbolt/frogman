; ============================================================================
; FROGMAN — BBC Micro Game
; Written by Matthew Godbolt & Richard Talbot-Watkins, February 1993
;
; Main build file for BeebASM reassembly.
; Assembles the engine code and builds a bootable disc image with all
; data files at their correct runtime load addresses.
;
; The original disc uses encrypted files decrypted by a 55-stage Loader.
; This build uses pre-decrypted data dumped from the running game,
; with a simple BASIC loader replacing the encryption chain.
; ============================================================================

; --- Assemble all code and data ---
INCLUDE "engine.asm"
INCLUDE "music.asm"

; --- Save files to disc using original names where applicable ---
SAVE "FastI/O", &0600, &0F00, init_game
PUTFILE "data/sprite_defs.bin",  "Level1S", &0300, &0300
PUTFILE "data/level_map.bin",    "Level1M", &0F00, &0F00
PUTFILE "data/level_map2.bin",   "MapGap",  &2300, &2300
PUTFILE "data/level_map3.bin",   "MapPt2",  &2800, &2800
PUTFILE "data/level1_gfx.bin",   "Level1G", &3700, &3700
PUTFILE "data/sprite_gfx.bin",   "Gcode",   &4800, &4800
PUTFILE "data/status_bar.bin",   "Tbar",    &7800, &7800

; --- Boot sequence ---
; BASIC loader that loads all files and starts the game.
; !Boot text file chains the BASIC program (mimics original boot pattern).
PUTBASIC "boot.bas", "Ribbit"
PUTTEXT "bootcmd.txt", "!Boot", 0

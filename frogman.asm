; ============================================================================
; FROGMAN — BBC Micro Game
; Written by Matthew Godbolt & Richard Talbot-Watkins, February 1993
;
; Main build file for BeebASM reassembly.
;
; Boot sequence:
;   !Boot loads pre-decrypted Gcode to &4800 and engine to &5800,
;   sets MODE 2, then JMP &48A0. The game code at &48A0 loads
;   level-specific files from disc, copies engine from &5800 to
;   &0700, sets up IRQ, and enters the game loop.
; ============================================================================

; --- Constants and zero page definitions ---
INCLUDE "constants.asm"
INCLUDE "zero_page.asm"

; --- Assemble engine code (tables + engine + music) ---
INCLUDE "engine.asm"
INCLUDE "music.asm"

; Save engine as "FastI/O" — the name the game code expects.
; The game does *Load FastI/O 5800, then init copies &5800→&0700.
SAVE "FastI/O", &0700, &0F00, &0700

; --- Game code ---
; Main game loop, IRQ handler, collision, keyboard, level loading.
; On the original disc this is encrypted as "Gcode".
INCLUDE "game.asm"
SAVE "Gcode", &4800, &5800, &4800

; --- Original disc files (used directly by game code at &48A0) ---
; These are loaded by *LOAD commands in the game code.
; Level1G/Level2G are unencrypted on the original disc.
; Level1S/Level2S, Level1T/Level2T, Tabs, Tbar are loaded as-is.
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

; --- Boot loader ---
; Ribbit is the tokenized BASIC program.
; !Boot is a text file that chains it (boot option 3 = *EXEC !Boot).
PUTBASIC "boot.bas", "Ribbit"
PUTTEXT "bootcmd.txt", "!Boot", 0

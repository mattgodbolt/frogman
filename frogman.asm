; ============================================================================
; FROGMAN — BBC Micro Game
; Written by Matthew Godbolt & Richard Talbot-Watkins, February 1993
;
; Main build file for BeebASM reassembly.
; ============================================================================

; Assembly order follows memory layout:
;   &0600-&065D  IRQ handler          (engine.asm, first section)
;   &06BA-&06C8  Sprite pointer table (engine.asm, second section)
;   &0700-&087F  Lookup tables        (tables.asm)
;   &0880-&0C79  Game engine          (engine.asm, third section)
;   &0C7A-&0EFF  Music data           (music.asm)
;
; BeebASM allows backward ORG as long as regions don't overlap,
; so the IRQ handler at &0600 is assembled first, then tables at
; &0700 fit in the gap before the engine at &0880.

INCLUDE "engine.asm"
INCLUDE "music.asm"

; --- Data files ---
; Binary data is placed in the disk image using PUTFILE.
; The BASIC loader (Ribbit) or machine code Loader loads these
; at runtime to their correct memory addresses.
;
SAVE "Engine", &0600, &0F00, &09BF

; Uncomment the following for a complete disk image build:
;
; PUTFILE "extracted/decrypted/tile_graphics_partial.bin", "Level1G", &3700, &3700
; PUTFILE "extracted/decrypted/sprite_graphics.bin", "Gcode", &4800, &4800
; PUTFILE "extracted/decrypted/status_bar.bin", "Tbar", &7800, &7800
; PUTFILE "extracted/decrypted/level_map_full.bin", "Level1M", &0F00, &0F00

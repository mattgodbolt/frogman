; ============================================================================
; FROGMAN — BBC Micro Game
; Written by Matthew Godbolt & Richard Talbot-Watkins, February 1993
;
; Main build file for BeebASM reassembly.
; Produces a clean build from annotated disassembly of the decrypted runtime.
; ============================================================================

; --- Screen memory layout ---
; BBC Micro MODE 2: screen at &3000-&7FFF (20KB)
; Each character row = &140 bytes (8 pixel rows x 40 bytes/row)
; Tiles are 8x8 pixels = 32 bytes each in MODE 2

; --- Build configuration ---

INCLUDE "tables.asm"        ; Lookup tables at &0700-&08FF
INCLUDE "engine.asm"        ; IRQ handler (&0600) + game engine (&0880)
INCLUDE "music.asm"         ; Music data at &0C78-&0EFF

; --- Data files (INCBINed at their load addresses) ---
; These are loaded by the BASIC loader or machine code loader.
; Level data, tile graphics, sprite graphics, and screen data
; are loaded separately by the loader and are not part of the
; core engine assembly.

; The following data regions are loaded at runtime:
;   Tile graphics:   &3700+ (loaded as Level1G/Level2G)
;   Level map:       &0F00+ (loaded as Level1M/Level2M)
;   Sprite data:     loaded as Level1S/Level2S
;   Screen image:    loaded as Screen
;   Status bar:      loaded as Tbar
;   Title text:      loaded as ScrText

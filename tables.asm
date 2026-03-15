; ============================================================================
; FROGMAN — Lookup Tables
; Loaded at &0700-&08FF
;
; These tables are pre-populated in memory before the game engine runs.
; They provide fast lookups for tile source addressing, colour cycling,
; and sound frequency envelope / descending curve calculations.
; ============================================================================

; ============================================================================
; Tile Source Low-Byte LUT (&0700-&073F)
; ============================================================================
; Maps a tile index (0-63) to the low byte of its graphics source address.
; Tiles are stored in 256-byte banks; each bank holds 4 tiles at offsets
; &00, &40, &80, &C0 (64 bytes per tile). The repeating pattern assigns
; each group of 4 consecutive tiles to the same source bank.

; P% should be &0700 here (flowing from engine.asm padding)
.tile_src_lo
    EQUB &00, &40, &80, &C0     ; Tiles 0-3: offsets within source bank
    EQUB &00, &40, &80, &C0     ; Tiles 4-7
    EQUB &00, &40, &80, &C0     ; Tiles 8-11
    EQUB &00, &40, &80, &C0     ; Tiles 12-15
    EQUB &00, &40, &80, &C0     ; Tiles 16-19
    EQUB &00, &40, &80, &C0     ; Tiles 20-23
    EQUB &00, &40, &80, &C0     ; Tiles 24-27
    EQUB &00, &40, &80, &C0     ; Tiles 28-31
    EQUB &00, &40, &80, &C0     ; Tiles 32-35
    EQUB &00, &40, &80, &C0     ; Tiles 36-39
    EQUB &00, &40, &80, &C0     ; Tiles 40-43
    EQUB &00, &40, &80, &C0     ; Tiles 44-47
    EQUB &00, &40, &80, &C0     ; Tiles 48-51
    EQUB &00, &40, &80, &C0     ; Tiles 52-55
    EQUB &00, &40, &80, &C0     ; Tiles 56-59
    EQUB &00, &40, &80, &C0     ; Tiles 60-63

; ============================================================================
; Tile Source High-Byte LUT (&0740-&077F)
; ============================================================================
; Maps a tile index to the high byte of its graphics source address.
; Tile graphics are stored in the region &3800-&47FF. Each group of 4
; entries shares the same high byte, corresponding to tiles sharing
; the same 256-byte source bank (each tile is 2 character rows = 16
; pixels tall). Values run from &38 to &47.

.tile_src_hi
    EQUB &38, &38, &38, &38     ; Tiles 0-3: source bank &3800
    EQUB &39, &39, &39, &39     ; Tiles 4-7: source bank &3900
    EQUB &3A, &3A, &3A, &3A     ; Tiles 8-11: source bank &3A00
    EQUB &3B, &3B, &3B, &3B     ; Tiles 12-15: source bank &3B00
    EQUB &3C, &3C, &3C, &3C     ; Tiles 16-19: source bank &3C00
    EQUB &3D, &3D, &3D, &3D     ; Tiles 20-23: source bank &3D00
    EQUB &3E, &3E, &3E, &3E     ; Tiles 24-27: source bank &3E00
    EQUB &3F, &3F, &3F, &3F     ; Tiles 28-31: source bank &3F00
    EQUB &40, &40, &40, &40     ; Tiles 32-35: source bank &4000
    EQUB &41, &41, &41, &41     ; Tiles 36-39: source bank &4100
    EQUB &42, &42, &42, &42     ; Tiles 40-43: source bank &4200
    EQUB &43, &43, &43, &43     ; Tiles 44-47: source bank &4300
    EQUB &44, &44, &44, &44     ; Tiles 48-51: source bank &4400
    EQUB &45, &45, &45, &45     ; Tiles 52-55: source bank &4500
    EQUB &46, &46, &46, &46     ; Tiles 56-59: source bank &4600
    EQUB &47, &47, &47, &47     ; Tiles 60-63: source bank &4700

; ============================================================================
; Palette / Colour Fade Tables (&0780-&07FF)
; ============================================================================
; 128 bytes of colour values used for palette cycling and fade effects.
; Each entry is a 4-bit logical colour value (0-15). The tables are
; indexed during colour fade-in/fade-out sequences and also used by
; the set_volume routine to look up volume/attenuation values for the
; SN76489 sound chip.
;
; The first portion contains colour cycling patterns for visual effects.
; The latter portion contains smooth fade-down ramps (15 to 0).

.palette_tables
    EQUB &0F, &01, &05, &0A     ; Bright cycling colours
    EQUB &0F, &05, &0C, &03
    EQUB &0B, &04, &0E, &08
    EQUB &03, &0E, &0A, &07
    EQUB &04, &02, &00, &0E     ; Mid cycling colours
    EQUB &0E, &0D, &0D, &0E
    EQUB &0F, &00, &02, &05
    EQUB &07, &0A, &0E, &01
    EQUB &05, &0A, &0F, &04     ; Warm cycling colours
    EQUB &09, &0F, &05, &0B
    EQUB &02, &09, &00, &07
    EQUB &0F, &06, &0E, &07
    EQUB &0F, &08, &01, &0A     ; Cool cycling colours
    EQUB &03, &0D, &07, &00
    EQUB &0A, &05, &0F, &0A
    EQUB &04, &0F, &0A, &05
    EQUB &01, &0C, &08, &03     ; Fade ramp group 1
    EQUB &0F, &0B, &07, &03
    EQUB &0F, &0C, &08, &05
    EQUB &01, &0E, &0B, &08
    EQUB &05, &02, &0F, &0D     ; Fade ramp group 2
    EQUB &0A, &07, &05, &02
    EQUB &00, &0E, &0C, &09
    EQUB &07, &05, &03, &01
    EQUB &0F, &0E, &0C, &0A     ; Smooth fade 15->0 (part 1)
    EQUB &08, &07, &05, &04
    EQUB &02, &01, &0F, &0E
    EQUB &0D, &0B, &0A, &09
    EQUB &08, &07, &06, &04     ; Smooth fade 15->0 (part 2)
    EQUB &03, &02, &01, &00
    EQUB &0F, &0F, &0E, &0D
    EQUB &0C, &0B, &0A, &0A

; ============================================================================
; Descending Curve Table (&0800-&087F)
; ============================================================================
; 128-byte lookup table providing a descending curve from 63 (&3F) to 1.
; Primary runtime use is as the second byte of SN76489 frequency data,
; called by set_tone to provide sound frequency envelope shaping.
; May also be used for physics calculations (the curve shape would
; suit deceleration or bounce dynamics).

; P% should be &0800 here (flowing from palette tables)
.physics_table
    EQUB &3F, &3E, &3C, &3A     ; 63, 62, 60, 58 — high values
    EQUB &38, &37, &35, &34     ; 56, 55, 53, 52
    EQUB &32, &31, &2F, &2E     ; 50, 49, 47, 46
    EQUB &2D, &2B, &2A, &29     ; 45, 43, 42, 41
    EQUB &28, &27, &26, &24     ; 40, 39, 38, 36
    EQUB &23, &22, &21, &20     ; 35, 34, 33, 32
    EQUB &1F, &1F, &1E, &1D     ; 31, 31, 30, 29
    EQUB &1C, &1B, &1A, &1A     ; 28, 27, 26, 26
    EQUB &19, &18, &17, &17     ; 25, 24, 23, 23 — mid range
    EQUB &16, &15, &15, &14     ; 22, 21, 21, 20
    EQUB &14, &13, &13, &12     ; 20, 19, 19, 18
    EQUB &11, &11, &10, &10     ; 17, 17, 16, 16
    EQUB &0F, &0F, &0F, &0E     ; 15, 15, 15, 14
    EQUB &0E, &0D, &0D, &0D     ; 14, 13, 13, 13
    EQUB &0C, &0C, &0B, &0B     ; 12, 12, 11, 11
    EQUB &0B, &0A, &0A, &0A     ; 11, 10, 10, 10
    EQUB &0A, &09, &09, &09     ; 10, 9, 9, 9 — slow range
    EQUB &08, &08, &08, &08     ; 8, 8, 8, 8
    EQUB &07, &07, &07, &07     ; 7, 7, 7, 7
    EQUB &07, &06, &06, &06     ; 7, 6, 6, 6
    EQUB &06, &06, &05, &05     ; 6, 6, 5, 5
    EQUB &05, &05, &05, &05     ; 5, 5, 5, 5
    EQUB &05, &04, &04, &04     ; 5, 4, 4, 4
    EQUB &04, &04, &04, &04     ; 4, 4, 4, 4
    EQUB &03, &03, &03, &03     ; 3, 3, 3, 3 — low values
    EQUB &03, &03, &03, &03     ; 3, 3, 3, 3
    EQUB &03, &03, &02, &02     ; 3, 3, 2, 2
    EQUB &02, &02, &02, &02     ; 2, 2, 2, 2
    EQUB &02, &02, &02, &02     ; 2, 2, 2, 2
    EQUB &02, &02, &02, &02     ; 2, 2, 2, 2
    EQUB &01, &01, &01, &01     ; 1, 1, 1, 1 — minimum values
    EQUB &01, &01, &01, &01     ; 1, 1, 1, 1

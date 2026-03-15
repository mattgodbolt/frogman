; ============================================================================
; FROGMAN — Lookup Tables
; Loaded at &0700-&08FF
;
; These tables are pre-populated in memory before the game engine runs.
; They provide fast lookups for screen addressing, colour cycling, and
; physics/gravity calculations.
; ============================================================================

; ============================================================================
; Screen Column Address LUT (&0700-&073F)
; ============================================================================
; Maps a tile column index (0-63) to the low byte of its screen address.
; Each tile is 8 pixels wide, but in MODE 2 each pixel row is interleaved
; across memory in 4-byte groups, giving column offsets of &00, &40, &80, &C0
; repeating. This pattern corresponds to the 4 character cells within each
; 320-byte (&140) screen row.

; P% should be &0700 here (flowing from engine.asm padding)
.screen_col_lut
    EQUB &00, &40, &80, &C0     ; Columns 0-3
    EQUB &00, &40, &80, &C0     ; Columns 4-7
    EQUB &00, &40, &80, &C0     ; Columns 8-11
    EQUB &00, &40, &80, &C0     ; Columns 12-15
    EQUB &00, &40, &80, &C0     ; Columns 16-19
    EQUB &00, &40, &80, &C0     ; Columns 20-23
    EQUB &00, &40, &80, &C0     ; Columns 24-27
    EQUB &00, &40, &80, &C0     ; Columns 28-31
    EQUB &00, &40, &80, &C0     ; Columns 32-35
    EQUB &00, &40, &80, &C0     ; Columns 36-39
    EQUB &00, &40, &80, &C0     ; Columns 40-43
    EQUB &00, &40, &80, &C0     ; Columns 44-47
    EQUB &00, &40, &80, &C0     ; Columns 48-51
    EQUB &00, &40, &80, &C0     ; Columns 52-55
    EQUB &00, &40, &80, &C0     ; Columns 56-59
    EQUB &00, &40, &80, &C0     ; Columns 60-63

; ============================================================================
; Screen Row High-Byte LUT (&0740-&077F)
; ============================================================================
; Maps a tile row index to the high byte of the screen address.
; Each tile row occupies 4 character rows (32 pixel rows in MODE 2).
; The screen starts at &3800 and each character row is &140 bytes apart,
; but tiles span multiple rows, so each group of 4 entries covers one
; tile row height. Values run from &38 (top of screen) to &47.

.screen_row_lut
    EQUB &38, &38, &38, &38     ; Tile row 0: screen &3800-&38FF
    EQUB &39, &39, &39, &39     ; Tile row 1: screen &3900-&39FF
    EQUB &3A, &3A, &3A, &3A     ; Tile row 2: screen &3A00-&3AFF
    EQUB &3B, &3B, &3B, &3B     ; Tile row 3: screen &3B00-&3BFF
    EQUB &3C, &3C, &3C, &3C     ; Tile row 4: screen &3C00-&3CFF
    EQUB &3D, &3D, &3D, &3D     ; Tile row 5: screen &3D00-&3DFF
    EQUB &3E, &3E, &3E, &3E     ; Tile row 6: screen &3E00-&3EFF
    EQUB &3F, &3F, &3F, &3F     ; Tile row 7: screen &3F00-&3FFF
    EQUB &40, &40, &40, &40     ; Tile row 8: screen &4000-&40FF
    EQUB &41, &41, &41, &41     ; Tile row 9: screen &4100-&41FF
    EQUB &42, &42, &42, &42     ; Tile row 10: screen &4200-&42FF
    EQUB &43, &43, &43, &43     ; Tile row 11: screen &4300-&43FF
    EQUB &44, &44, &44, &44     ; Tile row 12: screen &4400-&44FF
    EQUB &45, &45, &45, &45     ; Tile row 13: screen &4500-&45FF
    EQUB &46, &46, &46, &46     ; Tile row 14: screen &4600-&46FF
    EQUB &47, &47, &47, &47     ; Tile row 15: screen &4700-&47FF

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
; Physics / Gravity Table (&0800-&087F)
; ============================================================================
; 128-byte lookup table providing a descending curve from 63 (&3F) to 1.
; Used for gravity/falling physics: as a sprite falls, an index into this
; table increases, producing decreasing downward velocity — simulating
; the effect of terminal velocity or bounce deceleration.
;
; Also used by set_volume as a volume envelope table — the same curve
; shape provides a natural-sounding amplitude decay for sound effects.

; P% should be &0800 here (flowing from palette tables)
.physics_table
    EQUB &3F, &3E, &3C, &3A     ; 63, 62, 60, 58 — initial fast descent
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
    EQUB &03, &03, &03, &03     ; 3, 3, 3, 3 — near-terminal velocity
    EQUB &03, &03, &03, &03     ; 3, 3, 3, 3
    EQUB &03, &03, &02, &02     ; 3, 3, 2, 2
    EQUB &02, &02, &02, &02     ; 2, 2, 2, 2
    EQUB &02, &02, &02, &02     ; 2, 2, 2, 2
    EQUB &02, &02, &02, &02     ; 2, 2, 2, 2
    EQUB &01, &01, &01, &01     ; 1, 1, 1, 1 — minimum velocity
    EQUB &01, &01, &01, &01     ; 1, 1, 1, 1

; ============================================================================
; FROGMAN — Lookup Tables
;
; These tables are pre-populated in memory before the game engine runs.
; They provide fast lookups for tile source addressing, colour cycling,
; and sound frequency envelope / descending curve calculations.
; ============================================================================

; ============================================================================
; Tile Source Low-Byte LUT
; ============================================================================
; Maps a tile index (0-63) to the low byte of its graphics source address.
; Tiles are stored in 256-byte banks; each bank holds 4 tiles at offsets
; &00, &40, &80, &C0 (64 bytes per tile). The repeating pattern assigns
; each group of 4 consecutive tiles to the same source bank.

.tile_src_lo
FOR n, 0, 63
        EQUB (n MOD 4) * &40
NEXT

; ============================================================================
; Tile Source High-Byte LUT
; ============================================================================
; Maps a tile index to the high byte of its graphics source address.
; Tile graphics are stored starting at &3800. Each group of 4 tiles
; shares a 256-byte source bank. Values run from &38 to &47.

tile_src_base = &38

.tile_src_hi
FOR n, 0, 63
        EQUB tile_src_base + (n DIV 4)
NEXT

; ============================================================================
; Palette / Frequency Low-Nibble Table
; ============================================================================
; 128 bytes serving two purposes:
;   1. As palette colour indices for the IRQ handler's colour cycling
;   2. As the low nibble of SN76489 frequency latch bytes (used by set_tone)
;
; Each entry is a 4-bit value (0-15). The dual use works because the
; SN76489 frequency latch format is (1 cc 0 dddd) where dddd is ORed
; from this table — the same 4-bit range as logical colour numbers.

.palette_tables
    EQUB &0F, &01, &05, &0A
    EQUB &0F, &05, &0C, &03
    EQUB &0B, &04, &0E, &08
    EQUB &03, &0E, &0A, &07
    EQUB &04, &02, &00, &0E
    EQUB &0E, &0D, &0D, &0E
    EQUB &0F, &00, &02, &05
    EQUB &07, &0A, &0E, &01
    EQUB &05, &0A, &0F, &04
    EQUB &09, &0F, &05, &0B
    EQUB &02, &09, &00, &07
    EQUB &0F, &06, &0E, &07
    EQUB &0F, &08, &01, &0A
    EQUB &03, &0D, &07, &00
    EQUB &0A, &05, &0F, &0A
    EQUB &04, &0F, &0A, &05
    EQUB &01, &0C, &08, &03
    EQUB &0F, &0B, &07, &03
    EQUB &0F, &0C, &08, &05
    EQUB &01, &0E, &0B, &08
    EQUB &05, &02, &0F, &0D
    EQUB &0A, &07, &05, &02
    EQUB &00, &0E, &0C, &09
    EQUB &07, &05, &03, &01
    EQUB &0F, &0E, &0C, &0A
    EQUB &08, &07, &05, &04
    EQUB &02, &01, &0F, &0E
    EQUB &0D, &0B, &0A, &09
    EQUB &08, &07, &06, &04
    EQUB &03, &02, &01, &00
    EQUB &0F, &0F, &0E, &0D
    EQUB &0C, &0B, &0A, &0A

; ============================================================================
; Frequency Divider Table
; ============================================================================
; 128-byte lookup providing the high byte of SN76489 frequency divider
; values. Indexed by the envelope's frequency parameter (0-127).
; Values descend from 63 (&3F) to 1, producing a roughly logarithmic
; pitch curve — higher indices give higher pitches (lower dividers).

.freq_divider_table
    EQUB &3F, &3E, &3C, &3A     ; Lowest pitches (highest dividers)
    EQUB &38, &37, &35, &34     ; 56, 55, 53, 52
    EQUB &32, &31, &2F, &2E     ; 50, 49, 47, 46
    EQUB &2D, &2B, &2A, &29     ; 45, 43, 42, 41
    EQUB &28, &27, &26, &24     ; 40, 39, 38, 36
    EQUB &23, &22, &21, &20     ; 35, 34, 33, 32
    EQUB &1F, &1F, &1E, &1D     ; 31, 31, 30, 29
    EQUB &1C, &1B, &1A, &1A     ; 28, 27, 26, 26
    EQUB &19, &18, &17, &17     ; Mid-range pitches
    EQUB &16, &15, &15, &14     ; 22, 21, 21, 20
    EQUB &14, &13, &13, &12     ; 20, 19, 19, 18
    EQUB &11, &11, &10, &10     ; 17, 17, 16, 16
    EQUB &0F, &0F, &0F, &0E     ; 15, 15, 15, 14
    EQUB &0E, &0D, &0D, &0D     ; 14, 13, 13, 13
    EQUB &0C, &0C, &0B, &0B     ; 12, 12, 11, 11
    EQUB &0B, &0A, &0A, &0A     ; 11, 10, 10, 10
    EQUB &0A, &09, &09, &09     ; Higher pitches (lower dividers)
    EQUB &08, &08, &08, &08     ; 8, 8, 8, 8
    EQUB &07, &07, &07, &07     ; 7, 7, 7, 7
    EQUB &07, &06, &06, &06     ; 7, 6, 6, 6
    EQUB &06, &06, &05, &05     ; 6, 6, 5, 5
    EQUB &05, &05, &05, &05     ; 5, 5, 5, 5
    EQUB &05, &04, &04, &04     ; 5, 4, 4, 4
    EQUB &04, &04, &04, &04     ; 4, 4, 4, 4
    EQUB &03, &03, &03, &03     ; Near-maximum pitches
    EQUB &03, &03, &03, &03     ; 3, 3, 3, 3
    EQUB &03, &03, &02, &02     ; 3, 3, 2, 2
    EQUB &02, &02, &02, &02     ; 2, 2, 2, 2
    EQUB &02, &02, &02, &02     ; 2, 2, 2, 2
    EQUB &02, &02, &02, &02     ; 2, 2, 2, 2
    EQUB &01, &01, &01, &01     ; Maximum pitch (divider = 1)
    EQUB &01, &01, &01, &01

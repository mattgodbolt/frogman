; ============================================================================
; FROGMAN — Music and Sound Data
; ============================================================================
; Default music data for channels 1-3. This entire region is OVERWRITTEN
; when a level loads — Level?T (640 bytes) replaces all three channels.
; The data below is the Level 1 initial state, but since the game always
; loads Level?T before playing, it only matters for byte-exact matching.
;
; Music format: interleaved note/duration pairs where:
;   - Even bytes: frequency index (maps to SN76489 via freq_divider_table)
;   - Odd bytes: duration in 50Hz interrupt ticks
;   - &FE, &FF marks end of channel data (wraps to start)
;   - Bytes with bit 0 set encode frequency/volume parameter changes
;   - Bytes >= &80 with bit 0 clear are control tokens (&FC/&FA/&FE)
;
; Sound channel data pages (set by channel_data_hi in engine.asm):
;   Channel 1 → page &0C (this file starts at &0C80 after engine copy)
;   Channel 2 → page &0D
;   Channel 3 → page &0E
; ============================================================================

; Music data begins immediately after the tile renderer's RTS.
; No ORG needed — this continues from wherever engine.asm left off.

; --- Channel 1 data (overwritten by Level?T on load) ---
.music_data
    EQUB &4F, &56, &20, &52
    EQUB &30, &2C, &07, &F1

    ; Note/duration pairs for channel 1 melody
    EQUB &2E, &1E, &2E, &1E
    EQUB &34, &1E, &34, &1E
    EQUB &3E, &1E, &BE, &B8
    EQUB &3E, &1E, &3C, &1E
    EQUB &38, &1E, &30, &1E
    EQUB &2E, &1E, &26, &1E
    EQUB &2E, &1E, &2A, &1E
    EQUB &2A, &3C, &34, &1E
    EQUB &34, &1E, &3E, &1E
    EQUB &3E, &1E, &48, &1E
    EQUB &C6, &C2, &46, &1E
    EQUB &3E, &1E, &42, &1E
    EQUB &3C, &1E, &3E, &1E
    EQUB &C2, &BE, &3C, &3C
    EQUB &46, &3C, &3E, &1E
    EQUB &3E, &1E, &40, &1E
    EQUB &40, &1E, &42, &1E
    EQUB &42, &1E, &44, &1E
    EQUB &44, &1E, &46, &1E
    EQUB &BE, &B8, &46, &1E
    EQUB &46, &1E, &46, &3C
    EQUB &00, &1E, &46, &1E
    EQUB &48, &1E, &42, &1E
    EQUB &BE, &BC, &B8, &B4
    EQUB &46, &1E, &3E, &1E
    EQUB &B8, &B4, &B0, &B8
    EQUB &42, &1E, &38, &1E
    EQUB &BE, &BC, &B8, &B6
    EQUB &38, &3C, &38, &1E
    EQUB &34, &1E
    EQUB &FE, &FF              ; End of channel 1

    ; Residual data — overwritten by Level?T on load.
    EQUB &DD, &07, &4F, &47
    EQUB &B2, &DA
    EQUB &35, &D7, &2D, &49, &04, &BC, &E5, &79
    EQUB &71, &90, &32, &E7, &91, &5D, &9E, &5A
    EQUB &41, &3A, &96, &48, &5E, &01, &EF, &C7
    EQUB &91, &61, &E2, &13, &36, &22, &E8, &2F
    EQUB &46, &70, &D7, &15, &FD, &DF, &EF, &7D
    EQUB &CE, &33, &08, &C3, &CC, &FF, &B8, &62
    EQUB &0C, &B4, &A0, &BE, &47, &9F, &10, &54
    EQUB &9C, &3D, &FC, &23, &EC, &DB, &27, &52
    EQUB &BC, &28, &AD, &54, &D3, &5B, &DD, &F8
    EQUB &74, &97, &D3, &A9, &63, &85, &9E, &ED
    EQUB &58, &7B, &99, &9E, &23, &38, &F9, &58
    EQUB &EE, &A7, &FE, &BF, &AF, &B0, &81, &35
    EQUB &4B, &28, &CA, &01, &03, &A6, &61, &22
    EQUB &B4, &EB, &50, &8B, &6B, &39, &13, &CB
    EQUB &D4, &29, &1F, &56, &73, &D1, &92, &59
    EQUB &A4, &58, &DE, &01, &04, &6A, &65, &65

; --- Channel 2 data (overwritten by Level?T on load) ---
.music_data_2
    EQUB &07, &E1
    ; Note/duration pairs for channel 2
    EQUB &A6, &9C, &A6, &9C
    EQUB &AA, &9C, &AA, &9C
    EQUB &B8, &AE, &B8, &AE
    EQUB &B8, &AE, &B4, &AE
    EQUB &B0, &A6, &A6, &A0
    EQUB &A6, &9C, &A6, &9C
    EQUB &A0, &92, &A6, &A0
    EQUB &A6, &9C, &A4, &9C
    EQUB &AE, &A4, &AE, &A4
    EQUB &B4, &AE, &B4, &AE
    EQUB &BE, &B8, &3C, &1E
    EQUB &BC, &B4, &B8, &AE
    EQUB &B0, &B8, &B6, &AA
    EQUB &B8, &B0, &B0, &B8
    EQUB &36, &3C, &36, &3C
    EQUB &B8, &AE, &B8, &AE
    EQUB &B8, &AE, &B8, &AE
    EQUB &B8, &B0, &B8, &B0
    EQUB &B8, &B0, &B8, &B0
    EQUB &BE, &AE, &B8, &AE
    EQUB &B8, &B6, &B2, &B6
    EQUB &B8, &B4, &B8, &BA
    EQUB &B8, &B4, &B0, &AE
    EQUB &C2, &B8, &B0, &B8
    EQUB &2A, &1E, &2A, &1E
    EQUB &BE, &B4, &AE, &B4
    EQUB &26, &1E, &26, &1E
    EQUB &B0, &B8, &B0, &AA
    EQUB &2A, &1E, &2A, &1E
    EQUB &A6, &AE, &B8, &BE
    EQUB &BC, &B8, &B4, &B0
    EQUB &FE, &FF              ; End of channel 2

    ; Residual data — overwritten by Level?T on load
    EQUB &83, &BD, &17, &06, &4C, &E1, &D3, &F8
    EQUB &81, &3C, &7D, &C2, &6F, &85, &F6, &B2
    EQUB &A5, &B9, &2D, &B1, &E2, &8C, &0C, &03
    EQUB &E5, &62, &48, &49, &5A, &6B, &8A, &A2
    EQUB &D2, &92, &F0, &77, &44, &6A, &D5, &32
    EQUB &DE, &F1, &CE, &4F, &60, &94, &FA, &C8
    EQUB &E3, &46, &3B, &CD, &5E, &9E, &F3, &D2
    EQUB &26, &22, &9C, &D0, &B5, &7B, &6C, &AA
    EQUB &F2, &64, &8D, &92, &89, &93, &09, &1F
    EQUB &AF, &50, &BC, &96, &B2, &D8, &54, &0E
    EQUB &F3, &40, &A1, &CA, &6C, &97, &5F, &71
    EQUB &AB, &0F, &D9, &41, &D4, &3C, &16, &B0
    EQUB &D6, &55, &C6, &BB, &60, &49, &BE, &38
    EQUB &3C, &2B, &C9, &F8, &73, &5B, &D7, &EE
    EQUB &94, &9D, &DC, &02, &41, &0A, &B7, &48
    EQUB &6F, &90, &FF, &54, &00, &3D, &79, &53

; --- Channel 3 data (overwritten by Level?T on load) ---
.music_data_3
    EQUB &07, &D1
    ; Note/duration pairs for channel 3
    EQUB &0E, &3C, &0C, &3C
    EQUB &08, &3C, &16, &3C
    EQUB &18, &3C, &1C, &3C
    EQUB &1A, &3C, &1C, &3C
    EQUB &16, &3C, &20, &3C
    EQUB &12, &1E, &1C, &1E
    EQUB &16, &1E, &20, &1E
    EQUB &12, &1E, &16, &1E
    EQUB &18, &1E, &12, &1E
    EQUB &96, &92, &96, &98
    EQUB &96, &92, &8E, &8C
    EQUB &20, &3C, &1C, &3C
    EQUB &18, &3C, &18, &1E
    EQUB &B0, &98, &16, &3C
    EQUB &12, &1E, &12, &1E
    EQUB &10, &3C, &10, &3C
    EQUB &12, &3C, &1C, &3C
    EQUB &26, &3C, &18, &3C
    EQUB &12, &3C, &16, &3C
    EQUB &20, &3C, &24, &3C
    EQUB &FE, &FF              ; End of channel 3

    ; Residual data — overwritten by Level?T on load
    EQUB &2E, &63, &45, &1E
    EQUB &06, &54, &10, &59
    EQUB &9F, &48, &C8, &29
    EQUB &49, &DD, &6D, &90
    EQUB &FA, &7F, &E2, &15
    EQUB &2D, &95, &0E, &AD
    EQUB &6B, &91, &D5, &BF
    EQUB &DA, &70, &FC, &86
    EQUB &2A, &98, &73
.anim_timing_const                      ; Note duration base — level-specific (overwritten by Level?T)
    EQUB &0F, &36, &34, &30, &38
    EQUB &38, &29, &34, &65

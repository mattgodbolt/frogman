; ============================================================================
; FROGMAN — Music and Sound Data
; ============================================================================
; Contains music note/duration pairs and an encrypted data block.
;
; Music format: pairs of bytes (note, duration) where:
;   - Note values map to SN76489 frequency registers
;   - Duration is a countdown in interrupt ticks
;   - &FE &FF marks end of tune (loops or stops)
;   - Values in the &80-&BE range encode note pairs with timing
;
; The music data is referenced by the IRQ handler via self-modifying
; pointers at &0D3D/&0D3E.
;
; There are three tunes interleaved with encrypted blocks:
;   Tune 1 (followed by padding)
;   Tune 2 (encrypted block precedes)
;   Tune 3 (encrypted block precedes)
; ============================================================================

; Music data begins immediately after the tile renderer's RTS.
; No ORG needed — this continues from wherever engine.asm left off.

; --- Tune 1: Tune 1 (purpose unconfirmed) ---
.music_data
    EQUB &4F, &56, &20, &52     ; "OV R" — ASCII remnant or data header
    EQUB &30, &2C, &07, &F1     ; Tune header / initial note data

    ; Note/duration pairs — melody line
    EQUB &2E, &1E, &2E, &1E     ; Note pairs (pitch, duration)
    EQUB &34, &1E, &34, &1E
    EQUB &3E, &1E, &BE, &B8     ; &BE/&B8 = long notes or rest
    EQUB &3E, &1E, &3C, &1E
    EQUB &38, &1E, &30, &1E
    EQUB &2E, &1E, &26, &1E
    EQUB &2E, &1E, &2A, &1E
    EQUB &2A, &3C, &34, &1E     ; &3C = longer duration
    EQUB &34, &1E, &3E, &1E
    EQUB &3E, &1E, &48, &1E
    EQUB &C6, &C2, &46, &1E     ; &C6/&C2 = bass notes
    EQUB &3E, &1E, &42, &1E
    EQUB &3C, &1E, &3E, &1E
    EQUB &C2, &BE, &3C, &3C     ; Chord progression
    EQUB &46, &3C, &3E, &1E
    EQUB &3E, &1E, &40, &1E
    EQUB &40, &1E, &42, &1E
    EQUB &42, &1E, &44, &1E
    EQUB &44, &1E, &46, &1E
    EQUB &BE, &B8, &46, &1E     ; Descending phrase
    EQUB &46, &1E, &46, &3C
    EQUB &00, &1E, &46, &1E     ; &00 = rest/silence
    EQUB &48, &1E, &42, &1E
    EQUB &BE, &BC, &B8, &B4     ; Long bass sequence
    EQUB &46, &1E, &3E, &1E
    EQUB &B8, &B4, &B0, &B8
    EQUB &42, &1E, &38, &1E
    EQUB &BE, &BC, &B8, &B6
    EQUB &38, &3C, &38, &1E
    EQUB &34, &1E
    EQUB &FE, &FF              ; End of tune 1

    ; Unused padding to page boundary before sound_state_block
    EQUB &DD, &07, &4F, &47
    EQUB &B2, &DA

; --- Sound state block ---
; This 128-byte block is encrypted on disc but decrypted at runtime
; by the loader. Four locations within it are used as live mutable
; state by the IRQ handler:
;   music_note_reset  — patched with &2F silence token on note end
;   music_ptr_lo      — low byte of music playback pointer (INC'd)
;   music_ptr_hi      — high byte of music playback pointer (INC'd)
;   music_env_patch   — patched with &48 on final envelope tick
.sound_state_block
    EQUB &35, &D7, &2D, &49, &04, &BC, &E5, &79
    EQUB &71
.music_note_reset                                  ; patched with &2F on note end
    EQUB &90, &32, &E7, &91, &5D, &9E, &5A
    EQUB &41, &3A, &96, &48, &5E, &01, &EF, &C7
    EQUB &91, &61, &E2, &13, &36, &22, &E8, &2F
    EQUB &46, &70, &D7, &15, &FD, &DF, &EF, &7D
    EQUB &CE, &33, &08, &C3, &CC, &FF, &B8, &62
    EQUB &0C, &B4, &A0, &BE, &47, &9F, &10, &54
    EQUB &9C, &3D, &FC, &23, &EC
.music_ptr_lo                                      ; music playback pointer low
    EQUB &DB
.music_ptr_hi                                      ; music playback pointer high
    EQUB &27, &52
    EQUB &BC, &28, &AD, &54, &D3, &5B, &DD, &F8
    EQUB &74, &97, &D3, &A9
.music_env_patch                                   ; patched with &48 on envelope tick
    EQUB &63, &85, &9E, &ED
    EQUB &58, &7B, &99, &9E, &23, &38, &F9, &58
    EQUB &EE, &A7, &FE, &BF, &AF, &B0, &81, &35
    EQUB &4B, &28, &CA, &01, &03, &A6, &61, &22
    EQUB &B4, &EB, &50, &8B, &6B, &39, &13, &CB
    EQUB &D4, &29, &1F, &56, &73, &D1, &92, &59
    EQUB &A4, &58, &DE, &01, &04, &6A, &65, &65

; --- Tune 2: Tune 2 (purpose unconfirmed) ---
.music_data_2
    EQUB &07, &E1
    ; Bass line melody
    EQUB &A6, &9C, &A6, &9C     ; Deep bass notes
    EQUB &AA, &9C, &AA, &9C
    EQUB &B8, &AE, &B8, &AE
    EQUB &B8, &AE, &B4, &AE
    EQUB &B0, &A6, &A6, &A0
    EQUB &A6, &9C, &A6, &9C
    EQUB &A0, &92, &A6, &A0
    EQUB &A6, &9C, &A4, &9C
    EQUB &AE, &A4, &AE, &A4     ; Rising phrase
    EQUB &B4, &AE, &B4, &AE
    EQUB &BE, &B8, &3C, &1E
    EQUB &BC, &B4, &B8, &AE
    EQUB &B0, &B8, &B6, &AA
    EQUB &B8, &B0, &B0, &B8
    EQUB &36, &3C, &36, &3C     ; Alternating pattern
    EQUB &B8, &AE, &B8, &AE
    EQUB &B8, &AE, &B8, &AE
    EQUB &B8, &B0, &B8, &B0
    EQUB &B8, &B0, &B8, &B0
    EQUB &BE, &AE, &B8, &AE     ; Closing phrase
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
    EQUB &FE, &FF              ; End of tune 2

; --- Encrypted/compressed data block ---
.sound_data_block_2  ; Encrypted on disc, decrypted at runtime; no code references into it have been identified
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

; --- Tune 3: Tune 3 (purpose unconfirmed) ---
.music_data_3
    EQUB &07, &D1
    ; Short melodic sequence
    EQUB &0E, &3C, &0C, &3C
    EQUB &08, &3C, &16, &3C
    EQUB &18, &3C, &1C, &3C
    EQUB &1A, &3C, &1C, &3C
    EQUB &16, &3C, &20, &3C
    EQUB &12, &1E, &1C, &1E
    EQUB &16, &1E, &20, &1E
    EQUB &12, &1E, &16, &1E
    EQUB &18, &1E, &12, &1E
    ; Rhythmic section
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
    EQUB &FE, &FF              ; End of tune 3

    ; Trailing encrypted/data bytes
    EQUB &2E, &63, &45, &1E
    EQUB &06, &54, &10, &59
    EQUB &9F, &48, &C8, &29
    EQUB &49, &DD, &6D, &90
    EQUB &FA, &7F, &E2, &15
    EQUB &2D, &95, &0E, &AD
    EQUB &6B, &91, &D5, &BF
    EQUB &DA, &70, &FC, &86
    EQUB &2A, &98, &73
.anim_timing_const
    EQUB &0F, &36, &34, &30, &38
    EQUB &38, &29, &34, &65

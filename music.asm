; ============================================================================
; FROGMAN — Music data layout
; ============================================================================
; The IRQ reads each music channel from a fixed page-aligned address, with
; the page byte coming from channel_data_hi[X] (in engine.asm) and the offset
; from LO(music_ch1). Per-level note timing is read from anim_timing_const.
;
; Music format: interleaved note/duration pairs where:
;   - Even bytes: frequency index (maps to SN76489 via freq_divider_table)
;   - Odd bytes: duration in 50Hz interrupt ticks
;   - &FE, &FF marks end of channel data (wraps to start)
;   - Bytes with bit 0 set encode frequency/volume parameter changes
;   - Bytes >= &80 with bit 0 clear are control tokens (&FC/&FA/&FE)
;
; The labels here are anchors — the actual bytes get overwritten at level
; load. Sequence: level_loader runs *Load Level?T 5D80, game_init copies
; &5800-&5FFF to &0700-&0EFF (so &5D80 → &0C80), and the freshly-loaded
; Level?T data is what the IRQ actually reads. Anchoring with ORG lets
; engine code grow freely up to &0C80 without sliding the channels.
; ============================================================================

ORG &0C80
.music_ch1                      ; Channel 1 base — 256 bytes from Level?T file

ORG &0D80
.music_ch2                      ; Channel 2 base — 256 bytes from Level?T file

ORG &0E80
.music_ch3                      ; Channel 3 base — first 119 bytes are channel
                                ; data (FE/FF terminator + residual); byte 119
                                ; (= file offset 631) is the timing constant.

ORG &0EF7
.anim_timing_const              ; Per-level note duration (Level?T file offset 631)

; ============================================================================
; FROGMAN — Game Engine (Annotated Disassembly)
; Written by Matthew Godbolt & Richard Talbot-Watkins, February 1993
;
; Engine subroutines at &0700-&0C79, loaded as "FastI/O" to &5800
; then copied to &0700 during game init. Called by the game code
; (Gcode at &4800-&57FF) via the jump table at &0880.
;
; Every instruction is byte-accurate against the runtime memory dump.
; ============================================================================

; --- Lookup tables at &0700-&087F ---
ORG &0700
INCLUDE "tables.asm"

; ############################################################################
; GAME ENGINE
; ############################################################################
; Subroutines called by the game code (Gcode) via the jump table below:
;   - Tile rendering (block_copy, calc_screen_addr, render_map)
;   - Frog overlay renderer (tile_addr_setup, tile_render)
;   - 4-channel SN76489 sound sequencer (update_sound, init_channel)
;   - VIA port configuration for sound chip access
;
; Sound state uses X-indexed zero page arrays for 4 channels.
; ############################################################################

; === Jump Table ===
; External entry points — callers use these JMPs for indirection.

.jmp_block_copy     : JMP block_copy
.jmp_calc_scrn_addr : JMP calc_screen_addr
.jmp_setup_map      : JMP setup_map_render
.jmp_render_map     : JMP render_map
.jmp_init_channel   : JMP init_channel     ; Not called via table; init_channel called directly
.jmp_update_sound : JMP update_sound
.jmp_init_game      : JMP init_game

; === Block Copy ===
; Copies a tile from source to screen memory. 32-byte unrolled inner loop
; copies one row of tile data; loops for 2 rows per tile.
; Self-modifies to save/restore Y and X at bc_restore_y + 1 / bc_restore_x + 1.

.block_copy
    STY bc_restore_y + 1        ; Save Y into self-mod operand
    STX bc_restore_x + 1        ; Save X into self-mod operand
    TAY                         ; Tile index -> Y for LUT lookup
    LDA tile_src_lo,Y                 ; Tile graphics source low byte
    STA zp_src_lo                     ; Tile source pointer low
    LDA tile_src_hi,Y                 ; Tile graphics source high byte
    STA zp_src_hi                     ; Tile source pointer high
    JSR calc_screen_addr        ; Calculate screen dest address
    LDX #&01                    ; Copy 2 rows (counter: 1, 0)

; Fully unrolled 32-byte copy — speed-critical inner loop.
; The JMP at bc_done re-enters here, resetting Y each iteration.
.bc_copy_loop
    LDY #&00                    ; Reset byte offset for each row
    FOR n, 1, 32
        LDA (zp_src_lo),Y : STA (zp_dst_lo),Y : INY
    NEXT

    ; Advance source by 32 bytes
    CLC
    LDA zp_src_lo
    ADC #&20
    STA zp_src_lo
    BCC bc_no_carry
    INC zp_src_hi
.bc_no_carry
    INC zp_dst_hi                     ; Dest high += 2 (next character row)
    INC zp_dst_hi

    DEX
    BMI bc_done                 ; Both rows done
    JMP bc_copy_loop            ; Second row

.bc_done
.bc_restore_y
    LDY #&05                   ; Restore Y (self-modified)
.bc_restore_x
    LDX #&08                   ; Restore X (self-modified)
    RTS

; === Calculate Screen Address ===
; Input: zp_tile_x, zp_tile_y
; Output: zp_dst_lo/zp_dst_hi = screen memory address
; Screen display base is &5800 (custom CRTC configuration).
; Calculates: addr_hi = (tile_Y * 2) + &58 + hi(tile_X * 8), addr_lo = lo(tile_X * 8)

.calc_screen_addr
    LDA zp_tile_x                     ; Tile X
    STA zp_dst_lo
    LDA #&00
    ASL zp_dst_lo : ROL A             ; x2
    ASL zp_dst_lo : ROL A             ; x4
    ASL zp_dst_lo : ROL A             ; x8
    STA zp_dst_hi
    LDA zp_tile_y                     ; Tile Y
    ASL A                       ; x2
    ADC zp_dst_hi
    ADC #&58                    ; Screen display base &5800
    STA zp_dst_hi
    RTS

; === Setup Map Rendering ===
; Converts scroll position to map data pointer.
; Map data is based at &0F00.

.setup_map_render
    LDA zp_map_scroll_x                     ; Will become high byte bits after /2
    STA zp_map_src_hi
    LDA #&00
    LSR zp_map_src_hi                     ; Divide by 2
    ROR A                       ; Remainder -> A
    STA zp_map_src_lo                     ; Map pointer low
    LDA zp_map_scroll_y                     ; Scroll position high
    ASL A : ASL A               ; x4
    ADC zp_map_src_hi
    ADC #&0F                    ; Map base = &0F00
    STA zp_map_src_hi                     ; Map pointer high
    ; Falls through to render_map

; === Render Map ===
; Renders 16x8 visible tile grid to screen.

.render_map
    LDA #&00
    STA zp_tile_x                     ; Column = 0
    STA zp_tile_y                     ; Row = 0
    LDY #&00                    ; Map offset

.render_loop
    LDA (zp_map_src_lo),Y                 ; Read tile index
    JSR block_copy              ; Draw tile
    INY
    CLC
    LDA zp_tile_x
    ADC #&04                    ; Next column (+4 per tile)
    STA zp_tile_x
    CMP #&40                    ; End of row?
    BNE render_loop

    LDA #&00
    STA zp_tile_x                     ; Reset column
    INC zp_tile_y : INC zp_tile_y           ; Next row (+2)
    LDA zp_tile_y
    CMP #&10                    ; All rows done?
    BNE render_loop
    RTS

; === Game Initialization ===

.init_game
    JSR via_config_a           ; Configure System VIA ports
    LDX #&03
.init_silence
    LDA #&00                    ; Silence value
    JSR set_volume         ; Silence each channel
    DEX
    BPL init_silence
    JSR via_config_b           ; Configure System VIA ports
    RTS

; === Music Token Parser ===
; Parses music stream tokens for the 4-channel sound sequencer.
; Tokens: &FC=set loop, &FA=loop back, &FE=end, other=note data.

.parse_anim_token
    CMP #&FC                    ; Set loop point?
    BEQ anim_set_loop
    CMP #&FA                    ; Jump to loop?
    BEQ anim_loop_back
    CMP #&FE                    ; End of sequence?
    BNE anim_frame_data
    LDY #&00                    ; Reset stream index
    JMP read_music_token

.anim_frame_data
    AND #&7F                    ; Strip high bit
    STA zp_snd_tmp_frame                     ; Store frame byte
    INY
    LDA anim_timing_const                   ; Global note timing constant
    STA zp_snd_tmp_timer                     ; Note duration
    JMP anim_apply

.anim_set_loop
    TYA                         ; Save stream position
    STA channel_loop_y,X                 ; as loop-back point
    INY
    LDA (zp_snd_data_lo),Y                 ; Read repeat count
    STA channel_loop_ctr,X
    INY
    JMP read_music_token

.anim_loop_back
    STY anim_saved_y + 1        ; Save current Y (self-modifying immediate)
    LDY channel_loop_y,X    ; Restore loop-back position
    INY : INY                   ; Skip past &FC marker and count byte
    DEC channel_loop_ctr,X       ; Decrement repeat counter
    BNE read_music_token      ; Loop again if count > 0
.anim_saved_y
    LDY #&00                    ; Count exhausted — restore Y to &FA token position (patched)
    INY                         ; Advance past &FA token
    JMP read_music_token

; --- Frequency/volume decoding ---
; Bit 1 selects parameter: 0=frequency, 1=volume.
; Frequency: upper nibble >> 4. Volume: bits 3:2 >> 2.

.anim_apply_data
    LDA zp_snd_tmp_frame
    AND #&02                    ; Test bit 1
    BNE anim_set_horiz

    LDA zp_snd_tmp_frame
    LSR A : LSR A : LSR A : LSR A
    STA channel_freq_param,X                 ; Frequency parameter
    INY
    JMP read_music_token

.anim_set_horiz
    LDA zp_snd_tmp_frame
    LSR A : LSR A
    STA channel_vol_param,X                 ; Volume parameter
    INY
    JMP read_music_token

; === Update Sound ===
; Main per-frame sound update.
; Channels 1-3: music sequencer (data-driven note/envelope sequences)
; Channel 0: sound effects (envelope-driven)

.update_sound
    JSR via_config_a           ; Configure VIA for sound output

    LDX #&01                    ; Start with music channels (1-3)

.update_channel_loop
    LDA zp_snd_timer,X                   ; Note duration timer
    BNE next_channel             ; Still playing — skip

    ; Timer expired — read next token from music stream
    LDA #&80
    STA zp_snd_data_lo                     ; Music data ptr low = &80
    LDA channel_data_hi,X                 ; Music data page for channel X
    STA zp_snd_data_hi
    LDY zp_snd_anim_idx,X                   ; Music stream index

; --- Central music dispatch ---
; All token parser branches return here to read the next token.

.read_music_token
    LDA (zp_snd_data_lo),Y                 ; Read token from music stream
    STA zp_snd_tmp_frame
    AND #&01                    ; Test bit 0
    BNE anim_apply_data         ; Direction/speed change

    LDA zp_snd_tmp_frame
    BMI parse_anim_token        ; Special token (&FC/&FA/&FE)

    ; Normal frame: read duration
    INY
    LDA (zp_snd_data_lo),Y                 ; Read duration
    STA zp_snd_tmp_timer
    INY

.anim_apply
    STY zp_snd_anim_idx,X                   ; Update stream index
    LDA channel_freq_param,X                 ; Frequency parameter
    STA zp_snd_tmp_speed
    LDY channel_vol_param,X                 ; Volume parameter
    JSR init_channel            ; Set up channel envelope

.next_channel
    INX
    CPX #&04                    ; All channels done?
    BNE update_channel_loop

    ; --- Envelope processing loop (channels 0-3) ---
    LDX #&00

.process_envelope
    LDA zp_snd_freq,X                   ; Channel frequency
    BEQ channel_idle             ; Silent — skip

    LSR A                       ; Strip direction bit
    JSR set_tone                ; Set frequency from channel data

    LDA zp_snd_timer,X                   ; Note duration timer
    BEQ envelope_next            ; Timer expired

    ; Set volume from envelope position
    LDA zp_snd_vol,X                   ; Volume envelope
    LSR A : LSR A : LSR A : LSR A  ; -> table index
    JSR set_volume         ; Volume from position

    ; Load sequence data pointers
    LDY zp_snd_seq_idx,X
    LDA zp_snd_seq_lo,X : STA zp_move_ptr_lo         ; Sequence ptr low
    LDA zp_snd_seq_hi,X : STA zp_move_ptr_hi         ; Sequence ptr high

    ; Apply envelope deltas
    LDA (zp_move_ptr_lo),Y : CLC : ADC zp_snd_vol,X : STA zp_snd_vol,X : INY   ; Volume delta
    LDA (zp_move_ptr_lo),Y : CLC : ADC zp_snd_freq,X : STA zp_snd_freq,X         ; Frequency delta

    ; Envelope sub-counter
    DEC zp_snd_subctr,X
    BPL movement_timer

    ; Sub-counter expired — advance to next envelope step
    INY : INY
    LDA (zp_move_ptr_lo),Y : CLC : ADC zp_snd_seq_idx,X : STA zp_snd_seq_idx,X
    TAY
    INY : INY
    LDA (zp_move_ptr_lo),Y : STA zp_snd_subctr,X    ; New sub-counter

.movement_timer
    LDA zp_snd_timer,X                   ; Check note timer
    BEQ envelope_next
    DEC zp_snd_timer,X                   ; Decrement
    BNE envelope_next            ; Still running

    ; Note ended — chain to next envelope sequence
    LDY #&00
    LDA (zp_move_ptr_lo),Y                 ; Chain flag
    BMI channel_off             ; Bit 7 set = end of chain

    PHA                         ; Save chain index
    INY
    LDA (zp_move_ptr_lo),Y                 ; New timer value
    STA zp_snd_timer,X
    PLA
    ASL A                       ; x2 for word table
    TAY
    LDA move_ptr_table,Y : STA zp_snd_seq_lo,X : STA zp_move_ptr_lo   ; New movement ptr low
    LDA move_ptr_table + 1,Y : STA zp_snd_seq_hi,X : STA zp_move_ptr_hi   ; New movement ptr high
    LDA #&02 : STA zp_snd_seq_idx,X       ; Reset index (skip past 2-byte chain terminator)
    JMP envelope_next

.channel_off
    LDA #&00
    JSR set_volume         ; Silence channel

.envelope_next
    INX
    CPX #&04                    ; All channels done?
    BNE process_envelope

    JSR via_config_b           ; Restore VIA to normal configuration
    RTS

.channel_idle
    DEC zp_snd_timer,X                   ; Decrement rest timer
    JMP envelope_next

; === SN76489 Sound Chip Write ===
; Writes a byte to the SN76489 via System VIA.
; VIA_ORA = data bus to sound chip.
; VIA_ORB bit 3 = sound chip /WE (active low).
; Writing &00 asserts WE, &08 deasserts it.

.sn76489_write
    STA VIA_ORA                   ; Data byte -> System VIA port A (sound chip bus)
    LDA #&00
    STA VIA_ORB                   ; System VIA ORB: bit 3 low = assert /WE
    NOP : NOP : NOP : NOP       ; Wait for SN76489 timing (~4us)
    LDA #&08
    STA VIA_ORB                   ; System VIA ORB: bit 3 high = deassert /WE
    RTS

; === Set Tone ===
; Sends SN76489 frequency latch byte (1 cc 0 dddd), then a second
; frequency data byte. Both tables in tables.asm are indexed by Y
; (the frequency value from the envelope).
; palette_tables provides the low nibble of the latch byte.
; freq_divider_table provides the upper frequency data byte.

.set_tone
    TAY
    LDA channel_freq_regs,X     ; Frequency register byte (&E0/&C0/&A0/&80)
    ORA palette_tables,Y        ; OR in low nibble (dual-use: palette + freq data)
    JSR sn76489_write            ; Send frequency latch
    LDA freq_divider_table,Y    ; Frequency divider high byte
    JMP sn76489_write            ; Send frequency data

; === Set Volume ===
; Sends SN76489 volume/attenuation byte (1 cc 1 dddd).
; Caller convention: 0=silent, &0F=loud. EOR inverts to chip
; convention where 0=loud, &0F=silent.

.set_volume
    EOR #&0F                    ; Invert: caller 0=silent -> chip &0F=silent
    AND #&0F                    ; Mask to 4-bit attenuation
    ORA channel_vol_regs,X      ; Volume register byte (&F0/&D0/&B0/&90)
    JMP sn76489_write

; === Channel Register Tables ===

.channel_freq_regs
    EQUB &E0, &C0, &A0, &80    ; Ch 3,2,1,0 frequency latch (1 cc 0 0000)
.channel_vol_regs
    EQUB &F0, &D0, &B0, &90    ; Ch 3,2,1,0 volume/atten (1 cc 1 0000)

; Runtime sound channel state (X-indexed, modified during playback)
.channel_freq_param
    EQUB &00, &0F, &0E, &0D
.channel_vol_param
    EQUB &00, &01, &01, &01
.channel_loop_y
    EQUB &00, &00, &00, &00
.channel_loop_ctr
    EQUB &00, &00, &00, &00
.channel_data_hi
    EQUB &00, &0C, &0D, &0E

; === Init Sound Channel ===
; Initializes a sound channel with frequency, volume, and envelope data.
; Entry: zp_snd_tmp_timer, zp_snd_tmp_frame, zp_snd_tmp_speed, Y=sequence index, X=channel

.init_channel
    LDA zp_snd_tmp_timer : STA zp_snd_timer,X         ; Set note duration
    LDA zp_snd_tmp_frame : ASL A : STA zp_snd_freq,X ; Frequency value × 2
    LDA zp_snd_tmp_speed                     ; Volume level
    ASL A : ASL A : ASL A : ASL A  ; × 16 for envelope resolution
    STA zp_snd_vol,X                   ; Volume envelope position
    TYA : ASL A : TAY           ; Sequence index × 2 for word table
    LDA move_ptr_table,Y : STA zp_snd_seq_lo,X : STA zp_move_ptr_lo  ; Sequence ptr low
    LDA move_ptr_table + 1,Y : STA zp_snd_seq_hi,X : STA zp_move_ptr_hi  ; Sequence ptr high
    LDA #&02 : STA zp_snd_seq_idx,X        ; Sequence index (skip past 2-byte chain terminator)
    LDY #&04                    ; Offset 4 = sub-counter in envelope sequence
    LDA (zp_move_ptr_lo),Y : STA zp_snd_subctr,X     ; Initial sub-counter
    RTS

; === System VIA Port Config A ===
; Configures System VIA ports for sound output.
; VIA_ORB, VIA_DDRB, VIA_DDRA.

.via_config_a
    LDA #&0B : STA VIA_ORB        ; ORB = &0B: bit 3 high = sound /WE deasserted
    LDA #&FF : STA VIA_DDRA        ; DDRA = &FF: all port A bits output
    LDA #&FF : STA VIA_DDRB        ; DDRB = &FF: all port B bits output
    RTS

; === System VIA Port Config B ===
; Restores System VIA to normal BBC Micro configuration after sound output.
; DDRA bit 7 input enables keyboard scanning.

.via_config_b
    LDA #&03 : STA VIA_ORB        ; ORB = &03: restore normal port B state
    LDA #&7F : STA VIA_DDRA        ; DDRA = &7F: bit 7 input (keyboard), rest output
    LDA #&FF : STA VIA_DDRB        ; DDRB = &FF: all port B bits output
    RTS

; === Envelope Sequence Pointer Table ===
; 7 word entries pointing to envelope sequences.

.move_ptr_table
    EQUW move_seq_0             ; Seq 0
    EQUW move_seq_1             ; Seq 1
    EQUW move_seq_2             ; Seq 2
    EQUW move_seq_3             ; Seq 3
    EQUW move_seq_4             ; Seq 4
    EQUW move_seq_5             ; Seq 5
    EQUW move_seq_6             ; Seq 6

; === Envelope Sequences ===
; Per-frame delta patterns applied to sound channel frequency and volume.
; Format: vol_delta, freq_delta, index_step, sub_count
; (values like &FD/-3 and &FE/-2 are signed 8-bit deltas).
; &FF,&FF at the start of each sequence is the chain terminator —
; init_channel sets seq_idx=2 to skip past it. When a note ends,
; the engine reads byte 0; BMI (&FF) means end-of-chain → silence.

.move_seq_0
    EQUB &FF, &FF               ; Chain terminator (byte 0 has bit 7 set → end)
    EQUB &28, &00, &04, &04     ; vol +&28, freq +0, step 4, for 4 frames
    EQUB &00, &00, &20, &04     ; Hold (no change), step &20, for 4 frames
    EQUB &F6, &00, &10, &04     ; vol -10, freq +0, step &10, for 4 frames
    EQUB &00, &00, &00, &00     ; End (zero sub-count = stop)

.move_seq_1
    EQUB &FF, &FF               ; Chain terminator
    EQUB &FE, &00, &20, &00     ; vol -2, freq +0, step &20, immediate

.move_seq_3
    EQUB &FF, &FF               ; Chain terminator
    EQUB &FD, &14, &00, &04     ; vol -3, freq +&14
    EQUB &FD, &0C, &00, &04     ; vol -3, freq +&0C
    EQUB &FD, &E0, &00, &F8     ; vol -3, freq -&20

.move_seq_4
    EQUB &FF, &FF               ; Chain terminator
    EQUB &FD, &14, &00, &04     ; vol -3, freq +&14
    EQUB &FD, &08, &00, &04     ; vol -3, freq +&08
    EQUB &FD, &E4, &00, &F8     ; vol -3, freq -&1C

.move_seq_2
    EQUB &FF, &FF               ; Chain terminator
    EQUB &FE, &01, &01, &04     ; vol -2, freq +1, step 1, for 4 frames
    EQUB &FE, &FF, &01, &FC     ; vol -2, freq -1, step 1, for 252 frames

.move_seq_5
    EQUB &FF, &FF               ; Chain terminator
    EQUB &FD, &14, &00, &04     ; vol -3, freq +&14
    EQUB &FD, &10, &00, &04     ; vol -3, freq +&10
    EQUB &FD, &DC, &00, &F8     ; vol -3, freq -&24

.move_seq_6
    EQUB &FF, &FF               ; Chain terminator
    EQUB &FD, &14, &00, &04     ; vol -3, freq +&14
    EQUB &FD, &08, &00, &04     ; vol -3, freq +&08
    EQUB &FD, &E4, &00, &F8     ; vol -3, freq -&1C

; === Tile Column Mini-LUT ===
.tile_col_lut
    EQUB &00, &40, &80, &C0

; === Tile Address Setup ===
; Patches the tile graphics base address into the tile renderer.
; Uses direction to select tile column offset within the graphics page.

.tile_addr_setup
    LDY zp_direction                     ; Direction selects tile column offset (0→&00, 1→&40, 2→&80, 3→&C0)
.tile_addr_setup_y                       ; Entry with Y pre-set by caller
    LDA tile_col_lut,Y                 ; Level-indexed column offset
    STA tile_gfx_load + 1       ; Patch address low byte
    LDA #&37                    ; Tile graphics at &3700
    STA tile_gfx_load + 2       ; Patch address high byte
    BNE tile_render             ; Always branches (A=&37)

    ; Alternative entry: caller provides custom tile address in zp_src_lo/hi
.tile_addr_custom
    LDA zp_src_lo
    STA tile_gfx_load + 1
    LDA zp_src_hi
    STA tile_gfx_load + 2

; === Tile Renderer ===
; Core tile drawing routine. Reads tile graphics, masks with &0100 table,
; overlays onto screen content, and writes back.

.tile_render
    LDA zp_scroll_x                     ; Tile X coordinate
    STA zp_dst_lo
    LDA #&00
    ASL zp_dst_lo : ROL A             ; x2
    ASL zp_dst_lo : ROL A             ; x4
    ASL zp_dst_lo : ROL A             ; x8
    STA zp_dst_hi

    LDA zp_scroll_y                     ; Tile Y coordinate
    CMP #&A0                    ; Off screen?
    BCC tile_visible
    RTS                         ; Off screen — skip

.tile_visible
    AND #&F8                    ; Align to 8-pixel row boundary
    LSR A : LSR A               ; /4
    CLC
    ADC #&58                    ; Screen display base &5800
    ADC zp_dst_hi
    STA zp_dst_hi                     ; Final screen high byte

    LDA zp_scroll_y
    AND #&07                    ; Y pixel offset within tile (0-7)
    STA zp_tile_y_ofs

    LDA #&10                    ; 16 bytes per row pass
    STA zp_tile_width                     ; Width step
    STA zp_tile_limit                     ; Width limit
    LDA #&04                    ; 4 character rows per tile
    STA zp_tile_rows                     ; Row counter

    LDX #&00                    ; Tile graphics index

.tile_outer
    LDA zp_dst_lo : STA zp_map_ptr_lo     ; Screen base X -> working ptr
    LDA zp_dst_hi : STA zp_map_ptr_hi     ; Screen base Y -> working ptr
    LDY zp_tile_y_ofs                     ; Y offset within character cell

.tile_inner
    LDA (zp_map_ptr_lo),Y                 ; Read screen byte
    AND #&3F                    ; Mask lower 6 bits
    STA tile_mask + 1           ; Self-mod: patches mask table index in AND address below
.tile_gfx_load
    LDA &3700,X                 ; Read tile graphics (address is patched!)
.tile_mask
    AND &0100                   ; AND with mask table on stack page (&0100-&013F, populated at runtime)
    ORA (zp_map_ptr_lo),Y                 ; OR tile onto screen content
    STA (zp_map_ptr_lo),Y                 ; Write combined result

    INX : INY
    CPX zp_tile_limit                     ; Reached row width limit?
    BEQ tile_next_row

    CPY #&08                    ; End of character cell?
    BNE tile_inner

    ; Cross character cell boundary
    INC zp_map_ptr_hi : INC zp_map_ptr_hi           ; Next character row (+&200)
    LDY #&00
    BEQ tile_inner              ; Always branches

.tile_next_row
    LDA zp_dst_lo : ADC #&07 : STA zp_dst_lo  ; Advance 8 bytes to next tile column (carry set from CPX)
    BCC tile_no_carry
    INC zp_dst_hi
.tile_no_carry
    CLC
    LDA zp_tile_limit : ADC zp_tile_width : STA zp_tile_limit   ; Advance width limit
    DEC zp_tile_rows                     ; Decrement row counter
    BNE tile_outer              ; More rows — loop back
    RTS

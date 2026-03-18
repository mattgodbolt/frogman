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
; 1018 bytes implementing the complete game logic:
;   - Tile rendering with scrolling
;   - Sprite animation state machines
;   - Physics and gravity
;   - SN76489 sound chip control
;   - Game initialization
;
; Sprite state uses X-indexed zero page arrays for 4 sprites.
; ############################################################################

; === Jump Table ===
; External entry points — callers use these JMPs for indirection.

.jmp_block_copy     : JMP block_copy
.jmp_calc_scrn_addr : JMP calc_screen_addr
.jmp_setup_map      : JMP setup_map_render
.jmp_render_map     : JMP render_map
.jmp_spawn_sprite   : JMP spawn_sprite
.jmp_update_sprites : JMP update_sprites
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
    LDA zp_map_scroll_x                     ; Scroll position low
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

; === Animation Token Parser ===
; Parses animation stream tokens for sprite state machines.
; Tokens: &FC=set loop, &FA=loop back, &FE=end, other=frame data.

.parse_anim_token
    CMP #&FC                    ; Set loop point?
    BEQ anim_set_loop
    CMP #&FA                    ; Jump to loop?
    BEQ anim_loop_back
    CMP #&FE                    ; End of sequence?
    BNE anim_frame_data
    LDY #&00                    ; Reset animation index
    JMP update_sprite_read

.anim_frame_data
    AND #&7F                    ; Strip high bit
    STA zp_spr_frame                     ; Store frame byte
    INY
    LDA anim_timing_const                   ; Global animation timing constant
    STA zp_spr_timer                     ; Frame duration
    JMP anim_apply

.anim_set_loop
    TYA                         ; Save stream position
    STA sprite_anim_loop_y,X                 ; as loop-back point
    INY
    LDA (zp_anim_ptr_lo),Y                 ; Read repeat count
    STA sprite_anim_loop_ctr,X
    INY
    JMP update_sprite_read

.anim_loop_back
    STY anim_saved_y + 1        ; Save current Y (self-modifying immediate)
    LDY sprite_anim_loop_y,X    ; Restore loop-back position
    INY : INY                   ; Advance past loop body
    DEC sprite_anim_loop_ctr,X       ; Decrement repeat counter
    BNE update_sprite_read      ; Loop again if count > 0
.anim_saved_y
    LDY #&00                    ; Count exhausted (operand patched by STY above)
    INY                         ; Y = 1
    JMP update_sprite_read

; --- Direction/speed decoding ---
; Bit 1 selects axis: 0=vertical, 1=horizontal.
; Vertical: upper nibble >> 4. Horizontal: bits 3:2 >> 2.

.anim_apply_data
    LDA zp_spr_frame
    AND #&02                    ; Test bit 1
    BNE anim_set_horiz

    LDA zp_spr_frame
    LSR A : LSR A : LSR A : LSR A
    STA sprite_vert_speed,X                 ; Vertical speed
    INY
    JMP update_sprite_read

.anim_set_horiz
    LDA zp_spr_frame
    LSR A : LSR A
    STA sprite_horiz_param,X                 ; Horizontal speed
    INY
    JMP update_sprite_read

; === Update Sprites ===
; Main per-frame sprite update.
; Sprites 1-3: data-driven animation (objects/hazards follow scripted paths)
; Sprite 0: physics-driven movement (player)

.update_sprites
    JSR via_config_a           ; Refresh timer

    LDX #&01                    ; Start with object sprites

.update_object_loop
    LDA zp_spr_anim_tmr,X                   ; Animation timer
    BNE update_object_next       ; Active — skip to next

    ; Timer expired — read new animation from stream
    LDA #&80
    STA zp_anim_ptr_lo                     ; Animation ptr low = &80
    LDA sprite_anim_src_hi,X                 ; Animation source high for sprite X
    STA zp_anim_ptr_hi
    LDY zp_spr_anim_idx,X                   ; Animation stream index

; --- Central animation dispatch ---
; All token parser branches return here to read the next token.

.update_sprite_read
    LDA (zp_anim_ptr_lo),Y                 ; Read token from animation stream
    STA zp_spr_frame
    AND #&01                    ; Test bit 0
    BNE anim_apply_data         ; Direction/speed change

    LDA zp_spr_frame
    BMI parse_anim_token        ; Special token (&FC/&FA/&FE)

    ; Normal frame: read duration
    INY
    LDA (zp_anim_ptr_lo),Y                 ; Read duration
    STA zp_spr_timer
    INY

.anim_apply
    STY zp_spr_anim_idx,X                   ; Update animation index
    LDA sprite_vert_speed,X                 ; Vertical speed
    STA zp_spr_speed
    LDY sprite_horiz_param,X                 ; Horizontal speed
    JSR spawn_sprite            ; Set up sprite movement

.update_object_next
    INX
    CPX #&04                    ; All objects done?
    BNE update_object_loop

    ; --- Physics/movement loop (sprites 0-3) ---
    LDX #&00

.update_player
    LDA zp_spr_dir,X                   ; Sprite direction/speed
    BEQ player_no_movement      ; Not moving

    LSR A                       ; Strip direction bit
    JSR set_tone                ; Set movement sound frequency

    LDA zp_spr_anim_tmr,X                   ; Animation timer
    BEQ player_chain            ; Timer expired

    ; Set sound volume based on sub-pixel Y position
    LDA zp_spr_subpix,X                   ; Y sub-pixel
    LSR A : LSR A : LSR A : LSR A  ; -> table index
    JSR set_volume         ; Volume from position

    ; Load movement data pointers
    LDY zp_spr_move_idx,X
    LDA zp_spr_move_lo,X : STA zp_move_ptr_lo         ; Movement ptr low
    LDA zp_spr_move_hi,X : STA zp_move_ptr_hi         ; Movement ptr high

    ; Apply velocities
    LDA (zp_move_ptr_lo),Y : CLC : ADC zp_spr_subpix,X : STA zp_spr_subpix,X : INY   ; Y velocity
    LDA (zp_move_ptr_lo),Y : CLC : ADC zp_spr_dir,X : STA zp_spr_dir,X         ; X velocity

    ; Movement sub-counter
    DEC zp_spr_subctr,X
    BPL movement_timer

    ; Sub-counter expired — advance to next step
    INY : INY
    LDA (zp_move_ptr_lo),Y : CLC : ADC zp_spr_move_idx,X : STA zp_spr_move_idx,X
    TAY
    INY : INY
    LDA (zp_move_ptr_lo),Y : STA zp_spr_subctr,X    ; New sub-counter

.movement_timer
    LDA zp_spr_anim_tmr,X                   ; Check timer
    BEQ player_chain
    DEC zp_spr_anim_tmr,X                   ; Decrement
    BNE player_chain            ; Still running

    ; Timer hit zero — chain to next sequence
    LDY #&00
    LDA (zp_move_ptr_lo),Y                 ; Chain flag
    BMI sprite_kill             ; Bit 7 set = end of chain

    PHA                         ; Save chain index
    INY
    LDA (zp_move_ptr_lo),Y                 ; New timer value
    STA zp_spr_anim_tmr,X
    PLA
    ASL A                       ; x2 for word table
    TAY
    LDA move_ptr_table,Y : STA zp_spr_move_lo,X : STA zp_move_ptr_lo   ; New movement ptr low
    LDA move_ptr_table + 1,Y : STA zp_spr_move_hi,X : STA zp_move_ptr_hi   ; New movement ptr high
    LDA #&02 : STA zp_spr_move_idx,X       ; Reset index
    JMP player_chain

.sprite_kill
    LDA #&00
    JSR set_volume         ; Silence channel

.player_chain
    INX
    CPX #&04                    ; All sprites done?
    BNE update_player

    JSR via_config_b           ; Refresh timer
    RTS

.player_no_movement
    DEC zp_spr_anim_tmr,X                   ; Just decrement timer
    JMP player_chain

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
; frequency data byte from the physics table.

.set_tone
    TAY
    LDA channel_freq_regs,X     ; Frequency register byte (&E0/&C0/&A0/&80)
    ORA palette_tables,Y        ; OR in low nibble from palette table
    JSR sn76489_write            ; Send frequency latch
    LDA physics_table,Y         ; Second byte from physics table
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

; Runtime sprite state (X-indexed, modified during gameplay)
.sprite_vert_speed
    EQUB &00, &0F, &0E, &0D
.sprite_horiz_param
    EQUB &00, &01, &01, &01
.sprite_anim_loop_y
    EQUB &00, &00, &00, &00
.sprite_anim_loop_ctr
    EQUB &00, &00, &00, &00
.sprite_anim_src_hi
    EQUB &00, &0C, &0D, &0E

; === Spawn Sprite ===
; Initializes a sprite slot with position, speed, and movement data.
; Entry: &62=timer, &63=direction, &64=speed, Y=sequence index, X=slot

.spawn_sprite
    LDA zp_spr_timer : STA zp_spr_anim_tmr,X         ; Set animation timer
    LDA zp_spr_frame : ASL A : STA zp_spr_dir,X ; Direction x2
    LDA zp_spr_speed                     ; Movement speed
    ASL A : ASL A : ASL A : ASL A  ; x16 for sub-pixel
    STA zp_spr_subpix,X                   ; Y sub-pixel position
    TYA : ASL A : TAY           ; Sequence index x2
    LDA move_ptr_table,Y : STA zp_spr_move_lo,X : STA zp_move_ptr_lo  ; Movement ptr low
    LDA move_ptr_table + 1,Y : STA zp_spr_move_hi,X : STA zp_move_ptr_hi  ; Movement ptr high
    LDA #&02 : STA zp_spr_move_idx,X        ; Movement index (skip past chain terminator)
    LDY #&04
    LDA (zp_move_ptr_lo),Y : STA zp_spr_subctr,X     ; Initial sub-counter
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
; Reconfigures System VIA ports (different DDR settings).

.via_config_b
    LDA #&03 : STA VIA_ORB        ; ORB = &03: bit 3 low = sound /WE asserted
    LDA #&7F : STA VIA_DDRA        ; DDRA = &7F: bit 7 input, rest output
    LDA #&FF : STA VIA_DDRB        ; DDRB = &FF: all port B bits output
    RTS

; === Movement Data Pointer Table ===
; 7 word entries pointing to movement sequences.

.move_ptr_table
    EQUW move_seq_0             ; Seq 0
    EQUW move_seq_1             ; Seq 1
    EQUW move_seq_2             ; Seq 2
    EQUW move_seq_3             ; Seq 3
    EQUW move_seq_4             ; Seq 4
    EQUW move_seq_5             ; Seq 5
    EQUW move_seq_6             ; Seq 6

; === Movement Data Sequences ===
; Velocity/duration patterns for sprite movement.
; Each entry is: velocityY, velocityX, param1, param2
; (values like &FD/-3 and &FE/-2 are signed velocity bytes, not special prefixes).
; &FF,&FF at the start of each sequence is a chain terminator for the
; previous sequence (or initial guard — spawn code sets index=2 to skip past it).

.move_seq_0
    EQUB &FF, &FF               ; Chain terminator (BMI kills sprite reading byte 0)
    EQUB &28, &00, &04, &04     ; velY=&28, velX=&00
    EQUB &00, &00, &20, &04     ; Pause
    EQUB &F6, &00, &10, &04     ; velY=&F6 (-10)
    EQUB &00, &00, &00, &00     ; Stop

.move_seq_1
    EQUB &FF, &FF               ; Chain terminator
    EQUB &FE, &00, &20, &00     ; velY=&FE (-2), velX=&00

.move_seq_3
    EQUB &FF, &FF               ; Chain terminator
    EQUB &FD, &14, &00, &04     ; velY=&FD (-3), velX=&14
    EQUB &FD, &0C, &00, &04     ; velY=&FD (-3), velX=&0C
    EQUB &FD, &E0, &00, &F8     ; velY=&FD (-3), velX=&E0

.move_seq_4
    EQUB &FF, &FF               ; Chain terminator
    EQUB &FD, &14, &00, &04     ; velY=&FD (-3), velX=&14
    EQUB &FD, &08, &00, &04     ; velY=&FD (-3), velX=&08
    EQUB &FD, &E4, &00, &F8     ; velY=&FD (-3), velX=&E4

.move_seq_2
    EQUB &FF, &FF               ; Chain terminator
    EQUB &FE, &01, &01, &04     ; velY=&FE (-2), velX=&01
    EQUB &FE, &FF, &01, &FC     ; velY=&FE (-2), velX=&FF (-1)

.move_seq_5
    EQUB &FF, &FF               ; Chain terminator
    EQUB &FD, &14, &00, &04     ; velY=&FD (-3), velX=&14
    EQUB &FD, &10, &00, &04     ; velY=&FD (-3), velX=&10
    EQUB &FD, &DC, &00, &F8     ; velY=&FD (-3), velX=&DC

.move_seq_6
    EQUB &FF, &FF               ; Chain terminator
    EQUB &FD, &14, &00, &04     ; velY=&FD (-3), velX=&14
    EQUB &FD, &08, &00, &04     ; velY=&FD (-3), velX=&08
    EQUB &FD, &E4, &00, &F8     ; velY=&FD (-3), velX=&E4

; === Tile Column Mini-LUT ===
.tile_col_lut
    EQUB &00, &40, &80, &C0

; === Tile Address Setup ===
; Patches the tile graphics base address into the tile renderer using
; the current level number (&19) to select the tile set.

.tile_addr_setup
    LDY zp_direction                     ; TODO: investigate — &19 used as level number here but as direction flags in game code. Likely double-duty variable.
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
    STA tile_mask + 1           ; Self-mod: AND operand for mask below
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

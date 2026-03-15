; ============================================================================
; FROGMAN — Game Engine (Annotated Disassembly)
; Written by Matthew Godbolt & Richard Talbot-Watkins, February 1993
;
; Contains ALL executable code:
;   IRQ Handler           (94 bytes)
;   Sprite Pointer Table  (21 bytes)
;   Game Engine           (1018 bytes)
;
; Total executable code: ~1.1KB — remarkably compact for a full-featured
; platformer with scrolling, sprite animation, physics, and music.
;
; Every instruction is byte-accurate against the runtime memory dump.
; ============================================================================

; ############################################################################
; IRQ HANDLER
; ############################################################################
; Handles hardware interrupts from the System VIA:
;   - CA1+CA2 (VSYNC-related) both set → music note sequencing
;   - Other sources → sound envelope timing / delay generation
;
; Uses self-modifying code to patch values into the music data stream.
; ############################################################################

ORG &0600

.irq_handler
    PHA                         ; Save accumulator

    LDA &FE28                   ; Read System VIA interrupt flag register
    AND #&3F                    ; Mask to relevant bits
    CMP #&03                    ; CA1+CA2 both set? (CA1 = VSYNC on BBC)
    BEQ music_handler           ; Yes — handle music

    AND #&FC                    ; Check non-timer interrupt sources
    BNE store_irq_status        ; Other source — store and exit

    DEC &A5                     ; Decrement sound envelope counter
    BNE sound_tick              ; Not zero — process sound envelope

.store_irq_status
    STA &A2                     ; Store interrupt status for main loop
    PLA                         ; Restore A
    RTI                         ; Return from interrupt

; --- Sound envelope tick ---
; On the final tick (counter=1), if sound is enabled, patches a silence
; byte into the music data stream at music_env_patch.

.sound_tick
    LDA &A5                     ; Load envelope counter
    CMP #&01                    ; Final tick?
    BNE delay_loop              ; No — skip to delay

    LDA &A1                     ; Load sound enable flag
    ROR A                       ; Rotate bit 0 into carry
    BCC delay_loop              ; Sound disabled — skip

    LDA #&48                    ; Silence token
    STA music_env_patch                   ; Patch silence into live sound state (decrypted at runtime)

; --- VIA Timer 2 delay loop ---
; Brief busy-wait: writes to Timer 2 low counter, reads it back.
; They differ once the counter ticks, creating a short delay.

.delay_loop
    INC &CF                     ; Increment delay counter
    LDA &CF                     ; Load delay value
.delay_spin
    STA &FE2A                   ; Write to Timer 2 low counter
    CMP &FE2A                   ; Read back — values differ once counter ticks
    BNE delay_spin              ; Brief busy-wait creating a short delay

    LDA &A7                     ; IFR acknowledge mask
    STA &FE28                   ; Write to IFR to clear flagged interrupts
    PLA                         ; Restore A
    RTI

; --- Music note sequencing ---
; Advances music data pointer and decrements note duration.
; When a note ends, patches a reset token into the stream.

.music_handler
    LDA &FE2B                   ; Read Timer 2 high (pseudo-random seed)
    STA &8000                   ; Write to sideways RAM (purpose unclear — possibly RNG seed or bank signalling)

    INC music_ptr_lo                   ; Advance music pointer low (live runtime data)
    BNE skip_music_hi
    INC music_ptr_hi                   ; Carry to music pointer high (live runtime data)

.skip_music_hi
    DEC &A6                     ; Decrement note duration
    BNE done_music              ; Note still playing

    LDA #&2F                    ; Reset/silence token
    STA music_note_reset                   ; Patch reset into live sound state (decrypted at runtime)

.done_music
    PLA
    RTI

; --- System VIA Timer 2 acknowledge ---
.sysvia_t2_ack
    LDA &FE2B                   ; Read System VIA Timer 2 High to acknowledge
    PLA
    RTI

; --- Reset Timer 2 high byte ---
.irq_disable
    LDA #&00
    STA &FE2B                   ; Reset Timer 2 high byte to zero
    PLA
    RTI

; --- Padding (unused, zeroed) ---
    SKIP 92

; ############################################################################
; SPRITE ANIMATION POINTER TABLE
; ############################################################################
; 7 entries (low byte, high byte, bank) pointing to animation sequences.
; Used by the spawn code to look up how each sprite type animates.
; ############################################################################


.sprite_anim_ptrs
    EQUB &5D, &9D, &09          ; Type 0
    EQUB &4C, &97, &09          ; Type 1
    EQUB &5C, &98, &09          ; Type 2
    EQUB &4A, &99, &09          ; Type 3
    EQUB &A1, &9D, &09          ; Type 4
    EQUB &BD, &95, &09          ; Type 5
    EQUB &8E, &9D, &09          ; Type 6

; --- Padding (runtime residuals from game state) ---
    SKIP 42
    EQUB &DA                    ; Runtime residual
    SKIP 3
    EQUB &D9                    ; Runtime residual
    SKIP 2

; --- Lookup tables fill the gap between &0700-&087F ---
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
    STA &00                     ; Tile source pointer low
    LDA tile_src_hi,Y                 ; Tile graphics source high byte
    STA &01                     ; Tile source pointer high
    JSR calc_screen_addr        ; Calculate screen dest address -> &02/&03
    LDX #&01                    ; Copy 2 rows (counter: 1, 0)

; Fully unrolled 32-byte copy — speed-critical inner loop.
; The JMP at bc_done re-enters here, resetting Y each iteration.
.bc_copy_loop
    LDY #&00                    ; Reset byte offset for each row
    FOR n, 1, 32
        LDA (&00),Y : STA (&02),Y : INY
    NEXT

    ; Advance source by 32 bytes
    CLC
    LDA &00
    ADC #&20
    STA &00
    BCC bc_no_carry
    INC &01
.bc_no_carry
    INC &03                     ; Dest high += 2 (next character row)
    INC &03

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
; Input: &0A = tile X, &0B = tile Y
; Output: &02/&03 = screen memory address
; Screen display base is &5800 (custom CRTC configuration).
; Calculates: addr_hi = (tile_Y * 2) + &58 + hi(tile_X * 8), addr_lo = lo(tile_X * 8)

.calc_screen_addr
    LDA &0A                     ; Tile X
    STA &02
    LDA #&00
    ASL &02 : ROL A             ; x2
    ASL &02 : ROL A             ; x4
    ASL &02 : ROL A             ; x8
    STA &03
    LDA &0B                     ; Tile Y
    ASL A                       ; x2
    ADC &03
    ADC #&58                    ; Screen display base &5800
    STA &03
    RTS

; === Setup Map Rendering ===
; Converts scroll position (&13/&14) to map data pointer (&06/&07).
; Map data is based at &0F00.

.setup_map_render
    LDA &13                     ; Scroll position low
    STA &07
    LDA #&00
    LSR &07                     ; Divide by 2
    ROR A                       ; Remainder -> A
    STA &06                     ; Map pointer low
    LDA &14                     ; Scroll position high
    ASL A : ASL A               ; x4
    ADC &07
    ADC #&0F                    ; Map base = &0F00
    STA &07                     ; Map pointer high
    ; Falls through to render_map

; === Render Map ===
; Renders 16x8 visible tile grid to screen.

.render_map
    LDA #&00
    STA &0A                     ; Column = 0
    STA &0B                     ; Row = 0
    LDY #&00                    ; Map offset

.render_loop
    LDA (&06),Y                 ; Read tile index
    JSR block_copy              ; Draw tile
    INY
    CLC
    LDA &0A
    ADC #&04                    ; Next column (+4 per tile)
    STA &0A
    CMP #&40                    ; End of row?
    BNE render_loop

    LDA #&00
    STA &0A                     ; Reset column
    INC &0B : INC &0B           ; Next row (+2)
    LDA &0B
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
    STA &63                     ; Store frame byte
    INY
    LDA anim_timing_const                   ; Global animation timing constant
    STA &62                     ; Frame duration
    JMP anim_apply

.anim_set_loop
    TYA                         ; Save stream position
    STA sprite_anim_loop_y,X                 ; as loop-back point
    INY
    LDA (&90),Y                 ; Read repeat count
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
    LDA &63
    AND #&02                    ; Test bit 1
    BNE anim_set_horiz

    LDA &63
    LSR A : LSR A : LSR A : LSR A
    STA sprite_vert_speed,X                 ; Vertical speed
    INY
    JMP update_sprite_read

.anim_set_horiz
    LDA &63
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
    LDA &78,X                   ; Animation timer
    BNE update_object_next       ; Active — skip to next

    ; Timer expired — read new animation from stream
    LDA #&80
    STA &90                     ; Animation ptr low = &80
    LDA sprite_anim_src_hi,X                 ; Animation source high for sprite X
    STA &91
    LDY &8C,X                   ; Animation stream index

; --- Central animation dispatch ---
; All token parser branches return here to read the next token.

.update_sprite_read
    LDA (&90),Y                 ; Read token from animation stream
    STA &63
    AND #&01                    ; Test bit 0
    BNE anim_apply_data         ; Direction/speed change

    LDA &63
    BMI parse_anim_token        ; Special token (&FC/&FA/&FE)

    ; Normal frame: read duration
    INY
    LDA (&90),Y                 ; Read duration
    STA &62
    INY

.anim_apply
    STY &8C,X                   ; Update animation index
    LDA sprite_vert_speed,X                 ; Vertical speed
    STA &64
    LDY sprite_horiz_param,X                 ; Horizontal speed
    JSR spawn_sprite            ; Set up sprite movement

.update_object_next
    INX
    CPX #&04                    ; All objects done?
    BNE update_object_loop

    ; --- Physics/movement loop (sprites 0-3) ---
    LDX #&00

.update_player
    LDA &70,X                   ; Sprite direction/speed
    BEQ player_no_movement      ; Not moving

    LSR A                       ; Strip direction bit
    JSR set_tone                ; Set movement sound frequency

    LDA &78,X                   ; Animation timer
    BEQ player_chain            ; Timer expired

    ; Set sound volume based on sub-pixel Y position
    LDA &74,X                   ; Y sub-pixel
    LSR A : LSR A : LSR A : LSR A  ; -> table index
    JSR set_volume         ; Volume from position

    ; Load movement data pointers
    LDY &84,X
    LDA &7C,X : STA &60         ; Movement ptr low
    LDA &80,X : STA &61         ; Movement ptr high

    ; Apply velocities
    LDA (&60),Y : CLC : ADC &74,X : STA &74,X : INY   ; Y velocity
    LDA (&60),Y : CLC : ADC &70,X : STA &70,X         ; X velocity

    ; Movement sub-counter
    DEC &88,X
    BPL movement_timer

    ; Sub-counter expired — advance to next step
    INY : INY
    LDA (&60),Y : CLC : ADC &84,X : STA &84,X
    TAY
    INY : INY
    LDA (&60),Y : STA &88,X    ; New sub-counter

.movement_timer
    LDA &78,X                   ; Check timer
    BEQ player_chain
    DEC &78,X                   ; Decrement
    BNE player_chain            ; Still running

    ; Timer hit zero — chain to next sequence
    LDY #&00
    LDA (&60),Y                 ; Chain flag
    BMI sprite_kill             ; Bit 7 set = end of chain

    PHA                         ; Save chain index
    INY
    LDA (&60),Y                 ; New timer value
    STA &78,X
    PLA
    ASL A                       ; x2 for word table
    TAY
    LDA move_ptr_table,Y : STA &7C,X : STA &60   ; New movement ptr low
    LDA move_ptr_table + 1,Y : STA &80,X : STA &61   ; New movement ptr high
    LDA #&02 : STA &84,X       ; Reset index
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
    DEC &78,X                   ; Just decrement timer
    JMP player_chain

; === SN76489 Sound Chip Write ===
; Writes a byte to the SN76489 via System VIA.
; &FE41 = System VIA ORA (data bus to sound chip).
; &FE40 = System VIA ORB, bit 3 = sound chip /WE (active low).
; Writing &00 asserts WE, &08 deasserts it.

.sn76489_write
    STA &FE41                   ; Data byte -> System VIA port A (sound chip bus)
    LDA #&00
    STA &FE40                   ; System VIA ORB: bit 3 low = assert /WE
    NOP : NOP : NOP : NOP       ; Wait for SN76489 timing (~4us)
    LDA #&08
    STA &FE40                   ; System VIA ORB: bit 3 high = deassert /WE
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
    LDA &62 : STA &78,X         ; Set animation timer
    LDA &63 : ASL A : STA &70,X ; Direction x2
    LDA &64                     ; Movement speed
    ASL A : ASL A : ASL A : ASL A  ; x16 for sub-pixel
    STA &74,X                   ; Y sub-pixel position
    TYA : ASL A : TAY           ; Sequence index x2
    LDA move_ptr_table,Y : STA &7C,X : STA &60  ; Movement ptr low
    LDA move_ptr_table + 1,Y : STA &80,X : STA &61  ; Movement ptr high
    LDA #&02 : STA &84,X        ; Movement index (skip past chain terminator)
    LDY #&04
    LDA (&60),Y : STA &88,X     ; Initial sub-counter
    RTS

; === System VIA Port Config A ===
; Configures System VIA ports for sound output.
; &FE40 = ORB, &FE42 = DDRB, &FE43 = DDRA.

.via_config_a
    LDA #&0B : STA &FE40        ; ORB = &0B: bit 3 high = sound /WE deasserted
    LDA #&FF : STA &FE43        ; DDRA = &FF: all port A bits output
    LDA #&FF : STA &FE42        ; DDRB = &FF: all port B bits output
    RTS

; === System VIA Port Config B ===
; Reconfigures System VIA ports (different DDR settings).

.via_config_b
    LDA #&03 : STA &FE40        ; ORB = &03: bit 3 low = sound /WE asserted
    LDA #&7F : STA &FE43        ; DDRA = &7F: bit 7 input, rest output
    LDA #&FF : STA &FE42        ; DDRB = &FF: all port B bits output
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
    LDY &19                     ; Current level number
    LDA tile_col_lut,Y                 ; Level-indexed column offset
    STA tile_gfx_load + 1       ; Patch address low byte
    LDA #&37                    ; Tile graphics at &3700
    STA tile_gfx_load + 2       ; Patch address high byte
    BNE tile_render             ; Always branches (A=&37)

    ; Alternative entry: caller provides custom tile address in &00/&01
    LDA &00
    STA tile_gfx_load + 1
    LDA &01
    STA tile_gfx_load + 2

; === Tile Renderer ===
; Core tile drawing routine. Reads tile graphics, masks with &0100 table,
; overlays onto screen content, and writes back.

.tile_render
    LDA &0F                     ; Tile X coordinate
    STA &02
    LDA #&00
    ASL &02 : ROL A             ; x2
    ASL &02 : ROL A             ; x4
    ASL &02 : ROL A             ; x8
    STA &03

    LDA &10                     ; Tile Y coordinate
    CMP #&A0                    ; Off screen?
    BCC tile_visible
    RTS                         ; Off screen — skip

.tile_visible
    AND #&F8                    ; Align to 8-pixel row boundary
    LSR A : LSR A               ; /4
    CLC
    ADC #&58                    ; Screen display base &5800
    ADC &03
    STA &03                     ; Final screen high byte

    LDA &10
    AND #&07                    ; Y pixel offset within tile (0-7)
    STA &15

    LDA #&10                    ; 16 bytes per row pass
    STA &16                     ; Width step
    STA &17                     ; Width limit
    LDA #&04                    ; 4 character rows per tile
    STA &18                     ; Row counter

    LDX #&00                    ; Tile graphics index

.tile_outer
    LDA &02 : STA &04           ; Screen base X -> working ptr
    LDA &03 : STA &05           ; Screen base Y -> working ptr
    LDY &15                     ; Y offset within character cell

.tile_inner
    LDA (&04),Y                 ; Read screen byte
    AND #&3F                    ; Mask lower 6 bits
    STA tile_mask + 1           ; Self-mod: AND operand for mask below
.tile_gfx_load
    LDA &3700,X                 ; Read tile graphics (address is patched!)
.tile_mask
    AND &0100                   ; AND with mask table on stack page (&0100-&013F, populated at runtime)
    ORA (&04),Y                 ; OR tile onto screen content
    STA (&04),Y                 ; Write combined result

    INX : INY
    CPX &17                     ; Reached row width limit?
    BEQ tile_next_row

    CPY #&08                    ; End of character cell?
    BNE tile_inner

    ; Cross character cell boundary
    INC &05 : INC &05           ; Next character row (+&200)
    LDY #&00
    BEQ tile_inner              ; Always branches

.tile_next_row
    LDA &02 : ADC #&07 : STA &02  ; Advance 8 bytes to next tile column (carry set from CPX)
    BCC tile_no_carry
    INC &03
.tile_no_carry
    CLC
    LDA &17 : ADC &16 : STA &17   ; Advance width limit
    DEC &18                     ; Decrement row counter
    BNE tile_outer              ; More rows — loop back
    RTS

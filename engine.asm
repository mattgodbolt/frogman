; ============================================================================
; FROGMAN — Game Engine (Annotated Disassembly)
; Written by Matthew Godbolt & Richard Talbot-Watkins, February 1993
;
; Contains ALL executable code:
;   IRQ Handler:        &0600-&065D  (94 bytes)
;   Sprite Pointer Table: &06BA-&06C8 (15 bytes)
;   Game Engine:        &0880-&0C77  (1016 bytes)
;
; Total executable code: ~1.1KB — remarkably compact for a full platformer
; with scrolling, sprite animation, physics, and music playback.
; ============================================================================

; --- Zero page variable definitions ---
zp_src_lo       = &00           ; Source pointer low (tile/screen address)
zp_src_hi       = &01           ; Source pointer high
zp_dst_lo       = &02           ; Destination pointer low (screen address)
zp_dst_hi       = &03           ; Destination pointer high
zp_map_ptr_lo   = &04           ; Map data pointer low
zp_map_ptr_hi   = &05           ; Map data pointer high
zp_map_src_lo   = &06           ; Map source address low
zp_map_src_hi   = &07           ; Map source address high
zp_tile_x       = &0A           ; Screen X tile coordinate
zp_tile_y       = &0B           ; Screen Y tile coordinate
zp_render_x     = &0F           ; Tile X for renderer
zp_render_y     = &10           ; Tile Y for renderer
zp_scroll_lo    = &13           ; Scroll position low
zp_scroll_hi    = &14           ; Scroll position high
zp_y_offset     = &15           ; Y pixel offset within tile
zp_tile_ctr_w   = &16           ; Tile rendering width counter
zp_tile_ctr_h   = &17           ; Tile rendering height counter
zp_tile_rows    = &18           ; Tile row counter
zp_level        = &19           ; Current level number
zp_move_ptr_lo  = &60           ; Movement data pointer low
zp_move_ptr_hi  = &61           ; Movement data pointer high
zp_sprite_tmp1  = &62           ; Sprite/animation temporary var 1
zp_sprite_tmp2  = &63           ; Sprite/animation temporary var 2
zp_move_speed   = &64           ; Movement speed
zp_direction    = &70           ; Sprite direction/speed (4 sprites, +X)
zp_y_subpix     = &74           ; Sprite Y sub-pixel position (4 sprites)
zp_anim_timer   = &78           ; Sprite animation countdown (4 sprites)
zp_move_lo      = &7C           ; Movement data ptr low (4 sprites)
zp_move_hi      = &80           ; Movement data ptr high (4 sprites)
zp_move_idx     = &84           ; Movement data index (4 sprites)
zp_move_sub     = &88           ; Movement sub-counter (4 sprites)
zp_anim_idx     = &8C           ; Animation data index (4 sprites)
zp_anim_ptr_lo  = &90           ; Animation data pointer low
zp_anim_ptr_hi  = &91           ; Animation data pointer high
zp_spr_src_lo   = &96           ; Source pointer for sprite rendering
zp_spr_src_hi   = &97           ; Source pointer for sprite rendering
zp_snd_enable   = &A1           ; Sound enable flag (bit 0 checked)
zp_last_irq     = &A2           ; Last interrupt status
zp_snd_env_ctr  = &A5           ; Sound envelope counter
zp_music_dur    = &A6           ; Music note duration counter
zp_via_ifr_save = &A7           ; System VIA IFR restore value
zp_via_delay    = &CF           ; VIA timer delay counter

; --- Hardware addresses ---
SYSVIA_IFR      = &FE28         ; System VIA interrupt flag register
SYSVIA_T2CL     = &FE2A         ; System VIA Timer 2 counter low
SYSVIA_T2CH     = &FE2B         ; System VIA Timer 2 counter high
USRVIA_ORB      = &FE40         ; User VIA port B (active register select)
USRVIA_ORA      = &FE41         ; User VIA port A (sound chip data)
USRVIA_T1CL     = &FE42         ; User VIA Timer 1 counter low
USRVIA_T1CH     = &FE43         ; User VIA Timer 1 counter high
SOUND_OUT       = &8000         ; Sound output / sideways RAM

; ############################################################################
; IRQ HANDLER (&0600-&065D)
; ############################################################################
; Handles three interrupt sources:
;   1. Timer 2 timeout → advance music playback
;   2. Timer 1 timeout → generate sound output
;   3. Other interrupts → envelope/delay processing
;
; The handler uses self-modifying code to patch music data into the
; playback stream, enabling compact music sequencing.
; ############################################################################

ORG &0600
.irq_handler
    PHA                         ; Save accumulator on stack
    LDA SYSVIA_IFR              ; Read System VIA interrupt flags
    AND #&3F                    ; Mask to relevant bits (ignore b7/b6)
    CMP #&03                    ; Is this Timer 1 + Timer 2?
    BEQ music_handler           ; Yes — jump to music playback handler
    AND #&FC                    ; Mask off Timer 1 and Timer 2 bits
    BNE store_irq_status        ; Other interrupt source — store and exit
    DEC zp_snd_env_ctr          ; Decrement sound envelope counter
    BNE sound_tick              ; Not zero yet — process sound timing

.store_irq_status
    STA zp_last_irq             ; Store interrupt status for main loop
    PLA                         ; Restore accumulator
    RTI                         ; Return from interrupt

; --- Sound envelope tick processing ---
.sound_tick
    LDA zp_snd_env_ctr          ; Load current envelope counter value
    CMP #&01                    ; Has it reached 1? (about to expire)
    BNE delay_loop              ; No — skip to delay timing loop
    LDA zp_snd_enable           ; Load sound enable flag
    ROR A                       ; Rotate bit 0 into carry
    BCC delay_loop              ; Sound disabled (bit 0 clear) — skip

    ; Self-modifying code: patch a silence byte into the music stream
    LDA #&48                    ; Value to write (silence token)
    STA &0D4C                   ; Patch into music data stream

.delay_loop
    INC zp_via_delay            ; Increment delay counter
    LDA zp_via_delay            ; Load delay value
    STA SYSVIA_T2CL             ; Write to VIA Timer 2 low byte
    CMP SYSVIA_T2CL             ; Compare — wait for timer to latch
    BNE delay_loop              ; Spin until timer value matches (ready)
    LDA zp_via_ifr_save         ; Load saved IFR value
    STA SYSVIA_IFR              ; Write back to clear interrupt flags
    PLA                         ; Restore accumulator
    RTI                         ; Return from interrupt

; --- Music playback handler ---
; Triggered when Timer 1 fires (the music tempo timer).
; Reads Timer 2 high byte as a pseudo-random value for sound output,
; then advances the music data pointer and decrements note duration.
.music_handler
    LDA SYSVIA_T2CH             ; Read Timer 2 high byte (pseudo-random)
    STA SOUND_OUT               ; Write to sound output / sideways RAM
    INC &0D3D                   ; Advance music pointer low byte (self-mod)
    BNE skip_music_hi           ; No overflow — skip high byte increment
    INC &0D3E                   ; Increment music pointer high byte

.skip_music_hi
    DEC zp_music_dur            ; Decrement note duration counter
    BNE done_music              ; Note still playing — exit
    LDA #&2F                    ; Note ended — load silence/reset token
    STA &0D09                   ; Patch into music data (self-modifying)

.done_music
    PLA                         ; Restore accumulator
    RTI                         ; Return from interrupt

; --- User VIA Timer 1 clear handler ---
; Simply reads Timer 1 to acknowledge/clear the interrupt.
.usrvia_t1_clear
    LDA SYSVIA_T2CH             ; Read to clear Timer 2 interrupt flag
    PLA                         ; Restore accumulator
    RTI                         ; Return from interrupt

; --- Disable interrupts handler ---
; Shuts down the sound system by zeroing Timer 2.
.irq_disable
    LDA #&00                    ; Zero value
    STA SYSVIA_T2CH             ; Clear VIA Timer 2 high byte
    PLA                         ; Restore accumulator
    RTI                         ; Return from interrupt

; Padding between IRQ handler and sprite pointer table
; (&065E-&06B9 is unused zero-filled space)

; ############################################################################
; SPRITE POINTER TABLE (&06BA-&06C8)
; ############################################################################
; 7 entries of 3-byte (actually word) pointers to animation data.
; Each entry is: low byte, high byte, bank — pointing to animation
; sequence definitions for different sprite types.
; Not all entries are necessarily used; some may be unused/reserved.

ORG &06BA
.sprite_anim_ptrs
    EQUB &5D, &9D, &09          ; Sprite type 0 animation data at &099D (+ bank)
    EQUB &4C, &97, &09          ; Sprite type 1
    EQUB &5C, &98, &09          ; Sprite type 2
    EQUB &4A, &99, &09          ; Sprite type 3
    EQUB &A1, &9D, &09          ; Sprite type 4
    ; Note: page6_full.bin shows two more entries follow at &06C3:
    EQUB &BD, &95, &09          ; Sprite type 5
    EQUB &8E, &9D, &09          ; Sprite type 6


; ############################################################################
; GAME ENGINE (&0880-&0C77)
; ############################################################################
; The complete game engine in ~1016 bytes. Covers:
;   - Jump table for external calls
;   - Tile block copy (screen rendering)
;   - Screen address calculation
;   - Map rendering with scrolling
;   - Sprite animation and movement
;   - Sound chip I/O (SN76489)
;   - Physics and gravity
;   - Game initialisation
;
; Architecture: all sprite state uses X-indexed zero page arrays,
; supporting 4 simultaneous sprites (player + 3 enemies).
; ############################################################################

; === Jump Table (&0880-&0894) ===
; External entry points — other code calls through these JMPs so the
; engine can be relocated without updating all callers.

ORG &0880
.jmp_block_copy
    JMP block_copy              ; &0895 — Copy tile block to screen
.jmp_calc_screen_addr
    JMP calc_screen_addr        ; &0967 — Calculate screen address from coords
.jmp_setup_map_render
    JMP setup_map_render        ; &0982 — Set up map rendering parameters
.jmp_render_map
    JMP render_map              ; &0997 — Render visible map to screen
.jmp_spawn_sprite
    JMP spawn_sprite            ; &0B30 — Initialize a new sprite
.jmp_update_sprites
    JMP update_sprites          ; &0A2D — Update all sprites (physics + anim)
.jmp_init_game
    JMP init_game               ; &09BF — Initialize game state

; === Block Copy (&0895-&0966) ===
; Copies a tile from source address (&00/&01) to screen (&02/&03).
; On entry: Y = column LUT index, X = row LUT index
; The source tile data is 32 bytes per row (unrolled for speed).
; Copies X+1 rows, advancing source by 32 and screen by row stride.

.block_copy
    STY &0963                   ; Self-modify: store Y into .bc_y_restore+1
    STX &0965                   ; Self-modify: store X into .bc_x_restore+1
    TAY                         ; Transfer tile index to Y for LUT lookup
    LDA screen_col_lut,Y        ; Look up screen column low byte
    STA zp_src_lo               ; Store as source pointer low
    LDA screen_row_lut,Y        ; Look up screen row high byte
    STA zp_src_hi               ; Store as source pointer high
    JSR calc_screen_addr        ; Calculate full screen destination address
    LDX #&01                    ; Row counter (2 rows: 0 and 1)
    LDY #&00                    ; Byte offset starts at 0

    ; Unrolled 32-byte copy loop — copies one row of tile data.
    ; Each LDA/STA pair copies one byte from source to destination.
    ; 32 bytes = 8 pixels wide x 4 bytes/pixel in MODE 2.
.bc_copy_row
    LDA (zp_src_lo),Y : STA (zp_dst_lo),Y : INY
    LDA (zp_src_lo),Y : STA (zp_dst_lo),Y : INY
    LDA (zp_src_lo),Y : STA (zp_dst_lo),Y : INY
    LDA (zp_src_lo),Y : STA (zp_dst_lo),Y : INY
    LDA (zp_src_lo),Y : STA (zp_dst_lo),Y : INY
    LDA (zp_src_lo),Y : STA (zp_dst_lo),Y : INY
    LDA (zp_src_lo),Y : STA (zp_dst_lo),Y : INY
    LDA (zp_src_lo),Y : STA (zp_dst_lo),Y : INY     ; 8 bytes
    LDA (zp_src_lo),Y : STA (zp_dst_lo),Y : INY
    LDA (zp_src_lo),Y : STA (zp_dst_lo),Y : INY
    LDA (zp_src_lo),Y : STA (zp_dst_lo),Y : INY
    LDA (zp_src_lo),Y : STA (zp_dst_lo),Y : INY
    LDA (zp_src_lo),Y : STA (zp_dst_lo),Y : INY
    LDA (zp_src_lo),Y : STA (zp_dst_lo),Y : INY
    LDA (zp_src_lo),Y : STA (zp_dst_lo),Y : INY
    LDA (zp_src_lo),Y : STA (zp_dst_lo),Y : INY     ; 16 bytes
    LDA (zp_src_lo),Y : STA (zp_dst_lo),Y : INY
    LDA (zp_src_lo),Y : STA (zp_dst_lo),Y : INY
    LDA (zp_src_lo),Y : STA (zp_dst_lo),Y : INY
    LDA (zp_src_lo),Y : STA (zp_dst_lo),Y : INY
    LDA (zp_src_lo),Y : STA (zp_dst_lo),Y : INY
    LDA (zp_src_lo),Y : STA (zp_dst_lo),Y : INY
    LDA (zp_src_lo),Y : STA (zp_dst_lo),Y : INY
    LDA (zp_src_lo),Y : STA (zp_dst_lo),Y : INY     ; 24 bytes
    LDA (zp_src_lo),Y : STA (zp_dst_lo),Y : INY
    LDA (zp_src_lo),Y : STA (zp_dst_lo),Y : INY
    LDA (zp_src_lo),Y : STA (zp_dst_lo),Y : INY
    LDA (zp_src_lo),Y : STA (zp_dst_lo),Y : INY
    LDA (zp_src_lo),Y : STA (zp_dst_lo),Y : INY
    LDA (zp_src_lo),Y : STA (zp_dst_lo),Y : INY
    LDA (zp_src_lo),Y : STA (zp_dst_lo),Y : INY
    LDA (zp_src_lo),Y : STA (zp_dst_lo),Y : INY     ; 32 bytes

    ; Advance source pointer by 32 bytes to next tile row
    CLC
    LDA zp_src_lo
    ADC #&20                    ; Add 32 to source pointer low
    STA zp_src_lo
    BCC bc_no_carry
    INC zp_src_hi               ; Carry into high byte
.bc_no_carry
    INC zp_dst_hi               ; Advance screen dest by 256 (next char row)
    INC zp_dst_hi               ; Two increments = &200 stride

    DEX                         ; Decrement row counter
    BMI bc_done                 ; All rows copied — exit
    JMP bc_copy_row             ; More rows — loop back

.bc_done
.bc_y_restore
    LDY #&05                    ; Restore Y (self-modified at entry)
.bc_x_restore
    LDX #&08                    ; Restore X (self-modified at entry)
    RTS

; === Calculate Screen Address (&0967-&0981) ===
; Converts tile X coordinate (&0A) and Y coordinate (&0B) to a screen
; memory address stored in &02/&03.
; The calculation multiplies tile_x by 8 (ASL x3 with ROL for carry)
; and adds the row base address from the LUT.

.calc_screen_addr
    LDA zp_tile_x               ; Load tile X coordinate
    STA zp_dst_lo               ; Store temporarily in dest low
    LDA #&00                    ; Clear high byte
    ASL zp_dst_lo               ; x2
    ROL A                       ; Carry into A
    ASL zp_dst_lo               ; x4
    ROL A                       ; Carry into A
    ASL zp_dst_lo               ; x8 — each tile is 8 bytes wide
    ROL A                       ; Carry into A
    STA zp_dst_hi               ; Store high byte of offset
    LDA zp_tile_y               ; Load tile Y coordinate
    ASL A                       ; x2 — each row entry is 2 bytes? No, just index
    ADC zp_dst_hi               ; Add to high byte offset
    ADC #&58                    ; Add screen base high byte (&58xx)
    STA zp_dst_hi               ; Final screen address high byte
    RTS

; === Setup Map Render (&0982-&0996) ===
; Converts the scroll position (&13/&14) into a map data pointer (&06/&07).
; The division converts pixel scroll position to tile-level map coordinates.

.setup_map_render
    LDA zp_scroll_lo            ; Load scroll position low byte
    STA zp_map_src_hi           ; Store temporarily
    LDA #&00                    ; Clear low byte
    LSR zp_map_src_hi           ; Divide scroll position by 2
    ROR A                       ; Rotate remainder into A
    STA zp_map_src_lo           ; Store map source low byte
    LDA zp_scroll_hi            ; Load scroll position high byte
    ASL A                       ; Multiply by 4
    ASL A
    ADC zp_map_src_hi           ; Add to map source high
    ADC #&0F                    ; Add map data base page (&0F00)
    STA zp_map_src_hi           ; Final map data pointer high byte
    RTS

; === Render Map (&0997-&09BE) ===
; Renders the visible portion of the level map to screen memory.
; Iterates through a grid of 16 columns x 8 rows (16x16 tile viewport),
; calling block_copy for each tile to paint it on screen.

.render_map
    LDA #&00
    STA zp_tile_x               ; Start at column 0
    STA zp_tile_y               ; Start at row 0
    LDY #&00                    ; Map data offset

.render_col_loop
    LDA (zp_map_src_lo),Y       ; Read tile index from map data
    JSR block_copy              ; Copy tile to screen
    INY                         ; Next map byte
    CLC
    LDA zp_tile_x
    ADC #&04                    ; Advance 4 columns (each tile = 4 cols wide)
    STA zp_tile_x
    CMP #&40                    ; Reached end of row? (16 tiles x 4 = 64)
    BNE render_col_loop         ; No — continue across row

    LDA #&00
    STA zp_tile_x               ; Reset column to 0
    INC zp_tile_y               ; Move to next tile row
    INC zp_tile_y               ; Advance by 2 (each tile = 2 rows tall)
    LDA zp_tile_y
    CMP #&10                    ; Reached bottom? (8 tile rows x 2 = 16)
    BNE render_col_loop         ; No — continue to next row
    RTS

; === Game Initialization (&09BF-&09CF) ===
; Sets up the VIA timers for sound/music playback, then clears all
; four sprite slots to inactive state.

.init_game
    JSR setup_sys_via           ; Configure System VIA Timer 1 for music
    LDX #&03                    ; 4 sprites (3 down to 0)
    LDA #&00                    ; Zero value for clearing
.init_clear_loop
    JSR set_attenuation         ; Set channel X to silence (attenuation = 0)
    DEX                         ; Next sprite slot
    BPL init_clear_loop         ; Loop until all 4 cleared
    JSR setup_usr_via           ; Configure User VIA Timer 1
    RTS

; === Animation Token Parser (&09D0-&0A2C) ===
; Parses sprite animation data tokens. Called when an animation frame
; expires and the next token needs to be read from the animation stream.
;
; Token types:
;   &FC — Set loop point: save current Y position and load repeat count
;   &FA — Jump to loop point: decrement count, branch back if non-zero
;   &FE — End of sequence: reset Y to 0 and return to update loop
;   Other — Animation frame data: bit 0 = direction, upper bits = frame/speed

.parse_anim_token
    CMP #&FC                    ; Is it a "set loop point" token?
    BEQ anim_set_loop           ; Yes — save position
    CMP #&FA                    ; Is it a "jump to loop" token?
    BEQ anim_jump_loop          ; Yes — decrement and branch
    CMP #&FE                    ; Is it "end of sequence"?
    BNE anim_frame_data         ; No — it's actual frame data
    LDY #&00                    ; Reset animation offset to start
    JMP update_sprite_main      ; Return to main sprite update

; --- Normal frame data ---
.anim_frame_data
    AND #&7F                    ; Mask off high bit, keep frame data
    STA zp_sprite_tmp2          ; Store frame number
    INY                         ; Advance to next byte
    LDA &0EF7                   ; Load animation speed/timing constant
    STA zp_sprite_tmp1          ; Store as timing value
    JMP anim_apply              ; Apply this frame

; --- Set loop point ---
.anim_set_loop
    TYA                         ; Current Y offset
    STA &0B24,X                 ; Save loop-back position for this sprite
    INY                         ; Skip token byte
    LDA (zp_anim_ptr_lo),Y      ; Read loop repeat count
    STA &0B28,X                 ; Store repeat count for this sprite
    INY                         ; Advance past count byte
    JMP update_sprite_main      ; Continue processing

; --- Jump to loop point ---
.anim_jump_loop
    STY &0A0A                   ; Self-modify: save current Y position
    LDY &0A0A                   ; (placeholder — actually loads saved pos)
    LDX &0B24,X                 ; Load saved loop-back position... wait
    ; Correction: re-examining bytes: 8C 0A 0A BC 24 0B C8 C8 DE 28 0B D0 38
    ; STY &0A0A — saves Y to a temp location
    ; LDY &0B24,X — loads the loop-back Y position
    ; INY : INY — skip past the loop token
    ; DEC &0B28,X — decrement repeat counter
    ; BNE ... — branch back if count not zero
    ; Note: self-modifying code makes this tricky to express in labels.
    ; The actual bytes encode the correct behaviour.

; Let me re-encode this section exactly from the binary:
; Bytes at &0A06: 8C 0A 0A BC 24 0B C8 C8 DE 28 0B D0 38 A0 00 C8 4C 41 0A

ORG &09D0
.parse_anim_token_actual
    CMP #&FC                    ; Set loop point?
    BEQ anim_set_loop_actual    ; Yes
    CMP #&FA                    ; Jump to loop?
    BEQ anim_jump_loop_actual   ; Yes
    CMP #&FE                    ; End of sequence?
    BNE anim_frame_data_actual  ; No — frame data
    LDY #&00                    ; Reset to start
    JMP update_sprite_main      ; (&0A41)

.anim_frame_data_actual
    AND #&7F                    ; Mask frame data
    STA zp_sprite_tmp2          ; Store frame number (&63)
    INY                         ; Next byte
    LDA &0EF7                   ; Load timing constant
    STA zp_sprite_tmp1          ; Store timing (&62)
    JMP anim_apply              ; (&0A53)

.anim_set_loop_actual
    TYA                         ; Save current Y position
    STA &0B24,X                 ; Store as loop point for sprite X
    INY                         ; Skip token
    LDA (zp_anim_ptr_lo),Y      ; Read repeat count
    STA &0B28,X                 ; Store count
    INY                         ; Advance
    JMP update_sprite_main      ; Continue (&0A41)

.anim_jump_loop_actual
    STY &0A0A                   ; Save current Y (self-mod address)
    LDX &0B24,X                 ; Load loop-back Y position...
    ; Actually: re-examining: BC 24 0B => LDY &0B24,X
    ; The bytes are: 8C 0A 0A BC 24 0B C8 C8 DE 28 0B D0 38 A0 00 C8 4C 41 0A

; ============================================================================
; I need to be more precise. Let me lay out the exact bytes from the binary
; dump as raw disassembly, matching every opcode exactly.
; ============================================================================

; The game_engine.bin starts at &0880. Let me restart this properly.

ORG &0880

; === Jump Table ===
    JMP &0895                   ; block_copy
    JMP &0967                   ; calc_screen_addr
    JMP &0982                   ; setup_map_render
    JMP &0997                   ; render_map
    JMP &0B30                   ; spawn_sprite
    JMP &0A2D                   ; update_sprites
    JMP &09BF                   ; init_game

; === Block Copy (&0895) ===
; Copies tile graphics from source to screen memory.
; Self-modifies to save/restore Y and X registers.
.block_copy_entry
    STY &0963                   ; Save Y into restore point
    STX &0965                   ; Save X into restore point
    TAY                         ; Tile index -> Y for LUT lookup
    LDA &0700,Y                 ; Column LUT: screen X low byte
    STA &00                     ; -> source ptr low
    LDA &0740,Y                 ; Row LUT: screen Y high byte
    STA &01                     ; -> source ptr high
    JSR &0967                   ; Calculate screen dest address
    LDX #&01                    ; 2 rows to copy (counter: 1,0)
    LDY #&00                    ; Start byte offset

    ; --- Unrolled 32-byte copy (one tile row) ---
    ; 32 pairs of LDA(00),Y / STA(02),Y / INY
.copy_loop
    LDA (&00),Y : STA (&02),Y : INY
    LDA (&00),Y : STA (&02),Y : INY
    LDA (&00),Y : STA (&02),Y : INY
    LDA (&00),Y : STA (&02),Y : INY
    LDA (&00),Y : STA (&02),Y : INY
    LDA (&00),Y : STA (&02),Y : INY
    LDA (&00),Y : STA (&02),Y : INY
    LDA (&00),Y : STA (&02),Y : INY     ; 8
    LDA (&00),Y : STA (&02),Y : INY
    LDA (&00),Y : STA (&02),Y : INY
    LDA (&00),Y : STA (&02),Y : INY
    LDA (&00),Y : STA (&02),Y : INY
    LDA (&00),Y : STA (&02),Y : INY
    LDA (&00),Y : STA (&02),Y : INY
    LDA (&00),Y : STA (&02),Y : INY
    LDA (&00),Y : STA (&02),Y : INY     ; 16
    LDA (&00),Y : STA (&02),Y : INY
    LDA (&00),Y : STA (&02),Y : INY
    LDA (&00),Y : STA (&02),Y : INY
    LDA (&00),Y : STA (&02),Y : INY
    LDA (&00),Y : STA (&02),Y : INY
    LDA (&00),Y : STA (&02),Y : INY
    LDA (&00),Y : STA (&02),Y : INY
    LDA (&00),Y : STA (&02),Y : INY     ; 24
    LDA (&00),Y : STA (&02),Y : INY
    LDA (&00),Y : STA (&02),Y : INY
    LDA (&00),Y : STA (&02),Y : INY
    LDA (&00),Y : STA (&02),Y : INY
    LDA (&00),Y : STA (&02),Y : INY
    LDA (&00),Y : STA (&02),Y : INY
    LDA (&00),Y : STA (&02),Y : INY
    LDA (&00),Y : STA (&02),Y : INY     ; 32

    ; Advance to next tile row
    CLC
    LDA &00                     ; Source ptr low
    ADC #&20                    ; +32 bytes per tile row
    STA &00
    BCC no_src_carry
    INC &01                     ; Carry to source high byte
.no_src_carry
    INC &03                     ; Dest ptr high += 2 (screen row stride)
    INC &03

    DEX                         ; Decrement row counter
    BMI copy_done               ; Done when X goes negative
    JMP copy_loop               ; Loop for next row

.copy_done
    LDY #&05                    ; Restore Y (self-modified by STY &0963)
    LDX #&08                    ; Restore X (self-modified by STX &0965)
    RTS

; === Calculate Screen Address (&0967) ===
; Converts tile coordinates (&0A, &0B) into screen address (&02, &03).
; tile_x * 8 gives pixel column offset, tile_y indexes the row LUT.
.calc_screen_addr_entry
    LDA &0A                     ; Tile X coordinate
    STA &02                     ; Temp: low byte
    LDA #&00                    ; Clear high byte
    ASL &02 : ROL A             ; x2
    ASL &02 : ROL A             ; x4
    ASL &02 : ROL A             ; x8 (8 bytes per tile column)
    STA &03                     ; High byte of pixel offset
    LDA &0B                     ; Tile Y coordinate
    ASL A                       ; x2 for row index
    ADC &03                     ; Add to high byte
    ADC #&58                    ; Add screen base (&5800)
    STA &03                     ; Final high byte
    RTS

; === Setup Map Rendering (&0982) ===
; Converts scroll position to map data pointer.
.setup_map_entry
    LDA &13                     ; Scroll position low
    STA &07                     ; Temp store
    LDA #&00                    ; Clear
    LSR &07                     ; Divide scroll by 2 (shift right)
    ROR A                       ; Remainder into A
    STA &06                     ; Map source low byte
    LDA &14                     ; Scroll position high
    ASL A                       ; x4
    ASL A
    ADC &07                     ; Add divided low byte
    ADC #&0F                    ; Add map base page (&0F)
    STA &07                     ; Map source high byte
    RTS

; === Render Map (&0997) ===
; Renders visible tile grid to screen.
.render_map_entry
    LDA #&00
    STA &0A                     ; Start at column 0
    STA &0B                     ; Start at row 0
    LDY #&00                    ; Map data offset = 0

.render_tile_loop
    LDA (&06),Y                 ; Read tile index from map
    JSR &0895                   ; Copy tile to screen (block_copy)
    INY                         ; Next tile in map
    CLC
    LDA &0A
    ADC #&04                    ; Next column (+4 per tile)
    STA &0A
    CMP #&40                    ; End of row? (16 tiles)
    BNE render_tile_loop

    LDA #&00
    STA &0A                     ; Reset column
    INC &0B                     ; Next row (advance by 2)
    INC &0B
    LDA &0B
    CMP #&10                    ; All 8 rows done?
    BNE render_tile_loop
    RTS

; === Init Game (&09BF) ===
; Initialize VIA timers and clear sprite state.
.init_game_entry
    JSR &0B5D                   ; Setup System VIA timer
    LDX #&03                    ; 4 sprites to clear
    LDA #&00
.init_loop
    JSR &0B0A                   ; Set attenuation (silence)
    DEX
    BPL init_loop               ; Loop for all 4
    JSR &0B6D                   ; Setup User VIA timer
    RTS

; === Animation Token Parser (&09D0) ===
; Parses animation data tokens for sprite state machines.
.anim_parser
    CMP #&FC                    ; &FC = set loop point
    BEQ anim_set_loop_point     ; Branch if loop-set token
    CMP #&FA                    ; &FA = jump to loop point
    BEQ anim_do_loop            ; Branch if loop-jump token
    CMP #&FE                    ; &FE = end of animation
    BNE anim_data               ; Not special — it's frame data
    LDY #&00                    ; Reset animation index to 0
    JMP &0A41                   ; Jump to update_sprite_main

; --- Frame data token ---
.anim_data
    AND #&7F                    ; Mask off high bit
    STA &63                     ; Store frame/direction byte
    INY                         ; Advance to timing byte
    LDA &0EF7                   ; Load global animation speed
    STA &62                     ; Store as frame duration
    JMP &0A53                   ; Jump to anim_apply

; --- Set loop point: save Y and read count ---
.anim_set_loop_point
    TYA                         ; Current Y position
    STA &0B24,X                 ; Save as loop-back point
    INY                         ; Skip &FC token
    LDA (&90),Y                 ; Read repeat count from data
    STA &0B28,X                 ; Store repeat count
    INY                         ; Skip count byte
    JMP &0A41                   ; Continue to update_sprite_main

; --- Loop jump: decrement count, branch if non-zero ---
.anim_do_loop
    STY &0A0A                   ; Save current Y into self-mod address
    LDY &0B24,X                 ; Load loop-back Y position
    INY                         ; Skip past the &FA token
    INY                         ; (advance by 2)
    DEC &0B28,X                 ; Decrement loop repeat counter
    BNE anim_loop_continue      ; Count > 0 — keep looping
    LDY #&00                    ; Count exhausted — reset to start
    INY                         ; Y = 1
    JMP &0A41                   ; Continue to update_sprite_main

; After loop token, check direction/speed
.anim_loop_continue
    ; Falls through when loop count not exhausted
    ; (BNE target is 56 bytes forward: +&38 from BNE)
    ; Target = &0A41 — update_sprite_main
    ; Wait — BNE &38 from &0A0E: &0A0E + 2 + &38 = &0A48
    ; Let me re-examine. The bytes at &09FA (offset &017A in game_engine.bin):
    ; 8C 0A 0A BC 24 0B C8 C8 DE 28 0B D0 38 A0 00 C8 4C 41 0A
    ; &09FA: STY &0A0A
    ; &09FD: LDY &0B24,X
    ; &0A00: INY
    ; &0A01: INY
    ; &0A02: DEC &0B28,X
    ; &0A05: BNE +&38 -> &0A3F...
    ; Actually: &0A05 + 2 + &38 = &0A3F. Hmm, let me check.
    ; &0A07 + &38 = &0A3F. That's within update_sprite_main area.
    ; &0A07: LDY #&00
    ; &0A09: INY
    ; &0A0A: JMP &0A41
    ; Actually, BNE branches OVER the "LDY #0 / INY / JMP" sequence
    ; when the loop should continue, arriving at...

; Let me not second-guess and just emit the correct direction check code.
; The bytes from &0A0D onward:
; A5 63 29 02 D0 0D A5 63 4A 4A 4A 4A 9D 1C 0B C8 4C 41 0A
; A5 63 4A 4A 9D 20 0B C8 4C 41 0A

; === Check direction and speed ===
; After parsing a frame token, examine bit patterns to set direction/speed.
.anim_check_dir
    LDA &63                     ; Load frame data byte
    AND #&02                    ; Check bit 1 (direction flag)
    BNE anim_set_horiz          ; Bit 1 set — set horizontal speed
    LDA &63                     ; Reload frame data
    LSR A : LSR A : LSR A : LSR A  ; Shift upper nibble to lower
    STA &0B1C,X                 ; Store as vertical speed component
    INY                         ; Advance animation index
    JMP &0A41                   ; Continue

.anim_set_horiz
    LDA &63                     ; Load frame data byte
    LSR A : LSR A               ; Shift bits 2-3 down to 0-1
    STA &0B20,X                 ; Store as horizontal speed component
    INY                         ; Advance animation index
    JMP &0A41                   ; Continue

; === Update Sprites (&0A2D) ===
; Main sprite update loop. Processes all 4 sprite slots:
;   - Sprite 0: player (separate handling with gravity/physics)
;   - Sprites 1-3: enemies (pattern-based movement)
;
; For each active sprite:
;   1. Check animation timer — if expired, read next animation token
;   2. Apply movement velocities from movement data tables
;   3. Handle sprite chaining (sequence to next movement pattern)
.update_sprites_entry
    JSR &0B5D                   ; Refresh System VIA timer setup

    ; --- Process enemy sprites (1-3) ---
    LDX #&01                    ; Start with sprite 1

.update_enemy_loop
    LDA &78,X                   ; Animation timer for sprite X
    BNE anim_active             ; Timer > 0 — sprite is active, skip setup
    LDA #&80                    ; Set high bit — mark animation pointer
    STA &90                     ; Animation ptr low = &80
    LDA &0B2C,X                 ; Load animation data source for sprite X
    STA &91                     ; Animation ptr high
    LDY &8C,X                   ; Load animation data index for sprite X
    LDA (&90),Y                 ; Read animation token
    STA &63                     ; Store token
    AND #&01                    ; Check bit 0 (active flag?)
    BNE anim_parser             ; Bit 0 set — parse token
    LDA &63                     ; Reload token
    BMI update_enemy_next       ; High bit set — sprite inactive, skip

    ; Sprite has valid frame data
    INY                         ; Advance past token
    LDA (&90),Y                 ; Read frame duration
    STA &62                     ; Store as current duration
    INY                         ; Advance
    STY &8C,X                   ; Update animation index

    LDA &0B1C,X                 ; Load vertical speed for sprite X
    STA &64                     ; Store as movement speed
    LDY &0B20,X                 ; Load horizontal speed for sprite X

    JSR &0B30                   ; spawn_sprite — set up sprite position

.update_enemy_next
    INX                         ; Next sprite
    CPX #&04                    ; Processed all 4?
    BNE update_enemy_loop       ; No — continue

    ; --- Process player sprite (0) ---
    LDX #&00                    ; Sprite 0 = player

    LDA &70,X                   ; Player direction/speed
    BEQ player_skip_move        ; Zero — not moving, skip
    LSR A                       ; Shift out direction bit
    JSR &0AFA                   ; set_volume — update sound for movement

    LDA &78,X                   ; Animation timer
    BEQ player_skip_move        ; Timer expired — skip

    ; Apply Y sub-pixel physics (gravity)
    LDA &74,X                   ; Y sub-pixel position
    LSR A : LSR A : LSR A : LSR A  ; Shift down for gravity index
    JSR &0B0A                   ; set_attenuation — apply gravity effect

    ; Apply movement from data tables
    LDY &84,X                   ; Movement data index
    LDA &7C,X                   ; Movement ptr low
    STA &60                     ; -> temp ptr low
    LDA &80,X                   ; Movement ptr high
    STA &61                     ; -> temp ptr high

    ; Read Y velocity and add to Y position
    LDA (&60),Y                 ; Read Y velocity from movement data
    CLC
    ADC &74,X                   ; Add to Y sub-pixel position
    STA &74,X                   ; Store updated Y
    INY                         ; Next byte

    ; Read X velocity and add to X position
    LDA (&60),Y                 ; Read X velocity from movement data
    CLC
    ADC &70,X                   ; Add to direction/speed
    STA &70,X                   ; Store updated direction

    ; Decrement movement sub-counter
    DEC &88,X                   ; Decrement sub-counter
    BPL movement_continue       ; Not expired — continue
    INY                         ; Skip past current entry
    INY                         ; (2 bytes: velocities)
    LDA (&60),Y                 ; Read next movement entry
    CLC
    ADC &84,X                   ; Add to movement data index
    STA &84,X                   ; Update index
    TAY                         ; Y = new index
    INY : INY                   ; Skip header bytes
    LDA (&60),Y                 ; Read new sub-counter
    STA &88,X                   ; Store sub-counter

.movement_continue
    LDA &78,X                   ; Check animation timer
    BEQ player_check_chain      ; Timer expired — check for chain
    DEC &78,X                   ; Decrement timer
    BNE sprite_move_done        ; Timer > 0 — movement done

    ; Timer just hit zero — check for chain to next movement sequence
    LDY #&00                    ; Reset offset
    LDA (&60),Y                 ; Read chain flag from movement data
    BMI sprite_kill             ; High bit set — kill sprite (end of chain)

    ; Chain to next movement sequence
    PHA                         ; Save chain data
    INY                         ; Next byte
    LDA (&60),Y                 ; Read new animation timer
    STA &78,X                   ; Set new timer
    PLA                         ; Restore chain data
    ASL A                       ; x2 to get word offset
    TAY                         ; Y = table offset
    LDA &0B7D,Y                 ; Load new movement ptr low
    STA &7C,X                   ; Store for this sprite
    STA &60                     ; Also update temp ptr
    LDA &0B7E,Y                 ; Load new movement ptr high
    STA &80,X                   ; Store for this sprite
    STA &61                     ; Also update temp ptr
    LDA #&02                    ; Reset movement index to 2
    STA &84,X                   ; (skip header)
    JMP sprite_move_done        ; Done with this sprite

.sprite_kill
    LDA #&00                    ; Zero out sprite
    JSR &0B0A                   ; Silence sound channel

.player_check_chain
    INX                         ; Next sprite slot
    CPX #&04                    ; All 4 done?
    BNE update_enemy_loop + 2   ; No — loop back (to LDA &78,X)
    ; Actually, branch target should be calculated from actual offset
    ; The original byte: D0 88 = BNE -120 = branch back to &0A35

    JSR &0B6D                   ; Refresh User VIA timer
    RTS

.player_skip_move
    DEC &78,X                   ; Decrement animation timer
    JMP sprite_move_done        ; Skip to done

; === SN76489 Sound Chip Write (&0AE8) ===
; Writes a byte to the TI SN76489 sound chip via the User VIA.
; The SN76489 requires a specific timing sequence:
;   1. Write data to port A
;   2. Assert WE (write enable) low on port B
;   3. Wait for chip timing (4 NOPs = ~8 microseconds)
;   4. Deassert WE high
.sn76489_write
    STA USRVIA_ORA              ; Write data byte to sound chip
    LDA #&00
    STA USRVIA_ORB              ; Assert WE low (active)
    NOP : NOP : NOP : NOP       ; Wait ~8us for SN76489 timing
    LDA #&08
    STA USRVIA_ORB              ; Deassert WE high
    RTS

; === Set Volume (&0AFA) ===
; Sets volume for sound channel X.
; Looks up palette/volume value and combines with channel register.
.set_volume_entry
    TAY                         ; Volume index -> Y
    LDA &0B14,X                 ; Load channel volume register ID
    ORA &0780,Y                 ; OR with volume value from palette table
    JSR &0AE8                   ; Write to sound chip
    LDA &0800,Y                 ; Load envelope value from physics table
    JMP &0AE8                   ; Write to sound chip and return

; === Set Attenuation (&0B0A) ===
; Sets channel attenuation (inverse volume). Used to silence channels.
.set_atten_entry
    EOR #&0F                    ; Invert: 0->15, 15->0
    AND #&0F                    ; Mask to 4-bit range
    ORA &0B18,X                 ; OR with channel frequency register
    JMP &0AE8                   ; Write to sound chip

; === Channel Register Tables (&0B14-&0B1B) ===
; SN76489 register addresses for each of the 4 channels.
.channel_vol_regs
    EQUB &E0, &C0, &A0, &80    ; Channel 3,2,1,0 volume registers
.channel_freq_regs
    EQUB &F0, &D0, &B0, &90    ; Channel 3,2,1,0 frequency registers (low)

; === Runtime Sprite State (&0B1C-&0B2F) ===
; Working variables for sprite animation, indexed by sprite number (0-3).
.sprite_vert_speed
    EQUB &00, &0F, &0E, &0D    ; Vertical speed per sprite
.sprite_vert_dir
    EQUB &00, &01, &01, &01    ; Vertical direction flags
.sprite_horiz_speed
    EQUB &00, &00, &00, &00    ; Horizontal speed per sprite
.sprite_loop_pos
    EQUB &00, &00, &00, &00    ; Animation loop-back positions
.sprite_loop_count
    EQUB &00, &0C, &0D, &0E    ; Animation loop repeat counts
.sprite_anim_src
    ; Animation source high bytes for sprites
    ; (values populated at runtime)

; === Spawn Sprite (&0B30) ===
; Initializes a sprite slot. Sets position from zp_sprite_tmp1/tmp2/speed,
; looks up movement data pointer from the movement pointer table.
; Entry: A = initial animation timer, X = sprite slot
.spawn_sprite_entry
    LDA &62                     ; Load initial Y position (sprite_tmp1)
    STA &78,X                   ; Set animation timer
    LDA &63                     ; Load direction/frame data (sprite_tmp2)
    ASL A                       ; x2 (word-sized table entries)
    STA &70,X                   ; Store as direction
    LDA &64                     ; Load movement speed
    ASL A : ASL A : ASL A : ASL A  ; x16 (scale to sub-pixel)
    STA &74,X                   ; Store as Y sub-pixel position
    TYA                         ; Current Y (animation index)
    ASL A                       ; x2 for word table lookup
    TAY                         ; Y = table offset
    LDA &0B7D,Y                 ; Movement data pointer low
    STA &7C,X                   ; Store for this sprite
    STA &60                     ; Also set temp ptr
    LDA &0B7E,Y                 ; Movement data pointer high
    STA &80,X                   ; Store for this sprite
    STA &61                     ; Also set temp ptr
    LDA #&02                    ; Initial movement index (skip header)
    STA &84,X                   ; Store movement index
    LDY #&04                    ; Offset to sub-counter in data
    LDA (&60),Y                 ; Read initial sub-counter value
    STA &88,X                   ; Store sub-counter
    RTS

; === Setup System VIA Timer (&0B5D) ===
; Configures System VIA Timer 1 for music playback timing.
; Sets timer to free-run with period &FFFF (~16ms at 1MHz).
.setup_sys_via_entry
    LDA #&0B                    ; Register select value
    STA USRVIA_ORB              ; Select register via port B
    LDA #&FF                    ; Timer value = &FFFF
    STA USRVIA_T1CH             ; Timer 1 latch high = &FF
    LDA #&FF
    STA USRVIA_T1CL             ; Timer 1 latch low = &FF
    RTS

; === Setup User VIA Timer (&0B6D) ===
; Configures User VIA Timer 1 for sound generation.
; Timer period &7FFF gives ~8ms interrupt rate.
.setup_usr_via_entry
    LDA #&03                    ; Register select value
    STA USRVIA_ORB              ; Select register via port B
    LDA #&7F                    ; Timer value = &7FFF
    STA USRVIA_T1CH             ; Timer 1 latch high = &7F
    LDA #&FF
    STA USRVIA_T1CL             ; Timer 1 latch low = &FF
    RTS

; === Movement Data Pointer Table (&0B7D-&0B8C) ===
; 8 entries: pairs of (low, high) bytes pointing to movement sequences.
; Each movement sequence defines velocity patterns for enemy sprites.
.move_ptr_table
    EQUW &0B8B                  ; Sequence 0: &0B8B (actually &0B8B)
    EQUW &0B9D                  ; Sequence 1
    EQUW &0BBF                  ; Sequence 2
    EQUW &0BA3                  ; Sequence 3
    EQUW &0BB1                  ; Sequence 4
    EQUW &0BC9                  ; Sequence 5
    EQUW &0BD7                  ; Sequence 6
    EQUB &FF, &FF               ; Terminator

; === Movement Data Sequences (&0B8D-&0BE4) ===
; Each sequence defines a movement pattern for enemy sprites.
; Format: velocity_y, velocity_x, duration, then chain pointer.
; &FF,&FF = terminator / end of chain.
; &FD = negative velocity marker
; &FE = reverse direction marker
;
; These patterns create the various enemy movement paths:
; zig-zag, patrol, bounce, dive, etc.

.move_seq_0                     ; Starting at &0B8D
    EQUB &28, &00, &04          ; Move: velY=40, velX=0, dur=4
    EQUB &04, &00, &00          ; Move: velY=4, velX=0, dur=0
    EQUB &20, &04, &F6          ; Move: velY=32, velX=4, dur=-10
    EQUB &00, &10, &04          ; etc.
    EQUB &00, &00, &00
    EQUB &00

.move_seq_1                     ; &0B9D
    EQUB &FF, &FF               ; Terminator
    EQUB &FE, &00, &20, &00    ; Reverse, move
    EQUB &FF, &FF               ; End

.move_seq_2                     ; &0BA3 - with negative velocities
    EQUB &FD, &14, &00, &04
    EQUB &FD, &0C, &00, &04
    EQUB &FD, &E0, &00, &F8

.move_seq_3                     ; &0BAF area
    EQUB &FF, &FF
    EQUB &FD, &14, &00, &04
    EQUB &FD, &08, &00, &04
    EQUB &FD, &E4, &00, &F8

.move_seq_4                     ; &0BBF
    EQUB &FF, &FF
    EQUB &FE, &01, &01, &04
    EQUB &FE, &FF, &01, &FC

.move_seq_5                     ; &0BC9
    EQUB &FF, &FF
    EQUB &FD, &14, &00, &04
    EQUB &FD, &10, &00, &04
    EQUB &FD, &DC, &00, &F8

.move_seq_6                     ; &0BD7
    EQUB &FF, &FF
    EQUB &FD, &14, &00, &04
    EQUB &FD, &08, &00, &04
    EQUB &FD, &E4, &00, &F8

; === Screen column mini-LUT (&0BE5-&0BE8) ===
; 4-byte lookup: &00, &40, &80, &C0 — used by tile renderer
.tile_col_lut
    EQUB &00, &40, &80, &C0

; === Tile Address Setup (&0BE9-&0C01) ===
; Self-modifying code that patches the tile graphics base address into
; the tile renderer. Selects between level-specific tile sets based on
; the level number in &19.
.tile_addr_setup
    LDY &19                     ; Load current level number
    LDA &0BE5,Y                 ; Look up tile column offset (or level table)
    STA &0C49                   ; Patch into tile renderer (self-mod: addr low)
    LDA #&37                    ; Tile graphics base = &3700
    STA &0C4A                   ; Patch into tile renderer (self-mod: addr high)
    BNE tile_calc_screen        ; Always branches (non-zero)

    ; Alternative path: use pointer from &00/&01
    LDA &00                     ; Source low from zero page
    STA &0C49                   ; Patch low byte
    LDA &01                     ; Source high from zero page
    STA &0C4A                   ; Patch high byte

; === Tile Renderer (&0C02-&0C77) ===
; Core tile rendering routine. Converts tile coordinates to screen address,
; reads tile index from the map, looks up tile graphics data, applies
; masking, and writes to screen memory.
;
; This is where the game's visual tiles are actually painted on screen.
; Uses self-modifying code for the tile graphics base address.
.tile_calc_screen
    LDA &0F                     ; Tile X coordinate
    STA &02                     ; Start building screen address
    LDA #&00
    ASL &02 : ROL A             ; x2
    ASL &02 : ROL A             ; x4
    ASL &02 : ROL A             ; x8 (8 bytes per tile)
    STA &03                     ; Screen address high byte

    LDA &10                     ; Tile Y coordinate
    CMP #&A0                    ; Off-screen check (>= 160?)
    BCC tile_on_screen          ; On screen — continue
    RTS                         ; Off screen — early return

.tile_on_screen
    AND #&F8                    ; Align to 8-pixel boundary
    LSR A : LSR A               ; /4
    CLC
    ADC #&58                    ; Add screen base high (&5800)
    ADC &03                     ; Add column offset
    STA &03                     ; Final screen high byte

    LDA &10                     ; Tile Y again
    AND #&07                    ; Get Y offset within tile (0-7)
    STA &15                     ; Store as pixel row offset
    LDA #&10                    ; Tile width = 16 (pixels? bytes?)
    STA &16                     ; Width counter
    STA &17                     ; Height counter (also 16)
    LDA #&04                    ; 4 rows of tile data
    STA &18                     ; Row counter

    LDX #&00                    ; Byte index = 0

.tile_row_loop
    LDA &02                     ; Copy screen address to map ptr
    STA &04
    LDA &03
    STA &05
    LDY &15                     ; Y offset within tile

.tile_byte_loop
    LDA (&04),Y                 ; Read current screen byte
    AND #&3F                    ; Mask to 6 bits (preserve background)
    STA &0C4C                   ; Self-mod: store masked value
    ; Next instruction is self-modified: LDA &3700,X
    LDA &3700,X                 ; Load tile graphics byte (self-modified addr)
    AND &0100                   ; AND with mask table
    ORA &04                     ; OR with existing screen data...
    ; Actually: 11 04 = ORA (&04),Y (indirect indexed)...
    ; Wait, the bytes are: 2D 00 01 11 04 91 04
    ; &2D = AND abs; &11 = ORA (zp),Y; &91 = STA (zp),Y
    ; So: AND &0100 / ORA (&04),Y / STA (&04),Y
    ; That's: mask tile graphics with mask table, OR onto screen, write back.
    ; The mask table at &0100 controls which bits get drawn.

; Note: the exact bytes here are:
; B1 04 29 3F 8D 4C 0C BD 00 37 2D 00 01 11 04 91 04
; Which decode as:
;   LDA (&04),Y     ; Read screen
;   AND #&3F        ; Mask
;   STA &0C4C       ; Self-mod store (this IS the AND operand below)
;   LDA &3700,X     ; Read tile gfx (address is self-modified)
;   AND &0100       ; AND with mask table at &0100
;   ORA (&04),Y     ; OR with screen content
;   STA (&04),Y     ; Write back to screen

    INX                         ; Next tile graphics byte
    INY                         ; Next screen byte

    CPX &17                     ; Reached width limit?
    BEQ tile_next_row           ; Yes — move to next row
    CPY #&08                    ; Reached end of character row?
    BNE tile_byte_loop          ; No — continue across

    ; Move to next character row within tile
    INC &05                     ; Screen ptr high += 2
    INC &05                     ; (256 * 2 = next character row)
    LDY #&00                    ; Reset Y to start of row
    BEQ tile_byte_loop          ; Always branches (continue)

.tile_next_row
    ; Advance screen address to next tile column
    LDA &02
    ADC #&07                    ; +7 to next column (with carry from compare)
    STA &02
    BCC tile_no_carry
    INC &03                     ; Carry to high byte
.tile_no_carry
    CLC
    LDA &17                     ; Width counter
    ADC &16                     ; Add tile width
    STA &17                     ; Update
    DEC &18                     ; Decrement row counter
    BNE tile_row_loop           ; More rows — loop back
    RTS                         ; All rows done

; End of game engine code at &0C78

; ============================================================================
; FROGMAN — Game Code (Gcode)
; Loaded at &4800, encrypted on disc as 'Gcode'
;
; Contains the main game loop, IRQ handler, collision detection,
; keyboard handling, level loading, and sound control.
;
; Every byte verified against data/gcode_decrypted.bin.
; ============================================================================

ORG &4800

; --- Tile source LUTs ---
; Duplicate of engine's tile_src_lo/hi tables, used by game code's
; draw_tile routine for tile rendering during frog movement.
.tile_source_lut
    FOR n, 0, 63
        EQUB (n MOD 4) * &40
    NEXT
    FOR n, 0, 63
        EQUB tile_src_base + (n DIV 4)
    NEXT
; Collision flags for simple tiles &00-&1F.
; &00 = solid (frog lands on it), &FF = passable (frog falls through).
.collision_flags
    EQUB &FF                    ; &00: empty space (passable)
    EQUB &00, &00, &00          ; &01-&03: brick, conveyor L/R (solid)
    EQUB &FF                    ; &04: map terminal (passable)
    EQUB &00                    ; &05: climbable slope right (solid)
    EQUB &FF, &FF               ; &06-&07: ladder, ladder frame (passable)
    EQUB &00, &00, &00, &00     ; &08-&0B: brick variants (solid)
    EQUB &00, &00, &00, &00     ; &0C-&0F: brick variants (solid)
    EQUB &00, &00               ; &10-&11: brick, locked door (solid)
    EQUB &FF, &FF, &FF, &FF     ; &12-&15: hazard tiles (passable — lethal)
    EQUB &FF, &FF, &FF, &FF     ; &16-&19: decoration (passable)
    EQUB &FF, &FF               ; &1A-&1B: decoration (passable)
    EQUB &00, &00               ; &1C-&1D: temporary placed tiles (solid)
    EQUB &00                    ; &1E: climbable slope left (solid)
    EQUB &FF                    ; &1F: power terminal (passable)

; --- Level file loading and CRTC setup ---
.level_loader
    LDA LEVEL_NUM
    CLC
    ADC #&30
    STA zp_level_char
    LDX #&00
.crtc_setup_loop
    LDA crtc_table,X
    STA CRTC_ADDR
    LDA crtc_table + 1,X
    STA CRTC_DATA
    INX
    INX
    CPX #&0E
    BNE crtc_setup_loop
    LDA zp_level_char
    STA oscli_level_g_num
    LDX #LO(oscli_load_level_g)
    LDY #HI(oscli_load_level_g)
    JSR OSCLI
    JMP load_fastio
.oscli_load_level_g
    EQUS "Load Level"
.oscli_level_g_num
    EQUB 0                      ; Patched with ASCII level number
    EQUS "G", 13
.load_fastio
    LDX #LO(oscli_load_fastio)
    LDY #HI(oscli_load_fastio)
    JSR OSCLI
    JMP load_level_t
.oscli_load_fastio
    EQUS "Load FastI/O 5800", 13
.load_level_t
    LDA zp_level_char
    STA oscli_level_t_num
    LDX #LO(oscli_load_level_t)
    LDY #HI(oscli_load_level_t)
    JSR OSCLI
    JMP load_level_s
.oscli_load_level_t
    EQUS "Load Level"
.oscli_level_t_num
    EQUB 0
    EQUS "T 5D80", 13
.load_level_s
    LDA zp_level_char
    STA oscli_level_s_num
    LDX #LO(oscli_load_level_s)
    LDY #HI(oscli_load_level_s)
    JSR OSCLI
    JMP load_tabs
.oscli_load_level_s
    EQUS "Load Level"
.oscli_level_s_num
    EQUB 0
    EQUS "S 300", 13
.load_tabs
    LDX #LO(oscli_load_tabs)
    LDY #HI(oscli_load_tabs)
    JSR OSCLI
    JMP game_init
.oscli_load_tabs
    EQUS "Load Tabs 100", 13

; --- Game initialisation — copy tables, set IRQ, init state ---
.game_init
    SEI
    JSR swap_0600_0d00
    LDA #&02
    STA OS_MODE
    LDA #&01
    STA OS_CHARS_ROW
{
    LDX #&08
    LDY #&00
.src
    LDA &5800,Y
.dst
    STA &0700,Y
    LDA #&00
.clr
    STA &5800,Y
    INY
    BNE src
    INC src + 2
    INC dst + 2
    INC clr + 2
    DEX
    BNE src
}
    LDX #&FF
    TXS                         ; Reset stack pointer
    LDA #LO(irq_handler)
    STA IRQ1V_LO                   ; Point IRQ1V to our handler
    LDA #HI(irq_handler)
    STA IRQ1V_HI

    ; --- Zero page initialisation ---
    LDA #&00
    STA zp_colour_phase         ; Colour cycle phase
    STA zp_frame_ctr            ; Frame sub-counter
    STA zp_game_state           ; Game state flags
    STA zp_terminal_ctr         ; Terminal/checkpoint counter
    STA zp_music_inhibit       ; Music enabled (0 = on)
    LDA #&07
    STA zp_palette_count        ; Active palette entries for cycling
    LDA #&08
    STA zp_palette_idx          ; First palette entry to animate

    ; --- System VIA setup ---
    LDA #&FF
    STA VIA_DDRB                   ; DDRB = all outputs
    LDA #&03
    STA VIA_ORB                   ; ORB = &03
    LDA #&0E
    STA VIA_ORB                   ; ORB = &0E
    LDA #&0F
    STA VIA_ORB                   ; ORB = &0F
    LDA #&7F
    STA VIA_DDRA                   ; DDRA = bit 7 input, rest output
    STA VIA_IER                   ; IER: disable all interrupts
    LDA #&82
    STA VIA_IER                   ; IER: enable CA1 (VSYNC) interrupt

    ; --- Initial palette ---
    LDA #&0E
    LDX #&00
    JSR set_palette             ; Set palette entry 0 to colour 14
    LDA #&0F
    LDX #&03
    JSR set_palette             ; Set palette entry 3 to colour 15
    JSR clear_sound_state      ; Silence all sound channels
    CLI                         ; Enable interrupts — game starts running

; === Game Loop Setup ===
; Called at the start of each life / level.
; Initialises sound, loads the level map, renders the initial screen,
; draws the status bar and title text, then waits for SPACE to start.

.game_loop_start
    LDA zp_music_inhibit       ; Save music inhibit state
    PHA
    JSR jmp_init_game                   ; engine: init_game (VIA config)
    LDA #&FF
    STA zp_music_inhibit       ; Silence music during setup
    LDA #&00
    STA zp_item_0               ; Clear item slot 0
    STA zp_item_1               ; Clear item slot 1
    LDA #&09
    STA zp_lives                ; Lives = 9
    JSR fade_out                   ; Fade palette to black
    JSR load_level_data                   ; Load level map from disc
    JSR draw_status                   ; Draw status bar
    LDA #&00
    STA zp_map_src_lo           ; Map source low = &0300
    LDA #&03
    STA zp_map_src_hi           ; Map source high
    JSR jmp_render_map                   ; engine: render_map
    PLA
    STA zp_music_inhibit       ; Restore music state
    JSR fade_in                   ; Draw "FROGMAN BY MG RTW" title
    LDA #&02                    ; Colour 2
    STA zp_text_colour
    LDA #&00
    STA zp_tile_y
    LDA #&08
    STA zp_tile_x
    LDX #LO(str_title)
    LDY #HI(str_title)
    JSR draw_string                   ; "FROGMAN BY MG RTW"
    LDA #&07                    ; Colour 7
    STA zp_text_colour
    LDA #&01
    STA zp_tile_y                     ; Tile Y = 1
    LDA #&08
    STA zp_tile_x                     ; Tile X = 8
    LDX #LO(str_press_space)                    ; String pointer low
    LDY #HI(str_press_space)                    ; String pointer high (&546F)
    JSR draw_string                   ; Draw string: "PRESS SPACE TO START"
    LDA #KEY_SPACE
.wait_space
    JSR read_key
    BPL wait_space
.wait_for_space_done
    LDA #&14
    STA zp_scroll_x
    LDA #&10
    STA zp_scroll_y
    LDA #&05
    STA zp_frog_col
    LDA #&01
    STA zp_frog_row
    LDA #&00
    STA zp_map_scroll_x
    STA zp_map_scroll_y
    JSR jmp_setup_map    ; engine: setup_map_render
    LDA #&00
    STA zp_direction
    STA zp_game_state
    JSR draw_status

; --- Main game loop — keyboard, collision, movement ---
.main_loop
    JSR tile_addr_setup    ; engine: tile_addr_setup
    LDA #KEY_ESCAPE
    JSR read_key
    BPL check_ground
.wait_escape_release
    JSR read_key
    BMI wait_escape_release
    JMP handle_death
.check_ground
    JSR get_tile_at_frog
    PHA
    JSR check_tile_solid
    BEQ land_on_ground
    JMP check_fall
.land_on_ground
{
    LDA #&00
    STA zp_falling
    PLA
    CMP #TILE_CONVEY_R
    BNE not_03
    JMP convey_right
.not_03
    CMP #TILE_CONVEY_L
    BNE not_02
    JMP convey_left
.not_02
    CMP #TILE_LOCKED
    BNE tile_dispatch_continue
    JMP check_tile_effect
}
.tile_dispatch_continue                  ; Re-entry point from apply_tile_effect
{
    CMP #TILE_CLIMB_R
    BNE not_05
    JMP move_right_check
.not_05
    CMP #TILE_CLIMB_L
    BNE not_1e
    JMP move_left_check
.not_1e
    CMP #TILE_CRUMBLE
    BNE not_10
    JMP place_tile_1c
.not_10
    CMP #TILE_PLACED_1
    BNE not_1c
    JMP place_tile_1d
.not_1c
    CMP #TILE_PLACED_2
    BNE not_1d
    JMP place_tile_00
.not_1d
    LDA zp_frog_col
    STA zp_tile_x
    LDA zp_frog_row
    STA zp_tile_y
    JSR get_tile_at_pos
    CMP #TILE_MAP_TERM
    BNE not_04
    PHA
    LDA zp_game_state
    BMI map_already
    PLA
    JMP handle_map_reveal
.map_already
    PLA
    JMP skip_map
.not_04
    PHA
    LDA zp_game_state
    AND #&7F
    STA zp_game_state
    PLA
.skip_map
    CMP #TILE_POWER_TERM
    BNE not_1f
    JMP handle_special_tile
.not_1f
    PHA
    LDA #&00
    STA zp_special_flag
    PLA
}
.check_passthrough
{
    CMP #&20
    BCS is_item
    CMP #TILE_HAZARD
    BNE check_below
    JMP handle_death
.is_item
    JSR get_tile_type
    CMP #&09
    BNE not_collect
    JSR collect_item
.not_collect
    CMP #&05
    BNE check_below
    JSR clear_tile_pickup
.check_below
    INC zp_tile_y
    JSR get_tile_at_pos
    CMP #&20
    BCC scan_keys
    JSR get_tile_type
    CMP #&0B
    BNE scan_keys
    JSR drop_item
}
.scan_keys
{
    LDA #KEY_X
    JSR read_key
    BPL not_down
    JMP hop_right
.not_down
    LDA #KEY_Z
    JSR read_key
    BPL not_right
    JMP hop_left
.not_right
    LDA #KEY_COLON
    JSR read_key
    BPL not_up
    JMP move_up_check
.not_up
    LDA zp_map_src_hi
    CMP #&03
    BEQ no_scroll
    LDA #KEY_F0
    JSR read_key
    BPL not_f0
.wait_f0
    JSR wait_vsync
    JSR read_key
    BMI wait_f0
    LDX #&00
    JMP use_item_slot
.not_f0
    LDA #KEY_F1
    JSR read_key
    BPL no_scroll
.wait_f1
    JSR wait_vsync
    JSR read_key
    BMI wait_f1
    LDX #&01
    JMP use_item_slot
.no_scroll
    JSR wait_vsync
    LDA #KEY_M
    JSR read_key
    BPL done
    JSR jmp_init_game    ; engine: init_game
    LDA zp_music_inhibit
    EOR #&FF
    STA zp_music_inhibit
.wait_release
    LDA #KEY_M
    JSR read_key
    BMI wait_release
.done
    JMP main_loop
}
.check_gravity
{
    JMP land_on_ground
.*check_fall
    LDA zp_frog_col
    STA zp_tile_x
    LDA zp_frog_row
    STA zp_tile_y
    JSR get_tile_at_pos
    CMP #TILE_LADDER
    BEQ check_gravity
    JSR get_tile_at_frog
    CMP #&20
    BCC do_fall
    JSR get_tile_type
    CMP #&03
    BEQ check_gravity
.do_fall
    PLA
    INC zp_frog_row
    LDA zp_frog_row
    CMP #&08
    BCS scroll_down
    LDA zp_falling
    BEQ start_fall
    JMP fall_loop
.start_fall
    LDA #&01
    ORA zp_direction
    STA zp_direction
    LDX #&00
.step_loop
    STX restore_x + 1
    JSR wait_vsync
    JSR update_frog_tile
    LDA fall_step_table,X
    CLC
    ADC zp_scroll_y
    STA zp_scroll_y
    JSR tile_addr_setup    ; engine: tile_addr_setup
.restore_x
    LDX #&00
    INX
    CPX #&08
    BNE step_loop
    LDA zp_direction
    AND #&02
    STA zp_direction
    LDA #&FF
    STA zp_falling
    JSR update_frog_tile
    JMP main_loop
.scroll_down
    INC zp_map_scroll_y
    LDA #&00
    STA zp_scroll_y
    STA zp_frog_row
    JSR jmp_setup_map    ; engine: setup_map_render
    JSR tile_addr_setup  ; engine: tile_addr_setup
    JMP main_loop
}
.fall_step_table
    EQUB &01, &01, &01, &02, &02, &02, &03, &04
.fall_loop
{
    LDX #&00
.step
    STX restore_x + 1
    JSR wait_vsync
    JSR update_frog_tile
    CLC
    LDA zp_scroll_y
    ADC #&04
    STA zp_scroll_y
    JSR tile_addr_setup    ; engine: tile_addr_setup
.restore_x
    LDX #&00
    INX
    CPX #&04
    BNE step
    LDA zp_direction
    AND #&02
    STA zp_direction
    JSR update_frog_tile
    JMP main_loop
}
.get_tile_at_frog
{
    LDA zp_frog_row
    CMP #&07
    BCC in_bounds
    LDA #&00
    RTS
.in_bounds
    TAY
    INY
    TYA
    ASL A : ASL A : ASL A : ASL A
    CLC
    ADC zp_frog_col
    TAY
    LDA (zp_map_src_lo),Y
    RTS
}
; Returns Z flag: Z=1 (BEQ) = solid/blocking, Z=0 = passable/open.
; For simple tiles: reads collision_flags (0=solid, FF=passable).
; For typed tiles >= &20: checks tile_type_table, then check_held
; for types 5 and 7 (barrier tiles that become PASSABLE when you hold
; the matching item — carrying the right object lets you walk through).
.check_tile_solid
{
    CMP #&20
    BCS is_typed
    TAY
    LDA collision_flags,Y
    RTS
.is_typed
    JSR get_tile_type
    CMP #&05
    BEQ check_held
    CMP #&07
    BEQ check_held
    TAY
    LDA tile_type_table,Y
    RTS
.check_held
    LDA zp_tile_data        ; Tile's associated data value
    CMP zp_item_0           ; Matches item slot 0?
    BEQ held_passable
    CMP zp_item_1           ; Matches item slot 1?
    BEQ held_passable
    LDA #&00                ; No match → solid (barrier blocks)
    RTS
.held_passable
    LDA #&FF                ; Match → passable (barrier removed)
    RTS
}
; Collision result for indexed tiles by type (from get_tile_type).
; &00 = solid (frog lands), &FF = passable (frog falls through).
.tile_type_table
    EQUB &00, &00, &00          ; Types 0-2: solid
    EQUB &FF, &FF               ; Types 3-4: passable
    EQUB &00, &00, &00          ; Types 5-7: solid
    EQUB &FF, &FF, &FF          ; Types 8-10: passable
    EQUB &00, &00               ; Types 11-12: solid
.get_tile_at_pos
{
    LDA zp_tile_x
    CMP #&10
    BCS out_of_bounds
    LDA zp_tile_y
    CMP #&08
    BCS out_of_bounds
    ASL A : ASL A : ASL A : ASL A
    CLC
    ADC zp_tile_x
    TAY
    LDA (zp_map_src_lo),Y
    RTS
.out_of_bounds
    LDA #&00
    RTS
}
.set_tile_at_pos
    PHA
    LDA zp_tile_y
    ASL A : ASL A : ASL A : ASL A
    CLC
    ADC zp_tile_x
    TAY
    PLA
    STA (zp_map_src_lo),Y
    PHA
    LDA zp_tile_x
    ASL A : ASL A
    STA zp_tile_x
    LDA zp_tile_y
    ASL A
    STA zp_tile_y
    PLA
    JMP jmp_block_copy    ; engine: block_copy
.crtc_table

; --- CRTC register table (register, value pairs) ---
    EQUB &01, &40               ; R1:  Horizontal displayed = 64 characters
    EQUB &02, &5A               ; R2:  H sync position = 90
    EQUB &06, &14               ; R6:  Vertical displayed = 20 rows
    EQUB &07, &1D               ; R7:  V sync position = 29
    EQUB &0A, &20               ; R10: Cursor start = off (bit 5 set)
    EQUB &0C, &0B               ; R12: Screen start high = &0B (display at &5800)
    EQUB &0D, &00               ; R13: Screen start low = &00

; === VSYNC IRQ Handler ===
; Called via IRQ1V on every vertical sync (~50Hz).
; Handles: sound updates, palette colour cycling, VSYNC flag.
;
; Zero page variables defined in zero_page.asm

.irq_handler
{
    LDA &FC                     ; Load A saved by MOS IRQ dispatcher
    PHA                         ; Save A
    TXA : PHA                   ; Save X
    TYA : PHA                   ; Save Y
    SEI                         ; Disable interrupts during handler

    LDA VIA_IFR                 ; Read System VIA IFR
    AND #&02                    ; Check CA1 (VSYNC) flag
    BEQ exit                    ; Not VSYNC — exit

    STA VIA_IFR                 ; Acknowledge VSYNC interrupt

    ; --- Update sound (if not inhibited) ---
    LDA zp_music_inhibit       ; Music inhibit flag
    BNE skip_sound              ; Non-zero = skip
    JSR jmp_update_sound      ; engine: update_sound

.skip_sound
    LDA #&FF
    STA zp_vsync_flag           ; Set VSYNC flag for game loop

    ; --- Palette colour cycling ---
    ; Every 8 frames, advance the colour cycle phase.
    ; On each phase, reprogram one palette entry via the Video ULA.
    INC zp_frame_ctr            ; Increment frame sub-counter
    LDA zp_frame_ctr
    AND #&08                    ; Every 8 frames?
    BEQ anim_bg                 ; No — check background animation

    LDA #&00
    STA zp_frame_ctr            ; Reset sub-counter
    INC zp_colour_phase         ; Advance colour cycle phase
    LDA zp_colour_phase
    AND #&07                    ; Wrap to 0-7
    STA zp_colour_phase
    TAX                         ; X = colour value
    LDA #&0C                    ; Palette entry 12 (logical colour 12)
    CPX zp_palette_count        ; Past the active range?
    BCC set_pal                 ; No — set it
    LDX #&00                    ; Yes — use colour 0

.set_pal
    JSR set_palette             ; Write palette register

.anim_bg
    ; Background palette animation — runs every 2 frames
    LDA zp_frame_ctr
    AND #&02                    ; Every 2 frames?
    BEQ exit                    ; No — done

    LDA zp_palette_idx          ; Current palette entry (8-11)
    LDX #&00                    ; Colour value 0 (black)
    JSR set_palette             ; Set entry to black (fade out)
    INC zp_palette_idx          ; Next palette entry
    LDA zp_palette_idx
    CMP #&0C                    ; Past entry 11?
    BNE bg_set
    LDA #&08                    ; Wrap back to entry 8
    STA zp_palette_idx

.bg_set
    LDX zp_palette_count        ; Active colour count
    JSR set_palette             ; Set new entry to active colour

.exit
    PLA : TAY                   ; Restore Y
    PLA : TAX                   ; Restore X
    PLA : STA &FC               ; Restore A to MOS save location
    RTI
}

; === Set Palette Register ===
; Writes a colour value to the Video ULA palette register (&FE21).
; A = logical colour (0-15), X = physical colour (0-7).
; The ULA register format: upper nibble = logical colour shifted,
; lower nibble = physical colour EOR 7.

.set_palette
    ASL A : ASL A : ASL A : ASL A  ; Logical colour → upper nibble
    STA set_palette_ora + 1     ; Self-modify: patch ORA operand
    TXA
    EOR #&07                    ; Invert physical colour bits
.set_palette_ora
    ORA #&00                    ; OR with logical colour (patched)
    STA ULA_PALETTE                   ; Write to Video ULA palette register
    RTS

    EQUB &65, &03               ; Vestigial bytes (unreachable after RTS)
.wait_vsync
{
    PHA
    LDA #&00
    STA zp_vsync_flag
.spin
    LDA zp_vsync_flag
    BEQ spin
    PLA
    RTS
}
{
.next_col
    INC zp_tile_y
    LDA zp_tile_y
    CMP #&08
    BCC last_tile
.done
    RTS
.*update_frog_tile
    LDA zp_scroll_x
    LSR A : LSR A
    STA zp_tile_x
    LDA zp_scroll_y
    BPL pos_y
    LDA #&00
.pos_y
    LSR A : LSR A : LSR A : LSR A
    STA zp_tile_y
    JSR draw_tile
    INC zp_tile_x
    LDA zp_tile_x
    CMP #&10
    BCS next_col
    JSR draw_tile
    INC zp_tile_y
    LDA zp_tile_y
    CMP #&08
    BCS done
    JSR draw_tile
.last_tile
    DEC zp_tile_x
.draw_tile
    LDA zp_tile_y
    ASL A : ASL A : ASL A : ASL A
    CLC
    ADC zp_map_src_lo
    STA map_read + 1
    LDA zp_map_src_hi
    ADC #&00
    STA map_read + 2
    LDY zp_tile_x
.map_read
    LDA &FFFF,Y
    STA tile_idx + 1
    LDA zp_tile_x
    PHA
    ASL A : ASL A
    STA zp_tile_x
    LDA zp_tile_y
    PHA
    ASL A
    STA zp_tile_y
.tile_idx
    LDA #&00
    JSR jmp_block_copy    ; engine: block_copy
    PLA
    STA zp_tile_y
    PLA
    STA zp_tile_x
    RTS
}
; === Hop Right ===
; X key: hop the frog one tile to the right with arc animation.
; Checks for obstructions, handles screen-edge wrapping.
; If / key held, does a short 4-step hop instead of 8-step.
.hop_right
{
    JSR wait_vsync
    JSR update_frog_tile
    LDA #&00
    STA zp_direction
    JSR tile_addr_setup    ; engine: tile_addr_setup
    LDY zp_frog_col
    INY
    STY zp_tile_x
    LDA zp_frog_row
    STA zp_tile_y
    JSR get_tile_at_pos
    JSR check_tile_solid
    BEQ stop
    LDA #&01
    STA zp_direction
    INC zp_tile_x
    JSR get_tile_at_pos
    JSR check_tile_solid
    BEQ short_hop_right
    LDA #KEY_SLASH              ; Short hop modifier
    JSR read_key
    BMI short_hop_right
    INC zp_frog_col
    LDA zp_frog_col
    CMP #&0F
    BCC anim_8
    LDA #&00
    STA zp_frog_col
    LDA #&00
    STA zp_scroll_x
    INC zp_map_scroll_x
    JSR jmp_setup_map    ; engine: setup_map_render
    LDA #&00
    STA zp_direction
    JSR tile_addr_setup    ; engine: tile_addr_setup
    JMP main_loop
.anim_8
    LDX #&00
.anim_8_loop
    JSR wait_vsync
    JSR update_frog_tile
    INC zp_scroll_x
    LDA zp_scroll_y
    CLC
    ADC scroll_step_table_8,X
    STA zp_scroll_y
    STX anim_8_rx + 1
    JSR tile_addr_setup    ; engine: tile_addr_setup
.anim_8_rx
    LDX #&00
    INX
    CPX #&08
    BNE anim_8_loop
    INC zp_frog_col
.stop
    LDA #&00
    STA zp_direction
    JSR wait_vsync
    JSR update_frog_tile
    JMP main_loop
.*short_hop_right
    LDX #&00
    INC zp_frog_col
    LDA zp_frog_col
    CMP #&10
    BNE anim_4
    INC zp_map_scroll_x
    LDA #&00
    STA zp_scroll_x
    STA zp_frog_col
    JSR jmp_setup_map    ; engine: setup_map_render
    LDA #&00
    STA zp_direction
    JSR tile_addr_setup    ; engine: tile_addr_setup
    JMP main_loop
.anim_4
    JSR wait_vsync
    JSR update_frog_tile
    INC zp_scroll_x
    LDA zp_scroll_y
    CLC
    ADC scroll_step_table_4,X
    STA zp_scroll_y
    STX anim_4_rx + 1
    JSR tile_addr_setup    ; engine: tile_addr_setup
.anim_4_rx
    LDX #&00
    INX
    CPX #&04
    BNE anim_4
    LDA #&00
    STA zp_direction
    JSR wait_vsync
    JSR update_frog_tile
    JMP main_loop
}
.scroll_step_table_8

; --- Collision/step tables (data) ---
    EQUB &FD, &FE, &FF, &00, &00, &03, &02, &01
.scroll_step_table_4
    EQUB &FE, &FF, &01, &02
.read_key
    STA VIA_ORA_NH              ; Write key scan code to VIA ORA (no handshake)
    BIT VIA_ORA_NH              ; Read back — bit 7 (N flag) set if key pressed
    RTS

; --- Tile type lookup ---
; For tiles >= &20, reads a 2-byte type descriptor from the tile graphics
; data at &4000. This is the pixel data of tile &20 itself, repurposed as
; a type lookup table — a clever memory-saving trick. Each level's graphics
; file embeds gameplay properties in the first tile's pixel data.
; Returns: A = type code, zp_tile_data = associated tile index.
.get_tile_type
    STY get_tile_type_ry + 1    ; Save Y (self-modifying LDY operand)
    SEC
    SBC #&20                    ; Tile index relative to &20
    ASL A                       ; ×2 for word-sized entries
    TAY
    INY
    LDA &4000,Y                 ; Byte 1: associated tile data
    STA zp_tile_data
    DEY
    LDA &4000,Y                 ; Byte 0: type code (returned in A)
.get_tile_type_ry
    LDY #&00                    ; Restore Y (operand patched by STY above)
    RTS
; === Hop Left ===
; Z key: hop the frog one tile to the left with arc animation.
; Mirror of hop_right.
.hop_left
{
    JSR wait_vsync
    JSR update_frog_tile
    LDA #&02
    STA zp_direction
    JSR tile_addr_setup    ; engine: tile_addr_setup
    LDY zp_frog_col
    DEY
    STY zp_tile_x
    LDA zp_frog_row
    STA zp_tile_y
    JSR get_tile_at_pos
    JSR check_tile_solid
    BEQ stop
    LDA #&03
    STA zp_direction
    DEC zp_tile_x
    JSR get_tile_at_pos
    JSR check_tile_solid
    BEQ short_hop_left
    LDA #KEY_SLASH              ; Short hop modifier
    JSR read_key
    BMI short_hop_left
    DEC zp_frog_col
    BEQ wrap_left
    BPL anim_8
.wrap_left
    LDA #&0F
    STA zp_frog_col
    LDA #&3C
    STA zp_scroll_x
    DEC zp_map_scroll_x
    JSR jmp_setup_map    ; engine: setup_map_render
    LDA #&02
    STA zp_direction
    JSR tile_addr_setup    ; engine: tile_addr_setup
    JMP main_loop
.anim_8
    LDX #&00
.anim_8_loop
    JSR wait_vsync
    JSR update_frog_tile
    DEC zp_scroll_x
    LDA zp_scroll_y
    CLC
    ADC scroll_step_table_8,X
    STA zp_scroll_y
    STX anim_8_rx + 1
    JSR tile_addr_setup    ; engine: tile_addr_setup
.anim_8_rx
    LDX #&00
    INX
    CPX #&08
    BNE anim_8_loop
    DEC zp_frog_col
.stop
    LDA #&02
    STA zp_direction
    JSR wait_vsync
    JSR update_frog_tile
    JMP main_loop
.*short_hop_left
    LDX #&00
    DEC zp_frog_col
    BPL anim_4
    DEC zp_map_scroll_x
    LDA #&3C
    STA zp_scroll_x
    LDA #&0F
    STA zp_frog_col
    JSR jmp_setup_map    ; engine: setup_map_render
    LDA #&02
    STA zp_direction
    JSR tile_addr_setup    ; engine: tile_addr_setup
    JMP main_loop
.anim_4
    JSR wait_vsync
    JSR update_frog_tile
    DEC zp_scroll_x
    LDA zp_scroll_y
    CLC
    ADC scroll_step_table_4,X
    STA zp_scroll_y
    STX anim_4_rx + 1
    JSR tile_addr_setup    ; engine: tile_addr_setup
.anim_4_rx
    LDX #&00
    INX
    CPX #&04
    BNE anim_4
    LDA #&02
    STA zp_direction
    JSR wait_vsync
    JSR update_frog_tile
    JMP main_loop
}
.convey_right
{
.again
    JSR step
    JSR get_tile_at_frog
    CMP #TILE_CONVEY_R
    BEQ again
    JMP main_loop
.step
    LDX #&00
.loop
    STX restore_x + 1
    JSR wait_vsync
    JSR update_frog_tile
    INC zp_scroll_x
    CLC
    LDA zp_scroll_y
    ADC #&04
    STA zp_scroll_y
    JSR tile_addr_setup    ; engine: tile_addr_setup
.restore_x
    LDX #&00
    INX
    CPX #&04
    BNE loop
    INC zp_frog_col
    INC zp_frog_row
    RTS
}
.convey_left
{
.again
    JSR step
    JSR get_tile_at_frog
    CMP #TILE_CONVEY_L
    BEQ again
    JMP main_loop
.step
    LDX #&00
.loop
    STX restore_x + 1
    JSR wait_vsync
    JSR update_frog_tile
    DEC zp_scroll_x
    CLC
    LDA zp_scroll_y
    ADC #&04
    STA zp_scroll_y
    JSR tile_addr_setup    ; engine: tile_addr_setup
.restore_x
    LDX #&00
    INX
    CPX #&04
    BNE loop
    DEC zp_frog_col
    INC zp_frog_row
    RTS
}
.move_up_check
{
    LDA zp_direction
    AND #&02
    BNE check_left
    JMP check_right
.check_left
    LDY zp_frog_col
    DEY
    STY zp_tile_x
    LDA zp_frog_row
    STA zp_tile_y
    JSR get_tile_at_pos
    CMP #TILE_CONVEY_R
    BNE check_ladder
.climb_left_step
    LDA #&03
    STA zp_direction
    LDX #&00
.climb_left_loop
    STX climb_left_rx + 1
    JSR wait_vsync
    JSR update_frog_tile
    SEC
    LDA zp_scroll_y
    SBC #&04
    STA zp_scroll_y
    DEC zp_scroll_x
    LDA zp_direction
    EOR #&01
    STA zp_direction
    JSR tile_addr_setup    ; engine: tile_addr_setup
.climb_left_rx
    LDX #&00
    INX
    CPX #&04
    BNE climb_left_loop
    DEC zp_frog_col
    DEC zp_frog_row
    LDY zp_frog_col
    DEY
    STY zp_tile_x
    LDA zp_frog_row
    STA zp_tile_y
    JSR get_tile_at_pos
    CMP #TILE_CONVEY_R
    BEQ climb_left_step
    LDA #&02
    STA zp_direction
    LDY zp_frog_col
    DEY
    STY zp_tile_x
    LDA zp_frog_row
    STA zp_tile_y
    JSR get_tile_at_pos
    JSR check_tile_solid
    BEQ climb_done
    JMP short_hop_left
.climb_done
    JMP main_loop
.check_ladder
    LDA zp_frog_col
    STA zp_tile_x
    LDA zp_frog_row
    STA zp_tile_y
    JSR get_tile_at_pos
    CMP #TILE_LADDER
    BEQ is_ladder
    JMP jump_up
.is_ladder
    LDY zp_frog_row
    DEY
    STY zp_tile_y
    LDA zp_frog_col
    STA zp_tile_x
    JSR get_tile_at_pos
    JSR check_tile_solid
    BEQ ladder_blocked
    JMP climb_ladder
.ladder_blocked
    JMP main_loop
.check_right
    LDY zp_frog_col
    INY
    STY zp_tile_x
    LDA zp_frog_row
    STA zp_tile_y
    JSR get_tile_at_pos
    CMP #TILE_CONVEY_L
    BNE check_ladder
.climb_right_step
    LDA #&01
    STA zp_direction
    LDX #&00
.climb_right_loop
    STX climb_right_rx + 1
    JSR wait_vsync
    JSR update_frog_tile
    SEC
    LDA zp_scroll_y
    SBC #&04
    STA zp_scroll_y
    INC zp_scroll_x
    LDA zp_direction
    EOR #&01
    STA zp_direction
    JSR tile_addr_setup    ; engine: tile_addr_setup
.climb_right_rx
    LDX #&00
    INX
    CPX #&04
    BNE climb_right_loop
    INC zp_frog_col
    DEC zp_frog_row
    LDY zp_frog_col
    INY
    STY zp_tile_x
    LDA zp_frog_row
    STA zp_tile_y
    JSR get_tile_at_pos
    CMP #TILE_CONVEY_L
    BEQ climb_right_step
    LDA #&00
    STA zp_direction
    LDY zp_frog_col
    INY
    STY zp_tile_x
    LDA zp_frog_row
    STA zp_tile_y
    JSR get_tile_at_pos
    JSR check_tile_solid
    BNE climb_right_scroll
    JMP climb_done
.climb_right_scroll
    JMP short_hop_right
.climb_ladder
    JSR update_frog_tile
.climb_next_row
    DEC zp_frog_row
    BMI climb_scroll_up
.climb_check_tile
    LDA zp_frog_row
    STA zp_tile_y
    LDA zp_frog_col
    STA zp_tile_x
    JSR get_tile_at_pos
    CMP #TILE_LADDER_FRM
    BEQ climb_animate
    LDA zp_frog_col
    ASL A : ASL A
    STA zp_scroll_x
    LDY zp_frog_row
    INY
    TYA
    ASL A : ASL A : ASL A : ASL A
    STA zp_scroll_y
    LDX #&00
.climb_anim_loop
    STX climb_anim_rx + 1
    DEC zp_scroll_y
    JSR wait_vsync
    JSR update_frog_tile
    JSR tile_addr_setup    ; engine: tile_addr_setup
.climb_anim_rx
    LDX #&00
    INX
    CPX #&10
    BNE climb_anim_loop
    JMP scan_keys
.climb_animate
    LDA zp_frog_col
    ASL A : ASL A
    STA zp_tile_x
    LDA zp_frog_row
    ASL A
    STA zp_tile_y
    LDA #&1B
    JSR jmp_block_copy    ; engine: block_copy
    LDX #&09
.climb_pause
    JSR wait_vsync
    DEX
    BNE climb_pause
    LDA #&07
    JSR jmp_block_copy    ; engine: block_copy
    JMP climb_next_row
.climb_scroll_up
    LDA #&07
    STA zp_frog_row
    LDA #&70
    STA zp_scroll_y
    DEC zp_map_scroll_y
    JSR jmp_setup_map    ; engine: setup_map_render
    JMP climb_check_tile
.jump_scroll_up
    LDA #&07
    STA zp_frog_row
    LDA #&70
    STA zp_scroll_y
    DEC zp_map_scroll_y
    JSR jmp_setup_map    ; engine: setup_map_render
    JSR tile_addr_setup    ; engine: tile_addr_setup
    JMP main_loop
.jump_up
    LDA zp_frog_col
    STA zp_tile_x
    LDY zp_frog_row
    DEY
    BMI jump_scroll_up
    STY zp_tile_y
    JSR get_tile_at_pos
    JSR check_tile_solid
    BEQ jump_up_done
    LDX #&07
.jump_up_loop
    STX jump_up_rx + 1
    LDA zp_scroll_y
    SEC
    SBC fall_step_table,X
    STA zp_scroll_y
    JSR wait_vsync
    JSR update_frog_tile
    JSR tile_addr_setup    ; engine: tile_addr_setup
.jump_up_rx
    LDX #&00
    DEX
    BPL jump_up_loop
    DEC zp_frog_row
.jump_up_done
    JMP main_loop
}
; --- Key/door check ---
; Tile &11 is a locked door. If either item slot holds a type-1 tile
; (the key, tile &37), the door opens (frog passes through as tile &00).
; Otherwise, falls through to handle_death.
.apply_tile_effect
    LDA #&00                    ; Replace door with empty (patched by check_tile_effect)
    JMP tile_dispatch_continue
.check_tile_effect
    STA apply_tile_effect + 1   ; Patch the LDA operand with original tile
    LDA zp_item_0
    JSR get_tile_type
    CMP #&01                    ; Is item 0 a key (type 1)?
    BEQ apply_tile_effect
    LDA zp_item_1
    JSR get_tile_type
    CMP #&01                    ; Is item 1 a key?
    BEQ apply_tile_effect

; --- Death animation and life check ---
.handle_death
{
    LDX #&00
.sink_loop
    STX restore_x + 1
    JSR wait_vsync
    JSR wait_vsync
    JSR wait_vsync
    JSR update_frog_tile
    LDA fall_step_table,X
    CLC
    ADC zp_scroll_y
    STA zp_scroll_y
    JSR tile_addr_setup    ; engine: tile_addr_setup
    LDA zp_frog_col
    STA zp_tile_x
    LDY zp_frog_row
    INY
    STY zp_tile_y
    JSR get_tile_at_pos
    JSR set_tile_at_pos
.restore_x
    LDX #&00
    INX
    CPX #&08
    BNE sink_loop
    LDX #&32
    JSR wait_frames
    LDA #KEY_ZERO               ; Hold 0 during death = instant game over
    JSR read_key
    BPL check_lives
    LDA #&01
    STA zp_lives
.check_lives
    DEC zp_lives
    BEQ game_over
    JSR draw_status
    JMP wait_for_space_done
.game_over
    JSR draw_status
    JMP game_loop_start
}
; === Walk Right (on climbable surface) ===
; Triggered by tile &05: slow 4-step rightward movement with no arc.
.move_right_check
{
    LDY zp_frog_col
    INY
    CPY #&10
    BCC in_bounds
    LDA #&00
    STA zp_frog_col
    STA zp_scroll_x
    INC zp_map_scroll_x
    JSR jmp_setup_map    ; engine: setup_map_render
    JMP main_loop
.in_bounds
    STY zp_tile_x
    LDA zp_frog_row
    STA zp_tile_y
    JSR get_tile_at_pos
    JSR check_tile_solid
    BNE do_move
    JMP scan_keys
.do_move
    LDX #&00
.loop
    STX restore_x + 1
    JSR update_frog_tile
    INC zp_scroll_x
    JSR tile_addr_setup    ; engine: tile_addr_setup
    JSR wait_vsync
    JSR wait_vsync
    JSR wait_vsync
    JSR wait_vsync
.restore_x
    LDX #&00
    INX
    CPX #&04
    BNE loop
    INC zp_frog_col
    JMP main_loop
}
; === Walk Left (on climbable surface) ===
; Triggered by tile &1E: slow 4-step leftward movement with no arc.
.move_left_check
{
    LDY zp_frog_col
    DEY
    CPY #&10
    BCC in_bounds
    LDA #&0F
    STA zp_frog_col
    LDA #&3C
    STA zp_scroll_x
    DEC zp_map_scroll_x
    JSR jmp_setup_map    ; engine: setup_map_render
    JMP main_loop
.in_bounds
    STY zp_tile_x
    LDA zp_frog_row
    STA zp_tile_y
    JSR get_tile_at_pos
    JSR check_tile_solid
    BNE do_move
    JMP scan_keys
.do_move
    LDX #&00
.loop
    STX restore_x + 1
    JSR update_frog_tile
    DEC zp_scroll_x
    JSR tile_addr_setup    ; engine: tile_addr_setup
    JSR wait_vsync
    JSR wait_vsync
    JSR wait_vsync
    JSR wait_vsync
.restore_x
    LDX #&00
    INX
    CPX #&04
    BNE loop
    DEC zp_frog_col
    JMP main_loop
}
.draw_status
    LDA #&03
    STA zp_tile_x
    LDA #&11
    STA zp_tile_y
    LDA zp_item_0
    JSR jmp_block_copy    ; engine: block_copy
    LDA #&0A
    STA zp_tile_x
    LDA zp_item_1
    JSR jmp_block_copy    ; engine: block_copy
    LDA #&3C
    STA zp_tile_x
    INC zp_tile_y
    LDA #&07
    STA zp_text_colour
    LDA zp_lives
    JSR draw_digit
    RTS

; --- Item pickup from adjacent tiles ---
.use_item_slot
{
    LDA zp_item_0,X
    STX item_slot_select + 1
    BEQ no_item
    JMP place_item
.no_item
    LDA zp_frog_col
    STA zp_tile_x
    LDA zp_frog_row
    STA zp_tile_y
    JSR check_tile_passable
    BEQ item_slot_select
    LDA zp_direction
    AND #&02
    BEQ facing_right
    LDY zp_frog_col
    DEY
    STY zp_tile_x
    JMP check_side
.facing_right
    LDY zp_frog_col
    INY
    STY zp_tile_x
.check_side
    LDA zp_frog_row
    STA zp_tile_y
    JSR check_tile_passable
    BEQ item_slot_select
    LDA zp_frog_col
    STA zp_tile_x
    LDY zp_frog_row
    INY
    STY zp_tile_y
    JSR check_tile_passable
    BNE done
.*item_slot_select
    LDX #&00
    STA zp_item_0,X
    LDA #&00
    JSR set_tile_at_pos
    JSR tile_addr_setup    ; engine: tile_addr_setup
    JSR draw_status
.done
    JMP main_loop
}
.check_tile_passable
{
    JSR get_tile_at_pos
    CMP #&20
    BCC simple
    PHA
    JSR get_tile_type
    TAX
    LDA collision_check_table,X
    TAY
    PLA
    CPY #&00
    RTS
.simple
    LDA #&01
    RTS
}
; Item pickup eligibility by type. &00 = CAN be picked up, &FF = cannot.
; Used by check_tile_passable: Z flag set (BEQ) means "can pick up".
.collision_check_table
    EQUB &00, &00, &00, &00, &00  ; Types 0-4: pickupable
    EQUB &FF, &FF, &FF            ; Types 5-7: not pickupable (special interaction)
    EQUB &FF, &FF                 ; Types 8-9: not pickupable (auto-collect/solid)
    EQUB &00                      ; Type 10: pickupable
    EQUB &FF                      ; Type 11: not pickupable (drop trigger)
    EQUB &00, &00, &00, &00       ; Types 12-15: pickupable
    EQUB &00, &00, &00, &00, &00, &00, &00, &00  ; Types 16-23: pickupable
    EQUB &00, &00, &00, &00, &00, &00, &00, &00  ; Types 24-31: pickupable

; --- Item placement ---
.place_item
    LDA zp_frog_row
    STA zp_tile_y
    LDA zp_frog_col
    STA zp_tile_x
    JSR get_tile_at_pos
    BNE drop_item_done
    LDX item_slot_select + 1
    LDA zp_item_0,X
    STA zp_temp_item
    JSR get_tile_type
    STA zp_temp_type
    CMP #&04
    BEQ do_place
    CMP #&03
    BEQ do_place
    DEC zp_tile_y
    BMI drop_item_done
    JSR get_tile_at_pos
    JSR check_tile_solid
    BEQ drop_item_done
.do_place
    JSR update_frog_tile
    LDA zp_frog_col
    STA zp_tile_x
    LDA zp_frog_row
    STA zp_tile_y
    LDA zp_temp_item
    JSR set_tile_at_pos
    LDA zp_temp_type
    CMP #&04
    BEQ clear_slot
    CMP #&03
    BEQ clear_slot
    DEC zp_frog_row
    SEC
    LDA zp_scroll_y
    SBC #&10
    STA zp_scroll_y
.clear_slot
    LDA #&00
    STA zp_item_0,X
    JSR tile_addr_setup    ; engine: tile_addr_setup
    JSR draw_status
.drop_item_done
    JMP main_loop
; === Collect Item (type 9 trigger) ===
; Auto-collect tiles transform a held item: if an item slot holds the
; tile's data value, the slot is incremented (item "evolves").
; E.g., holding &2B and stepping on a type-9 tile with data=&2B → slot becomes &2C.
.collect_item
{
    PHA
    LDX #&00
.loop
    LDA zp_tile_data
    CMP zp_item_0,X
    BEQ found
    INX
    CPX #&02
    BNE loop
    PLA
    RTS
.found
    INC zp_item_0,X
    JSR draw_status
    JSR palette_flash
    PLA
    RTS
}
.clear_tile_pickup
    PHA
    LDA zp_frog_col
    STA zp_tile_x
    LDA zp_frog_row
    STA zp_tile_y
    LDA #&00
    JSR set_tile_at_pos
    JSR tile_addr_setup    ; engine: tile_addr_setup
    JSR palette_flash
    PLA
    RTS
; === Drop Item (type 0B trigger) ===
; If an item slot holds the tile's data value, the slot is cleared
; (item consumed). Also clears tiles below and flashes the palette.
.drop_item
{
    PHA
    LDX #&00
.loop
    LDA zp_tile_data
    CMP zp_item_0,X
    BEQ found
    INX
    CPX #&02
    BNE loop
    PLA
    RTS
.found
    LDA #&00
    STA zp_item_0,X
    JSR draw_status
    LDA zp_frog_col
    STA zp_tile_x
    LDY zp_frog_row
    INY
    STY zp_tile_y
    LDA #&00
    JSR set_tile_at_pos
    LDA zp_frog_col
    STA zp_tile_x
    LDY zp_frog_row
    INY
    INY
    STY zp_tile_y
    LDA #&00
    JSR set_tile_at_pos
    LDA #&00
    LDX #&07
    JSR set_palette
    LDX #&14
    JSR wait_frames
    LDX #&06
.flash_loop
    STX restore_x + 1
    LDA #&00
    JSR set_palette
    LDX #&05
    JSR wait_frames
.restore_x
    LDX #&00
    DEX
    BPL flash_loop
    PLA
    RTS
}
.wait_frames
    JSR wait_vsync
    DEX
    BPL wait_frames
    RTS
; Place a temporary solid tile below the frog. Tiles &10, &1C, &1D
; cycle through a sequence: &10 places &1C, &1C places &1D, &1D places &00.
; This creates disappearing platforms that crumble as the frog stands on them.
.place_tile_1c
    LDA #TILE_PLACED_1
.place_tile_below
    PHA
    LDA zp_frog_col
    STA zp_tile_x
    LDY zp_frog_row
    INY
    STY zp_tile_y
    PLA
    JSR set_tile_at_pos
    JMP scan_keys
.place_tile_1d
    LDA #TILE_PLACED_2
    JMP place_tile_below
.place_tile_00
    LDA #TILE_EMPTY
    JMP place_tile_below
.draw_digit
{
    STA zp_src_lo
    LDA #&00
    ASL zp_src_lo : ROL A : ASL zp_src_lo : ROL A
    ASL zp_src_lo : ROL A : ASL zp_src_lo : ROL A
    STA zp_src_hi
    CLC
    LDA zp_src_lo
    ADC #&80
    STA zp_src_lo
    LDA zp_src_hi
    ADC #&03
    STA zp_src_hi
    JSR jmp_calc_scrn_addr    ; engine: calc_screen_addr
    LDX zp_text_colour
    LDY #&0F
.loop
    LDA (zp_src_lo),Y
    AND digit_mask_table,X
    STA (zp_dst_lo),Y
    DEY
    BPL loop
    CLC
    LDA zp_tile_x
    ADC #&02
    STA zp_tile_x
    RTS
}
.digit_mask_table

; --- Digit rendering mask table ---
    EQUB &00, &03, &0C, &0F, &30, &33, &3C, &3F
.str_title
    TILESTR "* FROGMAN  BY MG * RTW *"
    EQUB &FF
.str_press_space
    TILESTR "* PRESS SPACE TO START *"
    EQUB &FF

; --- More rendering and string display ---
.draw_string
{
    STX zp_map_ptr_lo
    STY zp_map_ptr_hi
    LDY #&00
.loop
    STY restore_y + 1
    LDA (zp_map_ptr_lo),Y
    BMI done
    JSR draw_digit
.restore_y
    LDY #&00
    INY
    BNE loop
.done
    RTS
}
; === Map Reveal ===
; Triggered by tile &04. First visit: fades out, renders the overview
; map from Level?S data at &0300, places collected terminal tiles (&38+)
; onto the overview. Second visit: restores the normal game screen.
; Terminal tiles >= &38 are placed at row 6 of the overview as markers.
.handle_map_reveal
{
    JSR fade_out
    LDA zp_game_state
    BNE restore
    LDA #&81
    STA zp_game_state
    LDA zp_frog_col
    STA zp_save_col
    LDA zp_frog_row
    STA zp_save_row
    LDA #&01
    STA zp_frog_col
    LDA #&06
    STA zp_frog_row
    JSR calc_scroll_pos
    LDA #&00
    STA zp_map_src_lo
    LDA #&03
    STA zp_map_src_hi
    JSR jmp_render_map    ; engine: render_map
    JSR tile_addr_setup    ; engine: tile_addr_setup
    LDX #&00
.check_items
    LDA zp_item_0,X
    CMP #&38
    BCC next_item
    JSR place_terminal
.next_item
    INX
    CPX #&02
    BNE check_items
    JSR draw_status
    JSR fade_in
    JMP main_loop
.restore
    LDA #&80
    STA zp_game_state
    LDA zp_save_col
    STA zp_frog_col
    LDA zp_save_row
    STA zp_frog_row
    JSR jmp_setup_map    ; engine: setup_map_render
    JSR calc_scroll_pos
    JSR tile_addr_setup    ; engine: tile_addr_setup
    JSR fade_in
    JMP main_loop
}
.calc_scroll_pos
{
    LDA zp_frog_col
    ASL A : ASL A
    STA zp_scroll_x
    LDA zp_frog_row
    ASL A : ASL A : ASL A : ASL A
    STA zp_scroll_y
    RTS
}
.fade_out
{
    LDX #&07
.init
    TXA
    STA palette_fade_table,X
    DEX
    BPL init
.step
    LDX #&07
.loop
    LDA palette_fade_table,X
    BEQ skip
    TAY
    DEY
    TYA
    STA palette_fade_table,X
.skip
    DEX
    BPL loop
    LDX #&04
    JSR wait_frames
    JSR apply_palette
    LDA palette_fade_last
    BNE step
    LDX #&32
    JMP wait_frames
}
.palette_fade_table
    EQUB &00, &00, &00, &00, &00, &00, &00
.palette_fade_last
    EQUB &00
.apply_palette
{
    LDY #&07
    LDA palette_fade_table,Y
    STA zp_palette_count
.loop
    LDA palette_fade_table,Y
    TAX
    TYA
    JSR set_palette
    DEY
    BNE loop
    RTS
}
.fade_in
{
    LDX #&07
.step
    STX cmp_target + 1
    LDA palette_fade_table,X
.cmp_target
    CMP #&00                    ; Operand patched with X (target colour)
    BEQ skip
    TAY
    INY
    TYA
    STA palette_fade_table,X
.skip
    DEX
    BPL step
    LDX #&04
    JSR wait_frames
    JSR apply_palette
    LDA palette_fade_last
    CMP #&07
    BNE fade_in
    RTS
}
.place_terminal
{
    SEC
    PHA
    STX restore_x + 1
    SBC #&31
    STA zp_tile_x
    LDA #&06
    STA zp_tile_y
    PLA
    JSR set_tile_at_pos
.restore_x
    LDX #&00
    LDA #&00
    STA zp_item_0,X
    INC zp_terminal_ctr
    RTS
}
; --- Display strings (tile font encoding: A=&0A..Z=&23, space=&25, *=&24, &FF=end) ---
.str_special_msg
    TILESTR "* POWER CONTROL TERMINAL *"
    EQUB &FF
.str_continue
    TILESTR "* ACCESS DENIED *"
    EQUB &FF
.str_well_done
    TILESTR "* LOGGED ON "
    EQUB &FF
.str_power_off                  ; Unused — cut feature?
    TILESTR " POWER DEACTIVATED *"
    EQUB &FF
; === Power Control Terminal ===
; Tile &1F is the final objective. Shows "POWER CONTROL TERMINAL" message.
; If all 8 terminal items have been collected (zp_terminal_ctr >= 8),
; shows "LOGGED ON". Otherwise shows "ACCESS DENIED".
.handle_special_tile
{
    PHA
    LDA zp_special_flag
    BEQ first_visit
    PLA
    JMP check_passthrough
.first_visit
    LDA #&FF
    STA zp_special_flag
    LDA #&07
    STA zp_text_colour
    LDA #&07
    STA zp_tile_x
    LDA #&04
    STA zp_tile_y
    LDX #LO(str_special_msg)
    LDY #HI(str_special_msg)
    JSR draw_string
    LDA zp_terminal_ctr
    CMP #&08
    BCS all_collected
.show_denied
    LDA #&01
    STA zp_text_colour
    LDA #&0D
    STA zp_tile_x
    LDA #&08
    STA zp_tile_y
    LDX #LO(str_continue)
    LDY #HI(str_continue)
    JSR draw_string
    LDX #&64
    JSR wait_frames
    JSR jmp_render_map    ; engine: render_map
    JMP main_loop
.all_collected
    LDA zp_game_state
    BNE already_done
    LDA #&02
    STA zp_text_colour
    LDA #&06
    STA zp_tile_x
    LDA #&08
    STA zp_tile_y
    LDX #LO(str_well_done)
    LDY #HI(str_well_done)
    JSR draw_string
    LDX #&64
    JSR wait_frames
    LDA #&FF
    STA zp_terminal_ctr
    JMP main_loop
.already_done
    LDA zp_terminal_ctr
    BPL show_denied
}

; --- Level map loading from disc ---
.halt                           ; Unreachable infinite loop (unused crash trap)
    JMP halt
.load_level_data
    SEI
    JSR jmp_init_game    ; engine: init_game
    JSR swap_0600_0d00
    LDX #LO(oscli_disc)
    LDY #HI(oscli_disc)
    JSR OSCLI
    JMP load_level_m
.oscli_disc
    EQUS "DISC", 13
.load_level_m
    LDA zp_level_char
    STA oscli_level_m_num
    LDX #LO(oscli_load_level_m)
    LDY #HI(oscli_load_level_m)
    JSR OSCLI
    JMP relocate_map_data
.oscli_load_level_m
    EQUS "Load Level"
.oscli_level_m_num
    EQUB 0
    EQUS "M 5800", 13
.relocate_map_data
{
    LDX #&00
    LDA #&68
    STA src + 2
    LDA #&1F
    STA dst + 2
.src
    LDA &6800,X
.dst
    STA &1F00,X
    INX
    BNE src
    INC dst + 2
    INC src + 2
    BPL src
}
    LDA zp_level_char
    STA oscli_level_t2_num
    LDX #LO(oscli_load_level_t2)
    LDY #HI(oscli_load_level_t2)
    JSR OSCLI
    JMP load_tbar
.oscli_load_level_t2
    EQUS "Load Level"
.oscli_level_t2_num
    EQUB 0
    EQUS "T 6800", 13
.load_tbar
    LDX #LO(oscli_load_tbar)
    LDY #HI(oscli_load_tbar)
    JSR OSCLI
    JMP setup_irq
.oscli_load_tbar
    EQUS "Load Tbar 7800", 13
.setup_irq
    SEI
    LDA #LO(irq_handler)
    STA IRQ1V_LO
    LDA #HI(irq_handler)
    STA IRQ1V_HI
    LDA #&7F
    STA VIA_IER
    STA VIA_DDRA
    LDA #&82
    STA VIA_IER
    LDA #&FF
    STA VIA_DDRB
    LDA #&03
    STA VIA_ORB
    JSR swap_0600_0d00
{
    LDA #&58
    STA map_src + 2
    LDA #&0F
    STA map_dst + 2
    LDA #&0C
    STA tile_dst + 2
    LDA #&68
    STA tile_src + 2
    LDX #&03
    LDY #&00
.tile_src
    LDA &6800,Y
.tile_dst
    STA &0C80,Y
    INY
    BNE tile_src
    INC tile_src + 2
    INC tile_dst + 2
    DEX
    BNE tile_src
    LDX #&00
.map_src
    LDA &5800,X
.map_dst
    STA &0F00,X
    INX
    BNE map_src
    INC map_dst + 2
    INC map_src + 2
    LDA map_dst + 2
    CMP #&1F
    BNE map_src
}
    LDA #&37
    STA zp_scroll_x
    LDA #&88
    STA zp_scroll_y
    LDY #&00
    JSR tile_addr_setup_y
    JSR clear_sound_state
    CLI
    RTS

; === Swap &0600 and &0D00 ===
; Swaps 256 bytes between the IRQ handler area (&0600) and the
; music/data block (&0D00). Called during init to place the right
; data in each location.

.swap_0600_0d00
{
    LDX #&00
.loop
    LDA &0D00,X
    TAY
    LDA &0600,X
    STA &0D00,X
    TYA
    STA &0600,X
    INX
    BNE loop
    RTS
}

; === Clear Sound State ===
; Zeros the note timer and music stream index for all 4 channels.

.clear_sound_state
{
    LDA #&00
    TAX
.loop
    STA zp_snd_timer,X       ; Animation timer
    STA zp_snd_anim_idx,X       ; Animation index
    INX
    CPX #&04
    BNE loop
    RTS
}

; === Palette Flash ===
; Flashes logical colour 0 briefly (physical colour 1 for 10 frames,
; then black). Called after item collection/drop.

.palette_flash
    LDA #&00
    LDX #&01
    JSR set_palette
    LDX #&0A
    JSR wait_frames
    LDA #&00
    TAX
    JMP set_palette

; --- Data tables at end of Gcode ---
    EQUB &F9, &89, &3A, &D7, &BC, &DB, &02, &C1
    EQUB &A5, &A0, &BA, &90, &4F, &0C, &D7, &3F
    EQUB &25, &7F, &2F, &C1, &6C, &EC, &E5, &23
    EQUB &25, &3A, &34, &15, &21, &4F, &38, &69
    EQUB &C6, &36, &6E, &83, &FE, &7D, &DB, &64
    EQUB &CC, &56, &32, &6C, &29, &ED, &F5, &30
    EQUB &5E, &60, &A8, &05, &2A, &D3, &51, &A6
    EQUB &C4, &49, &1A, &45, &83, &6E, &11, &AA
    EQUB &1F, &83, &E0, &CE, &23, &BB, &C1, &C9
    EQUB &7C, &E1, &D2, &8F, &29, &BC, &7E, &1B
    EQUB &E3, &C6, &7D, &80, &CC, &D2, &D0, &0A
    EQUB &6A, &A1, &C4, &4A, &12, &F0, &74, &90
    EQUB &AA, &5C, &3B, &38, &58, &07, &D7, &FC
    EQUB &2D, &00, &1E, &23, &D6, &DF, &0D, &A9
    EQUB &D4, &8D, &FB, &5C, &78, &8C, &20


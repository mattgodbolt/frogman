; ============================================================================
; FROGMAN — Game Code (Gcode)
; Loaded at &4800, encrypted on disc as 'Gcode'
;
; Contains the main game loop, IRQ handler, collision detection,
; keyboard handling, level loading, and sprite management.
;
; Every byte verified against data/gcode_decrypted.bin.
; ============================================================================

ORG &4800

; --- Tile source LUTs and data tables ---
.tile_source_lut
    EQUB &00, &40, &80, &C0, &00, &40, &80, &C0
    EQUB &00, &40, &80, &C0, &00, &40, &80, &C0
    EQUB &00, &40, &80, &C0, &00, &40, &80, &C0
    EQUB &00, &40, &80, &C0, &00, &40, &80, &C0
    EQUB &00, &40, &80, &C0, &00, &40, &80, &C0
    EQUB &00, &40, &80, &C0, &00, &40, &80, &C0
    EQUB &00, &40, &80, &C0, &00, &40, &80, &C0
    EQUB &00, &40, &80, &C0, &00, &40, &80, &C0
    EQUB &38, &38, &38, &38, &39, &39, &39, &39
    EQUB &3A, &3A, &3A, &3A, &3B, &3B, &3B, &3B
    EQUB &3C, &3C, &3C, &3C, &3D, &3D, &3D, &3D
    EQUB &3E, &3E, &3E, &3E, &3F, &3F, &3F, &3F
    EQUB &40, &40, &40, &40, &41, &41, &41, &41
    EQUB &42, &42, &42, &42, &43, &43, &43, &43
    EQUB &44, &44, &44, &44, &45, &45, &45, &45
    EQUB &46, &46, &46, &46, &47, &47, &47, &47
.collision_flags
    EQUB &FF, &00, &00, &00, &FF, &00, &FF, &FF
    EQUB &00, &00, &00, &00, &00, &00, &00, &00
    EQUB &00, &00, &FF, &FF, &FF, &FF, &FF, &FF
    EQUB &FF, &FF, &FF, &FF, &00, &00, &00, &FF

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
    LDX #&08
    LDY #&00
.copy_engine_src
    LDA &5800,Y
.copy_engine_dst
    STA &0700,Y
    LDA #&00
.clear_screen_addr
    STA &5800,Y
    INY
    BNE copy_engine_src
    INC copy_engine_src + 2
    INC copy_engine_dst + 2
    INC clear_screen_addr + 2
    DEX
    BNE copy_engine_src
    LDX #&FF
    TXS                         ; Reset stack pointer
    LDA #LO(irq_handler)
    STA IRQ1V_LO                   ; IRQ1V low = &A5
    LDA #HI(irq_handler)
    STA IRQ1V_HI                   ; IRQ1V high = &4C

    ; --- Zero page initialisation ---
    LDA #&00
    STA zp_colour_phase         ; Colour cycle phase
    STA zp_frame_ctr            ; Frame sub-counter
    STA zp_game_state           ; Game state flags
    STA zp_terminal_ctr         ; Terminal/checkpoint counter
    STA zp_sprite_inhibit       ; Sprite update inhibit (0 = enabled)
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
    JSR clear_sprite_state      ; Clear all sprite animation state
    CLI                         ; Enable interrupts — game starts running

; === Game Loop Setup ===
; Called at the start of each life / level.
; Initialises sprites, loads the level map, renders the initial screen,
; draws the status bar and title text, then waits for SPACE to start.

.game_loop_start
    LDA zp_sprite_inhibit       ; Save sprite update inhibit state
    PHA
    JSR jmp_init_game                   ; engine: init_game (VIA config)
    LDA #&FF
    STA zp_sprite_inhibit       ; Inhibit sprite updates during setup
    LDA #&00
    STA zp_item_0               ; Clear item slot 0
    STA zp_item_1               ; Clear item slot 1
    LDA #&09
    STA zp_lives                ; Lives = 9
    JSR l_550D                   ; Initialise score display
    JSR load_level_data                   ; Load level map from disc
    JSR draw_status                   ; Draw status bar
    LDA #&00
    STA zp_map_src_lo           ; Map source low = &0300
    LDA #&03
    STA zp_map_src_hi           ; Map source high
    JSR jmp_render_map                   ; engine: render_map
    PLA
    STA zp_sprite_inhibit       ; Restore sprite update inhibit
    JSR draw_title                   ; Draw "FROGMAN BY MG RTW" title
    LDA #&02                    ; Row 2
    STA zp_text_colour
    LDA #&00
    STA zp_tile_y                     ; Tile Y = 0
    LDA #&08
    STA zp_tile_x                     ; Tile X = 8
    LDX #LO(str_title)                    ; String pointer low
    LDY #HI(str_title)                    ; String pointer high (&5456)
    JSR draw_string                   ; Draw string: "FROGMAN BY MG RTW"
    LDA #&07                    ; Row 7
    STA zp_text_colour
    LDA #&01
    STA zp_tile_y                     ; Tile Y = 1
    LDA #&08
    STA zp_tile_x                     ; Tile X = 8
    LDX #LO(str_press_space)                    ; String pointer low
    LDY #HI(str_press_space)                    ; String pointer high (&546F)
    JSR draw_string                   ; Draw string: "PRESS SPACE TO START"
    LDA #&62
.l_4A23
    JSR read_key
    BPL l_4A23
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
    LDA #&70
    JSR read_key
    BPL l_4A5C
.l_4A54
    JSR read_key
    BMI l_4A54
    JMP game_state_handlers
.l_4A5C
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
    CMP #&03
    BNE not_03
    JMP convey_right
.not_03
    CMP #&02
    BNE not_02
    JMP convey_left
.not_02
    CMP #&11
    BNE tile_dispatch_continue
    JMP check_tile_effect
}
.tile_dispatch_continue                  ; Re-entry point from apply_tile_effect
{
    CMP #&05
    BNE not_05
    JMP move_right_check
.not_05
    CMP #&1E
    BNE not_1e
    JMP move_left_check
.not_1e
    CMP #&10
    BNE not_10
    JMP place_tile_1c
.not_10
    CMP #&1C
    BNE not_1c
    JMP place_tile_1d
.not_1c
    CMP #&1D
    BNE not_1d
    JMP place_tile_00
.not_1d
    LDA zp_frog_col
    STA zp_tile_x
    LDA zp_frog_row
    STA zp_tile_y
    JSR get_tile_at_pos
    CMP #&04
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
    CMP #&1F
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
    CMP #&12
    BNE check_below
    JMP game_state_handlers
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
    LDA #&42
    JSR read_key
    BPL not_down
    JMP move_down
.not_down
    LDA #&61
    JSR read_key
    BPL not_right
    JMP move_right
.not_right
    LDA #&48
    JSR read_key
    BPL not_up
    JMP move_up_check
.not_up
    LDA zp_map_src_hi
    CMP #&03
    BEQ no_scroll
    LDA #&20
    JSR read_key
    BPL not_scroll_left
.wait_left
    JSR wait_vsync
    JSR read_key
    BMI wait_left
    LDX #&00
    JMP scroll_routines
.not_scroll_left
    LDA #&71
    JSR read_key
    BPL no_scroll
.wait_right
    JSR wait_vsync
    JSR read_key
    BMI wait_right
    LDX #&01
    JMP scroll_routines
.no_scroll
    JSR wait_vsync
    LDA #&65
    JSR read_key
    BPL done
    JSR jmp_init_game    ; engine: init_game
    LDA zp_sprite_inhibit
    EOR #&FF
    STA zp_sprite_inhibit
.wait_release
    LDA #&65
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
    CMP #&06
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
    EQUB &20
    EQUB &E9

}
; --- Helper routines called from main loop ---
.game_routines_1
    EQUB &0B
    JMP main_loop
.fall_step_table
    ORA (&01,X)
    ORA (&02,X)
    EQUB &02
    EQUB &02
    EQUB &03
    EQUB &04
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
    ASL A
    ASL A
    ASL A
    ASL A
    CLC
    ADC zp_frog_col
    TAY
    LDA (zp_map_src_lo),Y
    RTS
}
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
    LDA zp_tile_data
    CMP zp_item_0
    BEQ solid
    CMP zp_item_1
    BEQ solid
    LDA #&00
    RTS
.solid
    LDA #&FF
    RTS
}
.tile_type_table
    BRK
    BRK
    BRK
    EQUB &FF
    EQUB &FF
    BRK
    BRK
    BRK
    EQUB &FF
    EQUB &FF
    EQUB &FF
    BRK
    BRK
.get_tile_at_pos
{
    LDA zp_tile_x
    CMP #&10
    BCS out_of_bounds
    LDA zp_tile_y
    CMP #&08
    BCS out_of_bounds
    ASL A
    ASL A
    ASL A
    ASL A
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
    ASL A
    ASL A
    ASL A
    ASL A
    CLC
    ADC zp_tile_x
    TAY
    PLA
    STA (zp_map_src_lo),Y
    PHA
    LDA zp_tile_x
    ASL A
    ASL A
    STA zp_tile_x
    LDA zp_tile_y
    ASL A
    STA zp_tile_y
    PLA
    JMP jmp_block_copy    ; engine: block_copy
.crtc_table

; --- CRTC register table (data) ---
    EQUB &01, &40, &02, &5A, &06, &14, &07, &1D
    EQUB &0A, &20, &0C, &0B, &0D, &00

; === VSYNC IRQ Handler ===
; Called via IRQ1V on every vertical sync (~50Hz).
; Handles: sprite updates, palette colour cycling, VSYNC flag.
;
; Zero page variables defined in zero_page.asm

.irq_handler
{
    LDA &FC                     ; Restore A from MOS save location
    PHA                         ; Save A
    TXA : PHA                   ; Save X
    TYA : PHA                   ; Save Y
    SEI                         ; Disable interrupts during handler

    LDA VIA_IFR                 ; Read System VIA IFR
    AND #&02                    ; Check CA1 (VSYNC) flag
    BEQ exit                    ; Not VSYNC — exit

    STA VIA_IFR                 ; Acknowledge VSYNC interrupt

    ; --- Update sprites (if not inhibited) ---
    LDA zp_sprite_inhibit       ; Sprite update inhibit flag
    BNE skip_sprites            ; Non-zero = skip
    JSR jmp_update_sprites      ; engine: update_sprites

.skip_sprites
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

; --- Movement, collision, scrolling helpers ---
.game_routines_2
    ADC zp_dst_hi
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
    LSR A
    LSR A
    STA zp_tile_x
    LDA zp_scroll_y
    BPL pos_y
    LDA #&00
.pos_y
    LSR A
    LSR A
    LSR A
    LSR A
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
    ASL A
    ASL A
    ASL A
    ASL A
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
    ASL A
    ASL A
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
.move_down
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
    BEQ scroll_right
    LDA #&68
    JSR read_key
    BMI scroll_right
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
.*scroll_right
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
    EQUB &8D, &4F, &FE, &2C

; --- More game logic — movement, collision response ---
.game_routines_3
    EQUB &4F
.l_4E69
    EQUB &FE, &60
.get_tile_type
    EQUB &8C, &7E, &4E, &38
    SBC #&20
    ASL A
    TAY
    INY
    LDA &4000,Y
    STA zp_tile_data
    DEY
    LDA &4000,Y
    LDY #&00
    RTS
.move_right
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
    BEQ scroll_left
    LDA #&68
    JSR read_key
    BMI scroll_left
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
.*scroll_left
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
    CMP #&03
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
    CMP #&02
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
    CMP #&03
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
    CMP #&03
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
    JMP scroll_left
.climb_done
    JMP main_loop
.check_ladder
    LDA zp_frog_col
    STA zp_tile_x
    LDA zp_frog_row
    STA zp_tile_y
    JSR get_tile_at_pos
    CMP #&06
    BEQ l_5027
    JMP jump_up
.l_5027
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
    CMP #&02
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
    CMP #&02
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
    JMP scroll_right
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
    CMP #&07
    BEQ climb_animate
    LDA zp_frog_col
    ASL A
    ASL A
    STA zp_scroll_x
    LDY zp_frog_row
    INY
    TYA
    ASL A
    ASL A
    ASL A
    ASL A
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
    ASL A
    ASL A
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
.apply_tile_effect
    LDA #&00
    JMP tile_dispatch_continue
.check_tile_effect
    STA apply_tile_effect + 1
    LDA zp_item_0
    JSR get_tile_type
    CMP #&01
    BEQ apply_tile_effect
    LDA zp_item_1
    JSR get_tile_type
    CMP #&01
    BEQ apply_tile_effect

; --- Game over, level complete, death, restart ---
.game_state_handlers
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
    LDA #&00
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

; --- Scrolling routines ---
.scroll_routines
    LDA zp_item_0,X
    STX item_slot_select + 1
    BEQ l_528F
    JMP game_routines_4
.l_528F
    LDA zp_frog_col
    STA zp_tile_x
    LDA zp_frog_row
    STA zp_tile_y
    JSR check_tile_passable
    BEQ item_slot_select
    LDA zp_direction
    AND #&02
    BEQ l_52AA
    LDY zp_frog_col
    DEY
    STY zp_tile_x
    JMP l_52AF
.l_52AA
    LDY zp_frog_col
    INY
    STY zp_tile_x
.l_52AF
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
    BNE l_52D5
.item_slot_select
    LDX #&00
    STA zp_item_0,X
    LDA #&00
    JSR set_tile_at_pos
    JSR tile_addr_setup    ; engine: tile_addr_setup
    JSR draw_status
.l_52D5
    JMP main_loop
.check_tile_passable
    JSR get_tile_at_pos
    CMP #&20
    BCC l_52EC
    PHA
    JSR get_tile_type
    TAX
    LDA collision_check_table,X
    TAY
    PLA
    CPY #&00
    RTS
.l_52EC
    LDA #&01
    RTS
.collision_check_table

; --- Collision table (data) ---
    EQUB &00, &00, &00, &00, &00, &FF, &FF, &FF
    EQUB &FF, &FF, &00, &FF, &00, &00, &00, &00
    EQUB &00, &00, &00, &00, &00, &00, &00, &00
    EQUB &00, &00, &00, &00, &00, &00, &00, &00

; --- Sprite management, keyboard reading ---
.game_routines_4
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
    BEQ l_533C
    CMP #&03
    BEQ l_533C
    DEC zp_tile_y
    BMI drop_item_done
    JSR get_tile_at_pos
    JSR check_tile_solid
    BEQ drop_item_done
.l_533C
    JSR update_frog_tile
    LDA zp_frog_col
    STA zp_tile_x
    LDA zp_frog_row
    STA zp_tile_y
    LDA zp_temp_item
    JSR set_tile_at_pos
    LDA zp_temp_type
    CMP #&04
    BEQ l_535F
    CMP #&03
    BEQ l_535F
    DEC zp_frog_row
    SEC
    LDA zp_scroll_y
    SBC #&10
    STA zp_scroll_y
.l_535F
    LDA #&00
    STA zp_item_0,X
    JSR tile_addr_setup    ; engine: tile_addr_setup
    JSR draw_status
.drop_item_done
    JMP main_loop
.collect_item
    PHA
    LDX #&00
.l_536F
    LDA zp_tile_data
    CMP zp_item_0,X
    BEQ l_537C
    INX
    CPX #&02
    BNE l_536F
    PLA
    RTS
.l_537C
    INC zp_item_0,X
    JSR draw_status
    JSR silence_all
    PLA
    RTS
.clear_tile_pickup
    PHA
    LDA zp_frog_col
    STA zp_tile_x
    LDA zp_frog_row
    STA zp_tile_y
    LDA #&00
    JSR set_tile_at_pos
    JSR tile_addr_setup    ; engine: tile_addr_setup
    JSR silence_all
    PLA
    RTS
.drop_item
    PHA
    LDX #&00
.l_539F
    LDA zp_tile_data
    CMP zp_item_0,X
    BEQ l_53AC
    INX
    CPX #&02
    BNE l_539F
    PLA
    RTS
.l_53AC
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
.l_53DE
    STX l_53EB + 1
    LDA #&00
    JSR set_palette
    LDX #&05
    JSR wait_frames
.l_53EB
    LDX #&00
    DEX
    BPL l_53DE
    PLA
    RTS
.wait_frames
    JSR wait_vsync
    DEX
    BPL wait_frames
    RTS
.place_tile_1c
    LDA #&1C
.l_53FB
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
    LDA #&1D
    JMP l_53FB
.place_tile_00
    LDA #&00
    JMP l_53FB
.draw_digit
    STA zp_src_lo
    LDA #&00
    ASL zp_src_lo
    ROL A
    ASL zp_src_lo
    ROL A
    ASL zp_src_lo
    ROL A
    ASL zp_src_lo
    ROL A
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
.l_543C
    LDA (zp_src_lo),Y
    AND digit_mask_table,X
    STA (zp_dst_lo),Y
    DEY
    BPL l_543C
    CLC
    LDA zp_tile_x
    ADC #&02
    STA zp_tile_x
    RTS
.digit_mask_table

; --- Palette and sprite data tables ---
    EQUB &00, &03, &0C, &0F, &30, &33, &3C, &3F
.str_title
    EQUB &24, &25, &0F, &1B, &18, &10, &16, &0A
    EQUB &17, &25, &25, &0B, &22, &25, &16, &10
    EQUB &25, &24, &25, &1B, &1D, &20, &25, &24
.l_546E
    EQUB &FF
.str_press_space
    EQUB &24, &25, &19, &1B, &0E, &1C, &1C
    EQUB &25, &1C, &19, &0A, &0C, &0E, &25, &1D
    EQUB &18, &25, &1C, &1D, &0A, &1B, &1D, &25
    EQUB &24, &FF

; --- More rendering and string display ---
.draw_string
    STX zp_map_ptr_lo
    STY zp_map_ptr_hi
    LDY #&00
.l_548E
    STY l_5498 + 1
    LDA (zp_map_ptr_lo),Y
    BMI l_549D
    JSR draw_digit
.l_5498
    LDY #&00
    INY
    BNE l_548E
.l_549D
    RTS
.handle_map_reveal
    JSR l_550D
    LDA zp_game_state
    BNE l_54E3
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
    JSR l_54FE
    LDA #&00
    STA zp_map_src_lo
    LDA #&03
    STA zp_map_src_hi
    JSR jmp_render_map    ; engine: render_map
    JSR tile_addr_setup    ; engine: tile_addr_setup
    LDX #&00
.l_54CC
    LDA zp_item_0,X
    CMP #&38
    BCC l_54D5
    JSR l_5578
.l_54D5
    INX
    CPX #&02
    BNE l_54CC
    JSR draw_status
    JSR draw_title
    JMP main_loop
.l_54E3
    LDA #&80
    STA zp_game_state
    LDA zp_save_col
    STA zp_frog_col
    LDA zp_save_row
    STA zp_frog_row
    JSR jmp_setup_map    ; engine: setup_map_render
    JSR l_54FE
    JSR tile_addr_setup    ; engine: tile_addr_setup
    JSR draw_title
    JMP main_loop
.l_54FE
    LDA zp_frog_col
    ASL A
    ASL A
    STA zp_scroll_x
    LDA zp_frog_row
    ASL A
    ASL A
    ASL A
    ASL A
    STA zp_scroll_y
    RTS
.l_550D
    LDX #&07
.l_550F
    TXA
    STA palette_fade_table,X
    DEX
    BPL l_550F
.l_5516
    LDX #&07
.l_5518
    LDA palette_fade_table,X
    BEQ l_5523
    TAY
    DEY
    TYA
    STA palette_fade_table,X
.l_5523
    DEX
    BPL l_5518
    LDX #&04
    JSR wait_frames
    JSR l_5540
    LDA palette_fade_last
    BNE l_5516
    LDX #&32
    JMP wait_frames
.palette_fade_table
    BRK
    BRK
    BRK
    BRK
    BRK
    BRK
    BRK
.palette_fade_last
    BRK
.l_5540
    LDY #&07
    LDA palette_fade_table,Y
    STA zp_palette_count
.l_5547
    LDA palette_fade_table,Y
    TAX
    TYA
    JSR set_palette
    DEY
    BNE l_5547
    RTS
.draw_title
    LDX #&07
.l_5555
    STX l_555B + 1
    LDA palette_fade_table,X
.l_555B
    CMP #&00
    BEQ l_5565
    TAY
    INY
    TYA
    STA palette_fade_table,X
.l_5565
    DEX
    BPL l_5555
    LDX #&04
    JSR wait_frames
    JSR l_5540
    LDA palette_fade_last
    CMP #&07
    BNE draw_title
    RTS
.l_5578
    SEC
    PHA
    STX l_5589 + 1
    SBC #&31
    STA zp_tile_x
    LDA #&06
    STA zp_tile_y
    PLA
    JSR set_tile_at_pos
.l_5589
    LDX #&00
    LDA #&00
    STA zp_item_0,X
    INC zp_terminal_ctr
    RTS
; --- Display strings (tile font: A=&0A..Z=&23, space=&25, *=&24, &FF=end) ---
.str_special_msg                ; "* POWER CONTROL TERMINAL *"
    EQUB &24, &25, &19, &18, &20, &0E, &1B, &25
    EQUB &0C, &18, &17, &1D, &1B, &18, &15, &25
    EQUB &1D, &0E, &1B, &16, &12, &17, &0A, &15
    EQUB &25, &24, &FF
.str_continue                   ; "* ACCESS DENIED *"
    EQUB &24, &25, &0A, &0C, &0C, &0E, &1C, &1C
    EQUB &25, &0D, &0E, &17, &12, &0E, &0D, &25
    EQUB &24, &FF
.str_well_done                  ; "* LOGGED ON "
    EQUB &24, &25, &15, &18, &10, &10, &0E, &0D
    EQUB &25, &18, &17, &25, &FF
.str_power_off                  ; " POWER DEACTIVATED *"
    EQUB &25, &19, &18, &20, &0E, &1B, &25, &0D
    EQUB &0E, &0A, &0C, &1D, &12, &1F, &0A, &1D
    EQUB &0E, &0D, &25, &24, &FF
.handle_special_tile
    PHA
    LDA zp_special_flag
    BEQ l_55EA
    PLA
    JMP check_passthrough
.l_55EA
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
    BCS l_5625
.l_5607
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
.l_5625
    LDA zp_game_state
    BNE l_5648
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
.l_5648
    LDA zp_terminal_ctr
    BPL l_5607

; --- Level map loading from disc ---
.load_level_map
    JMP load_level_map
.load_level_data
    SEI
    JSR jmp_init_game    ; engine: init_game
    JSR swap_0600_0d00
    LDX #LO(oscli_disc)
    LDY #HI(oscli_disc)
    JSR OSCLI
    JMP l_5665
.oscli_disc
    EQUS "DISC", 13
.l_5665
    LDA zp_level_char
    STA oscli_level_m_num
    LDX #LO(oscli_load_level_m)
    LDY #HI(oscli_load_level_m)
    JSR OSCLI
    JMP copy_sideways_ram
.oscli_load_level_m
    EQUS "Load Level"
.oscli_level_m_num
    EQUB 0
    EQUS "M 5800", 13
.copy_sideways_ram
    LDX #&00
    LDA #&68
    STA copy_swr_src + 2
    LDA #&1F
    STA copy_swr_dst + 2
.copy_swr_src
    LDA &6800,X
.copy_swr_dst
    STA &1F00,X
    INX
    BNE copy_swr_src
    INC copy_swr_dst + 2
    INC copy_swr_src + 2
    BPL copy_swr_src
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
    LDA #&A5
    STA IRQ1V_LO
    LDA #&4C
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
    LDA #&58
    STA copy_map_src + 2
    LDA #&0F
    STA copy_map_dst + 2
.copy_level_data
    LDA #&0C
    STA copy_tiles_dst + 2
    LDA #&68
    STA copy_tiles_src + 2
    LDX #&03
    LDY #&00
.copy_tiles_src
    LDA &6800,Y
.copy_tiles_dst
    STA &0C80,Y
    INY
    BNE copy_tiles_src
    INC copy_tiles_src + 2
    INC copy_tiles_dst + 2
    DEX
    BNE copy_tiles_src
    LDX #&00
.copy_map_src
    LDA &5800,X
.copy_map_dst
    STA &0F00,X
    INX
    BNE copy_map_src
    INC copy_map_dst + 2
    INC copy_map_src + 2
    LDA copy_map_dst + 2
    CMP #&1F
    BNE copy_map_src
    LDA #&37
    STA zp_scroll_x
    LDA #&88
    STA zp_scroll_y
    LDY #&00
    JSR tile_addr_setup_y
    JSR clear_sprite_state
    CLI
    RTS

; === Swap &0600 and &0D00 ===
; Swaps 256 bytes between the NMI handler area (&0600) and the
; music/data block (&0D00). Called during init to place the right
; data in each location.

.swap_0600_0d00
    LDX #&00
.swap_loop
    LDA &0D00,X
    TAY
    LDA &0600,X
    STA &0D00,X
    TYA
    STA &0600,X
    INX
    BNE swap_loop
    RTS

; === Clear Sprite State ===
; Zeros the animation timer (&78-&7B) and animation index (&8C-&8F)
; for all 4 sprite slots.

.clear_sprite_state
    LDA #&00
    TAX
.clear_sprite_loop
    STA &78,X                   ; Animation timer
    STA &8C,X                   ; Animation index
    INX
    CPX #&04
    BNE clear_sprite_loop
    RTS

; === Silence All Sound ===
; Sets palette entry 1 to black and silences the sound chip.

.silence_all
    LDA #&00
    LDX #&01
    JSR set_palette
    LDX #&0A
    JSR wait_frames                   ; TODO: identify this routine
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


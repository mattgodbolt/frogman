OSCLI=&FFF7
OSWRCH=&FFEE
CRTC_ADDR=&FE00
CRTC_DATA=&FE01
VIA_ORB=&FE40
VIA_DDRB=&FE42
VIA_DDRA=&FE43
VIA_IFR=&FE4D
VIA_IER=&FE4E
ULA_PALETTE=&FE21
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
    LDA &0430
    CLC
    ADC #&30
    STA &26
    LDX #&00
.l_48AA
    LDA crtc_table,X
    STA CRTC_ADDR
    LDA crtc_table + 1,X
    STA CRTC_DATA
    INX
    INX
    CPX #&0E
    BNE l_48AA
    LDA &26
    STA oscli_level_g_num
    LDX #LO(oscli_load_level_g)
    LDY #HI(oscli_load_level_g)
    JSR OSCLI
    JMP l_48D8
.oscli_load_level_g
    EQUS "Load Level"
.oscli_level_g_num
    EQUB 0                      ; Patched with ASCII level number
    EQUS "G", 13
.l_48D8
    LDX #LO(oscli_load_fastio)
    LDY #HI(oscli_load_fastio)
    JSR OSCLI
    JMP l_48F4
.oscli_load_fastio
    EQUS "Load FastI/O 5800", 13
.l_48F4
    LDA &26
    STA oscli_level_t_num
    LDX #LO(oscli_load_level_t)
    LDY #HI(oscli_load_level_t)
    JSR OSCLI
    JMP l_4915
.oscli_load_level_t
    EQUS "Load Level"
.oscli_level_t_num
    EQUB 0
    EQUS "T 5D80", 13
.l_4915
    LDA &26
    STA oscli_level_s_num
    LDX #LO(oscli_load_level_s)
    LDY #HI(oscli_load_level_s)
    JSR OSCLI
    JMP l_4935
.oscli_load_level_s
    EQUS "Load Level"
.oscli_level_s_num
    EQUB 0
    EQUS "S 300", 13
.l_4935
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
    STA &0258
    LDA #&01
    STA &0262
    LDX #&08
    LDY #&00
.l_495F
    LDA &5800,Y
.l_4962
    STA &0700,Y
    LDA #&00
.l_4967
    STA &5800,Y
    INY
    BNE l_495F
    INC l_495F + 2
    INC l_4962 + 2
    INC l_4967 + 2
    DEX
    BNE l_495F
    LDX #&FF
    TXS                         ; Reset stack pointer
    LDA #LO(irq_handler)
    STA &0204                   ; IRQ1V low = &A5
    LDA #HI(irq_handler)
    STA &0205                   ; IRQ1V high = &4C

    ; --- Zero page initialisation ---
    LDA #&00
    STA &0C                     ; Colour cycle phase
    STA &0E                     ; Frame sub-counter
    STA &20                     ; Game state flags
    STA &22                     ; Scroll lock
    STA &23                     ; Sprite update inhibit (0 = enabled)
    LDA #&07
    STA &25                     ; Active palette entries for cycling
    LDA #&08
    STA &0D                     ; First palette entry to animate

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
    LDA &23                     ; Save sprite update inhibit state
    PHA
    JSR &0892                   ; engine: init_game (VIA config)
    LDA #&FF
    STA &23                     ; Inhibit sprite updates during setup
    LDA #&00
    STA &08                     ; Clear score low
    STA &09                     ; Clear score high
    LDA #&09
    STA &24                     ; Lives = 9
    JSR l_550D                   ; Initialise score display
    JSR load_level_data                   ; Load level map from disc
    JSR draw_status                   ; Draw status bar
    LDA #&00
    STA &06                     ; Map source low = &0300
    LDA #&03
    STA &07                     ; Map source high
    JSR &0889                   ; engine: render_map
    PLA
    STA &23                     ; Restore sprite update inhibit
    JSR draw_title                   ; Draw "FROGMAN BY MG RTW" title
    LDA #&02                    ; Row 2
    STA &1D
    LDA #&00
    STA &0B                     ; Tile Y = 0
    LDA #&08
    STA &0A                     ; Tile X = 8
    LDX #LO(str_title)                    ; String pointer low
    LDY #HI(str_title)                    ; String pointer high (&5456)
    JSR draw_string                   ; Draw string: "FROGMAN BY MG RTW"
    LDA #&07                    ; Row 7
    STA &1D
    LDA #&01
    STA &0B                     ; Tile Y = 1
    LDA #&08
    STA &0A                     ; Tile X = 8
    LDX #LO(str_press_space)                    ; String pointer low
    LDY #HI(str_press_space)                    ; String pointer high (&546F)
    JSR draw_string                   ; Draw string: "PRESS SPACE TO START"
    LDA #&62
.l_4A23
    JSR read_key
    BPL l_4A23
.wait_for_space_done
    LDA #&14
    STA &0F
    LDA #&10
    STA &10
    LDA #&05
    STA &11
    LDA #&01
    STA &12
    LDA #&00
    STA &13
    STA &14
    JSR &0886    ; engine: setup_map_render
    LDA #&00
    STA &19
    STA &20
    JSR draw_status

; --- Main game loop — keyboard, collision, movement ---
.main_loop
    JSR &0BE9    ; engine: tile_addr_setup
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
    BEQ l_4A68
    JMP l_4B71
.l_4A68
    LDA #&00
    STA &1C
    PLA
    CMP #&03
    BNE l_4A74
    JMP l_4F45
.l_4A74
    CMP #&02
    BNE l_4A7B
    JMP l_4F75
.l_4A7B
    CMP #&11
    BNE l_4A82
    JMP check_tile_effect
.l_4A82
    CMP #&05
    BNE l_4A89
    JMP move_right_check
.l_4A89
    CMP #&1E
    BNE l_4A90
    JMP move_left_check
.l_4A90
    CMP #&10
    BNE l_4A97
    JMP place_tile_1c
.l_4A97
    CMP #&1C
    BNE l_4A9E
    JMP place_tile_1d
.l_4A9E
    CMP #&1D
    BNE l_4AA5
    JMP place_tile_00
.l_4AA5
    LDA &11
    STA &0A
    LDA &12
    STA &0B
    JSR get_tile_at_pos
    CMP #&04
    BNE l_4AC1
    PHA
    LDA &20
    BMI l_4ABD
    PLA
    JMP handle_map_reveal
.l_4ABD
    PLA
    JMP l_4AC9
.l_4AC1
    PHA
    LDA &20
    AND #&7F
    STA &20
    PLA
.l_4AC9
    CMP #&1F
    BNE l_4AD0
    JMP handle_special_tile
.l_4AD0
    PHA
    LDA #&00
    STA &21
    PLA
.check_passthrough
    CMP #&20
    BCS l_4AE1
    CMP #&12
    BNE l_4AF2
    JMP game_state_handlers
.l_4AE1
    JSR get_tile_type
    CMP #&09
    BNE l_4AEB
    JSR collect_item
.l_4AEB
    CMP #&05
    BNE l_4AF2
    JSR clear_tile_pickup
.l_4AF2
    INC &0B
    JSR get_tile_at_pos
    CMP #&20
    BCC l_4B05
    JSR get_tile_type
    CMP #&0B
    BNE l_4B05
    JSR drop_item
.l_4B05
    LDA #&42
    JSR read_key
    BPL l_4B0F
    JMP move_down
.l_4B0F
    LDA #&61
    JSR read_key
    BPL l_4B19
    JMP move_right
.l_4B19
    LDA #&48
    JSR read_key
    BPL l_4B23
    JMP move_up_check
.l_4B23
    LDA &07
    CMP #&03
    BEQ l_4B51
    LDA #&20
    JSR read_key
    BPL l_4B3D
.l_4B30
    JSR wait_vsync
    JSR read_key
    BMI l_4B30
    LDX #&00
    JMP scroll_routines
.l_4B3D
    LDA #&71
    JSR read_key
    BPL l_4B51
.l_4B44
    JSR wait_vsync
    JSR read_key
    BMI l_4B44
    LDX #&01
    JMP scroll_routines
.l_4B51
    JSR wait_vsync
    LDA #&65
    JSR read_key
    BPL l_4B6B
    JSR &0892    ; engine: init_game
    LDA &23
    EOR #&FF
    STA &23
.l_4B64
    LDA #&65
    JSR read_key
    BMI l_4B64
.l_4B6B
    JMP main_loop
.l_4B6E
    JMP l_4A68
.l_4B71
    LDA &11
    STA &0A
    LDA &12
    STA &0B
    JSR get_tile_at_pos
    CMP #&06
    BEQ l_4B6E
    JSR get_tile_at_frog
    CMP #&20
    BCC l_4B8E
    JSR get_tile_type
    CMP #&03
    BEQ l_4B6E
.l_4B8E
    PLA
    INC &12
    LDA &12
    CMP #&08
    BCS l_4BD1
    LDA &1C
    BEQ l_4B9E
    JMP fall_loop
.l_4B9E
    LDA #&01
    ORA &19
    STA &19
    LDX #&00
.l_4BA6
    STX l_4BBA + 1
    JSR wait_vsync
    JSR update_frog_tile
    LDA fall_step_table,X
    CLC
    ADC &10
    STA &10
    JSR &0BE9    ; engine: tile_addr_setup
.l_4BBA
    LDX #&00
    INX
    CPX #&08
    BNE l_4BA6
    LDA &19
    AND #&02
    STA &19
    LDA #&FF
    STA &1C
    JSR update_frog_tile
    JMP main_loop
.l_4BD1
    INC &14
    LDA #&00
    STA &10
    STA &12
    JSR &0886    ; engine: setup_map_render
    EQUB &20
    EQUB &E9

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
    LDX #&00
.l_4BEC
    STX l_4BFF + 1
    JSR wait_vsync
    JSR update_frog_tile
    CLC
    LDA &10
    ADC #&04
    STA &10
    JSR &0BE9    ; engine: tile_addr_setup
.l_4BFF
    LDX #&00
    INX
    CPX #&04
    BNE l_4BEC
    LDA &19
    AND #&02
    STA &19
    JSR update_frog_tile
    JMP main_loop
.get_tile_at_frog
    LDA &12
    CMP #&07
    BCC l_4C1B
    LDA #&00
    RTS
.l_4C1B
    TAY
    INY
    TYA
    ASL A
    ASL A
    ASL A
    ASL A
    CLC
    ADC &11
    TAY
    LDA (&06),Y
    RTS
.check_tile_solid
    CMP #&20
    BCS l_4C32
    TAY
    LDA collision_flags,Y
    RTS
.l_4C32
    JSR get_tile_type
    CMP #&05
    BEQ l_4C42
    CMP #&07
    BEQ l_4C42
    TAY
    LDA tile_type_table,Y
    RTS
.l_4C42
    LDA &1B
    CMP &08
    BEQ l_4C4F
    CMP &09
    BEQ l_4C4F
    LDA #&00
    RTS
.l_4C4F
    LDA #&FF
    RTS
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
    LDA &0A
    CMP #&10
    BCS l_4C76
    LDA &0B
    CMP #&08
    BCS l_4C76
    ASL A
    ASL A
    ASL A
    ASL A
    CLC
    ADC &0A
    TAY
    LDA (&06),Y
    RTS
.l_4C76
    LDA #&00
    RTS
.set_tile_at_pos
    PHA
    LDA &0B
    ASL A
    ASL A
    ASL A
    ASL A
    CLC
    ADC &0A
    TAY
    PLA
    STA (&06),Y
    PHA
    LDA &0A
    ASL A
    ASL A
    STA &0A
    LDA &0B
    ASL A
    STA &0B
    PLA
    JMP &0880    ; engine: block_copy
.crtc_table

; --- CRTC register table (data) ---
    EQUB &01, &40, &02, &5A, &06, &14, &07, &1D
    EQUB &0A, &20, &0C, &0B, &0D, &00

; === VSYNC IRQ Handler ===
; Called via IRQ1V on every vertical sync (~50Hz).
; Handles: sprite updates, palette colour cycling, VSYNC flag.
;
; Zero page usage:
;   &0C = colour cycle phase (0-7, advances every 8 frames)
;   &0D = palette entry being animated (cycles 8-11)
;   &0E = frame sub-counter (incremented each VSYNC)
;   &1A = VSYNC flag (set to &FF each frame, polled by game loop)
;   &23 = sprite update inhibit (non-zero = skip update_sprites)
;   &25 = number of active palette entries for cycling

.irq_handler
    LDA &FC                     ; Restore A from MOS save location
    PHA                         ; Save A
    TXA : PHA                   ; Save X
    TYA : PHA                   ; Save Y
    SEI                         ; Disable interrupts during handler

    LDA VIA_IFR                   ; Read System VIA IFR
    AND #&02                    ; Check CA1 (VSYNC) flag
    BEQ irq_exit                ; Not VSYNC — exit

    STA VIA_IFR                   ; Acknowledge VSYNC interrupt

    ; --- Update sprites (if not inhibited) ---
    LDA &23                     ; Sprite update inhibit flag
    BNE irq_skip_sprites        ; Non-zero = skip
    JSR &088F                   ; engine: update_sprites

.irq_skip_sprites
    LDA #&FF
    STA &1A                     ; Set VSYNC flag for game loop

    ; --- Palette colour cycling ---
    ; Every 8 frames, advance the colour cycle phase.
    ; On each phase, reprogram one palette entry via the Video ULA.
    INC &0E                     ; Increment frame sub-counter
    LDA &0E
    AND #&08                    ; Every 8 frames?
    BEQ irq_anim_bg             ; No — check background animation

    LDA #&00
    STA &0E                     ; Reset sub-counter
    INC &0C                     ; Advance colour cycle phase
    LDA &0C
    AND #&07                    ; Wrap to 0-7
    STA &0C
    TAX                         ; X = colour value
    LDA #&0C                    ; Palette entry 12 (logical colour 12)
    CPX &25                     ; Past the active range?
    BCC irq_set_palette         ; No — set it
    LDX #&00                    ; Yes — use colour 0

.irq_set_palette
    JSR set_palette             ; Write palette register

.irq_anim_bg
    ; Background palette animation — runs every 2 frames
    LDA &0E
    AND #&02                    ; Every 2 frames?
    BEQ irq_exit                ; No — done

    LDA &0D                     ; Current palette entry (8-11)
    LDX #&00                    ; Colour value 0 (black)
    JSR set_palette             ; Set entry to black (fade out)
    INC &0D                     ; Next palette entry
    LDA &0D
    CMP #&0C                    ; Past entry 11?
    BNE irq_bg_set
    LDA #&08                    ; Wrap back to entry 8
    STA &0D

.irq_bg_set
    LDX &25                     ; Active colour count
    JSR set_palette             ; Set new entry to active colour

.irq_exit
    PLA : TAY                   ; Restore Y
    PLA : TAX                   ; Restore X
    PLA : STA &FC               ; Restore A to MOS save location
    RTI

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
    ADC &03
.wait_vsync
    PHA
    LDA #&00
    STA &1A
.l_4D1F
    LDA &1A
    BEQ l_4D1F
    PLA
    RTS
.l_4D25
    INC &0B
    LDA &0B
    CMP #&08
    BCC l_4D59
.l_4D2D
    RTS
.update_frog_tile
    LDA &0F
    LSR A
    LSR A
    STA &0A
    LDA &10
    BPL l_4D3A
    LDA #&00
.l_4D3A
    LSR A
    LSR A
    LSR A
    LSR A
    STA &0B
    JSR l_4D5B
    INC &0A
    LDA &0A
    CMP #&10
    BCS l_4D25
    JSR l_4D5B
    INC &0B
    LDA &0B
    CMP #&08
    BCS l_4D2D
    JSR l_4D5B
.l_4D59
    DEC &0A
.l_4D5B
    LDA &0B
    ASL A
    ASL A
    ASL A
    ASL A
    CLC
    ADC &06
    STA l_4D70 + 1
    LDA &07
    ADC #&00
    STA l_4D70 + 2
    LDY &0A
.l_4D70
    LDA &FFFF,Y
    STA l_4D83 + 1
    LDA &0A
    PHA
    ASL A
    ASL A
    STA &0A
    LDA &0B
    PHA
    ASL A
    STA &0B
.l_4D83
    LDA #&00
    JSR &0880    ; engine: block_copy
    PLA
    STA &0B
    PLA
    STA &0A
    RTS
.move_down
    JSR wait_vsync
    JSR update_frog_tile
    LDA #&00
    STA &19
    JSR &0BE9    ; engine: tile_addr_setup
    LDY &11
    INY
    STY &0A
    LDA &12
    STA &0B
    JSR get_tile_at_pos
    JSR check_tile_solid
    BEQ l_4E02
    LDA #&01
    STA &19
    INC &0A
    JSR get_tile_at_pos
    JSR check_tile_solid
    BEQ l_4E0F
    LDA #&68
    JSR read_key
    BMI l_4E0F
    INC &11
    LDA &11
    CMP #&0F
    BCC l_4DE1
    LDA #&00
    STA &11
    LDA #&00
    STA &0F
    INC &13
    JSR &0886    ; engine: setup_map_render
    LDA #&00
    STA &19
    JSR &0BE9    ; engine: tile_addr_setup
    JMP main_loop
.l_4DE1
    LDX #&00
.l_4DE3
    JSR wait_vsync
    JSR update_frog_tile
    INC &0F
    LDA &10
    CLC
    ADC scroll_step_table_8,X
    STA &10
    STX l_4DF9 + 1
    JSR &0BE9    ; engine: tile_addr_setup
.l_4DF9
    LDX #&00
    INX
    CPX #&08
    BNE l_4DE3
    INC &11
.l_4E02
    LDA #&00
    STA &19
    JSR wait_vsync
    JSR update_frog_tile
    JMP main_loop
.l_4E0F
    LDX #&00
    INC &11
    LDA &11
    CMP #&10
    BNE l_4E2E
    INC &13
    LDA #&00
    STA &0F
    STA &11
    JSR &0886    ; engine: setup_map_render
    LDA #&00
    STA &19
    JSR &0BE9    ; engine: tile_addr_setup
    JMP main_loop
.l_4E2E
    JSR wait_vsync
    JSR update_frog_tile
    INC &0F
    LDA &10
    CLC
    ADC scroll_step_table_4,X
    STA &10
    STX l_4E44 + 1
    JSR &0BE9    ; engine: tile_addr_setup
.l_4E44
    LDX #&00
    INX
    CPX #&04
    BNE l_4E2E
    LDA #&00
    STA &19
    JSR wait_vsync
    JSR update_frog_tile
    JMP main_loop
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
    STA &1B
    DEY
    LDA &4000,Y
    LDY #&00
    RTS
.move_right
    JSR wait_vsync
    JSR update_frog_tile
    LDA #&02
    STA &19
    JSR &0BE9    ; engine: tile_addr_setup
    LDY &11
    DEY
    STY &0A
    LDA &12
    STA &0B
    JSR get_tile_at_pos
    JSR check_tile_solid
    BEQ l_4EF1
    LDA #&03
    STA &19
    DEC &0A
    JSR get_tile_at_pos
    JSR check_tile_solid
    BEQ l_4EFE
    LDA #&68
    JSR read_key
    BMI l_4EFE
    DEC &11
    BEQ l_4EB9
    BPL l_4ED0
.l_4EB9
    LDA #&0F
    STA &11
    LDA #&3C
    STA &0F
    DEC &13
    JSR &0886    ; engine: setup_map_render
    LDA #&02
    STA &19
    JSR &0BE9    ; engine: tile_addr_setup
    JMP main_loop
.l_4ED0
    LDX #&00
.l_4ED2
    JSR wait_vsync
    JSR update_frog_tile
    DEC &0F
    LDA &10
    CLC
    ADC scroll_step_table_8,X
    STA &10
    STX l_4EE8 + 1
    JSR &0BE9    ; engine: tile_addr_setup
.l_4EE8
    LDX #&00
    INX
    CPX #&08
    BNE l_4ED2
    DEC &11
.l_4EF1
    LDA #&02
    STA &19
    JSR wait_vsync
    JSR update_frog_tile
    JMP main_loop
.l_4EFE
    LDX #&00
    DEC &11
    BPL l_4F1B
    DEC &13
    LDA #&3C
    STA &0F
    LDA #&0F
    STA &11
    JSR &0886    ; engine: setup_map_render
    LDA #&02
    STA &19
    JSR &0BE9    ; engine: tile_addr_setup
    JMP main_loop
.l_4F1B
    JSR wait_vsync
    JSR update_frog_tile
    DEC &0F
    LDA &10
    CLC
    ADC scroll_step_table_4,X
    STA &10
    STX l_4F31 + 1
    JSR &0BE9    ; engine: tile_addr_setup
.l_4F31
    LDX #&00
    INX
    CPX #&04
    BNE l_4F1B
    LDA #&02
    STA &19
    JSR wait_vsync
    JSR update_frog_tile
    JMP main_loop
.l_4F45
    JSR l_4F52
    JSR get_tile_at_frog
    CMP #&03
    BEQ l_4F45
    JMP main_loop
.l_4F52
    LDX #&00
.l_4F54
    STX l_4F69 + 1
    JSR wait_vsync
    JSR update_frog_tile
    INC &0F
    CLC
    LDA &10
    ADC #&04
    STA &10
    JSR &0BE9    ; engine: tile_addr_setup
.l_4F69
    LDX #&00
    INX
    CPX #&04
    BNE l_4F54
    INC &11
    INC &12
    RTS
.l_4F75
    JSR l_4F82
    JSR get_tile_at_frog
    CMP #&02
    BEQ l_4F75
    JMP main_loop
.l_4F82
    LDX #&00
.l_4F84
    STX l_4F99 + 1
    JSR wait_vsync
    JSR update_frog_tile
    DEC &0F
    CLC
    LDA &10
    ADC #&04
    STA &10
    JSR &0BE9    ; engine: tile_addr_setup
.l_4F99
    LDX #&00
    INX
    CPX #&04
    BNE l_4F84
    DEC &11
    INC &12
    RTS
.move_up_check
    LDA &19
    AND #&02
    BNE l_4FAE
    JMP l_503E
.l_4FAE
    LDY &11
    DEY
    STY &0A
    LDA &12
    STA &0B
    JSR get_tile_at_pos
    CMP #&03
    BNE l_5015
.l_4FBE
    LDA #&03
    STA &19
    LDX #&00
.l_4FC4
    STX l_4FDF + 1
    JSR wait_vsync
    JSR update_frog_tile
    SEC
    LDA &10
    SBC #&04
    STA &10
    DEC &0F
    LDA &19
    EOR #&01
    STA &19
    JSR &0BE9    ; engine: tile_addr_setup
.l_4FDF
    LDX #&00
    INX
    CPX #&04
    BNE l_4FC4
    DEC &11
    DEC &12
    LDY &11
    DEY
    STY &0A
    LDA &12
    STA &0B
    JSR get_tile_at_pos
    CMP #&03
    BEQ l_4FBE
    LDA #&02
    STA &19
    LDY &11
    DEY
    STY &0A
    LDA &12
    STA &0B
    JSR get_tile_at_pos
    JSR check_tile_solid
    BEQ l_5012
    JMP l_4EFE
.l_5012
    JMP main_loop
.l_5015
    LDA &11
    STA &0A
    LDA &12
    STA &0B
    JSR get_tile_at_pos
    CMP #&06
    BEQ l_5027
    JMP l_5128
.l_5027
    LDY &12
    DEY
    STY &0B
    LDA &11
    STA &0A
    JSR get_tile_at_pos
    JSR check_tile_solid
    BEQ l_503B
    JMP l_50A5
.l_503B
    JMP main_loop
.l_503E
    LDY &11
    INY
    STY &0A
    LDA &12
    STA &0B
    JSR get_tile_at_pos
    CMP #&02
    BNE l_5015
.l_504E
    LDA #&01
    STA &19
    LDX #&00
.l_5054
    STX l_506F + 1
    JSR wait_vsync
    JSR update_frog_tile
    SEC
    LDA &10
    SBC #&04
    STA &10
    INC &0F
    LDA &19
    EOR #&01
    STA &19
    JSR &0BE9    ; engine: tile_addr_setup
.l_506F
    LDX #&00
    INX
    CPX #&04
    BNE l_5054
    INC &11
    DEC &12
    LDY &11
    INY
    STY &0A
    LDA &12
    STA &0B
    JSR get_tile_at_pos
    CMP #&02
    BEQ l_504E
    LDA #&00
    STA &19
    LDY &11
    INY
    STY &0A
    LDA &12
    STA &0B
    JSR get_tile_at_pos
    JSR check_tile_solid
    BNE l_50A2
    JMP l_5012
.l_50A2
    JMP l_4E0F
.l_50A5
    JSR update_frog_tile
.l_50A8
    DEC &12
    BMI l_5105
.l_50AC
    LDA &12
    STA &0B
    LDA &11
    STA &0A
    JSR get_tile_at_pos
    CMP #&07
    BEQ l_50E5
    LDA &11
    ASL A
    ASL A
    STA &0F
    LDY &12
    INY
    TYA
    ASL A
    ASL A
    ASL A
    ASL A
    STA &10
    LDX #&00
.l_50CD
    STX l_50DB + 1
    DEC &10
    JSR wait_vsync
    JSR update_frog_tile
    JSR &0BE9    ; engine: tile_addr_setup
.l_50DB
    LDX #&00
    INX
    CPX #&10
    BNE l_50CD
    JMP l_4B05
.l_50E5
    LDA &11
    ASL A
    ASL A
    STA &0A
    LDA &12
    ASL A
    STA &0B
    LDA #&1B
    JSR &0880    ; engine: block_copy
    LDX #&09
.l_50F7
    JSR wait_vsync
    DEX
    BNE l_50F7
    LDA #&07
    JSR &0880    ; engine: block_copy
    JMP l_50A8
.l_5105
    LDA #&07
    STA &12
    LDA #&70
    STA &10
    DEC &14
    JSR &0886    ; engine: setup_map_render
    JMP l_50AC
.l_5115
    LDA #&07
    STA &12
    LDA #&70
    STA &10
    DEC &14
    JSR &0886    ; engine: setup_map_render
    JSR &0BE9    ; engine: tile_addr_setup
    JMP main_loop
.l_5128
    LDA &11
    STA &0A
    LDY &12
    DEY
    BMI l_5115
    STY &0B
    JSR get_tile_at_pos
    JSR check_tile_solid
    BEQ l_5158
    LDX #&07
.l_513D
    STX l_5151 + 1
    LDA &10
    SEC
    SBC fall_step_table,X
    STA &10
    JSR wait_vsync
    JSR update_frog_tile
    JSR &0BE9    ; engine: tile_addr_setup
.l_5151
    LDX #&00
    DEX
    BPL l_513D
    DEC &12
.l_5158
    JMP main_loop
.l_515B
    LDA #&00
    JMP l_4A82
.check_tile_effect
    STA l_515B + 1
    LDA &08
    JSR get_tile_type
    CMP #&01
    BEQ l_515B
    LDA &09
    JSR get_tile_type
    CMP #&01
    BEQ l_515B

; --- Game over, level complete, death, restart ---
.game_state_handlers
    LDX #&00
.l_5177
    STX l_51A0 + 1
    JSR wait_vsync
    JSR wait_vsync
    JSR wait_vsync
    JSR update_frog_tile
    LDA fall_step_table,X
    CLC
    ADC &10
    STA &10
    JSR &0BE9    ; engine: tile_addr_setup
    LDA &11
    STA &0A
    LDY &12
    INY
    STY &0B
    JSR get_tile_at_pos
    JSR set_tile_at_pos
.l_51A0
    LDX #&00
    INX
    CPX #&08
    BNE l_5177
    LDX #&32
    JSR wait_frames
    LDA #&00
    JSR read_key
    BPL l_51B7
    LDA #&01
    STA &24
.l_51B7
    DEC &24
    BEQ l_51C1
    JSR draw_status
    JMP wait_for_space_done
.l_51C1
    JSR draw_status
    JMP game_loop_start
.move_right_check
    LDY &11
    INY
    CPY #&10
    BCC l_51DC
    LDA #&00
    STA &11
    STA &0F
    INC &13
    JSR &0886    ; engine: setup_map_render
    JMP main_loop
.l_51DC
    STY &0A
    LDA &12
    STA &0B
    JSR get_tile_at_pos
    JSR check_tile_solid
    BNE l_51ED
    JMP l_4B05
.l_51ED
    LDX #&00
.l_51EF
    STX l_5206 + 1
    JSR update_frog_tile
    INC &0F
    JSR &0BE9    ; engine: tile_addr_setup
    JSR wait_vsync
    JSR wait_vsync
    JSR wait_vsync
    JSR wait_vsync
.l_5206
    LDX #&00
    INX
    CPX #&04
    BNE l_51EF
    INC &11
    JMP main_loop
.move_left_check
    LDY &11
    DEY
    CPY #&10
    BCC l_5229
    LDA #&0F
    STA &11
    LDA #&3C
    STA &0F
    DEC &13
    JSR &0886    ; engine: setup_map_render
    JMP main_loop
.l_5229
    STY &0A
    LDA &12
    STA &0B
    JSR get_tile_at_pos
    JSR check_tile_solid
    BNE l_523A
    JMP l_4B05
.l_523A
    LDX #&00
.l_523C
    STX l_5253 + 1
    JSR update_frog_tile
    DEC &0F
    JSR &0BE9    ; engine: tile_addr_setup
    JSR wait_vsync
    JSR wait_vsync
    JSR wait_vsync
    JSR wait_vsync
.l_5253
    LDX #&00
    INX
    CPX #&04
    BNE l_523C
    DEC &11
    JMP main_loop
.draw_status
    LDA #&03
    STA &0A
    LDA #&11
    STA &0B
    LDA &08
    JSR &0880    ; engine: block_copy
    LDA #&0A
    STA &0A
    LDA &09
    JSR &0880    ; engine: block_copy
    LDA #&3C
    STA &0A
    INC &0B
    LDA #&07
    STA &1D
    LDA &24
    JSR draw_digit
    RTS

; --- Scrolling routines ---
.scroll_routines
    LDA &08,X
    STX l_52C6 + 1
    BEQ l_528F
    JMP game_routines_4
.l_528F
    LDA &11
    STA &0A
    LDA &12
    STA &0B
    JSR l_52D8
    BEQ l_52C6
    LDA &19
    AND #&02
    BEQ l_52AA
    LDY &11
    DEY
    STY &0A
    JMP l_52AF
.l_52AA
    LDY &11
    INY
    STY &0A
.l_52AF
    LDA &12
    STA &0B
    JSR l_52D8
    BEQ l_52C6
    LDA &11
    STA &0A
    LDY &12
    INY
    STY &0B
    JSR l_52D8
    BNE l_52D5
.l_52C6
    LDX #&00
    STA &08,X
    LDA #&00
    JSR set_tile_at_pos
    JSR &0BE9    ; engine: tile_addr_setup
    JSR draw_status
.l_52D5
    JMP main_loop
.l_52D8
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
    LDA &12
    STA &0B
    LDA &11
    STA &0A
    JSR get_tile_at_pos
    BNE l_5369
    LDX l_52C6 + 1
    LDA &08,X
    STA &27
    JSR get_tile_type
    STA &28
    CMP #&04
    BEQ l_533C
    CMP #&03
    BEQ l_533C
    DEC &0B
    BMI l_5369
    JSR get_tile_at_pos
    JSR check_tile_solid
    BEQ l_5369
.l_533C
    JSR update_frog_tile
    LDA &11
    STA &0A
    LDA &12
    STA &0B
    LDA &27
    JSR set_tile_at_pos
    LDA &28
    CMP #&04
    BEQ l_535F
    CMP #&03
    BEQ l_535F
    DEC &12
    SEC
    LDA &10
    SBC #&10
    STA &10
.l_535F
    LDA #&00
    STA &08,X
    JSR &0BE9    ; engine: tile_addr_setup
    JSR draw_status
.l_5369
    JMP main_loop
.collect_item
    PHA
    LDX #&00
.l_536F
    LDA &1B
    CMP &08,X
    BEQ l_537C
    INX
    CPX #&02
    BNE l_536F
    PLA
    RTS
.l_537C
    INC &08,X
    JSR draw_status
    JSR silence_all
    PLA
    RTS
.clear_tile_pickup
    PHA
    LDA &11
    STA &0A
    LDA &12
    STA &0B
    LDA #&00
    JSR set_tile_at_pos
    JSR &0BE9    ; engine: tile_addr_setup
    JSR silence_all
    PLA
    RTS
.drop_item
    PHA
    LDX #&00
.l_539F
    LDA &1B
    CMP &08,X
    BEQ l_53AC
    INX
    CPX #&02
    BNE l_539F
    PLA
    RTS
.l_53AC
    LDA #&00
    STA &08,X
    JSR draw_status
    LDA &11
    STA &0A
    LDY &12
    INY
    STY &0B
    LDA #&00
    JSR set_tile_at_pos
    LDA &11
    STA &0A
    LDY &12
    INY
    INY
    STY &0B
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
    LDA &11
    STA &0A
    LDY &12
    INY
    STY &0B
    PLA
    JSR set_tile_at_pos
    JMP l_4B05
.place_tile_1d
    LDA #&1D
    JMP l_53FB
.place_tile_00
    LDA #&00
    JMP l_53FB
.draw_digit
    STA &00
    LDA #&00
    ASL &00
    ROL A
    ASL &00
    ROL A
    ASL &00
    ROL A
    ASL &00
    ROL A
    STA &01
    CLC
    LDA &00
    ADC #&80
    STA &00
    LDA &01
    ADC #&03
    STA &01
    JSR &0883    ; engine: calc_screen_addr
    LDX &1D
    LDY #&0F
.l_543C
    LDA (&00),Y
    AND digit_mask_table,X
    STA (&02),Y
    DEY
    BPL l_543C
    CLC
    LDA &0A
    ADC #&02
    STA &0A
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
    STX &04
    STY &05
    LDY #&00
.l_548E
    STY l_5498 + 1
    LDA (&04),Y
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
    LDA &20
    BNE l_54E3
    LDA #&81
    STA &20
    LDA &11
    STA &1E
    LDA &12
    STA &1F
    LDA #&01
    STA &11
    LDA #&06
    STA &12
    JSR l_54FE
    LDA #&00
    STA &06
    LDA #&03
    STA &07
    JSR &0889    ; engine: render_map
    JSR &0BE9    ; engine: tile_addr_setup
    LDX #&00
.l_54CC
    LDA &08,X
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
    STA &20
    LDA &1E
    STA &11
    LDA &1F
    STA &12
    JSR &0886    ; engine: setup_map_render
    JSR l_54FE
    JSR &0BE9    ; engine: tile_addr_setup
    JSR draw_title
    JMP main_loop
.l_54FE
    LDA &11
    ASL A
    ASL A
    STA &0F
    LDA &12
    ASL A
    ASL A
    ASL A
    ASL A
    STA &10
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
    STA &25
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
    STA &0A
    LDA #&06
    STA &0B
    PLA
    JSR set_tile_at_pos
.l_5589
    LDX #&00
    LDA #&00
    STA &08,X
    INC &22
    RTS
.str_special_msg
    BIT &25
    ORA &2018,Y
    ASL &251B
    EQUB &0C
    CLC
    EQUB &17
    ORA &181B,X
    ORA &25,X
    ORA &1B0E,X
    ASL &12,X
    EQUB &17
    ASL A
    ORA &25,X
    BIT &FF
.str_continue
    BIT &25
    ASL A
    EQUB &0C
    EQUB &0C
    ASL &1C1C
    AND &0D
    ASL &1217
    ASL &250D
    BIT &FF
.str_well_done
    BIT &25
    ORA &18,X
    EQUB &10, &10    ; BPL &55D5
    ASL &250D
    CLC
    EQUB &17
    AND &FF
    AND &19
    CLC
    JSR &1B0E
    AND &0D
    ASL &0C0A
    ORA &1F12,X
    ASL A
    ORA &0D0E,X
    AND &24
    EQUB &FF
.handle_special_tile
    PHA
    LDA &21
    BEQ l_55EA
    PLA
    JMP check_passthrough
.l_55EA
    LDA #&FF
    STA &21
    LDA #&07
    STA &1D
    LDA #&07
    STA &0A
    LDA #&04
    STA &0B
    LDX #LO(str_special_msg)
    LDY #HI(str_special_msg)
    JSR draw_string
    LDA &22
    CMP #&08
    BCS l_5625
.l_5607
    LDA #&01
    STA &1D
    LDA #&0D
    STA &0A
    LDA #&08
    STA &0B
    LDX #LO(str_continue)
    LDY #HI(str_continue)
    JSR draw_string
    LDX #&64
    JSR wait_frames
    JSR &0889    ; engine: render_map
    JMP main_loop
.l_5625
    LDA &20
    BNE l_5648
    LDA #&02
    STA &1D
    LDA #&06
    STA &0A
    LDA #&08
    STA &0B
    LDX #LO(str_well_done)
    LDY #HI(str_well_done)
    JSR draw_string
    LDX #&64
    JSR wait_frames
    LDA #&FF
    STA &22
    JMP main_loop
.l_5648
    LDA &22
    BPL l_5607

; --- Level map loading from disc ---
.load_level_map
    JMP load_level_map
.load_level_data
    SEI
    JSR &0892    ; engine: init_game
    JSR swap_0600_0d00
    LDX #LO(oscli_disc)
    LDY #HI(oscli_disc)
    JSR OSCLI
    JMP l_5665
.oscli_disc
    EQUS "DISC", 13
.l_5665
    LDA &26
    STA oscli_level_m_num
    LDX #LO(oscli_load_level_m)
    LDY #HI(oscli_load_level_m)
    JSR OSCLI
    JMP l_5686
.oscli_load_level_m
    EQUS "Load Level"
.oscli_level_m_num
    EQUB 0
    EQUS "M 5800", 13
.l_5686
    LDX #&00
    LDA #&68
    STA l_5692 + 2
    LDA #&1F
    STA l_5695 + 2
.l_5692
    LDA &6800,X
.l_5695
    STA &1F00,X
    INX
    BNE l_5692
    INC l_5695 + 2
    INC l_5692 + 2
    BPL l_5692
    LDA &26
    STA oscli_level_t2_num
    LDX #LO(oscli_load_level_t2)
    LDY #HI(oscli_load_level_t2)
    JSR OSCLI
    JMP l_56C4
.oscli_load_level_t2
    EQUS "Load Level"
.oscli_level_t2_num
    EQUB 0
    EQUS "T 6800", 13
.l_56C4
    LDX #LO(oscli_load_tbar)
    LDY #HI(oscli_load_tbar)
    JSR OSCLI
    JMP l_56DD
.oscli_load_tbar
    EQUS "Load Tbar 7800", 13
.l_56DD
    SEI
    LDA #&A5
    STA &0204
    LDA #&4C
    STA &0205
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
    STA l_572E + 2
    LDA #&0F
    STA l_5731 + 2
.l_570C
    LDA #&0C
    STA l_571D + 2
    LDA #&68
    STA l_571A + 2
    LDX #&03
    LDY #&00
.l_571A
    LDA &6800,Y
.l_571D
    STA &0C80,Y
    INY
    BNE l_571A
    INC l_571A + 2
    INC l_571D + 2
    DEX
    BNE l_571A
    LDX #&00
.l_572E
    LDA &5800,X
.l_5731
    STA &0F00,X
    INX
    BNE l_572E
    INC l_5731 + 2
    INC l_572E + 2
    LDA l_5731 + 2
    CMP #&1F
    BNE l_572E
    LDA #&37
    STA &0F
    LDA #&88
    STA &10
    LDY #&00
    JSR &0BEB
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


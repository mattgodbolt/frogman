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
    LDA &4C97,X
    STA &FE00
    LDA &4C98,X
    STA &FE01
    INX
    INX
    CPX #&0E
    BNE l_48AA
    LDA &26
    STA &48D5
    LDX #&CB
    LDY #&48
    JSR &FFF7    ; OSCLI
    JMP &48D8
    EQUB &4C, &6F, &61, &64, &20, &4C, &65, &76
    EQUB &65, &6C, &00, &47, &0D
.l_48D8
    LDX #&E2
    LDY #&48
    JSR &FFF7    ; OSCLI
    JMP &48F4
    EQUB &4C, &6F, &61, &64, &20, &46, &61, &73
    EQUB &74, &49, &2F, &4F, &20, &35, &38, &30
    EQUB &30, &0D
.l_48F4
    LDA &26
    STA &490D
    LDX #&03
    LDY #&49
    JSR &FFF7    ; OSCLI
    JMP &4915
    EQUB &4C, &6F, &61, &64, &20, &4C, &65, &76
    EQUB &65, &6C, &00, &54, &20, &35, &44, &38
    EQUB &30, &0D
.l_4915
    LDA &26
    STA &492E
    LDX #&24
    LDY #&49
    JSR &FFF7    ; OSCLI
    JMP &4935
    EQUB &4C, &6F, &61, &64, &20, &4C, &65, &76
    EQUB &65, &6C, &00, &53, &20, &33, &30, &30
    EQUB &0D
.l_4935
    LDX #&3F
    LDY #&49
    JSR &FFF7    ; OSCLI
    JMP &494D
    EQUB &4C, &6F, &61, &64, &20, &54, &61, &62
    EQUB &73, &20, &31, &30, &30, &0D

; --- Game initialisation — copy tables, set IRQ, init state ---
.game_init
    SEI
    JSR &5756
    LDA #&02
    STA &0258
    LDA #&01
    STA &0262
    LDX #&08
    LDY #&00
.l_495F
    LDA &5800,Y
    STA &0700,Y
    LDA #&00
    STA &5800,Y
    INY
    BNE l_495F
    INC &4961
    INC &4964
    INC &4969
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
    STA &FE42                   ; DDRB = all outputs
    LDA #&03
    STA &FE40                   ; ORB = &03
    LDA #&0E
    STA &FE40                   ; ORB = &0E
    LDA #&0F
    STA &FE40                   ; ORB = &0F
    LDA #&7F
    STA &FE43                   ; DDRA = bit 7 input, rest output
    STA &FE4E                   ; IER: disable all interrupts
    LDA #&82
    STA &FE4E                   ; IER: enable CA1 (VSYNC) interrupt

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
    JSR &550D                   ; Initialise score display
    JSR &564F                   ; Load level map from disc
    JSR &525F                   ; Draw status bar
    LDA #&00
    STA &06                     ; Map source low = &0300
    LDA #&03
    STA &07                     ; Map source high
    JSR &0889                   ; engine: render_map
    PLA
    STA &23                     ; Restore sprite update inhibit
    JSR &5553                   ; Draw "FROGMAN BY MG RTW" title
    LDA #&02                    ; Row 2
    STA &1D
    LDA #&00
    STA &0B                     ; Tile Y = 0
    LDA #&08
    STA &0A                     ; Tile X = 8
    LDX #&56                    ; String pointer low
    LDY #&54                    ; String pointer high (&5456)
    JSR &5488                   ; Draw string: "FROGMAN BY MG RTW"
    LDA #&07                    ; Row 7
    STA &1D
    LDA #&01
    STA &0B                     ; Tile Y = 1
    LDA #&08
    STA &0A                     ; Tile X = 8
    LDX #&6F                    ; String pointer low
    LDY #&54                    ; String pointer high (&546F)
    JSR &5488                   ; Draw string: "PRESS SPACE TO START"
    LDA #&62
.l_4A23
    JSR &4E64
    BPL l_4A23
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
    JSR &525F

; --- Main game loop — keyboard, collision, movement ---
.main_loop
    JSR &0BE9    ; engine: tile_addr_setup
    LDA #&70
    JSR &4E64
    BPL l_4A5C
.l_4A54
    JSR &4E64
    BMI l_4A54
    JMP &5175
.l_4A5C
    JSR &4C12
    PHA
    JSR &4C29
    BEQ l_4A68
    JMP &4B71
.l_4A68
    LDA #&00
    STA &1C
    PLA
    CMP #&03
    BNE l_4A74
    JMP &4F45
.l_4A74
    CMP #&02
    BNE l_4A7B
    JMP &4F75
.l_4A7B
    CMP #&11
    BNE l_4A82
    JMP &5160
.l_4A82
    CMP #&05
    BNE l_4A89
    JMP &51C7
.l_4A89
    CMP #&1E
    BNE l_4A90
    JMP &5212
.l_4A90
    CMP #&10
    BNE l_4A97
    JMP &53F9
.l_4A97
    CMP #&1C
    BNE l_4A9E
    JMP &540C
.l_4A9E
    CMP #&1D
    BNE l_4AA5
    JMP &5411
.l_4AA5
    LDA &11
    STA &0A
    LDA &12
    STA &0B
    JSR &4C5F
    CMP #&04
    BNE l_4AC1
    PHA
    LDA &20
    BMI l_4ABD
    PLA
    JMP &549E
.l_4ABD
    PLA
    JMP &4AC9
.l_4AC1
    PHA
    LDA &20
    AND #&7F
    STA &20
    PLA
.l_4AC9
    CMP #&1F
    BNE l_4AD0
    JMP &55E1
.l_4AD0
    PHA
    LDA #&00
    STA &21
    PLA
    CMP #&20
    BCS l_4AE1
    CMP #&12
    BNE l_4AF2
    JMP &5175
.l_4AE1
    JSR &4E6B
    CMP #&09
    BNE l_4AEB
    JSR &536C
.l_4AEB
    CMP #&05
    BNE l_4AF2
    JSR &5386
.l_4AF2
    INC &0B
    JSR &4C5F
    CMP #&20
    BCC l_4B05
    JSR &4E6B
    CMP #&0B
    BNE l_4B05
    JSR &539C
.l_4B05
    LDA #&42
    JSR &4E64
    BPL l_4B0F
    JMP &4D8F
.l_4B0F
    LDA #&61
    JSR &4E64
    BPL l_4B19
    JMP &4E80
.l_4B19
    LDA #&48
    JSR &4E64
    BPL l_4B23
    JMP &4FA5
.l_4B23
    LDA &07
    CMP #&03
    BEQ l_4B51
    LDA #&20
    JSR &4E64
    BPL l_4B3D
.l_4B30
    JSR &4D1A
    JSR &4E64
    BMI l_4B30
    LDX #&00
    JMP &5285
.l_4B3D
    LDA #&71
    JSR &4E64
    BPL l_4B51
.l_4B44
    JSR &4D1A
    JSR &4E64
    BMI l_4B44
    LDX #&01
    JMP &5285
.l_4B51
    JSR &4D1A
    LDA #&65
    JSR &4E64
    BPL l_4B6B
    JSR &0892    ; engine: init_game
    LDA &23
    EOR #&FF
    STA &23
.l_4B64
    LDA #&65
    JSR &4E64
    BMI l_4B64
.l_4B6B
    JMP &4A4A
.l_4B6E
    JMP &4A68
.l_4B71
    LDA &11
    STA &0A
    LDA &12
    STA &0B
    JSR &4C5F
    CMP #&06
    BEQ l_4B6E
    JSR &4C12
    CMP #&20
    BCC l_4B8E
    JSR &4E6B
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
    JMP &4BEA
.l_4B9E
    LDA #&01
    ORA &19
    STA &19
    LDX #&00
.l_4BA6
    STX &4BBB
    JSR &4D1A
    JSR &4D2E
    LDA &4BE2,X
    CLC
    ADC &10
    STA &10
    JSR &0BE9    ; engine: tile_addr_setup
    LDX #&00
    INX
    CPX #&08
    BNE l_4BA6
    LDA &19
    AND #&02
    STA &19
    LDA #&FF
    STA &1C
    JSR &4D2E
    JMP &4A4A
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
    JMP &4A4A
    ORA (&01,X)
    ORA (&02,X)
    EQUB &02
    EQUB &02
    EQUB &03
    EQUB &04
    LDX #&00
.l_4BEC
    STX &4C00
    JSR &4D1A
    JSR &4D2E
    CLC
    LDA &10
    ADC #&04
    STA &10
    JSR &0BE9    ; engine: tile_addr_setup
    LDX #&00
    INX
    CPX #&04
    BNE l_4BEC
    LDA &19
    AND #&02
    STA &19
    JSR &4D2E
    JMP &4A4A
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
    CMP #&20
    BCS l_4C32
    TAY
    LDA &4880,Y
    RTS
.l_4C32
    JSR &4E6B
    CMP #&05
    BEQ l_4C42
    CMP #&07
    BEQ l_4C42
    TAY
    LDA &4C52,Y
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

    LDA &FE4D                   ; Read System VIA IFR
    AND #&02                    ; Check CA1 (VSYNC) flag
    BEQ irq_exit                ; Not VSYNC — exit

    STA &FE4D                   ; Acknowledge VSYNC interrupt

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
    STA &FE21                   ; Write to Video ULA palette register
    RTS

; --- Movement, collision, scrolling helpers ---
.game_routines_2
    ADC &03
.l_4D1A
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
.l_4D2E
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
    JSR &4D5B
    INC &0A
    LDA &0A
    CMP #&10
    BCS l_4D25
    JSR &4D5B
    INC &0B
    LDA &0B
    CMP #&08
    BCS l_4D2D
    JSR &4D5B
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
    STA &4D71
    LDA &07
    ADC #&00
    STA &4D72
    LDY &0A
    LDA &FFFF,Y
    STA &4D84
    LDA &0A
    PHA
    ASL A
    ASL A
    STA &0A
    LDA &0B
    PHA
    ASL A
    STA &0B
    LDA #&00
    JSR &0880    ; engine: block_copy
    PLA
    STA &0B
    PLA
    STA &0A
    RTS
    JSR &4D1A
    JSR &4D2E
    LDA #&00
    STA &19
    JSR &0BE9    ; engine: tile_addr_setup
    LDY &11
    INY
    STY &0A
    LDA &12
    STA &0B
    JSR &4C5F
    JSR &4C29
    BEQ l_4E02
    LDA #&01
    STA &19
    INC &0A
    JSR &4C5F
    JSR &4C29
    BEQ l_4E0F
    LDA #&68
    JSR &4E64
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
    JMP &4A4A
.l_4DE1
    LDX #&00
.l_4DE3
    JSR &4D1A
    JSR &4D2E
    INC &0F
    LDA &10
    CLC
    ADC &4E58,X
    STA &10
    STX &4DFA
    JSR &0BE9    ; engine: tile_addr_setup
    LDX #&00
    INX
    CPX #&08
    BNE l_4DE3
    INC &11
.l_4E02
    LDA #&00
    STA &19
    JSR &4D1A
    JSR &4D2E
    JMP &4A4A
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
    JMP &4A4A
.l_4E2E
    JSR &4D1A
    JSR &4D2E
    INC &0F
    LDA &10
    CLC
    ADC &4E60,X
    STA &10
    STX &4E45
    JSR &0BE9    ; engine: tile_addr_setup
    LDX #&00
    INX
    CPX #&04
    BNE l_4E2E
    LDA #&00
    STA &19
    JSR &4D1A
    JSR &4D2E
    JMP &4A4A

; --- Collision/step tables (data) ---
    EQUB &FD, &FE, &FF, &00, &00, &03, &02, &01
    EQUB &FE, &FF, &01, &02, &8D, &4F, &FE, &2C

; --- More game logic — movement, collision response ---
.game_routines_3
    EQUB &4F
    INC &8C60,X
    ROR &384E,X
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
    JSR &4D1A
    JSR &4D2E
    LDA #&02
    STA &19
    JSR &0BE9    ; engine: tile_addr_setup
    LDY &11
    DEY
    STY &0A
    LDA &12
    STA &0B
    JSR &4C5F
    JSR &4C29
    BEQ l_4EF1
    LDA #&03
    STA &19
    DEC &0A
    JSR &4C5F
    JSR &4C29
    BEQ l_4EFE
    LDA #&68
    JSR &4E64
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
    JMP &4A4A
.l_4ED0
    LDX #&00
.l_4ED2
    JSR &4D1A
    JSR &4D2E
    DEC &0F
    LDA &10
    CLC
    ADC &4E58,X
    STA &10
    STX &4EE9
    JSR &0BE9    ; engine: tile_addr_setup
    LDX #&00
    INX
    CPX #&08
    BNE l_4ED2
    DEC &11
.l_4EF1
    LDA #&02
    STA &19
    JSR &4D1A
    JSR &4D2E
    JMP &4A4A
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
    JMP &4A4A
.l_4F1B
    JSR &4D1A
    JSR &4D2E
    DEC &0F
    LDA &10
    CLC
    ADC &4E60,X
    STA &10
    STX &4F32
    JSR &0BE9    ; engine: tile_addr_setup
    LDX #&00
    INX
    CPX #&04
    BNE l_4F1B
    LDA #&02
    STA &19
    JSR &4D1A
    JSR &4D2E
    JMP &4A4A
.l_4F45
    JSR &4F52
    JSR &4C12
    CMP #&03
    BEQ l_4F45
    JMP &4A4A
.l_4F52
    LDX #&00
.l_4F54
    STX &4F6A
    JSR &4D1A
    JSR &4D2E
    INC &0F
    CLC
    LDA &10
    ADC #&04
    STA &10
    JSR &0BE9    ; engine: tile_addr_setup
    LDX #&00
    INX
    CPX #&04
    BNE l_4F54
    INC &11
    INC &12
    RTS
.l_4F75
    JSR &4F82
    JSR &4C12
    CMP #&02
    BEQ l_4F75
    JMP &4A4A
.l_4F82
    LDX #&00
.l_4F84
    STX &4F9A
    JSR &4D1A
    JSR &4D2E
    DEC &0F
    CLC
    LDA &10
    ADC #&04
    STA &10
    JSR &0BE9    ; engine: tile_addr_setup
    LDX #&00
    INX
    CPX #&04
    BNE l_4F84
    DEC &11
    INC &12
    RTS
    LDA &19
    AND #&02
    BNE l_4FAE
    JMP &503E
.l_4FAE
    LDY &11
    DEY
    STY &0A
    LDA &12
    STA &0B
    JSR &4C5F
    CMP #&03
    BNE l_5015
.l_4FBE
    LDA #&03
    STA &19
    LDX #&00
.l_4FC4
    STX &4FE0
    JSR &4D1A
    JSR &4D2E
    SEC
    LDA &10
    SBC #&04
    STA &10
    DEC &0F
    LDA &19
    EOR #&01
    STA &19
    JSR &0BE9    ; engine: tile_addr_setup
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
    JSR &4C5F
    CMP #&03
    BEQ l_4FBE
    LDA #&02
    STA &19
    LDY &11
    DEY
    STY &0A
    LDA &12
    STA &0B
    JSR &4C5F
    JSR &4C29
    BEQ l_5012
    JMP &4EFE
.l_5012
    JMP &4A4A
.l_5015
    LDA &11
    STA &0A
    LDA &12
    STA &0B
    JSR &4C5F
    CMP #&06
    BEQ l_5027
    JMP &5128
.l_5027
    LDY &12
    DEY
    STY &0B
    LDA &11
    STA &0A
    JSR &4C5F
    JSR &4C29
    BEQ l_503B
    JMP &50A5
.l_503B
    JMP &4A4A
.l_503E
    LDY &11
    INY
    STY &0A
    LDA &12
    STA &0B
    JSR &4C5F
    CMP #&02
    BNE l_5015
.l_504E
    LDA #&01
    STA &19
    LDX #&00
.l_5054
    STX &5070
    JSR &4D1A
    JSR &4D2E
    SEC
    LDA &10
    SBC #&04
    STA &10
    INC &0F
    LDA &19
    EOR #&01
    STA &19
    JSR &0BE9    ; engine: tile_addr_setup
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
    JSR &4C5F
    CMP #&02
    BEQ l_504E
    LDA #&00
    STA &19
    LDY &11
    INY
    STY &0A
    LDA &12
    STA &0B
    JSR &4C5F
    JSR &4C29
    BNE l_50A2
    JMP &5012
.l_50A2
    JMP &4E0F
.l_50A5
    JSR &4D2E
.l_50A8
    DEC &12
    BMI l_5105
.l_50AC
    LDA &12
    STA &0B
    LDA &11
    STA &0A
    JSR &4C5F
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
    STX &50DC
    DEC &10
    JSR &4D1A
    JSR &4D2E
    JSR &0BE9    ; engine: tile_addr_setup
    LDX #&00
    INX
    CPX #&10
    BNE l_50CD
    JMP &4B05
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
    JSR &4D1A
    DEX
    BNE l_50F7
    LDA #&07
    JSR &0880    ; engine: block_copy
    JMP &50A8
.l_5105
    LDA #&07
    STA &12
    LDA #&70
    STA &10
    DEC &14
    JSR &0886    ; engine: setup_map_render
    JMP &50AC
.l_5115
    LDA #&07
    STA &12
    LDA #&70
    STA &10
    DEC &14
    JSR &0886    ; engine: setup_map_render
    JSR &0BE9    ; engine: tile_addr_setup
    JMP &4A4A
.l_5128
    LDA &11
    STA &0A
    LDY &12
    DEY
    BMI l_5115
    STY &0B
    JSR &4C5F
    JSR &4C29
    BEQ l_5158
    LDX #&07
.l_513D
    STX &5152
    LDA &10
    SEC
    SBC &4BE2,X
    STA &10
    JSR &4D1A
    JSR &4D2E
    JSR &0BE9    ; engine: tile_addr_setup
    LDX #&00
    DEX
    BPL l_513D
    DEC &12
.l_5158
    JMP &4A4A
.l_515B
    LDA #&00
    JMP &4A82
    STA &515C
    LDA &08
    JSR &4E6B
    CMP #&01
    BEQ l_515B
    LDA &09
    JSR &4E6B
    CMP #&01
    BEQ l_515B

; --- Game over, level complete, death, restart ---
.game_state_handlers
    LDX #&00
.l_5177
    STX &51A1
    JSR &4D1A
    JSR &4D1A
    JSR &4D1A
    JSR &4D2E
    LDA &4BE2,X
    CLC
    ADC &10
    STA &10
    JSR &0BE9    ; engine: tile_addr_setup
    LDA &11
    STA &0A
    LDY &12
    INY
    STY &0B
    JSR &4C5F
    JSR &4C79
    LDX #&00
    INX
    CPX #&08
    BNE l_5177
    LDX #&32
    JSR &53F2
    LDA #&00
    JSR &4E64
    BPL l_51B7
    LDA #&01
    STA &24
.l_51B7
    DEC &24
    BEQ l_51C1
    JSR &525F
    JMP &4A28
.l_51C1
    JSR &525F
    JMP &49CD
    LDY &11
    INY
    CPY #&10
    BCC l_51DC
    LDA #&00
    STA &11
    STA &0F
    INC &13
    JSR &0886    ; engine: setup_map_render
    JMP &4A4A
.l_51DC
    STY &0A
    LDA &12
    STA &0B
    JSR &4C5F
    JSR &4C29
    BNE l_51ED
    JMP &4B05
.l_51ED
    LDX #&00
.l_51EF
    STX &5207
    JSR &4D2E
    INC &0F
    JSR &0BE9    ; engine: tile_addr_setup
    JSR &4D1A
    JSR &4D1A
    JSR &4D1A
    JSR &4D1A
    LDX #&00
    INX
    CPX #&04
    BNE l_51EF
    INC &11
    JMP &4A4A
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
    JMP &4A4A
.l_5229
    STY &0A
    LDA &12
    STA &0B
    JSR &4C5F
    JSR &4C29
    BNE l_523A
    JMP &4B05
.l_523A
    LDX #&00
.l_523C
    STX &5254
    JSR &4D2E
    DEC &0F
    JSR &0BE9    ; engine: tile_addr_setup
    JSR &4D1A
    JSR &4D1A
    JSR &4D1A
    JSR &4D1A
    LDX #&00
    INX
    CPX #&04
    BNE l_523C
    DEC &11
    JMP &4A4A
.l_525F
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
    JSR &5416
    RTS

; --- Scrolling routines ---
.scroll_routines
    LDA &08,X
    STX &52C7
    BEQ l_528F
    JMP &530F
.l_528F
    LDA &11
    STA &0A
    LDA &12
    STA &0B
    JSR &52D8
    BEQ l_52C6
    LDA &19
    AND #&02
    BEQ l_52AA
    LDY &11
    DEY
    STY &0A
    JMP &52AF
.l_52AA
    LDY &11
    INY
    STY &0A
.l_52AF
    LDA &12
    STA &0B
    JSR &52D8
    BEQ l_52C6
    LDA &11
    STA &0A
    LDY &12
    INY
    STY &0B
    JSR &52D8
    BNE l_52D5
.l_52C6
    LDX #&00
    STA &08,X
    LDA #&00
    JSR &4C79
    JSR &0BE9    ; engine: tile_addr_setup
    JSR &525F
.l_52D5
    JMP &4A4A
.l_52D8
    JSR &4C5F
    CMP #&20
    BCC l_52EC
    PHA
    JSR &4E6B
    TAX
    LDA &52EF,X
    TAY
    PLA
    CPY #&00
    RTS
.l_52EC
    LDA #&01
    RTS

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
    JSR &4C5F
    BNE l_5369
    LDX &52C7
    LDA &08,X
    STA &27
    JSR &4E6B
    STA &28
    CMP #&04
    BEQ l_533C
    CMP #&03
    BEQ l_533C
    DEC &0B
    BMI l_5369
    JSR &4C5F
    JSR &4C29
    BEQ l_5369
.l_533C
    JSR &4D2E
    LDA &11
    STA &0A
    LDA &12
    STA &0B
    LDA &27
    JSR &4C79
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
    JSR &525F
.l_5369
    JMP &4A4A
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
    JSR &525F
    JSR &5777
    PLA
    RTS
    PHA
    LDA &11
    STA &0A
    LDA &12
    STA &0B
    LDA #&00
    JSR &4C79
    JSR &0BE9    ; engine: tile_addr_setup
    JSR &5777
    PLA
    RTS
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
    JSR &525F
    LDA &11
    STA &0A
    LDY &12
    INY
    STY &0B
    LDA #&00
    JSR &4C79
    LDA &11
    STA &0A
    LDY &12
    INY
    INY
    STY &0B
    LDA #&00
    JSR &4C79
    LDA #&00
    LDX #&07
    JSR &4D08
    LDX #&14
    JSR &53F2
    LDX #&06
.l_53DE
    STX &53EC
    LDA #&00
    JSR &4D08
    LDX #&05
    JSR &53F2
    LDX #&00
    DEX
    BPL l_53DE
    PLA
    RTS
.l_53F2
    JSR &4D1A
    DEX
    BPL l_53F2
    RTS
    LDA #&1C
.l_53FB
    PHA
    LDA &11
    STA &0A
    LDY &12
    INY
    STY &0B
    PLA
    JSR &4C79
    JMP &4B05
    LDA #&1D
    JMP &53FB
    LDA #&00
    JMP &53FB
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
    AND &544E,X
    STA (&02),Y
    DEY
    BPL l_543C
    CLC
    LDA &0A
    ADC #&02
    STA &0A
    RTS

; --- Palette and sprite data tables ---
    EQUB &00, &03, &0C, &0F, &30, &33, &3C, &3F
    EQUB &24, &25, &0F, &1B, &18, &10, &16, &0A
    EQUB &17, &25, &25, &0B, &22, &25, &16, &10
    EQUB &25, &24, &25, &1B, &1D, &20, &25, &24
    EQUB &FF, &24, &25, &19, &1B, &0E, &1C, &1C
    EQUB &25, &1C, &19, &0A, &0C, &0E, &25, &1D
    EQUB &18, &25, &1C, &1D, &0A, &1B, &1D, &25
    EQUB &24, &FF

; --- More rendering and string display ---
.game_routines_5
    STX &04
    STY &05
    LDY #&00
.l_548E
    STY &5499
    LDA (&04),Y
    BMI l_549D
    JSR &5416
    LDY #&00
    INY
    BNE l_548E
.l_549D
    RTS
    JSR &550D
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
    JSR &54FE
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
    JSR &5578
.l_54D5
    INX
    CPX #&02
    BNE l_54CC
    JSR &525F
    JSR &5553
    JMP &4A4A
.l_54E3
    LDA #&80
    STA &20
    LDA &1E
    STA &11
    LDA &1F
    STA &12
    JSR &0886    ; engine: setup_map_render
    JSR &54FE
    JSR &0BE9    ; engine: tile_addr_setup
    JSR &5553
    JMP &4A4A
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
    STA &5538,X
    DEX
    BPL l_550F
.l_5516
    LDX #&07
.l_5518
    LDA &5538,X
    BEQ l_5523
    TAY
    DEY
    TYA
    STA &5538,X
.l_5523
    DEX
    BPL l_5518
    LDX #&04
    JSR &53F2
    JSR &5540
    LDA &553F
    BNE l_5516
    LDX #&32
    JMP &53F2
    BRK
    BRK
    BRK
    BRK
    BRK
    BRK
    BRK
    BRK
.l_5540
    LDY #&07
    LDA &5538,Y
    STA &25
.l_5547
    LDA &5538,Y
    TAX
    TYA
    JSR &4D08
    DEY
    BNE l_5547
    RTS
.l_5553
    LDX #&07
.l_5555
    STX &555C
    LDA &5538,X
    CMP #&00
    BEQ l_5565
    TAY
    INY
    TYA
    STA &5538,X
.l_5565
    DEX
    BPL l_5555
    LDX #&04
    JSR &53F2
    JSR &5540
    LDA &553F
    CMP #&07
    BNE l_5553
    RTS
.l_5578
    SEC
    PHA
    STX &558A
    SBC #&31
    STA &0A
    LDA #&06
    STA &0B
    PLA
    JSR &4C79
    LDX #&00
    LDA #&00
    STA &08,X
    INC &22
    RTS
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
    BIT &25
    ASL A
    EQUB &0C
    EQUB &0C
    ASL &1C1C
    AND &0D
    ASL &1217
    ASL &250D
    BIT &FF
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
    PHA
    LDA &21
    BEQ l_55EA
    PLA
    JMP &4AD6
.l_55EA
    LDA #&FF
    STA &21
    LDA #&07
    STA &1D
    LDA #&07
    STA &0A
    LDA #&04
    STA &0B
    LDX #&92
    LDY #&55
    JSR &5488
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
    LDX #&AD
    LDY #&55
    JSR &5488
    LDX #&64
    JSR &53F2
    JSR &0889    ; engine: render_map
    JMP &4A4A
.l_5625
    LDA &20
    BNE l_5648
    LDA #&02
    STA &1D
    LDA #&06
    STA &0A
    LDA #&08
    STA &0B
    LDX #&BF
    LDY #&55
    JSR &5488
    LDX #&64
    JSR &53F2
    LDA #&FF
    STA &22
    JMP &4A4A
.l_5648
    LDA &22
    BPL l_5607

; --- Level map loading from disc ---
.load_level_map
    JMP &564C
    SEI
    JSR &0892    ; engine: init_game
    JSR &5756
    LDX #&60
    LDY #&56
    JSR &FFF7    ; OSCLI
    JMP &5665
    EQUB &44, &49, &53, &43, &0D
.l_5665
    LDA &26
    STA &567E
    LDX #&74
    LDY #&56
    JSR &FFF7    ; OSCLI
    JMP &5686
    EQUB &4C, &6F, &61, &64, &20, &4C, &65, &76
    EQUB &65, &6C, &00, &4D, &20, &35, &38, &30
    EQUB &30, &0D
.l_5686
    LDX #&00
    LDA #&68
    STA &5694
    LDA #&1F
    STA &5697
.l_5692
    LDA &6800,X
    STA &1F00,X
    INX
    BNE l_5692
    INC &5697
    INC &5694
    BPL l_5692
    LDA &26
    STA &56BC
    LDX #&B2
    LDY #&56
    JSR &FFF7    ; OSCLI
    JMP &56C4
    EQUB &4C, &6F, &61, &64, &20, &4C, &65, &76
    EQUB &65, &6C, &00, &54, &20, &36, &38, &30
    EQUB &30, &0D
.l_56C4
    LDX #&CE
    LDY #&56
    JSR &FFF7    ; OSCLI
    JMP &56DD
    EQUB &4C, &6F, &61, &64, &20, &54, &62, &61
    EQUB &72, &20, &37, &38, &30, &30, &0D
.l_56DD
    SEI
    LDA #&A5
    STA &0204
    LDA #&4C
    STA &0205
    LDA #&7F
    STA &FE4E
    STA &FE43
    LDA #&82
    STA &FE4E
    LDA #&FF
    STA &FE42
    LDA #&03
    STA &FE40
    JSR &5756
    LDA #&58
    STA &5730
    LDA #&0F
    STA &5733
.l_570C
    LDA #&0C
    STA &571F
    LDA #&68
    STA &571C
    LDX #&03
    LDY #&00
.l_571A
    LDA &6800,Y
    STA &0C80,Y
    INY
    BNE l_571A
    INC &571C
    INC &571F
    DEX
    BNE l_571A
    LDX #&00
.l_572E
    LDA &5800,X
    STA &0F00,X
    INX
    BNE l_572E
    INC &5733
    INC &5730
    LDA &5733
    CMP #&1F
    BNE l_572E
    LDA #&37
    STA &0F
    LDA #&88
    STA &10
    LDY #&00
    JSR &0BEB
    JSR &576A
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
    JSR &53F2                   ; TODO: identify this routine
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


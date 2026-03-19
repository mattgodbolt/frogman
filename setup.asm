; ============================================================================
; FROGMAN — Setup Code (Title Screen + Game Launcher)
;
; Displays the RLE-compressed title screen from Data2, waits for
; SPACE, then loads the game files and starts.
;
; Called from BASIC after level number is set at &0430.
;
; RLE format (source at &1300, dest starts at &3000):
;   bit7=0, bit6=0: literal — copy byte to dest, advance both
;   bit7=0, bit6=1: fill page — fill 256 bytes with (token & &3F)
;   bit7=1:         repeat — fill (next byte) copies of (token & &3F),
;                            advance dest by (next byte)
;   Decompression ends when dest high byte goes negative (>= &80)
; ============================================================================


.*setup_entry
{
    ; --- Blank display before mode change ---
    LDA #&01 : STA CRTC_ADDR    ; CRTC R1
    LDA #&00 : STA CRTC_DATA    ; Horizontal displayed = 0 (blank)

    ; --- MODE 2, cursor off ---
    LDA #&16 : JSR OSWRCH       ; VDU 22
    LDA #&02 : JSR OSWRCH       ; Mode 2

    LDA #&0A : STA CRTC_ADDR    ; CRTC R10
    LDA #&20 : STA CRTC_DATA    ; Cursor off

    LDA #&02 : STA OS_MODE

    ; --- Load title screen RLE data ---
    LDX #LO(oscli_load_data2)
    LDY #HI(oscli_load_data2)
    JSR OSCLI                    ; *L.Data2 (&1300)

    ; --- RLE decompress: &1300 → &3000 (screen memory) ---
    LDA #&00 : STA &70           ; Source low
    LDA #&13 : STA &71           ; Source high (&1300)
    LDA #&00 : STA &72           ; Dest low
    LDA #&30 : STA &73           ; Dest high (&3000)

{
.token_loop
    LDY #&00
    LDA (&70),Y                  ; Read token byte
    BMI repeat                   ; Bit 7 set → repeat fill
    AND #&40
    BNE fill_page                ; Bit 6 set → page fill

    ; --- Literal: copy 1 byte ---
    LDA (&70),Y
    STA (&72),Y
    INC &70 : BNE skip1 : INC &71
.skip1
    INC &72 : BNE token_loop
    INC &73 : BPL token_loop
    JMP done

    ; --- Repeat: fill (count) bytes with (value) ---
.repeat
    AND #&3F                     ; Value = token & &3F
    STA &74
    INY
    LDA (&70),Y                  ; Count byte
    STA &75
    TAX                          ; X = count
    CLC
    LDA &70 : ADC #&02 : STA &70 ; Source += 2
    LDA &71 : ADC #&00 : STA &71
    LDY #&00
    LDA &74                      ; Fill value
.repeat_loop
    STA (&72),Y
    INY
    DEX
    BNE repeat_loop
    CLC
    LDA &75 : ADC &72 : STA &72  ; Dest += count
    LDA &73 : ADC #&00 : STA &73
    BPL token_loop
    JMP done

    ; --- Fill page: fill 256 bytes with (value) ---
.fill_page
    LDA (&70),Y                  ; Re-read token
    INC &70 : BNE skip2 : INC &71
.skip2
    AND #&3F                     ; Fill value
    LDY #&00
.fill_loop
    STA (&72),Y
    INY
    BNE fill_loop
    INC &73
    BPL token_loop

.done
}

    ; --- Restore VIA for keyboard ---
    LDA #&7F : STA VIA_DDRA
    LDA #&FF : STA VIA_DDRB
    LDA #&03 : STA VIA_ORB

    ; --- Wait for SPACE ---
{
.wait
    LDA #&62                     ; SPACE key
    STA VIA_ORA_NH
    BIT VIA_ORA_NH
    BPL wait
}

    ; --- Clear screen memory and blank display ---
    LDA #&01 : STA CRTC_ADDR
    LDA #&00 : STA CRTC_DATA    ; Blank display
{
    LDA #&00
    TAX
.clear_src
    STA &3000,X
    DEX
    BNE clear_src
    INC clear_src + 2
    BPL clear_src              ; Loop &3000-&7FFF
}

    ; --- Load game files and start ---
    LDX #LO(oscli_load_gcode)
    LDY #HI(oscli_load_gcode)
    JSR OSCLI                    ; *LOAD Gcode

    LDX #LO(oscli_load_fastio)
    LDY #HI(oscli_load_fastio)
    JSR OSCLI                    ; *LOAD FastI/O 5800

    JMP &48A0                    ; Start the game

.oscli_load_data2
    EQUS "L.Data2", 13
.oscli_load_gcode
    EQUS "L.Gcode", 13
.oscli_load_fastio
    EQUS "L.FastI/O 5800", 13
}

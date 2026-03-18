; ============================================================================
; FROGMAN — System Constants
; ============================================================================

; --- MOS entry points ---
OSCLI   = &FFF7
OSBYTE  = &FFF4
OSWORD  = &FFF1
OSWRCH  = &FFEE

; --- System VIA (6522 at &FE40) ---
VIA_ORB      = &FE40           ; Output Register B
VIA_ORA      = &FE41           ; Output Register A
VIA_DDRB     = &FE42           ; Data Direction Register B
VIA_DDRA     = &FE43           ; Data Direction Register A
VIA_ORA_NH   = &FE4F           ; Output Register A (no handshake)
VIA_IFR      = &FE4D           ; Interrupt Flag Register
VIA_IER      = &FE4E           ; Interrupt Enable Register

; --- Video ---
CRTC_ADDR    = &FE00           ; 6845 CRTC address register
CRTC_DATA    = &FE01           ; 6845 CRTC data register
ULA_PALETTE  = &FE21           ; Video ULA palette register

; --- OS workspace ---
IRQ1V_LO     = &0204           ; IRQ1 vector low byte
IRQ1V_HI     = &0205           ; IRQ1 vector high byte
LEVEL_NUM    = &0430           ; Level number (set by BASIC loader)
OS_MODE      = &0258           ; OS workspace: current screen mode
OS_CHARS_ROW = &0262           ; OS workspace: characters per row

; --- Memory regions ---
ENGINE_LOAD  = &5800           ; Engine loaded here, then copied to ENGINE_RUN
ENGINE_RUN   = &0700           ; Engine runtime address
SCREEN_BASE  = &5800           ; Custom CRTC screen display base

; --- Tile font string macro ---
; The game uses tile indices for text: A=&0A..Z=&23, space=&25, *=&24.
; This macro temporarily remaps characters for EQUS, then resets.
MACRO TILESTR s
    MAPCHAR 32, &25 : MAPCHAR 42, &24 : MAPCHAR 65,90, &0A
    EQUS s
    MAPCHAR 32, 32  : MAPCHAR 42, 42  : MAPCHAR 65,90, 65
ENDMACRO

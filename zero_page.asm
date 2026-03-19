; ============================================================================
; FROGMAN — Zero Page Variable Definitions
; ============================================================================

ORG &00

; --- Pointers (used by engine for tile/screen operations) ---
.zp_src_lo      SKIP 1          ; Source pointer low
.zp_src_hi      SKIP 1          ; Source pointer high
.zp_dst_lo      SKIP 1          ; Destination pointer low
.zp_dst_hi      SKIP 1          ; Destination pointer high
.zp_map_ptr_lo  SKIP 1          ; Map data pointer low
.zp_map_ptr_hi  SKIP 1          ; Map data pointer high
.zp_map_src_lo  SKIP 1          ; Map source address low
.zp_map_src_hi  SKIP 1          ; Map source address high

; --- Score and inventory ---
.zp_item_0      SKIP 1          ; Collected item slot 0
.zp_item_1      SKIP 1          ; Collected item slot 1
.zp_tile_x      SKIP 1          ; Current tile X coordinate
.zp_tile_y      SKIP 1          ; Current tile Y coordinate

; --- Palette and animation state ---
.zp_colour_phase SKIP 1         ; Colour cycle phase (0-7)
.zp_palette_idx  SKIP 1         ; Palette entry being animated (8-11)
.zp_frame_ctr    SKIP 1         ; Frame sub-counter
.zp_frog_x       SKIP 1         ; Frog X in character columns (0-60; 1 tile = 4 cols)
.zp_frog_y       SKIP 1         ; Frog Y in scanlines (0-127; 1 tile = 16 lines; >=160 off-screen)

; --- Frog position ---
.zp_frog_col     SKIP 1         ; Frog tile column within current screen
.zp_frog_row     SKIP 1         ; Frog tile row within current screen
.zp_screen_x     SKIP 1         ; Current screen column in level map grid
.zp_screen_y     SKIP 1         ; Current screen row in level map grid

; --- Tile renderer temporaries ---
.zp_tile_y_ofs   SKIP 1         ; Y pixel offset within tile
.zp_tile_width   SKIP 1         ; Width step for tile loop
.zp_tile_limit   SKIP 1         ; Width limit counter
.zp_tile_rows    SKIP 1         ; Row counter

; --- Game state ---
.zp_direction    SKIP 1         ; Frog direction: 0=right, 1=right-hop, 2=left, 3=left-hop
.zp_vsync_flag   SKIP 1         ; Set to &FF each VSYNC, polled by game loop
.zp_tile_data    SKIP 1         ; Tile data value from map lookup
.zp_falling      SKIP 1         ; Non-zero when frog is falling
.zp_text_colour  SKIP 1         ; Colour mask for string drawing
.zp_save_col     SKIP 1         ; Saved frog column (for map reveal)
.zp_save_row     SKIP 1         ; Saved frog row (for map reveal)
.zp_game_state   SKIP 1         ; Game state flags (bit 7 = map revealed)
.zp_special_flag SKIP 1         ; Special tile interaction flag
.zp_terminal_ctr SKIP 1         ; Terminal/checkpoint counter
.zp_music_inhibit SKIP 1       ; Non-zero = skip sound updates in IRQ
.zp_lives        SKIP 1         ; Lives remaining
.zp_palette_count SKIP 1        ; Number of active palette entries for cycling
.zp_level_char   SKIP 1         ; ASCII level number character ('1' or '2')
.zp_temp_item    SKIP 1         ; Temporary: item tile being placed
.zp_temp_type    SKIP 1         ; Temporary: item type being placed

; --- Engine temporaries (used during sound channel update) ---
ORG &60
.zp_move_ptr_lo  SKIP 1         ; Current envelope sequence pointer low
.zp_move_ptr_hi  SKIP 1         ; Current envelope sequence pointer high
.zp_snd_tmp_timer    SKIP 1         ; Note duration temporary
.zp_snd_tmp_token    SKIP 1         ; Music stream token temporary
.zp_snd_tmp_speed    SKIP 1         ; Volume parameter temporary

; --- Sound channel state (X-indexed, 4 channels) ---
ORG &70
.zp_snd_freq      SKIP 4         ; Channel frequency value
.zp_snd_vol       SKIP 4         ; Channel volume envelope position
.zp_snd_timer     SKIP 4         ; Channel note duration timer
.zp_snd_seq_lo    SKIP 4         ; Sequence data pointer low
.zp_snd_seq_hi    SKIP 4         ; Sequence data pointer high
.zp_snd_seq_idx   SKIP 4         ; Sequence data index
.zp_snd_subctr    SKIP 4         ; Envelope sub-counter
.zp_snd_anim_idx  SKIP 4         ; Music stream index
.zp_snd_data_lo   SKIP 1         ; Music data pointer low
.zp_snd_data_hi   SKIP 1         ; Music data pointer high

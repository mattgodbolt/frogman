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
.zp_scroll_x     SKIP 1         ; Frog pixel X within current screen
.zp_scroll_y     SKIP 1         ; Frog pixel Y within current screen

; --- Frog position ---
.zp_frog_col     SKIP 1         ; Frog tile column within current screen
.zp_frog_row     SKIP 1         ; Frog tile row within current screen
.zp_map_scroll_x SKIP 1         ; Current screen X in map
.zp_map_scroll_y SKIP 1         ; Current screen Y in map

; --- Tile renderer temporaries ---
.zp_tile_y_ofs   SKIP 1         ; Y pixel offset within tile
.zp_tile_width   SKIP 1         ; Width step for tile loop
.zp_tile_limit   SKIP 1         ; Width limit counter
.zp_tile_rows    SKIP 1         ; Row counter

; --- Game state ---
.zp_direction    SKIP 1         ; Movement direction flags
.zp_vsync_flag   SKIP 1         ; Set to &FF each VSYNC, polled by game loop
.zp_tile_data    SKIP 1         ; Tile data value from map lookup
.zp_falling      SKIP 1         ; Non-zero when frog is falling
.zp_text_colour  SKIP 1         ; Colour mask for string drawing
.zp_save_col     SKIP 1         ; Saved frog column (for map reveal)
.zp_save_row     SKIP 1         ; Saved frog row (for map reveal)
.zp_game_state   SKIP 1         ; Game state flags (bit 7 = map revealed)
.zp_special_flag SKIP 1         ; Special tile interaction flag
.zp_terminal_ctr SKIP 1         ; Terminal/checkpoint counter
.zp_sprite_inhibit SKIP 1       ; Non-zero = skip sprite updates in IRQ
.zp_lives        SKIP 1         ; Lives remaining
.zp_palette_count SKIP 1        ; Number of active palette entries for cycling
.zp_level_char   SKIP 1         ; ASCII level number character ('1' or '2')
.zp_temp_item    SKIP 1         ; Temporary: item tile being placed
.zp_temp_type    SKIP 1         ; Temporary: item type being placed

; --- Engine temporaries (used during sprite update) ---
ORG &60
.zp_move_ptr_lo  SKIP 1         ; Current movement data pointer low
.zp_move_ptr_hi  SKIP 1         ; Current movement data pointer high
.zp_spr_timer    SKIP 1         ; Sprite timer temporary
.zp_spr_frame    SKIP 1         ; Sprite frame/direction temporary
.zp_spr_speed    SKIP 1         ; Sprite speed temporary

; --- Sprite state arrays (X-indexed, 4 sprites each) ---
ORG &70
.zp_spr_dir      SKIP 4         ; Sprite direction/speed (&70-&73)
.zp_spr_subpix   SKIP 4         ; Sprite Y sub-pixel position (&74-&77)
.zp_spr_anim_tmr SKIP 4         ; Sprite animation timer (&78-&7B)
.zp_spr_move_lo  SKIP 4         ; Sprite movement ptr low (&7C-&7F)
.zp_spr_move_hi  SKIP 4         ; Sprite movement ptr high (&80-&83)
.zp_spr_move_idx SKIP 4         ; Sprite movement index (&84-&87)
.zp_spr_subctr   SKIP 4         ; Sprite movement sub-counter (&88-&8B)
.zp_spr_anim_idx SKIP 4         ; Sprite animation stream index (&8C-&8F)
.zp_anim_ptr_lo  SKIP 1         ; Animation data pointer low (&90)
.zp_anim_ptr_hi  SKIP 1         ; Animation data pointer high (&91)

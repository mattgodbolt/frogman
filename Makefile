# FROGMAN — Build System
#
# The canonical map sources are the Tiled .tmx files in tiled/.
# The Makefile generates Level?M binaries from them, assembles the
# engine/game code, and produces a bootable .ssd disc image.
#
# Requires: beebasm, python3 with Pillow

BEEBASM ?= beebasm
PYTHON  ?= python3
TARGET   = frogman_rebuilt.ssd
TITLE    = FROGMAN

# Source files
ASM_SRCS = frogman.asm engine.asm tables.asm music.asm game.asm \
           constants.asm zero_page.asm setup.asm boot.bas bootcmd.txt
MAP_SRCS = tiled/level1.tmx tiled/level2.tmx
GFX_SRCS = extracted/Level1G extracted/Level2G
DATA_SRCS = extracted/Level1S extracted/Level2S \
            extracted/Level1T extracted/Level2T \
            extracted/Tabs extracted/Tbar extracted/Data2

# Generated map binaries
LEVEL1M = extracted/Level1M
LEVEL2M = extracted/Level2M

.PHONY: all clean verify maps

all: $(TARGET)

# --- Map conversion: Tiled .tmx → Level?M binary ---

$(LEVEL1M): tiled/level1.tmx import_tiled.py
	$(PYTHON) import_tiled.py $< $@

$(LEVEL2M): tiled/level2.tmx import_tiled.py
	$(PYTHON) import_tiled.py $< $@

maps: $(LEVEL1M) $(LEVEL2M)
	@echo "Maps generated from Tiled sources"

# --- Main disc image ---

$(TARGET): $(ASM_SRCS) $(LEVEL1M) $(LEVEL2M) $(GFX_SRCS) $(DATA_SRCS)
	$(BEEBASM) -i frogman.asm -do $(TARGET) -title $(TITLE) -opt 3
	@echo "Built $(TARGET)"

# --- Verification ---

verify: $(TARGET)
	./verify.sh

# --- Map overview PNGs ---

map_level1.png map_level2.png: render_map.py $(LEVEL1M) $(LEVEL2M) $(GFX_SRCS)
	$(PYTHON) render_map.py

# --- Tiled export (regenerate .tmx from binaries — use sparingly) ---

export-tiled: $(LEVEL1M) $(LEVEL2M) $(GFX_SRCS)
	$(PYTHON) export_tiled.py

# --- Clean ---

clean:
	rm -f $(TARGET) _verify* $(LEVEL1M) $(LEVEL2M)

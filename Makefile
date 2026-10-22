# FROGMAN — Build System
#
# The canonical map sources are the Tiled .tmx files in tiled/.
# The Makefile generates Level?M binaries from them, assembles the
# engine/game code, and produces a bootable .ssd disc image.
#
# Requires: beebasm, python3 with Pillow
# The playthrough targets also need node and npm (and ffmpeg for video).

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

# Playthrough (see playthrough/README.md)
PLAY       = playthrough
LABELS     = $(PLAY)/build/frogman.labels
NODE_DEPS  = $(PLAY)/node_modules/.installed
ROUTE      = $(PLAY)/build/level1-route.json
KEYLOG     = $(PLAY)/level1.keys
NODE      ?= node

.PHONY: all clean verify maps playthrough route record video capture

all: $(TARGET)

# --- Map conversion: Tiled .tmx → Level?M binary ---

$(LEVEL1M): tiled/level1.tmx import_tiled.py
	$(PYTHON) import_tiled.py $< $@

$(LEVEL2M): tiled/level2.tmx import_tiled.py
	$(PYTHON) import_tiled.py $< $@

maps: $(LEVEL1M) $(LEVEL2M)
	@echo "Maps generated from Tiled sources"

# --- Main disc image ---

# Also writes every label (scoped ones too) for the playthrough recorder.
ASSEMBLE = @mkdir -p $(PLAY)/build && \
	$(BEEBASM) -i frogman.asm -do $(TARGET) -title $(TITLE) -opt 3 -dd -labels $(LABELS)

$(TARGET): $(ASM_SRCS) $(LEVEL1M) $(LEVEL2M) $(GFX_SRCS) $(DATA_SRCS)
	$(ASSEMBLE)
	@echo "Built $(TARGET)"

$(LABELS): $(ASM_SRCS) $(LEVEL1M) $(LEVEL2M) $(GFX_SRCS) $(DATA_SRCS)
	$(ASSEMBLE)

# --- Verification ---

verify: $(TARGET)
	./verify.sh

# --- Map overview PNGs ---

map_level1.png map_level2.png: render_map.py $(LEVEL1M) $(LEVEL2M) $(GFX_SRCS)
	$(PYTHON) render_map.py

# --- Tiled export (regenerate .tmx from binaries — use sparingly) ---

export-tiled: $(LEVEL1M) $(LEVEL2M) $(GFX_SRCS)
	$(PYTHON) export_tiled.py

# --- Playthrough: plan, record and replay a completion of level 1 ---

$(NODE_DEPS): $(PLAY)/package.json $(PLAY)/package-lock.json
	cd $(PLAY) && npm ci --omit=optional --no-audit --no-fund
	@touch $@

# Replay the committed key log and check it logs on to the power terminal.
playthrough: $(TARGET) $(NODE_DEPS)
	$(NODE) $(PLAY)/replay.mjs $(TARGET) $(KEYLOG) --expect-logon

# Plan the route from the hand-written goals (slow-ish: a few minutes).
route: $(ROUTE)
$(ROUTE): $(PLAY)/level1.plan $(PLAY)/plan.py $(PLAY)/frogsim.py $(LEVEL1M)
	@mkdir -p $(PLAY)/build
	cd $(PLAY) && $(PYTHON) plan.py level1.plan build/level1-route.json

# Re-record the key log from the route (overwrites the committed one).
record: $(ROUTE) $(LABELS) $(NODE_DEPS)
	$(NODE) $(PLAY)/record.mjs $(TARGET) $(LABELS) $(ROUTE) $(KEYLOG)

video: $(PLAY)/build/level1.mp4
$(PLAY)/build/level1.mp4: $(TARGET) $(KEYLOG) $(NODE_DEPS)
	$(NODE) $(PLAY)/replay.mjs $(TARGET) $(KEYLOG) --video $@

# The key log as a beebjit capture: beebjit -0 frogman_rebuilt.ssd -replay <file>
capture: $(PLAY)/build/level1.beebjit
$(PLAY)/build/level1.beebjit: $(KEYLOG) $(NODE_DEPS)
	$(NODE) $(PLAY)/beebjit.mjs to-capture $(KEYLOG) $@

# --- Clean ---

clean:
	rm -f $(TARGET) _verify* $(LEVEL1M) $(LEVEL2M)
	rm -rf $(PLAY)/build

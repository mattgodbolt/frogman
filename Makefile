# FROGMAN — BeebASM Build
#
# Produces a bootable .ssd disk image from the annotated disassembly.
# Requires: beebasm (https://github.com/stardot/beebasm)

BEEBASM ?= beebasm
TARGET  = frogman_rebuilt.ssd
SOURCE  = frogman.asm
TITLE   = FROGMAN

# Data files (decrypted binary dumps)
DATA_DIR = extracted/decrypted

.PHONY: all clean verify

all: $(TARGET)

$(TARGET): $(SOURCE) engine.asm tables.asm music.asm loader.asm
	$(BEEBASM) -i $(SOURCE) -do $(TARGET) -title $(TITLE)
	@echo "Built $(TARGET)"

clean:
	rm -f $(TARGET)

# Verify: compare rebuilt binary against original memory dump
verify: $(TARGET)
	@echo "TODO: boot in jsbeeb and compare memory dumps"
	@echo "  1. Boot $(TARGET) in jsbeeb (Master model)"
	@echo "  2. Select level 1, wait for game to load"
	@echo "  3. Dump &0600-&0C78 and compare with extracted/decrypted/game_engine.bin"
	@echo "  4. Screenshot compare: title screen and in-game"

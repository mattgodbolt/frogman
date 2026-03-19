#!/bin/bash
# Verify byte-exact match of assembled output against reference binaries.
set -e

cat > _verify.asm << 'EOF'
INCLUDE "constants.asm"
INCLUDE "zero_page.asm"
ORG &0700
INCLUDE "tables.asm"
INCLUDE "engine.asm"
INCLUDE "music.asm"
SAVE "_verify_engine.bin", &0700, &0F00
ORG &4800
INCLUDE "game.asm"
SAVE "_verify_game.bin", &4800, &5800
EOF

beebasm -i _verify.asm > /dev/null 2>&1

echo -n "Engine (&0700-&0EFF): "
cmp <(dd if=extracted/decrypted/full_memory.bin bs=1 skip=$((0x700)) count=$((0x800)) 2>/dev/null) _verify_engine.bin 2>/dev/null && echo "BYTE-EXACT" || echo "MISMATCH"

echo -n "Game   (&4800-&57FF): "
cmp data/gcode_decrypted.bin _verify_game.bin 2>/dev/null && echo "BYTE-EXACT" || echo "MISMATCH"

echo -n "Disc image: "
beebasm -i frogman.asm -do frogman_rebuilt.ssd -title "FROGMAN" -opt 3 > /dev/null 2>&1 && echo "OK" || echo "BUILD FAILED"

rm -f _verify.asm _verify_engine.bin _verify_game.bin

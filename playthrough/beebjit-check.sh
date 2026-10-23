#!/bin/bash
# Replay a key log in beebjit and check it logs on to the power terminal.
#   beebjit-check.sh <beebjit binary dir> <disc.ssd> <log.keys> <capture file>
# beebjit runs in its interpreter (its JIT wants fixed mmap addresses some
# sandboxes refuse) with the same ROMs jsbeeb's B-DFS1.2 uses: OS 1.2,
# BASIC 2 and Acorn DNFS (DFS 1.20).
set -euo pipefail
dir=$1 disc=$(realpath "$2") log=$3 cap=$(realpath "$4")
end=$(awk '$2 == "END" { print $1 }' "$log")
# zp_terminal_ctr is &22, zp_lives &24.
zp=$(cd "$dir" && ./beebjit -headless -mode interp -fast -accurate -dfs12 -0 "$disc" -replay "$cap" \
        -debug -commands "breakat $end;c;m 20;q" < /dev/null 2>&1 | awk '/^0020:/ { print $4, $6 }')
read -r terminals lives <<< "$zp"
echo "beebjit: terminal counter &$terminals, lives $((16#$lives))"
[ "$terminals" = "FF" ] || { echo "expected LOGGED ON (terminal counter &FF)"; exit 1; }

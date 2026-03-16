# jsbeeb MCP Enhancement Proposals for FROGMAN Reverse Engineering

## Already Available (missed earlier!)

- `read_registers` — reads PC, A, X, Y, SP, processor status. This is huge — we can find the main loop by trapping execution and reading PC.

## Proposed New Tools

### 1. `set_breakpoint` — Execution Breakpoint

```json
{
  "address": 10507,
  "type": "execute",
  "enabled": true
}
```

**Returns:** breakpoint ID.

**Behaviour:** When the CPU's PC reaches the address, emulation pauses (as if `run_for_cycles` completed). The caller can then `read_registers`, `read_memory`, etc.

**Why needed:** The Loader's 55-stage EOR decryption chain advances through memory one 256-byte page at a time. Each stage decrypts the next page, then falls through. We need to catch execution at the boundary between stages. Without breakpoints, we can only run N cycles and hope — which is unreliable because the decryption speed depends on VIA timer values.

**Use case 1 — Trace decryption chain:**
1. Load the Loader without executing: `*LOAD Loader 2800`
2. Set breakpoint at each stage's fall-through point
3. `CALL &290B` to start execution
4. When breakpoint hits, dump the newly-decrypted page
5. Disassemble to find the next stage's entry/exit
6. Set new breakpoint, continue
7. Repeat until we find the final stage that jumps to the game

**Use case 2 — Find main game loop:**
1. Boot original game fully
2. Set breakpoint at `update_sprites` (&0A2D) or `render_map` (&0997)
3. When it hits, `read_registers` to get return address from stack
4. That tells us where the main loop is

### 2. `run_until_breakpoint`

```json
{
  "session_id": "...",
  "timeout_secs": 30
}
```

**Returns:** Which breakpoint was hit (or timeout), plus register state.

**Why needed:** Companion to `set_breakpoint`. Runs emulation until any breakpoint fires or timeout. More useful than `run_for_cycles` when you don't know how many cycles something takes.

### 3. `clear_breakpoint`

```json
{
  "breakpoint_id": 1
}
```

**Why needed:** Clean up breakpoints that are no longer needed. Avoids accumulating stale breakpoints.

### 4. `single_step`

```json
{
  "session_id": "...",
  "count": 1
}
```

**Returns:** Register state after each step.

**Why needed:** For tracing small sections of code instruction by instruction. Useful once we've breakpointed near the end of the decryption chain — we can single-step through the final few instructions to see exactly where the game starts.

**Lower priority** than breakpoints — we can achieve most goals with breakpoints + read_registers.

### 5. `read_memory` enhancement: larger reads

Current limit is 256 bytes per call. For dumping large regions (tile graphics, level maps), allowing up to 4096 or 8192 bytes per call would reduce the number of round trips from ~80 to ~8.

**Not blocking** but would have saved significant time during the initial memory dumping phase.

## Priority Order

1. **`set_breakpoint` + `run_until_breakpoint` + `clear_breakpoint`** — These three unlock everything. The decryption chain, the main loop, the IRQ handler — all findable with breakpoints.

2. **`single_step`** — Nice to have for detailed tracing once we're close.

3. **`read_memory` larger reads** — Quality of life improvement.

## Specific Investigation Plan Once Breakpoints Are Available

### Find the end of the Loader decryption chain:
1. `*LOAD Loader 2800` (load without executing)
2. Read &290B-&293F to find first EOR loop end address
3. Set breakpoint just after the loop (the fall-through point)
4. `CALL &290B`
5. At each breakpoint: read the newly-decrypted page, find the next loop, set new breakpoint, continue
6. Eventually a stage won't be another EOR loop — it'll be the actual game setup code

### Find the real IRQ handler:
1. Boot original game fully (level loaded, game running)
2. Read &0204/&0205 (IRQ1V) — we found &4CA5, need to understand why
3. Read the code at &4CA5 to see if it's actually an IRQ handler embedded in graphics data, or if the vector value is stale/wrong
4. Set breakpoint at common IRQ entry patterns (PHA at &4CA5 if it exists)

### Find the main game loop:
1. Boot game fully
2. Set breakpoint at &0A2D (update_sprites entry) or &0997 (render_map)
3. When it hits, read SP, then read the stack to find the return address
4. That return address is inside the main loop
5. Dump and disassemble the main loop code

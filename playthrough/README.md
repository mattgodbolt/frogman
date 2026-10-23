# FROGMAN level 1 playthrough

`level1.keys` is a complete run of level 1, from switching the machine on
to the power control terminal saying **LOGGED ON**. It holds nothing but
key presses, with the time of each one, so replaying it from power-on
reproduces the run exactly.

```bash
make playthrough   # replay it in jsbeeb and check it logs on
make video         # ... and render playthrough/build/level1.mp4
make capture       # convert it to a beebjit capture file
make beebjit-check # ... and check it logs on in beebjit too
```

The run takes 9.5 emulated minutes on a Model B (`B-DFS1.2`) with
`frogman_rebuilt.ssd` in drive 0, and finishes with 5 of the 9 lives left.

## Playing fair

Everything the frog does, a player could do: the log only presses the keys
the game reads (Z, X, :, /, f0, f1, SPACE, ESCAPE, plus 1 at the level
prompt and the SHIFT of SHIFT+BREAK). There are no pokes, no cheat keys
and no stitched-together save states. ESCAPE is used four times as a
deliberate "die and restart at home" to get back from one-way areas; the
game puts that in the player's hands, so it's fair game.

The route was found with tools, though, which a player wouldn't have. The
tools read the map and the machine's memory to plan the route and check it,
but nothing is ever written to the machine except key presses.

## How it was made

1. **`frogsim.py`** ports `game.asm`'s main loop to Python at tile level.
   The game decides everything on the 16x8 tile grid of a screen: the arcs
   of a hop are drawn but never consulted. So one pass of `main_loop` can
   be simulated exactly, quirks and all: 8-bit wrap-around,
   out-of-bounds reads that return tile &00, writes that land on a
   neighbouring screen, and the stale `zp_tile_x`/`zp_tile_y` that
   `check_below` inherits from whatever was drawn last.

2. **`level1.plan`** is the route, written by hand as a list of goals:
   "hold the bible and the candle", "drop the yellow key at (4,2) on the
   start screen", "8 terminals on the map", "log on". The comments in it
   explain the puzzle.

3. **`plan.py`** finds, for each goal in turn, the quickest key presses (in
   frames) that reach it from where the last one left off. It's a Dijkstra
   search over the simulator, forbidden from changing the inventory except
   as the goal asks. Each leg is small: with the inventory fixed, the frog
   can only be in a few hundred places.

4. **`record.mjs`** plays the route in [jsbeeb](https://github.com/mattgodbolt/jsbeeb)
   and writes the key log. The game polls the keyboard, so timing matters:
   - keys only change at the start of the vsync interrupt, which the game
     waits for before every read;
   - the recorder waits until the game has finished with the previous keys:
     a hop reads `/` a frame after it starts, and f0/f1 wait for the key to
     be let go.

   At every `scan_keys` it checks the frog against the model and stops at
   the first disagreement. On the full route they agreed at all 1490 key
   reads. Finally, every key change is moved to the middle of the window
   between the game's last read of the key's old state and its first read
   of the new one. In jsbeeb that changes nothing, but it gives another
   emulator the most slack possible. The boot keys are pressed well after
   the machine starts waiting for them, so that a slower or faster disc
   still starts the game at the same moment.

5. **`replay.mjs`** plays a log back from power-on with nothing but its key
   presses, and can pipe the frames to ffmpeg.

Rebuilding everything: `make route` re-plans (about 15 seconds) and
`make record` re-records `level1.keys` from that route (about 2 minutes).

## The key log format

```
# comments
<2MHz cycles since power-on> <KEY> <down|up>
...
<cycles> END
```

Keys are `SHIFT ESCAPE F0 F1 X Z COLON SLASH SPACE 1`. The machine starts
switched off with no keys down. Cycles are counted the way beebjit counts
the ticks in its keyboard captures, so `beebjit.mjs` converts both ways
exactly:

```bash
node beebjit.mjs to-capture level1.keys level1.cap      # then: beebjit -0 frogman_rebuilt.ssd -replay level1.cap
node beebjit.mjs from-capture some.cap some.keys
```

`make beebjit-check` builds beebjit from source (a pinned revision) and
replays the same log in it: it logs on too, with the same 5 lives. The two
emulators don't agree to the cycle, so getting there took some care:

- Their disc timing differs. jsbeeb models the drive spinning up and the
  Model B's index-pulse ready latch; beebjit reports a spinning drive ready
  at once. jsbeeb's Model B also has 16 separate ROM banks, while beebjit
  mirrors the four ROM sockets across them like a stock machine, which
  slows the MOS's start-up ROM scan. So the game reaches each prompt at a
  different moment. The log presses each boot key a couple of seconds
  after jsbeeb starts waiting for it, so beebjit is waiting too, and the
  game starts at the same cycle in both.
- That still leaves the two machines' vsyncs about 5000 cycles apart, so
  every key change sits in the middle of its window (see above). The one
  place that isn't enough is `wait_escape_release`, which spins on ESCAPE
  with no vsync in the loop. ESCAPE is let go 12000 cycles after the game
  notices it, mid-frame, so the death starts in the same frame on both
  machines.

beebjit's JIT wants fixed mmap addresses, which some sandboxes refuse, so
the check runs its interpreter (`-mode interp`).

## The route

In brief (see `level1.plan` for the details):

1. Library ticket → bible (walk it over the blank tiles on screen (6,1)).
2. Candle → lit at the fire on (7,3) → blows up the TNT on (3,3), opening
   the way to the bottom of the map.
3. Wand → into the top hat on (0,9): rabbit. The rabbit gets through the
   barriers on (4,9) to the white key. Beyond the key is locked floor, so:
   ESCAPE.
4. Fetch the yellow key and set up a delivery station by the yellow door.
5. Terminals 7 and 3 (bible), then 2, 5 and 1 (on foot), then 4 and 6
   (white key, one-way, ESCAPE back), all to the map terminal.
6. The ring, to stand on the locked floor next to terminal 8. ESCAPE home,
   deliver it, and walk back across the locked floor to the power terminal.

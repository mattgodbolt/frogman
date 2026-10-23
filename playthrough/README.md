# FROGMAN level 1 playthrough

`level1.keys` is a complete run of level 1, from switching the machine on
to the power control terminal saying **LOGGED ON**. It holds nothing but
key presses, with the time of each one, so replaying it from power-on
reproduces the run exactly.

```bash
make playthrough   # replay it in jsbeeb and check it logs on
make video         # ... and render playthrough/build/level1.mp4
make capture       # convert it to a beebjit capture file
```

The run takes 9.4 emulated minutes on a Model B (`B-DFS1.2`) with
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
   reads.

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

Whether a capture replays to the same ending in beebjit depends on the two
emulators agreeing cycle for cycle, from disc loading onwards. That hasn't
been tested yet.

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

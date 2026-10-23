#!/usr/bin/env python3
"""Tile-level simulator of FROGMAN's main loop (game.asm).

Everything the game decides is decided on the 16x8 tile grid: the pixel
arcs of a hop are drawn but never consulted. So one pass of main_loop can
be replayed exactly here, which makes route-finding a graph search
instead of an emulator grind.

The port follows game.asm routine by routine, including its quirks:
8-bit wrap-around of rows and columns, out-of-bounds reads returning
tile &00, writes that land in a neighbouring screen, and the stale
zp_tile_x/zp_tile_y that check_below inherits from whatever drew last.

A state sits at one of two places in the loop:
  MAIN - the top of main_loop (ground check next; no keys read except ESCAPE)
  SCAN - scan_keys, where the player's keys are read
advance() runs the forced part from MAIN; act() applies a key at SCAN.
Both return the next state and an approximate frame cost (one per
wait_vsync), which is good enough for comparing routes; the emulator
harness is the authority on real timing.
"""

import os
from dataclasses import dataclass, replace

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)

MAP_BASE = 0x0F00
MAP_SIZE = 0x2800
OVERVIEW = 0x0300
TYPE_TABLE = 0x4000
G_LOAD = 0x3700

# Tiles (constants.asm)
EMPTY, CONVEY_L, CONVEY_R, MAP_TERM, CLIMB_R = 0x00, 0x02, 0x03, 0x04, 0x05
LADDER, LADDER_FRM, CRUMBLE, LOCKED, HAZARD = 0x06, 0x07, 0x10, 0x11, 0x12
PLACED_1, PLACED_2, CLIMB_L, POWER_TERM = 0x1C, 0x1D, 0x1E, 0x1F

COLLISION_FLAGS = (
    [0xFF, 0, 0, 0, 0xFF, 0, 0xFF, 0xFF] + [0] * 10 + [0xFF] * 10 + [0, 0, 0, 0xFF]
)
TILE_TYPE_TABLE = [0, 0, 0, 0xFF, 0xFF, 0, 0, 0, 0xFF, 0xFF, 0xFF, 0, 0]
COLLISION_CHECK_TABLE = (
    [0] * 5 + [0xFF] * 3 + [0xFF, 0xFF] + [0] + [0xFF] + [0] * 20
)

KEYS = ("none", "right", "right_short", "left", "left_short", "up", "f0", "f1", "escape")


class Level:
    def __init__(self, n=1):
        ext = os.path.join(ROOT, "extracted")
        self.map = open(os.path.join(ext, f"Level{n}M"), "rb").read()
        self.gfx = open(os.path.join(ext, f"Level{n}G"), "rb").read()
        self.overview = open(os.path.join(ext, f"Level{n}S"), "rb").read()[:0x80]

    def base_byte(self, addr):
        if MAP_BASE <= addr < MAP_BASE + MAP_SIZE:
            return self.map[addr - MAP_BASE]
        if OVERVIEW <= addr < OVERVIEW + 0x80:
            return self.overview[addr - OVERVIEW]
        raise OffMap(addr)

    def gfx_byte(self, addr):
        return self.gfx[addr - G_LOAD]


class OffMap(Exception):
    """The frog has wandered into memory that isn't level data."""


class Died(Exception):
    pass


MAIN, SCAN = "MAIN", "SCAN"


@dataclass(frozen=True)
class State:
    sx: int = 0
    sy: int = 0
    col: int = 5
    row: int = 1
    dir: int = 0
    falling: int = 0
    item0: int = 0
    item1: int = 0
    gstate: int = 0
    special: int = 0
    tctr: int = 0
    lives: int = 9
    save_col: int = 0
    save_row: int = 0
    src: int = MAP_BASE
    entry: str = MAIN
    mods: tuple = ()  # sorted ((addr, value), ...) differences from the level data

    def key(self):
        return (self.sx, self.sy, self.col, self.row, self.dir, self.item0, self.item1,
                self.gstate, self.special, self.tctr, self.lives, self.save_col,
                self.save_row, self.src, self.entry, self.mods)


def map_src_for(sx, sy):
    """setup_map_render: &0F00 + sy*&400 + sx*&80, in 8-bit arithmetic."""
    lo = (sx & 1) << 7
    a = (sy << 2) & 0xFF
    carry = (sy >> 6) & 1  # left by the second ASL
    a += ((sx & 0xFF) >> 1) + carry
    a, carry = a & 0xFF, a >> 8
    a += 0x0F + carry
    return ((a & 0xFF) << 8) | lo


class Sim:
    """Mutable working copy of a State while one pass of the loop runs."""

    def __init__(self, level, s):
        self.L = level
        self.__dict__.update({k: getattr(s, k) for k in State.__dataclass_fields__})
        self.mods = dict(s.mods)
        self.tx = 0
        self.ty = 0
        self.tile_data = 0
        self.frames = 0
        self.events = []

    def freeze(self, entry):
        d = {k: getattr(self, k) for k in State.__dataclass_fields__ if k not in ("mods", "entry")}
        return State(**d, entry=entry, mods=tuple(sorted(self.mods.items())))

    # --- memory ---
    def rd(self, addr):
        addr &= 0xFFFF
        if addr in self.mods:
            return self.mods[addr]
        return self.L.base_byte(addr)

    def wr(self, addr, val):
        addr &= 0xFFFF
        self.L.base_byte(addr)  # raise OffMap if it's not level data
        if self.L.base_byte(addr) == val:
            self.mods.pop(addr, None)
        else:
            self.mods[addr] = val

    def vsync(self, n=1):
        self.frames += n

    # --- game.asm helpers ---
    def get_tile_at_frog(self):
        if self.row >= 7:
            return 0
        return self.rd(self.src + ((((self.row + 1) << 4) + self.col) & 0xFF))

    def get_tile_at_pos(self):
        if self.tx >= 0x10 or self.ty >= 8:
            return 0
        return self.rd(self.src + (((self.ty << 4) + self.tx) & 0xFF))

    def set_tile_at_pos(self, a):
        self.wr(self.src + (((self.ty << 4) + self.tx) & 0xFF), a)
        self.tx = (self.tx << 2) & 0xFF
        self.ty = (self.ty << 1) & 0xFF

    def get_tile_type(self, a):
        y = (((a - 0x20) & 0xFF) << 1) & 0xFF
        self.tile_data = self.L.gfx_byte(TYPE_TABLE + y + 1)
        return self.L.gfx_byte(TYPE_TABLE + y)

    def check_tile_solid(self, a):
        """True = solid (Z set in the asm)."""
        if a < 0x20:
            return COLLISION_FLAGS[a] == 0
        t = self.get_tile_type(a)
        if t in (5, 7):
            return not (self.tile_data == self.item0 or self.tile_data == self.item1)
        return TILE_TYPE_TABLE[t] == 0

    def draw_status(self):
        # Only its side effects on zp_tile_x/y matter here.
        self.tx = 0x3E
        self.ty = 0x12

    def setup_map(self):
        self.src = map_src_for(self.sx, self.sy)
        self.tx = 0
        self.ty = 0x10

    def palette_flash(self):
        self.vsync(11)

    def die(self):
        for _ in range(8):
            self.vsync(3)
            self.tx = self.col
            self.ty = (self.row + 1) & 0xFF
            self.set_tile_at_pos(self.get_tile_at_pos())
        self.vsync(51)
        self.lives -= 1
        self.events.append("death")
        if self.lives == 0:
            raise Died()
        self.respawn()
        return MAIN

    def respawn(self):
        self.col, self.row, self.sx, self.sy = 5, 1, 0, 0
        self.setup_map()
        self.dir = 0
        self.gstate = 0

    # --- main_loop from the top ---
    def main(self):
        a = self.get_tile_at_frog()
        if self.check_tile_solid(a):
            return self.land_on_ground(a)
        return self.check_fall(a)

    def land_on_ground(self, a):
        self.falling = 0
        if a == CONVEY_R:
            return self.convey(+1, CONVEY_R)
        if a == CONVEY_L:
            return self.convey(-1, CONVEY_L)
        if a == LOCKED:
            if self.get_tile_type(self.item0) != 1 and self.get_tile_type(self.item1) != 1:
                return self.die()
        return self.tile_dispatch(a)

    def tile_dispatch(self, a):
        if a == CLIMB_R:
            return self.walk(+1)
        if a == CLIMB_L:
            return self.walk(-1)
        if a in (CRUMBLE, PLACED_1, PLACED_2):
            nxt = {CRUMBLE: PLACED_1, PLACED_1: PLACED_2, PLACED_2: EMPTY}[a]
            self.tx = self.col
            self.ty = (self.row + 1) & 0xFF
            self.set_tile_at_pos(nxt)
            return SCAN
        self.tx, self.ty = self.col, self.row
        a = self.get_tile_at_pos()
        if a == MAP_TERM:
            if not (self.gstate & 0x80):
                return self.map_reveal()
        else:
            self.gstate &= 0x7F
        if a == POWER_TERM:
            r = self.special_tile()
            if r is not None:
                return r
        else:
            self.special = 0
        return self.check_passthrough(a)

    def check_passthrough(self, a):
        if a >= 0x20:
            t = self.get_tile_type(a)
            if t == 9:
                self.collect_item()
            if t == 5:
                self.tx, self.ty = self.col, self.row
                self.set_tile_at_pos(0)
                self.palette_flash()
                self.events.append("barrier_cleared")
        elif a == HAZARD:
            return self.die()
        self.ty = (self.ty + 1) & 0xFF
        a = self.get_tile_at_pos()
        if a >= 0x20 and self.get_tile_type(a) == 0x0B:
            self.drop_item()
        return SCAN

    def collect_item(self):
        for slot in ("item0", "item1"):
            if getattr(self, slot) == self.tile_data:
                setattr(self, slot, (getattr(self, slot) + 1) & 0xFF)
                self.draw_status()
                self.palette_flash()
                self.events.append(f"evolve {slot} -> {getattr(self, slot):02x}")
                return

    def drop_item(self):
        for slot in ("item0", "item1"):
            if getattr(self, slot) == self.tile_data:
                self.events.append(f"consumed {getattr(self, slot):02x}")
                setattr(self, slot, 0)
                self.draw_status()
                self.tx, self.ty = self.col, (self.row + 1) & 0xFF
                self.set_tile_at_pos(0)
                self.tx, self.ty = self.col, (self.row + 2) & 0xFF
                self.set_tile_at_pos(0)
                self.vsync(21 + 7 * 6)
                return

    def check_fall(self, below):
        self.tx, self.ty = self.col, self.row
        if self.get_tile_at_pos() == LADDER:
            return self.land_on_ground(below)
        a = self.get_tile_at_frog()
        if a >= 0x20 and self.get_tile_type(a) == 3:
            return self.land_on_ground(below)
        self.row = (self.row + 1) & 0xFF
        if self.row >= 8:
            self.sy = (self.sy + 1) & 0xFF
            self.row = 0
            self.setup_map()
            return MAIN
        if self.falling == 0:
            self.dir |= 1
            self.vsync(8)
            self.dir &= 2
            self.falling = 0xFF
        else:
            self.vsync(4)
            self.dir &= 2
        return MAIN

    def convey(self, d, tile):
        while True:
            self.vsync(4)
            self.col = (self.col + d) & 0xFF
            self.row = (self.row + 1) & 0xFF
            if self.get_tile_at_frog() != tile:
                return MAIN

    def walk(self, d):
        """move_right_check / move_left_check: tiles &05 and &1E carry the frog."""
        y = (self.col + d) & 0xFF
        if y >= 0x10:
            self.col = 0 if d > 0 else 0x0F
            self.sx = (self.sx + d) & 0xFF
            self.setup_map()
            return MAIN
        self.tx, self.ty = y, self.row
        if self.check_tile_solid(self.get_tile_at_pos()):
            return SCAN
        self.vsync(16)
        self.col = (self.col + d) & 0xFF
        return MAIN

    def map_reveal(self):
        self.vsync(7 * 5 + 51)
        if self.gstate != 0:
            self.gstate = 0x80
            self.col, self.row = self.save_col, self.save_row
            self.setup_map()
            self.vsync(7 * 5)
            self.events.append("map_closed")
            return MAIN
        self.gstate = 0x81
        self.save_col, self.save_row = self.col, self.row
        self.col, self.row = 1, 6
        self.src = OVERVIEW
        for slot in ("item0", "item1"):
            v = getattr(self, slot)
            if v >= 0x38:
                self.tx, self.ty = (v - 0x31) & 0xFF, 6
                self.set_tile_at_pos(v)
                setattr(self, slot, 0)
                self.tctr = (self.tctr + 1) & 0xFF
                self.events.append(f"terminal {v - 0x37} placed")
        self.vsync(7 * 5)
        self.events.append("map_opened")
        return MAIN

    def special_tile(self):
        """handle_special_tile. None means 'carry on into check_passthrough'."""
        if self.special:
            return None
        self.special = 0xFF
        if self.tctr >= 8:
            if self.gstate == 0:
                self.vsync(101)
                self.tctr = 0xFF
                self.events.append("LOGGED ON")
                return MAIN
            if self.tctr & 0x80:
                raise OffMap("halt")  # already_done falls into the JMP halt trap
        self.vsync(101)
        self.events.append("ACCESS DENIED")
        self.tx, self.ty = 0, 0x10
        return MAIN

    # --- scan_keys ---
    def act(self, key):
        if key in ("right", "right_short"):
            return self.hop(+1, key.endswith("short"))
        if key in ("left", "left_short"):
            return self.hop(-1, key.endswith("short"))
        if key == "up":
            return self.move_up()
        if key in ("f0", "f1") and (self.src >> 8) != 3:
            return self.use_item(0 if key == "f0" else 1)
        self.vsync()
        if key == "escape":
            return self.die()
        return MAIN

    def hop(self, d, slash):
        self.vsync()
        self.dir = 0 if d > 0 else 2
        self.tx, self.ty = (self.col + d) & 0xFF, self.row
        if self.check_tile_solid(self.get_tile_at_pos()):
            self.vsync()
            return MAIN
        self.dir |= 1
        self.tx = (self.tx + d) & 0xFF
        if self.check_tile_solid(self.get_tile_at_pos()) or slash:
            return self.short_hop(d)
        self.col = (self.col + d) & 0xFF
        if d > 0 and self.col >= 0x0F or d < 0 and (self.col == 0 or self.col & 0x80):
            self.col = 0 if d > 0 else 0x0F
            self.sx = (self.sx + d) & 0xFF
            self.setup_map()
            self.dir = 0 if d > 0 else 2
            return MAIN
        self.vsync(8)
        self.col = (self.col + d) & 0xFF
        self.dir = 0 if d > 0 else 2
        self.vsync()
        return MAIN

    def short_hop(self, d):
        self.col = (self.col + d) & 0xFF
        if d > 0 and self.col == 0x10 or d < 0 and self.col & 0x80:
            self.col = 0 if d > 0 else 0x0F
            self.sx = (self.sx + d) & 0xFF
            self.setup_map()
            self.dir = 0 if d > 0 else 2
            return MAIN
        self.vsync(4)
        self.dir = 0 if d > 0 else 2
        self.vsync()
        return MAIN

    def move_up(self):
        left = bool(self.dir & 2)
        d = -1 if left else 1
        stair = CONVEY_R if left else CONVEY_L
        self.tx, self.ty = (self.col + d) & 0xFF, self.row
        if self.get_tile_at_pos() == stair:
            while True:
                self.vsync(4)
                self.col = (self.col + d) & 0xFF
                self.row = (self.row - 1) & 0xFF
                self.tx, self.ty = (self.col + d) & 0xFF, self.row
                if self.get_tile_at_pos() != stair:
                    break
            self.dir = 2 if left else 0
            self.tx, self.ty = (self.col + d) & 0xFF, self.row
            if self.check_tile_solid(self.get_tile_at_pos()):
                return MAIN
            return self.short_hop(d)
        # check_ladder
        self.tx, self.ty = self.col, self.row
        if self.get_tile_at_pos() != LADDER:
            return self.jump_up()
        self.ty = (self.row - 1) & 0xFF
        self.tx = self.col
        if self.check_tile_solid(self.get_tile_at_pos()):
            return MAIN
        while True:
            self.row = (self.row - 1) & 0xFF
            if self.row & 0x80:
                self.row = 7
                self.sy = (self.sy - 1) & 0xFF
                self.setup_map()
            self.ty, self.tx = self.row, self.col
            if self.get_tile_at_pos() == LADDER_FRM:
                self.vsync(9)
                continue
            self.vsync(16)
            return SCAN

    def jump_up(self):
        self.tx = self.col
        y = (self.row - 1) & 0xFF
        if y & 0x80:
            self.row = 7
            self.sy = (self.sy - 1) & 0xFF
            self.setup_map()
            return MAIN
        self.ty = y
        if self.check_tile_solid(self.get_tile_at_pos()):
            return MAIN
        self.vsync(8)
        self.row = y
        return MAIN

    def pickable(self):
        """check_tile_passable: True when the tile at (tx, ty) can be picked up."""
        a = self.get_tile_at_pos()
        if a < 0x20:
            return None
        t = self.get_tile_type(a)
        return a if COLLISION_CHECK_TABLE[t] == 0 else None

    def use_item(self, slot):
        self.vsync(2)  # wait for the key to be released
        name = ("item0", "item1")[slot]
        if getattr(self, name):
            return self.place_item(slot)
        self.tx, self.ty = self.col, self.row
        a = self.pickable()
        if a is None:
            self.tx = (self.col + (-1 if self.dir & 2 else 1)) & 0xFF
            self.ty = self.row
            a = self.pickable()
        if a is None:
            self.tx, self.ty = self.col, (self.row + 1) & 0xFF
            a = self.pickable()
            if a is None:
                return MAIN
        setattr(self, name, a)
        self.set_tile_at_pos(0)
        self.events.append(f"picked up {a:02x} into f{slot}")
        return MAIN

    def place_item(self, slot):
        name = ("item0", "item1")[slot]
        self.tx, self.ty = self.col, self.row
        if self.get_tile_at_pos() != 0:
            return MAIN
        item = getattr(self, name)
        t = self.get_tile_type(item)
        if t not in (3, 4):
            self.ty = (self.ty - 1) & 0xFF
            if self.ty & 0x80:
                return MAIN
            if self.check_tile_solid(self.get_tile_at_pos()):
                return MAIN
        self.tx, self.ty = self.col, self.row
        self.set_tile_at_pos(item)
        if t not in (3, 4):
            self.row = (self.row - 1) & 0xFF
        setattr(self, name, 0)
        self.events.append(f"placed {item:02x} from f{slot}")
        return MAIN


def step(level, s, key="none"):
    """One transition. From MAIN the key is ignored (only ESCAPE is read there,
    and act() models ESCAPE at SCAN instead). Returns (state, frames, events)."""
    sim = Sim(level, s)
    if s.entry == MAIN:
        entry = sim.main()
    else:
        entry = sim.act(key)
    return sim.freeze(entry), sim.frames, sim.events


def settle(level, s, limit=200):
    """Run forced MAIN passes until the game next reads the keyboard."""
    frames, events = 0, []
    for _ in range(limit):
        if s.entry == SCAN:
            return s, frames, events
        s, f, e = step(level, s)
        frames += f
        events += e
    raise RuntimeError("never reached scan_keys")


def start_state(level):
    s = State()
    sim = Sim(level, s)
    sim.setup_map()
    return sim.freeze(MAIN)

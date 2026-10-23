#!/usr/bin/env python3
"""Turn a hand-written list of goals into a key-by-key route with frogsim.

The high-level plan (which item to fetch next, where to drop things) is
written by a human in a plan file; for each leg this finds the quickest
sequence of key presses, in frames, that reaches the leg's goal without
any inventory change the leg didn't ask for.

Plan file: one goal per line, '#' comments.
  have <item>[,<item>]     both slots end up holding these (hex, any order;
                           '-' for an empty slot)
  drop <item> at <sx>,<sy>[,<col>,<row>]
                           place <item> on that screen (and on that tile)
  at <sx>,<sy>[,<col>,<row>] be on that screen (and tile)
  event <text...>          an event whose description starts with <text>
                           happens (e.g. "event consumed 30" for the TNT)
  terminals <n>            the overview shows n terminals
  logon                    the power terminal says LOGGED ON
Options after the goal, separated by spaces:
  deaths=<n>               allow up to n deaths (ESCAPE or otherwise) in this leg
  deaths=?                 walk if at all possible, else allow one death
  via=<sx>,<sy>            the leg must pass through that screen (repeatable,
                           visited in order) - handy to steer around traps

Output: a JSON route that harness.mjs records into a key log.
"""

import heapq
import itertools
import json
import sys

from frogsim import OVERVIEW, Died, Level, OffMap, map_src_for, settle, start_state, step

ITEM_EVENTS = ("picked", "placed", "evolve", "consumed", "terminal")
ACTIONS = ("none", "right", "right_short", "left", "left_short", "up", "f0", "f1", "escape")


def parse_items(text):
    return tuple(sorted(0 if t == "-" else int(t, 16) for t in text.split(",")))


class Goal:
    def __init__(self, line):
        words = line.split()
        self.text = line
        self.kind = words[0]
        self.deaths = 0
        self.via = []
        rest = words[1:]
        if self.kind == "have":
            want = parse_items(rest[0])
            self.want = tuple(sorted(want + (0,) * (2 - len(want))))
            rest = rest[1:]
        elif self.kind == "drop":
            self.item = int(rest[0], 16)
            where = tuple(map(int, rest[2].split(",")))
            self.screen, self.tile = where[:2], where[2:]
            rest = rest[3:]
        elif self.kind == "at":
            self.where = tuple(map(int, rest[0].split(",")))
            rest = rest[1:]
        elif self.kind == "event":
            n = next((i for i, w in enumerate(rest) if "=" in w), len(rest))
            self.event = " ".join(rest[:n])
            rest = rest[n:]
        elif self.kind == "terminals":
            self.n = int(rest[0])
            rest = rest[1:]
        elif self.kind != "logon":
            raise ValueError(f"unknown goal: {line}")
        for opt in rest:
            k, v = opt.split("=")
            if k == "deaths":
                self.deaths = -1 if v == "?" else int(v)
            elif k == "via":
                self.via.append(tuple(map(int, v.split(","))))
            else:
                raise ValueError(f"unknown option {opt}")

    def may_change_items(self):
        """An event goal about something else (a barrier, say) mustn't be met by
        an inventory change on the way, like dropping an item to climb onto."""
        return self.kind != "event" or self.event.startswith(ITEM_EVENTS)

    def done(self, s, events):
        if self.kind == "have":
            return tuple(sorted((s.item0, s.item1))) == self.want
        if self.kind == "drop":
            if not (f"placed {self.item:02x}" in " ".join(events)
                    and (s.sx, s.sy) == self.screen and s.src != OVERVIEW):
                return False
            if not self.tile:
                return True
            col, row = self.tile
            addr = map_src_for(s.sx, s.sy) + row * 16 + col
            return dict(s.mods).get(addr) == self.item
        if self.kind == "at":
            here = (s.sx, s.sy, s.col, s.row)[:len(self.where)]
            return here == self.where and s.src != OVERVIEW
        if self.kind == "event":
            return any(e.startswith(self.event) for e in events)
        if self.kind == "terminals":
            return s.tctr == self.n
        return "LOGGED ON" in events


def transition(level, s, a):
    t, frames, events = step(level, s, a)
    t, f2, e2 = settle(level, t)
    return t, frames + f2, events + e2


def leg(level, start, goal, max_states=2_000_000):
    """Dijkstra from start to goal. Returns (frames, actions, end_state, events)."""
    tie = itertools.count()
    lives_floor = start.lives - goal.deaths
    nvia = len(goal.via)
    # The via-progress counter is part of the search state.
    heap = [(0, next(tie), start, 0, (), ())]
    best = {(start.key(), 0): 0}
    popped = 0
    while heap:
        d, _, s, v, path, evs = heapq.heappop(heap)
        if v == nvia and goal.done(s, evs[-1] if evs else ()):
            return d, path, s, evs
        if best.get((s.key(), v), 1 << 60) < d:
            continue
        popped += 1
        if popped > max_states:
            break
        for a in ACTIONS:
            if a == "escape" and s.lives - 1 < max(lives_floor, 1):
                continue
            try:
                t, f, ev = transition(level, s, a)
            except (OffMap, RuntimeError, Died):
                continue
            if t.lives < max(lives_floor, 1):
                continue
            nv = v
            if nv < nvia and (t.sx, t.sy) == goal.via[nv] and t.src != OVERVIEW:
                nv += 1
            changed = (t.item0, t.item1, t.tctr) != (s.item0, s.item1, s.tctr)
            if changed or "LOGGED ON" in ev:
                if not (nv == nvia and goal.done(t, ev)):
                    continue
                if changed and not goal.may_change_items():
                    continue
            nd = d + f
            k = (t.key(), nv)
            if nd < best.get(k, 1 << 60):
                best[k] = nd
                heapq.heappush(heap, (nd, next(tie), t, nv, path + (a,), evs + (tuple(ev),)))
    return None


def expected_scans(level, s, path):
    """The machine state the harness should see at each scan_keys visit of a leg,
    and whether an extra idle pass there would be harmless."""
    out = []
    for a in path:
        idle, _, _ = transition(level, s, "none")
        out.append({"key": a, "sx": s.sx, "sy": s.sy, "col": s.col, "row": s.row,
                    "dir": s.dir, "items": [s.item0, s.item1], "lives": s.lives,
                    "terminals": s.tctr, "idle_ok": idle.key() == s.key()})
        s, _, _ = transition(level, s, a)
    return out


def run_plan(lines, level=None, log=sys.stderr):
    level = level or Level(1)
    s, f, _ = settle(level, start_state(level))
    total = f
    legs = []
    for line in lines:
        line = line.split("#")[0].strip()
        if not line:
            continue
        goal = Goal(line)
        if goal.deaths < 0:
            goal.deaths = 0
            r = leg(level, s, goal)
            if r is None:
                goal.deaths = 1
                r = leg(level, s, goal)
        else:
            r = leg(level, s, goal)
        if r is None:
            print(f"FAILED: {line}  (from screen {s.sx},{s.sy} col {s.col} row {s.row}, "
                  f"items {s.item0:02x} {s.item1:02x}, lives {s.lives})", file=log)
            return None, legs, s
        frames, path, end, evs = r
        scans = expected_scans(level, s, path)
        s = end
        total += frames
        notable = [e for ev in evs for e in ev]
        print(f"{line:40s} {frames:6d} frames, {len(path):3d} keys -> screen ({s.sx},{s.sy}) "
              f"col {s.col} row {s.row}, items {s.item0:02x} {s.item1:02x}, lives {s.lives}, "
              f"terminals {s.tctr}; {', '.join(notable)}", file=log)
        legs.append({"goal": line, "frames": frames, "keys": list(path), "scans": scans,
                     "events": notable,
                     "end": {"screen": [s.sx, s.sy], "col": s.col, "row": s.row,
                             "items": [s.item0, s.item1], "lives": s.lives, "terminals": s.tctr}})
    return total, legs, s


def main():
    plan_file = sys.argv[1]
    out = sys.argv[2] if len(sys.argv) > 2 else None
    lines = open(plan_file).read().splitlines()
    total, legs, s = run_plan(lines)
    if total is None:
        return 1
    print(f"total ~{total} frames (~{total / 50 / 60:.1f} minutes)", file=sys.stderr)
    if out:
        with open(out, "w") as f:
            json.dump({"level": 1, "frames": total, "legs": legs}, f, indent=1)
    return 0


if __name__ == "__main__":
    sys.exit(main())

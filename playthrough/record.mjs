#!/usr/bin/env node
// Play a planned route (plan.py's JSON) on an emulated BBC Micro and record
// the key presses that do it as a key log.
//
//   node record.mjs <disc.ssd> <labels> <route.json> <out.keys>
//
// The planner says which keys to hold at each visit to scan_keys; this
// works out when to press and release them. Keys only ever change at the
// start of the vsync interrupt, and only once the game has finished with
// the previous ones: a hop reads '/' a frame after it starts, and f0/f1
// wait for the key to be let go before acting. At every scan_keys the frog
// is checked against where the planner expected it, so a model that has
// drifted from the real game stops the recording at once.
//
// Labels and machine state are read only to decide timing and to check;
// nothing is ever written to the emulated machine except key presses.

import { ACTION_KEYS, LoggedKeyboard, frogState, loadLabels, newMachine, writeLog } from "./beeb.mjs";
import { readFileSync, writeFileSync } from "fs";

const [disc, labelsPath, routePath, outPath] = process.argv.slice(2);
if (!outPath) {
    console.error("usage: record.mjs <disc.ssd> <labels> <route.json> <out.keys>");
    process.exit(2);
}

const BOOT_SHIFT_CYCLES = 1_600_000; // SHIFT held for 0.8s from power-on: SHIFT+BREAK
const CYCLES_PER_FRAME = 40_000;
const TAIL_FRAMES = 250; // let the last action play out (LOGGED ON shows for 100 frames)
const BOOT_MARGIN_FRAMES = 100;
// wait_escape_release spins on the key with no vsync in between, so when
// ESCAPE goes up decides which frame the death starts in. Let go mid-frame,
// well clear of both vsyncs, rather than at one.
const ESCAPE_HOLD_CYCLES = 12_000;

const L = loadLabels(labelsPath);
const route = JSON.parse(readFileSync(routePath, "utf8"));
const scans = route.legs.flatMap((leg) => leg.scans);
const actions = scans.map((s) => s.key);

const session = await newMachine(disc);
const cpu = session._machine.processor;
const kb = new LoggedKeyboard(session);

function fail(message, extra = {}) {
    const state = frogState(session);
    console.error(`FAILED at scan ${j}/${scans.length} (cycle ${session.elapsedCycles}): ${message}`);
    console.error("  machine:", JSON.stringify(state));
    console.error("  details:", JSON.stringify(extra));
    writeFileSync(outPath + ".fb", session._completeFb8);
    writeLog(outPath, events, session.elapsedCycles, ["FAILED recording: " + message]);
    process.exit(1);
}

// --- Boot: SHIFT+BREAK from power-on, then choose level 1 ---
if (session.elapsedCycles !== 0) throw new Error("machine has already run");
kb.set(["SHIFT"]);
await session.runFor(BOOT_SHIFT_CYCLES);
kb.set([]);
for (let i = 0; ; i++) {
    await session.runFrames(5);
    const text = session
        .drainOutput()
        .elements.map((e) => e.text)
        .join("");
    if (text.includes("Choose level")) break;
    if (i > 400) throw new Error("never saw the level prompt");
}
await session.runFrames(10);
kb.set(["1"]);
await session.runFrames(25);
kb.set([]);
// The title picture waits for SPACE by writing its key number (&62) to the
// System VIA's port A and reading the key's state back.
let pollingSpace = false;
const spaceWatch = cpu.debugWrite.add((addr, value) => {
    if (addr === 0xfe4f && value === 0x62) pollingSpace = true;
    return false;
});
for (let i = 0; !pollingSpace; i++) {
    await session.runFrames(1);
    if (i > 3000) throw new Error("never saw the title screen wait for SPACE");
}
spaceWatch.remove();
// Generous margins from here to the start of the game, so that another
// emulator whose disc loads a little faster or slower is waiting for each
// key when it comes, and starts the game at the same moment.
await session.runFrames(BOOT_MARGIN_FRAMES);
kb.set(["SPACE"]);
await session.runFrames(BOOT_MARGIN_FRAMES);
kb.set([]);
await session.runUntilAddress(L.wait_space, 120);
await session.runFrames(BOOT_MARGIN_FRAMES);
kb.set(["SPACE"]);
const gameStart = session.elapsedCycles;

// --- The game ---
let j = 0; // next planned scan_keys visit
let prev = "none"; // the action under way
let slashPending = false; // a hop that hasn't read '/' yet
let fPending = false; // f0/f1 waiting for its key to be let go
let escape = 0; // 1: ESCAPE held; 2: the game saw it and waits for release; 3: released
let escapeSeen = 0;
let spaceHeld = true;
let done = false;
let doneCycle = 0;
const watch = new Map();

function desired() {
    if (escape === 1 || escape === 2) return ["ESCAPE"];
    if (escape === 3 || j >= actions.length) return [];
    if (slashPending) return ACTION_KEYS[prev];
    const next = actions[j];
    if (next === "escape") {
        escape = 1;
        return ["ESCAPE"];
    }
    let keys = ACTION_KEYS[next];
    if (fPending) keys = keys.filter((k) => !ACTION_KEYS[prev].includes(k));
    return keys;
}

function matches(exp, st) {
    return (
        exp.col === st.col &&
        exp.row === st.row &&
        exp.sx === st.sx &&
        exp.sy === st.sy &&
        exp.dir === st.dir &&
        exp.items[0] === st.item0 &&
        exp.items[1] === st.item1 &&
        exp.lives === st.lives &&
        exp.terminals === st.terminals
    );
}

function onScan() {
    if (spaceHeld || escape || done) return;
    const exp = scans[j];
    const st = frogState(session);
    const want = ACTION_KEYS[exp.key];
    if (!matches(exp, st)) fail("frog not where the plan expected", { expected: exp, held: [...kb.held] });
    if (kb.sameAs(want)) {
        prev = exp.key;
        j++;
        slashPending = prev.startsWith("right") || prev.startsWith("left");
        fPending = prev === "f0" || prev === "f1";
        if (j === actions.length) {
            done = true;
            doneCycle = session.elapsedCycles;
        }
    } else if (!(kb.held.size === 0 && exp.idle_ok)) {
        fail("wrong keys held at scan_keys", { expected: exp, held: [...kb.held] });
    }
}

watch.set(L.irq_handler, () => {
    if (spaceHeld) return;
    if (!kb.sameAs(desired())) kb.set(desired());
});
// Every keyboard read in the game goes through read_key, with the key
// number in A: log them all, to move each key change to the middle of the
// window in which nothing reads that key.
const KEY_NUMBERS = { 0x42: "X", 0x61: "Z", 0x48: "COLON", 0x68: "SLASH", 0x20: "F0", 0x71: "F1", 0x70: "ESCAPE", 0x62: "SPACE" };
const reads = Object.fromEntries(Object.values(KEY_NUMBERS).map((k) => [k, []]));
watch.set(L.scan_keys, onScan);
watch.set(L.wait_for_space_done, () => {
    spaceHeld = false;
});
for (const name of ["hop_right.stop", "hop_left.stop", "hop_right.short_hop_right", "hop_left.short_hop_left"])
    watch.set(L[name], () => (slashPending = false));
watch.set(L.read_key, () => {
    if (cpu.a === 0x68) slashPending = false;
    if (escape === 2 && cpu.a === 0x70 && session.elapsedCycles - escapeSeen >= ESCAPE_HOLD_CYCLES) {
        kb.set([]);
        escape = 3;
    }
    const key = KEY_NUMBERS[cpu.a];
    if (key) reads[key].push(session.elapsedCycles);
});
watch.set(L.use_item_slot, () => (fPending = false));
watch.set(L.wait_escape_release, () => {
    if (escape === 1) {
        escape = 2;
        escapeSeen = session.elapsedCycles;
    }
});
watch.set(L.handle_death, () => {
    if (escape === 3) {
        escape = 0;
        prev = "escape";
        j++;
        if (j === actions.length) {
            done = true;
            doneCycle = session.elapsedCycles;
        }
    }
});

const hook = cpu.debugInstruction.add((pc) => {
    const f = watch.get(pc);
    if (f) f();
    return false;
});

let lastReport = 0;
while (!done || session.elapsedCycles < doneCycle + TAIL_FRAMES * CYCLES_PER_FRAME) {
    await session.runFor(10 * CYCLES_PER_FRAME);
    if (j - lastReport >= 100) {
        console.error(`  ${j}/${actions.length} scans, ${(session.elapsedCycles / 2e6).toFixed(0)}s emulated`);
        lastReport = j;
    }
    if (session.elapsedCycles > 4 * 3600 * 2e6) fail("ran for four emulated hours");
}
hook.remove();

// The game only sees a key when read_key reads it, so a change can happen
// anywhere between the last read of the old state and the first read of
// the new one without making any difference here. Put it in the middle of
// that window, which leaves the most room for an emulator whose frames
// fall at slightly different moments. A press and release with no read in
// between is invisible, and goes.
function firstAtOrAfter(list, cycle) {
    let lo = 0;
    let hi = list.length;
    while (lo < hi) {
        const mid = (lo + hi) >> 1;
        if (list[mid] < cycle) lo = mid + 1;
        else hi = mid;
    }
    return lo;
}
const boot = kb.events.filter((e) => e.cycle < gameStart || !(e.key in reads));
const game = kb.events.filter((e) => e.cycle >= gameStart && e.key in reads);
const moved = [];
for (const key of Object.keys(reads)) {
    const list = reads[key];
    const evs = game.filter((e) => e.key === key);
    for (let i = 0; i < evs.length; i++) {
        const e = evs[i];
        const n = firstAtOrAfter(list, e.cycle);
        const next = list[n];
        if (i + 1 < evs.length && (next === undefined || evs[i + 1].cycle <= next)) {
            i++; // pressed and let go unseen
            continue;
        }
        const prevRead = n > 0 ? list[n - 1] : undefined;
        const cycle = prevRead === undefined || next === undefined ? e.cycle : Math.floor((prevRead + next) / 2);
        moved.push({ ...e, cycle: Math.max(cycle, gameStart) });
    }
}
const events = [...boot, ...moved].sort((a, b) => a.cycle - b.cycle);

const st = frogState(session);
writeLog(outPath, events, session.elapsedCycles, [
    "FROGMAN key log, recorded by playthrough/record.mjs",
    `machine: ${session.modelName}, disc: ${disc.split("/").pop()}, from power-on`,
    `route: ${routePath.split("/").pop()}, ${actions.length} moves`,
    `final state: ${JSON.stringify(st)}`,
    "format: <2MHz cycles since power-on> <key> <down|up>",
    "each key changes midway between the game's reads of it, for slack",
]);
console.error(
    `recorded ${events.length} key events over ${(session.elapsedCycles / 2e6 / 60).toFixed(1)} emulated minutes; ` +
        `final ${JSON.stringify(st)}`,
);

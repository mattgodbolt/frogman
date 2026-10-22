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
    writeLog(outPath, kb.events, session.elapsedCycles, ["FAILED recording: " + message]);
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
kb.set(["1"]);
await session.runFrames(5);
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
kb.set(["SPACE"]);
await session.runFrames(10);
kb.set([]);
await session.runUntilAddress(L.wait_space, 120);
kb.set(["SPACE"]);

// --- The game ---
let j = 0; // next planned scan_keys visit
let prev = "none"; // the action under way
let slashPending = false; // a hop that hasn't read '/' yet
let fPending = false; // f0/f1 waiting for its key to be let go
let escape = 0; // 1: ESCAPE held; 2: the game saw it and waits for release
let spaceHeld = true;
let done = false;
let doneCycle = 0;
const watch = new Map();

function desired() {
    if (escape === 1) return ["ESCAPE"];
    if (escape === 2 || j >= actions.length) return [];
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
watch.set(L.scan_keys, onScan);
watch.set(L.wait_for_space_done, () => {
    spaceHeld = false;
    kb.set([]);
});
for (const name of ["hop_right.stop", "hop_left.stop", "hop_right.short_hop_right", "hop_left.short_hop_left"])
    watch.set(L[name], () => (slashPending = false));
watch.set(L.read_key, () => {
    if (cpu.a === 0x68) slashPending = false;
});
watch.set(L.use_item_slot, () => (fPending = false));
watch.set(L.wait_escape_release, () => {
    if (escape === 1) escape = 2;
});
watch.set(L.handle_death, () => {
    if (escape === 2) {
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

const st = frogState(session);
writeLog(outPath, kb.events, session.elapsedCycles, [
    "FROGMAN key log, recorded by playthrough/record.mjs",
    `machine: ${session.modelName}, disc: ${disc.split("/").pop()}, from power-on`,
    `route: ${routePath.split("/").pop()}, ${actions.length} moves`,
    `final state: ${JSON.stringify(st)}`,
    "format: <2MHz cycles since power-on> <key> <down|up>",
]);
console.error(
    `recorded ${kb.events.length} key events over ${(session.elapsedCycles / 2e6 / 60).toFixed(1)} emulated minutes; ` +
        `final ${JSON.stringify(st)}`,
);

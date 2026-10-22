// Shared bits for recording and replaying FROGMAN key logs in jsbeeb.
//
// A key log is plain text: one key event per line,
//   <2MHz cycles since power-on> <KEY> <down|up>
// with '#' comments, ending in "<cycles> END". The machine starts powered
// off with no keys down, and the log holds every key - including the SHIFT
// of SHIFT+BREAK - so nothing else is needed to reproduce a run. Cycles
// are the unit beebjit's capture files count in, so a log converts to a
// beebjit -replay file one event per record (see beebjit.mjs).

import { readFileSync, writeFileSync } from "fs";
import { MachineSession } from "jsbeeb/machine-session";

export const MODEL = "B-DFS1.2";

// [column, row] in the BBC keyboard matrix (jsbeeb's keyDownRaw), and the
// code beebjit uses for the same physical key in its capture files.
export const KEYS = {
    SHIFT: { matrix: [0, 0], beebjit: 133 },
    ESCAPE: { matrix: [0, 7], beebjit: 128 },
    F0: { matrix: [0, 2], beebjit: 136 },
    F1: { matrix: [1, 7], beebjit: 137 },
    X: { matrix: [2, 4], beebjit: "X".charCodeAt(0) },
    Z: { matrix: [1, 6], beebjit: "Z".charCodeAt(0) },
    COLON: { matrix: [8, 4], beebjit: "'".charCodeAt(0) }, // beebjit maps host ' to BBC :
    SLASH: { matrix: [8, 6], beebjit: "/".charCodeAt(0) },
    SPACE: { matrix: [2, 6], beebjit: " ".charCodeAt(0) },
    1: { matrix: [0, 3], beebjit: "1".charCodeAt(0) },
};

// The planner's action names (frogsim.py) and the keys each one holds.
export const ACTION_KEYS = {
    none: [],
    right: ["X"],
    right_short: ["X", "SLASH"],
    left: ["Z"],
    left_short: ["Z", "SLASH"],
    up: ["COLON"],
    f0: ["F0"],
    f1: ["F1"],
    escape: ["ESCAPE"],
};

// Zero page locations (zero_page.asm).
export const ZP = {
    item0: 0x08,
    item1: 0x09,
    col: 0x11,
    row: 0x12,
    sx: 0x13,
    sy: 0x14,
    dir: 0x19,
    gameState: 0x20,
    terminals: 0x22,
    lives: 0x24,
};

/** Read the labels beebasm writes with -dd -labels: {'.name':123L, '.scope.local':456L, ...}. */
export function loadLabels(path) {
    const labels = {};
    for (const m of readFileSync(path, "utf8").matchAll(/'([^']+)':(\d+)L/g)) labels[m[1].replace(/^\./, "")] = +m[2];
    return labels;
}

export async function newMachine(disc) {
    const session = new MachineSession(MODEL, { discImage: disc });
    await session.initialise();
    return session;
}

/** A keyboard whose every change is logged against the machine's cycle count. */
export class LoggedKeyboard {
    constructor(session) {
        this.session = session;
        this.held = new Set();
        this.events = [];
    }

    set(names) {
        const want = new Set(names);
        const now = this.session.elapsedCycles;
        for (const k of [...this.held]) {
            if (!want.has(k)) {
                this.session.keyUpRaw(KEYS[k].matrix);
                this.held.delete(k);
                this.events.push({ cycle: now, key: k, down: false });
            }
        }
        for (const k of want) {
            if (!this.held.has(k)) {
                this.session.keyDownRaw(KEYS[k].matrix);
                this.held.add(k);
                this.events.push({ cycle: now, key: k, down: true });
            }
        }
    }

    sameAs(names) {
        return names.length === this.held.size && names.every((k) => this.held.has(k));
    }
}

export function writeLog(path, events, endCycle, header) {
    const lines = header.map((h) => `# ${h}`);
    for (const e of events) lines.push(`${e.cycle} ${e.key} ${e.down ? "down" : "up"}`);
    lines.push(`${endCycle} END`);
    writeFileSync(path, lines.join("\n") + "\n");
}

export function readLog(path) {
    const events = [];
    let end = null;
    for (const raw of readFileSync(path, "utf8").split("\n")) {
        const line = raw.replace(/#.*/, "").trim();
        if (!line) continue;
        const [cycle, key, dir] = line.split(/\s+/);
        if (key === "END") {
            end = +cycle;
            continue;
        }
        if (!(key in KEYS) || !["down", "up"].includes(dir)) throw new Error(`bad log line: ${raw}`);
        events.push({ cycle: +cycle, key, down: dir === "down" });
    }
    if (end === null) throw new Error(`${path} has no END line`);
    return { events, end };
}

export function frogState(session) {
    const zp = session.readMemory(0, 0x30);
    const out = {};
    for (const [name, addr] of Object.entries(ZP)) out[name] = zp[addr];
    return out;
}

/** The framebuffer as raw RGBA, 1024x625. */
export function frameBuffer(session) {
    return session._completeFb8;
}

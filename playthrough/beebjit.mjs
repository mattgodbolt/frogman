#!/usr/bin/env node
// Convert between our text key logs and beebjit's keyboard capture files.
//
//   node beebjit.mjs to-capture <log.keys> <out.cap>
//   node beebjit.mjs from-capture <in.cap> <out.keys>
//
// beebjit records with -capture <file> and plays back with -replay <file>.
// A capture is a 32-byte header ("beebjit-capture", NUL padded, with the
// writing version at offset 16) followed by one record per instant that
// keys changed: u64 timer ticks (2MHz cycles since power-on, little endian),
// u8 key count, that many beebjit key codes, then that many is-down bytes.
// Both emulators count the same 2MHz cycles, so the conversion is exact;
// whether the game then behaves identically is down to the emulators
// agreeing cycle for cycle.

import { readFileSync, writeFileSync } from "fs";
import { KEYS, readLog, writeLog } from "./beeb.mjs";

const HEADER = "beebjit-capture";
const HEADER_SIZE = 32;
const VERSION_OFFSET = 16;
const VERSION = "0.9.9";

function toCapture(logPath, outPath) {
    const { events } = readLog(logPath);
    const chunks = [];
    const header = Buffer.alloc(HEADER_SIZE);
    header.write(HEADER, 0, "latin1");
    header.write(VERSION, VERSION_OFFSET, "latin1");
    chunks.push(header);
    for (let i = 0; i < events.length; ) {
        const cycle = events[i].cycle;
        const group = [];
        for (; i < events.length && events[i].cycle === cycle; i++) group.push(events[i]);
        const rec = Buffer.alloc(9 + 2 * group.length);
        rec.writeBigUInt64LE(BigInt(cycle), 0);
        rec.writeUInt8(group.length, 8);
        group.forEach((e, n) => {
            rec.writeUInt8(KEYS[e.key].beebjit, 9 + n);
            rec.writeUInt8(e.down ? 1 : 0, 9 + group.length + n);
        });
        chunks.push(rec);
    }
    writeFileSync(outPath, Buffer.concat(chunks));
}

function fromCapture(capPath, outPath) {
    const buf = readFileSync(capPath);
    if (buf.toString("latin1", 0, HEADER.length) !== HEADER) throw new Error(`${capPath}: not a beebjit capture`);
    const version = buf.toString("latin1", VERSION_OFFSET, HEADER_SIZE).replace(/\0.*$/, "");
    const byCode = new Map(Object.entries(KEYS).map(([name, k]) => [k.beebjit, name]));
    const events = [];
    let pos = HEADER_SIZE;
    while (pos < buf.length) {
        const cycle = Number(buf.readBigUInt64LE(pos));
        const n = buf.readUInt8(pos + 8);
        for (let i = 0; i < n; i++) {
            const code = buf.readUInt8(pos + 9 + i);
            const name = byCode.get(code);
            if (!name) throw new Error(`beebjit key code ${code} isn't one FROGMAN uses`);
            events.push({ cycle, key: name, down: buf.readUInt8(pos + 9 + n + i) === 1 });
        }
        pos += 9 + 2 * n;
    }
    const end = events.length ? events[events.length - 1].cycle : 0;
    writeLog(outPath, events, end, [`converted from beebjit ${version} capture ${capPath.split("/").pop()}`]);
}

const [mode, from, to] = process.argv.slice(2);
if (mode === "to-capture") toCapture(from, to);
else if (mode === "from-capture") fromCapture(from, to);
else {
    console.error("usage: beebjit.mjs to-capture <log.keys> <out.cap> | from-capture <in.cap> <out.keys>");
    process.exit(2);
}

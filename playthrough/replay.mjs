#!/usr/bin/env node
// Replay a key log from power-on and report how the game ended up.
//
//   node replay.mjs <disc.ssd> <log.keys> [--expect-logon] [--video out.mp4] [--frames N]
//                   [--trace <labels> <out.txt>]
//
// Nothing but the logged key presses reaches the machine. --expect-logon
// exits non-zero unless the power terminal has said LOGGED ON (that leaves
// zp_terminal_ctr at &FF). --video pipes every frame to ffmpeg (no sound:
// jsbeeb runs headless without audio). --frames N stops early. --trace
// writes the frog's state at every scan_keys, for comparing emulators.

import { spawn } from "child_process";
import { writeFileSync } from "fs";
import { KEYS, frogState, loadLabels, newMachine, readLog } from "./beeb.mjs";

const args = process.argv.slice(2);
const [disc, logPath] = args;
const expectLogon = args.includes("--expect-logon");
const videoAt = args.indexOf("--video");
const video = videoAt >= 0 ? args[videoAt + 1] : null;
const framesAt = args.indexOf("--frames");
const maxFrames = framesAt >= 0 ? +args[framesAt + 1] : Infinity;

const traceAt = args.indexOf("--trace");

const { events, end } = readLog(logPath);
const session = await newMachine(disc);

const trace = [];
if (traceAt >= 0) {
    const scanKeys = loadLabels(args[traceAt + 1]).scan_keys;
    session._machine.processor.debugInstruction.add((pc) => {
        if (pc === scanKeys) {
            const st = frogState(session);
            trace.push(`${session.elapsedCycles} ${Object.values(st).join(" ")}`);
        }
        return false;
    });
}

let ffmpeg = null;
if (video) {
    // Crop the 1024x625 framebuffer to the game's display (512x318 at
    // 264,160) plus a small border, and double it.
    ffmpeg = spawn(
        "ffmpeg",
        ["-loglevel", "error", "-y", "-f", "rawvideo", "-pix_fmt", "rgba", "-s", "1024x625", "-r", "50", "-i", "-",
            "-vf", "crop=544:336:248:152,scale=1088:672:flags=neighbor", "-pix_fmt", "yuv420p", "-c:v", "libx264",
            "-crf", "18", video],
        { stdio: ["pipe", "inherit", "inherit"] },
    );
}

async function writeFrame() {
    if (!ffmpeg) return;
    if (!ffmpeg.stdin.write(Buffer.from(session._completeFb8))) await new Promise((r) => ffmpeg.stdin.once("drain", r));
}

// Run to each key event in turn, a frame at a time when recording video.
let next = 0;
async function runTo(cycle) {
    while (session.elapsedCycles < cycle) {
        if (ffmpeg) {
            const before = session.frameCount;
            const { completed } = await session.runFrames(1, { maxCycles: cycle - session.elapsedCycles });
            if (session.frameCount !== before) await writeFrame();
            if (!completed && session.elapsedCycles >= cycle) break;
        } else {
            await session.runFor(cycle - session.elapsedCycles);
        }
        if (session.frameCount >= maxFrames) return false;
    }
    return true;
}

let stopped = false;
while (next < events.length) {
    if (!(await runTo(events[next].cycle))) {
        stopped = true;
        break;
    }
    // A key changes at the first instruction boundary at or after its cycle.
    if (session.elapsedCycles - events[next].cycle > 16)
        throw new Error(`overshot event ${next}: at ${session.elapsedCycles}, wanted ${events[next].cycle}`);
    for (; next < events.length && events[next].cycle <= session.elapsedCycles; next++) {
        const e = events[next];
        if (e.down) session.keyDownRaw(KEYS[e.key].matrix);
        else session.keyUpRaw(KEYS[e.key].matrix);
    }
}
if (!stopped) await runTo(end);

if (ffmpeg) {
    ffmpeg.stdin.end();
    await new Promise((r) => ffmpeg.on("close", r));
}

if (traceAt >= 0) writeFileSync(args[traceAt + 2], trace.join("\n") + "\n");

const st = frogState(session);
const loggedOn = st.terminals === 0xff;
console.log(
    `replayed ${next}/${events.length} key events, ${(session.elapsedCycles / 2e6 / 60).toFixed(2)} emulated minutes; ` +
        `final ${JSON.stringify(st)}${loggedOn ? " - LOGGED ON" : ""}`,
);
if (expectLogon && !loggedOn) {
    console.error("expected the power terminal to have logged on");
    process.exit(1);
}

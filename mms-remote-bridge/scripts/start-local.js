#!/usr/bin/env node
// FILE: start-local.js
// Purpose: Makes `npm start` in a source checkout use the local relay launcher.
// Layer: developer utility
// Exports: none
// Depends on: child_process, fs, path

const { spawn } = require("child_process");
const fs = require("fs");
const path = require("path");

const bridgeDir = path.resolve(__dirname, "..");
const sourceLauncher = path.resolve(bridgeDir, "..", "run-local-mms-remote.sh");
const args = process.argv.slice(2);
const hasSourceLauncher = fs.existsSync(sourceLauncher);

const command = hasSourceLauncher ? sourceLauncher : process.execPath;
const commandArgs = hasSourceLauncher
  ? args
  : [path.join(bridgeDir, "bin", "mms-remote.js"), "up", ...args];
const cwd = hasSourceLauncher ? path.dirname(sourceLauncher) : bridgeDir;

const child = spawn(command, commandArgs, {
  cwd,
  env: process.env,
  stdio: "inherit",
});

child.on("error", (error) => {
  console.error(`[mms-remote] Failed to start local bridge: ${error.message}`);
  process.exit(1);
});

child.on("exit", (code, signal) => {
  if (signal) {
    console.error(`[mms-remote] Local bridge stopped by ${signal}`);
    process.exit(1);
  }
  process.exit(code ?? 0);
});

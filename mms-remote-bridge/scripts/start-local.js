#!/usr/bin/env node
// FILE: start-local.js
// Purpose: Makes `npm start` in a source checkout use the local relay launcher.
// Layer: developer utility
// Exports: none
// Depends on: child_process, fs, path

const { spawn } = require("child_process");
const fs = require("fs");
const os = require("os");
const path = require("path");

const bridgeDir = path.resolve(__dirname, "..");
const sourceLauncher = path.resolve(bridgeDir, "..", "run-local-mms-remote.sh");
const args = process.argv.slice(2);
const hasSourceLauncher = fs.existsSync(sourceLauncher);

function readSavedRelayUrls() {
  const stateDir =
    process.env.MMS_REMOTE_DEVICE_STATE_DIR ||
    path.join(os.homedir(), ".mms-remote");
  const configPath =
    process.env.MMS_REMOTE_CONFIG_PATH ||
    path.join(stateDir, "daemon-config.json");

  try {
    const config = JSON.parse(fs.readFileSync(configPath, "utf8"));
    const relayUrls = Array.isArray(config.relayUrls)
      ? config.relayUrls
      : [];
    return Array.from(
      new Set(
        [...relayUrls, config.relayUrl]
          .filter((url) => typeof url === "string")
          .map((url) => url.trim())
          .filter(Boolean)
      )
    );
  } catch {
    return [];
  }
}

function appendSavedRelayArgs(rawArgs) {
  if (!hasSourceLauncher) {
    return rawArgs;
  }

  const existingRelayUrls = new Set();
  for (let index = 0; index < rawArgs.length; index += 1) {
    if (rawArgs[index] === "--relay-url" || rawArgs[index] === "--extra-relay-url") {
      const nextValue = rawArgs[index + 1];
      if (typeof nextValue === "string") {
        existingRelayUrls.add(nextValue);
        index += 1;
      }
    }
  }

  const savedRelayArgs = [];
  for (const relayUrl of readSavedRelayUrls()) {
    if (existingRelayUrls.has(relayUrl)) {
      continue;
    }
    existingRelayUrls.add(relayUrl);
    savedRelayArgs.push("--extra-relay-url", relayUrl);
  }

  return [...rawArgs, ...savedRelayArgs];
}

const command = hasSourceLauncher ? sourceLauncher : process.execPath;
const commandArgs = hasSourceLauncher
  ? appendSavedRelayArgs(args)
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

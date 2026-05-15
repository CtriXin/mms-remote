#!/usr/bin/env node
// FILE: mms-remote.js
// Purpose: CLI surface for foreground bridge runs, pairing reset, thread resume, and macOS service control.
// Layer: CLI binary
// Exports: none
// Depends on: ../src, child_process, path

const { spawnSync } = require("child_process");
const path = require("path");

const {
  createTerminalHub,
  getMacOSBridgeServiceStatus,
  printMacOSBridgePairingQr,
  printMacOSBridgeServiceStatus,
  readBridgeConfig,
  resetMacOSBridgePairing,
  runMacOSBridgeService,
  startBridge,
  startMacOSBridgeService,
  stopMacOSBridgeService,
  resetBridgePairing,
  openLastActiveThread,
  watchThreadRollout,
} = require("../src");
const { version } = require("../package.json");

const defaultDeps = {
  createTerminalHub,
  getMacOSBridgeServiceStatus,
  printMacOSBridgePairingQr,
  printMacOSBridgeServiceStatus,
  readBridgeConfig,
  resetMacOSBridgePairing,
  runMacOSBridgeService,
  startBridge,
  startMacOSBridgeService,
  stopMacOSBridgeService,
  resetBridgePairing,
  openLastActiveThread,
  watchThreadRollout,
  spawnSync,
};
const TERMINAL_SMOKE_READY = "mms_remote_smoke_ready";
const TERMINAL_SMOKE_INPUT = "mms_remote_smoke_input";

if (require.main === module) {
  void main();
}

// ─── ENTRY POINT ─────────────────────────────────────────────

async function main({
  argv = process.argv,
  platform = process.platform,
  consoleImpl = console,
  exitImpl = process.exit,
  deps = defaultDeps,
} = {}) {
  const parsedArgs = parseCliArgs(argv.slice(2));
  const { command, jsonOutput, watchThreadId } = parsedArgs;

  if (isVersionCommand(command)) {
    emitVersion({ jsonOutput, consoleImpl });
    return;
  }

  if (command === "up") {
    if (platform === "darwin") {
      consoleImpl.log("[mms-remote] Starting bridge and pairing QR...");
      const result = await deps.startMacOSBridgeService({
        waitForPairing: true,
      });
      deps.printMacOSBridgePairingQr({
        pairingSession: result.pairingSession,
      });
      return;
    }

    deps.startBridge();
    return;
  }

  if (command === "run") {
    deps.startBridge();
    return;
  }

  if (command === "run-service") {
    deps.runMacOSBridgeService();
    return;
  }

  if (command === "terminal") {
    await runTerminalCliCommand({
      args: parsedArgs,
      deps,
      jsonOutput,
      consoleImpl,
      exitImpl,
    });
    return;
  }

  if (command === "start") {
    assertMacOSCommand(command, {
      platform,
      consoleImpl,
      exitImpl,
    });
    deps.readBridgeConfig();
    const result = await deps.startMacOSBridgeService({
      waitForPairing: false,
    });
    emitResult({
      payload: {
        ok: true,
        currentVersion: version,
        plistPath: result?.plistPath,
        pairingSession: result?.pairingSession,
      },
      message: "[mms-remote] macOS bridge service is running.",
      jsonOutput,
      consoleImpl,
    });
    return;
  }

  if (command === "restart") {
    assertMacOSCommand(command, {
      platform,
      consoleImpl,
      exitImpl,
    });
    deps.readBridgeConfig();
    const result = await deps.startMacOSBridgeService({
      waitForPairing: false,
    });
    emitResult({
      payload: {
        ok: true,
        currentVersion: version,
        plistPath: result?.plistPath,
        pairingSession: result?.pairingSession,
      },
      message: "[mms-remote] macOS bridge service restarted.",
      jsonOutput,
      consoleImpl,
    });
    return;
  }

  if (command === "stop") {
    assertMacOSCommand(command, {
      platform,
      consoleImpl,
      exitImpl,
    });
    deps.stopMacOSBridgeService();
    emitResult({
      payload: {
        ok: true,
        currentVersion: version,
      },
      message: "[mms-remote] macOS bridge service stopped.",
      jsonOutput,
      consoleImpl,
    });
    return;
  }

  if (command === "status") {
    assertMacOSCommand(command, {
      platform,
      consoleImpl,
      exitImpl,
    });
    if (jsonOutput) {
      emitJson({
        ...deps.getMacOSBridgeServiceStatus(),
        currentVersion: version,
      });
      return;
    }
    deps.printMacOSBridgeServiceStatus();
    return;
  }

  if (command === "reset-pairing") {
    try {
      if (platform === "darwin") {
        deps.resetMacOSBridgePairing();
        emitResult({
          payload: {
            ok: true,
            currentVersion: version,
            platform: "darwin",
          },
          message: "[mms-remote] Stopped the macOS bridge service and cleared the saved pairing state. Run `mms-remote up` to pair again.",
          jsonOutput,
          consoleImpl,
        });
      } else {
        deps.resetBridgePairing();
        emitResult({
          payload: {
            ok: true,
            currentVersion: version,
            platform,
          },
          message: "[mms-remote] Cleared the saved pairing state. Run `mms-remote up` to pair again.",
          jsonOutput,
          consoleImpl,
        });
      }
    } catch (error) {
      consoleImpl.error(`[mms-remote] ${(error && error.message) || "Failed to clear the saved pairing state."}`);
      exitImpl(1);
    }
    return;
  }

  if (command === "resume") {
    try {
      const state = deps.openLastActiveThread();
      emitResult({
        payload: {
          ok: true,
          currentVersion: version,
          threadId: state.threadId,
          source: state.source || "unknown",
        },
        message: `[mms-remote] Opened last active thread: ${state.threadId} (${state.source || "unknown"})`,
        jsonOutput,
        consoleImpl,
      });
    } catch (error) {
      consoleImpl.error(`[mms-remote] ${(error && error.message) || "Failed to reopen the last thread."}`);
      exitImpl(1);
    }
    return;
  }

  if (command === "watch") {
    try {
      deps.watchThreadRollout(watchThreadId);
    } catch (error) {
      consoleImpl.error(`[mms-remote] ${(error && error.message) || "Failed to watch the thread rollout."}`);
      exitImpl(1);
    }
    return;
  }

  consoleImpl.error(`Unknown command: ${command}`);
  consoleImpl.error(
    "Usage: mms-remote up | mms-remote run | mms-remote terminal <list|join|create [--open-visible --visible-app auto|ghostty|iterm|terminal]|open|smoke|snapshot|input|key|kill> | "
    + "mms-remote start | mms-remote restart | mms-remote stop | mms-remote status | "
    + "mms-remote reset-pairing | mms-remote resume | mms-remote watch [threadId] | mms-remote --version | "
    + "append --json to start/restart/stop/status/reset-pairing/resume for machine-readable output"
  );
  exitImpl(1);
}

function parseCliArgs(rawArgs) {
  const positionals = [];
  let jsonOutput = false;

  for (const arg of rawArgs) {
    if (arg === "--json") {
      jsonOutput = true;
      continue;
    }

    positionals.push(arg);
  }

  return {
    command: positionals[0] || "up",
    jsonOutput,
    positionals,
    watchThreadId: positionals[1] || "",
  };
}

async function runTerminalCliCommand({
  args,
  deps = defaultDeps,
  jsonOutput = false,
  consoleImpl = console,
  exitImpl = process.exit,
} = {}) {
  const subcommand = args.positionals[1] || "list";
  const terminalArgs = args.positionals.slice(2);
  const hub = deps.createTerminalHub();

  try {
    switch (subcommand) {
      case "list": {
        const result = await hub.list();
        emitTerminalResult({ result, jsonOutput, consoleImpl, formatter: formatTerminalList });
        return;
      }
      case "join": {
        const options = parseTerminalOptions(terminalArgs);
        const result = runTerminalJoin({
          options,
          positionalName: firstTerminalPositional(terminalArgs),
          cwd: options.cwd || process.cwd(),
          spawnSyncImpl: deps.spawnSync || spawnSync,
          stdin: deps.stdin || process.stdin,
          stdout: deps.stdout || process.stdout,
        });
        emitTerminalResult({ result, jsonOutput, consoleImpl, formatter: formatTerminalJoin });
        return;
      }
      case "create": {
        const options = parseTerminalOptions(terminalArgs);
        const result = await hub.create({
          name: options.name,
          cwd: options.cwd || process.cwd(),
          command: options.command,
          cols: parsePositiveInt(options.cols),
          rows: parsePositiveInt(options.rows),
          ...(hasTruthyTerminalOption(options, ["open-visible", "openVisible"]) ? { openVisible: true } : {}),
          ...visibleAppParam(options),
        });
        emitTerminalResult({ result, jsonOutput, consoleImpl, formatter: formatTerminalList });
        return;
      }
      case "smoke": {
        const options = parseTerminalOptions(terminalArgs);
        const result = await runTerminalSmoke({
          hub,
          options,
          cwd: options.cwd || process.cwd(),
        });
        emitTerminalResult({ result, jsonOutput, consoleImpl, formatter: formatTerminalSmoke });
        return;
      }
      case "snapshot": {
        const paneId = terminalArgs[0];
        const result = await hub.snapshot({ paneId });
        if (jsonOutput) {
          emitJson(result);
        } else {
          consoleImpl.log(result.content);
        }
        return;
      }
      case "open": {
        const paneId = terminalArgs[0];
        const options = parseTerminalOptions(terminalArgs.slice(1));
        const result = await hub.openVisible({ paneId, ...visibleAppParam(options) });
        emitTerminalResult({ result, jsonOutput, consoleImpl, formatter: () => "[mms-remote] terminal opened on Mac." });
        return;
      }
      case "input": {
        const paneId = terminalArgs[0];
        const text = terminalArgs.slice(1).join(" ");
        const result = await hub.input({ paneId, input: { kind: "text", text } });
        emitTerminalResult({ result, jsonOutput, consoleImpl, formatter: () => "[mms-remote] terminal input sent." });
        return;
      }
      case "key": {
        const paneId = terminalArgs[0];
        const key = terminalArgs[1];
        const result = await hub.input({ paneId, input: { kind: "key", key } });
        emitTerminalResult({ result, jsonOutput, consoleImpl, formatter: () => "[mms-remote] terminal key sent." });
        return;
      }
      case "kill": {
        const paneId = terminalArgs[0];
        const result = await hub.kill({ paneId });
        emitTerminalResult({ result, jsonOutput, consoleImpl, formatter: () => "[mms-remote] terminal pane closed." });
        return;
      }
      default:
        throw new Error(`Unknown terminal command: ${subcommand}`);
    }
  } catch (error) {
    consoleImpl.error(`[mms-remote] ${(error && error.message) || "Terminal command failed."}`);
    exitImpl(1);
  }
}

function hasTruthyTerminalOption(options, keys) {
  return keys.some((key) => {
    const value = options[key];
    return value === true || value === "true" || value === "1" || value === "yes";
  });
}

function visibleAppParam(options = {}) {
  const visibleApp = options["visible-app"] || options.visibleApp || options["terminal-app"] || options.terminalApp;
  return visibleApp ? { visibleApp } : {};
}

function firstTerminalPositional(args) {
  return args.find((arg) => !arg.startsWith("--")) || "";
}

function runTerminalJoin({
  options = {},
  positionalName = "",
  cwd = process.cwd(),
  spawnSyncImpl = spawnSync,
  stdin = process.stdin,
  stdout = process.stdout,
} = {}) {
  if (!stdin.isTTY || !stdout.isTTY) {
    throw new Error("terminal join must be run from a real interactive terminal, not a command runner");
  }

  const sessionName = normalizeTerminalSessionName(options.name || positionalName || defaultTerminalSessionName(cwd));
  const args = ["new-session", "-A", "-s", sessionName];
  const joinCwd = options.cwd || cwd;
  if (joinCwd) {
    args.push("-c", joinCwd);
  }
  if (options.command) {
    args.push(options.command);
  }

  const child = spawnSyncImpl("tmux", args, {
    cwd: joinCwd || cwd,
    stdio: "inherit",
  });
  if (child.error) {
    throw child.error;
  }
  if (child.status && child.status !== 0) {
    throw new Error(`tmux exited with status ${child.status}`);
  }
  return { ok: true, sessionName, args };
}

function defaultTerminalSessionName(cwd) {
  return path.basename(path.resolve(cwd || process.cwd())) || "mms-terminal";
}

function normalizeTerminalSessionName(value) {
  const normalized = String(value || "")
    .trim()
    .replace(/[^A-Za-z0-9_.-]+/g, "-")
    .replace(/^-+|-+$/g, "")
    .slice(0, 80);
  if (/^[A-Za-z0-9]/.test(normalized)) {
    return normalized;
  }
  return `mms-${Date.now()}`;
}

function parseTerminalOptions(args) {
  const options = {};
  for (let index = 0; index < args.length; index += 1) {
    const arg = args[index];
    if (!arg.startsWith("--")) {
      continue;
    }
    const key = arg.slice(2);
    const value = args[index + 1];
    if (value == null || value.startsWith("--")) {
      options[key] = "true";
      continue;
    }
    options[key] = value;
    index += 1;
  }
  return options;
}

function parsePositiveInt(value) {
  if (value == null) {
    return undefined;
  }
  const parsed = Number.parseInt(value, 10);
  return Number.isInteger(parsed) && parsed > 0 ? parsed : undefined;
}

async function runTerminalSmoke({
  hub,
  options = {},
  cwd = process.cwd(),
} = {}) {
  const sessionName = options.name || `mms-smoke-${process.pid}-${Date.now()}`;
  const keep = hasTruthyTerminalOption(options, ["keep"]);
  const openVisible = hasTruthyTerminalOption(options, ["open-visible", "openVisible"]);
  let pane = null;
  let createdSession = false;

  try {
    const createdList = await hub.create({
      name: sessionName,
      cwd,
      command: `printf '${TERMINAL_SMOKE_READY}\\n'; exec sh`,
      cols: parsePositiveInt(options.cols) || 96,
      rows: parsePositiveInt(options.rows) || 32,
      ...(openVisible ? { openVisible: true } : {}),
      ...visibleAppParam(options),
    });
    createdSession = true;
    pane = findTerminalPane(createdList, sessionName);
    if (!pane) {
      throw new Error("Terminal smoke could not find the created pane.");
    }

    await waitForTerminalContent({
      hub,
      paneId: pane.paneId,
      expected: TERMINAL_SMOKE_READY,
      label: "ready output",
    });
    await hub.input({ paneId: pane.paneId, input: { kind: "text", text: `printf ${TERMINAL_SMOKE_INPUT}` } });
    await hub.input({ paneId: pane.paneId, input: { kind: "key", key: "enter" } });
    await waitForTerminalContent({
      hub,
      paneId: pane.paneId,
      expected: TERMINAL_SMOKE_INPUT,
      label: "input output",
    });

    return {
      ok: true,
      sessionName,
      paneId: pane.paneId,
      ready: true,
      input: true,
      openVisible,
      kept: keep,
    };
  } finally {
    if (createdSession && !keep) {
      await hub.kill({ sessionName }).catch(() => {});
    }
  }
}

async function waitForTerminalContent({
  hub,
  paneId,
  expected,
  label,
  timeoutMs = 5000,
  intervalMs = 100,
} = {}) {
  const deadline = Date.now() + timeoutMs;
  let lastContent = "";
  while (Date.now() < deadline) {
    const snapshot = await hub.snapshot({ paneId });
    lastContent = snapshot.content || "";
    if (lastContent.includes(expected)) {
      return snapshot;
    }
    await new Promise((resolve) => setTimeout(resolve, intervalMs));
  }
  throw new Error(`Terminal smoke timed out waiting for ${label}.`);
}

function findTerminalPane(result, sessionName) {
  const panes = result?.panes || [];
  if (result?.created?.paneId) {
    const createdPane = panes.find((pane) => pane.paneId === result.created.paneId || pane.id === result.created.paneId);
    if (createdPane) {
      return createdPane;
    }
  }
  return panes.find((pane) => pane.sessionName === sessionName) || null;
}

function emitTerminalResult({ result, jsonOutput, consoleImpl, formatter }) {
  if (jsonOutput) {
    emitJson(result);
    return;
  }
  consoleImpl.log(formatter(result));
}

function formatTerminalSmoke(result) {
  return `[mms-remote] terminal smoke passed: ${result.paneId} (${result.sessionName})`;
}

function formatTerminalJoin(result) {
  return `[mms-remote] terminal joined: ${result.sessionName}`;
}

function formatTerminalList(result) {
  const panes = result?.panes || [];
  if (panes.length === 0) {
    return "[mms-remote] No managed tmux panes found.";
  }
  return panes
    .map((pane) => `${pane.paneId} ${pane.paneKey} ${pane.currentCommand || "shell"} ${pane.cwd || ""}`.trim())
    .join("\n");
}

function emitVersion({
  jsonOutput = false,
  consoleImpl = console,
} = {}) {
  if (jsonOutput) {
    emitJson({
      currentVersion: version,
    });
    return;
  }

  consoleImpl.log(version);
}

function emitResult({
  payload,
  message,
  jsonOutput = false,
  consoleImpl = console,
} = {}) {
  if (jsonOutput) {
    emitJson(payload);
    return;
  }

  consoleImpl.log(message);
}

function emitJson(payload) {
  process.stdout.write(`${JSON.stringify(payload, null, 2)}\n`);
}

function assertMacOSCommand(name, {
  platform = process.platform,
  consoleImpl = console,
  exitImpl = process.exit,
} = {}) {
  if (platform === "darwin") {
    return;
  }

  consoleImpl.error(`[mms-remote] \`${name}\` is only available on macOS. Use \`mms-remote up\` or \`mms-remote run\` for the foreground bridge on this OS.`);
  exitImpl(1);
}

function isVersionCommand(value) {
  return value === "-v" || value === "--v" || value === "-V" || value === "--version" || value === "version";
}

module.exports = {
  hasTruthyTerminalOption,
  isVersionCommand,
  main,
  parseTerminalOptions,
  defaultTerminalSessionName,
  normalizeTerminalSessionName,
  runTerminalJoin,
  runTerminalSmoke,
  runTerminalCliCommand,
  visibleAppParam,
};

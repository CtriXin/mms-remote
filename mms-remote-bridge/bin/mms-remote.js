#!/usr/bin/env node
// FILE: mms-remote.js
// Purpose: CLI surface for foreground bridge runs, pairing reset, thread resume, and macOS service control.
// Layer: CLI binary
// Exports: none
// Depends on: ../src

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
};

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
    "Usage: mms-remote up | mms-remote run | mms-remote terminal <list|create [--open-visible]|open|snapshot|input|key|kill> | "
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
      case "create": {
        const options = parseTerminalOptions(terminalArgs);
        const result = await hub.create({
          name: options.name,
          cwd: options.cwd || process.cwd(),
          command: options.command,
          cols: parsePositiveInt(options.cols),
          rows: parsePositiveInt(options.rows),
          ...(hasTruthyTerminalOption(options, ["open-visible", "openVisible"]) ? { openVisible: true } : {}),
        });
        emitTerminalResult({ result, jsonOutput, consoleImpl, formatter: formatTerminalList });
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
        const result = await hub.openVisible({ paneId });
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

function emitTerminalResult({ result, jsonOutput, consoleImpl, formatter }) {
  if (jsonOutput) {
    emitJson(result);
    return;
  }
  consoleImpl.log(formatter(result));
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
  runTerminalCliCommand,
};

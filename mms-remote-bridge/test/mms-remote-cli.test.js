// FILE: mms-remote-cli.test.js
// Purpose: Verifies the public CLI exposes version, service control, and machine-readable status output.
// Layer: Integration-lite test
// Exports: node:test suite
// Depends on: node:test, node:assert/strict, child_process, path, ../package.json, ../bin/mms-remote

const test = require("node:test");
const assert = require("node:assert/strict");
const { execFileSync } = require("child_process");
const path = require("path");
const { version } = require("../package.json");
const { main } = require("../bin/mms-remote");

test("mms-remote --version prints the package version", () => {
  const cliPath = path.join(__dirname, "..", "bin", "mms-remote.js");
  const output = execFileSync(process.execPath, [cliPath, "--version"], {
    encoding: "utf8",
  }).trim();

  assert.equal(output, version);
});

test("mms-remote restart reuses the macOS service start flow", async () => {
  const calls = [];
  const messages = [];

  await main({
    argv: ["node", "mms-remote", "restart"],
    platform: "darwin",
    consoleImpl: {
      log(message) {
        messages.push(message);
      },
      error(message) {
        messages.push(message);
      },
    },
    exitImpl(code) {
      throw new Error(`unexpected exit ${code}`);
    },
    deps: {
      readBridgeConfig() {
        calls.push("read-config");
      },
      async startMacOSBridgeService(options) {
        calls.push(["start-service", options]);
        return {
          plistPath: "/tmp/mms-remote.plist",
          pairingSession: { relay: "ws://127.0.0.1:9000/relay" },
        };
      },
    },
  });

  assert.deepEqual(calls, [
    "read-config",
    ["start-service", { waitForPairing: false }],
  ]);
  assert.deepEqual(messages, [
    "[mms-remote] macOS bridge service restarted.",
  ]);
});

test("mms-remote up shows a startup indicator while waiting for the pairing QR", async () => {
  const calls = [];
  const messages = [];

  await main({
    argv: ["node", "mms-remote", "up"],
    platform: "darwin",
    consoleImpl: {
      log(message) {
        messages.push(message);
      },
      error(message) {
        messages.push(message);
      },
    },
    exitImpl(code) {
      throw new Error(`unexpected exit ${code}`);
    },
    deps: {
      async startMacOSBridgeService(options) {
        calls.push(["start-service", options]);
        return {
          pairingSession: { pairingPayload: { sessionId: "session-up" } },
        };
      },
      printMacOSBridgePairingQr(options) {
        calls.push(["print-qr", options]);
      },
    },
  });

  assert.deepEqual(messages, [
    "[mms-remote] Starting bridge and pairing QR...",
  ]);
  assert.deepEqual(calls, [
    ["start-service", { waitForPairing: true }],
    ["print-qr", { pairingSession: { pairingPayload: { sessionId: "session-up" } } }],
  ]);
});

test("mms-remote status --json exposes daemon metadata for companion apps", async () => {
  const writes = [];
  const originalWrite = process.stdout.write;

  process.stdout.write = (chunk, encoding, callback) => {
    writes.push(String(chunk));
    if (typeof callback === "function") {
      callback();
    }
    return true;
  };

  try {
    await main({
      argv: ["node", "mms-remote", "status", "--json"],
      platform: "darwin",
      consoleImpl: {
        log() {},
        error(message) {
          throw new Error(`unexpected error: ${message}`);
        },
      },
      exitImpl(code) {
        throw new Error(`unexpected exit ${code}`);
      },
      deps: {
        getMacOSBridgeServiceStatus() {
          return {
            daemonConfig: {
              relayUrl: "ws://127.0.0.1:9000/relay",
            },
            bridgeStatus: {
              connectionStatus: "connected",
              pid: 77,
            },
            pairingSession: {
              pairingPayload: {
                relay: "ws://127.0.0.1:9000/relay",
                sessionId: "session-json",
              },
            },
          };
        },
        printMacOSBridgeServiceStatus() {
          throw new Error("status printer should not run for --json");
        },
      },
    });
  } finally {
    process.stdout.write = originalWrite;
  }

  const payload = JSON.parse(writes.join("").trim());
  assert.equal(payload.currentVersion, version);
  assert.equal(payload.daemonConfig?.relayUrl, "ws://127.0.0.1:9000/relay");
  assert.equal(payload.bridgeStatus?.connectionStatus, "connected");
  assert.equal(payload.pairingSession?.pairingPayload?.sessionId, "session-json");
});

test("mms-remote terminal list prints managed panes", async () => {
  const messages = [];

  await main({
    argv: ["node", "mms-remote", "terminal", "list"],
    consoleImpl: {
      log(message) { messages.push(message); },
      error(message) { throw new Error(`unexpected error: ${message}`); },
    },
    exitImpl(code) { throw new Error(`unexpected exit ${code}`); },
    deps: {
      createTerminalHub() {
        return {
          async list() {
            return {
              panes: [
                { paneId: "%1", paneKey: "dev:0.0", currentCommand: "zsh", cwd: "/tmp/dev" },
              ],
            };
          },
        };
      },
    },
  });

  assert.deepEqual(messages, ["%1 dev:0.0 zsh /tmp/dev"]);
});

test("mms-remote terminal create forwards cwd command and dimensions", async () => {
  let capturedParams;

  await main({
    argv: [
      "node",
      "mms-remote",
      "terminal",
      "create",
      "--name",
      "dev",
      "--cwd",
      "/tmp/dev",
      "--command",
      "zsh",
      "--cols",
      "100",
      "--rows",
      "30",
    ],
    consoleImpl: {
      log() {},
      error(message) { throw new Error(`unexpected error: ${message}`); },
    },
    exitImpl(code) { throw new Error(`unexpected exit ${code}`); },
    deps: {
      createTerminalHub() {
        return {
          async create(params) {
            capturedParams = params;
            return { panes: [] };
          },
        };
      },
    },
  });

  assert.deepEqual(capturedParams, {
    name: "dev",
    cwd: "/tmp/dev",
    command: "zsh",
    cols: 100,
    rows: 30,
  });
});

test("mms-remote terminal create forwards visible terminal request", async () => {
  let capturedParams;

  await main({
    argv: [
      "node",
      "mms-remote",
      "terminal",
      "create",
      "--name",
      "dev",
      "--cwd",
      "/tmp/dev",
      "--open-visible",
      "--visible-app",
      "iterm",
    ],
    consoleImpl: {
      log() {},
      error(message) { throw new Error(`unexpected error: ${message}`); },
    },
    exitImpl(code) { throw new Error(`unexpected exit ${code}`); },
    deps: {
      createTerminalHub() {
        return {
          async create(params) {
            capturedParams = params;
            return { panes: [] };
          },
        };
      },
    },
  });

  assert.equal(capturedParams.openVisible, true);
  assert.equal(capturedParams.visibleApp, "iterm");
});

test("mms-remote terminal open forwards the selected pane", async () => {
  let capturedParams;
  const messages = [];

  await main({
    argv: ["node", "mms-remote", "terminal", "open", "%1", "--visible-app", "ghostty"],
    consoleImpl: {
      log(message) { messages.push(message); },
      error(message) { throw new Error(`unexpected error: ${message}`); },
    },
    exitImpl(code) { throw new Error(`unexpected exit ${code}`); },
    deps: {
      createTerminalHub() {
        return {
          async openVisible(params) {
            capturedParams = params;
            return { ok: true, opened: true, paneId: "%1" };
          },
        };
      },
    },
  });

  assert.deepEqual(capturedParams, { paneId: "%1", visibleApp: "ghostty" });
  assert.deepEqual(messages, ["[mms-remote] terminal opened on Mac."]);
});

test("mms-remote terminal smoke validates create input snapshot and cleanup", async () => {
  const calls = [];
  const messages = [];
  let snapshotCount = 0;

  await main({
    argv: ["node", "mms-remote", "terminal", "smoke", "--name", "dev-smoke", "--cwd", "/tmp/dev"],
    consoleImpl: {
      log(message) { messages.push(message); },
      error(message) { throw new Error(`unexpected error: ${message}`); },
    },
    exitImpl(code) { throw new Error(`unexpected exit ${code}`); },
    deps: {
      createTerminalHub() {
        return {
          async create(params) {
            calls.push(["create", params]);
            return {
              created: { sessionName: params.name },
              panes: [{ paneId: "%1", sessionName: params.name }],
            };
          },
          async snapshot(params) {
            calls.push(["snapshot", params]);
            snapshotCount += 1;
            return {
              content: snapshotCount === 1
                ? "mms_remote_smoke_ready"
                : "mms_remote_smoke_ready\nmms_remote_smoke_input",
            };
          },
          async input(params) {
            calls.push(["input", params]);
            return { ok: true };
          },
          async kill(params) {
            calls.push(["kill", params]);
            return { ok: true };
          },
        };
      },
    },
  });

  assert.equal(calls[0][0], "create");
  assert.equal(calls[0][1].name, "dev-smoke");
  assert.equal(calls[0][1].cwd, "/tmp/dev");
  assert.equal(calls[0][1].command.includes("mms_remote_smoke_ready"), true);
  assert.deepEqual(calls.at(-1), ["kill", { sessionName: "dev-smoke" }]);
  assert.deepEqual(messages, ["[mms-remote] terminal smoke passed: %1 (dev-smoke)"]);
});

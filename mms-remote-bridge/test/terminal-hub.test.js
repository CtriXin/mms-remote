// FILE: terminal-hub.test.js
// Purpose: Verifies managed tmux terminal hub operations without iOS.
// Layer: Unit/integration test
// Exports: node:test suite
// Depends on: node:test, node:assert/strict, child_process, fs, os, path, ../src/terminal-hub, ../src/tmux-adapter

const test = require("node:test");
const assert = require("node:assert/strict");
const { execFileSync } = require("child_process");
const fs = require("fs");
const os = require("os");
const path = require("path");
const {
  createTerminalHub,
  handleTerminalMethod,
  handleTerminalRequest,
  syntheticOrdinalPaneIndex,
} = require("../src/terminal-hub");
const { createTmuxAdapter } = require("../src/tmux-adapter");

const hasTmux = (() => {
  try {
    execFileSync("tmux", ["-V"], { stdio: "ignore" });
    return true;
  } catch {
    return false;
  }
})();

function makeHub() {
  const socketName = `mms-remote-test-${process.pid}-${Date.now()}-${Math.random().toString(16).slice(2)}`;
  const adapter = createTmuxAdapter({ socketName, timeoutMs: 3000 });
  return { adapter, hub: createTerminalHub({ adapter }) };
}

async function cleanup(adapter) {
  await adapter.killServer().catch(() => {});
}

async function waitFor(predicate, label) {
  const deadline = Date.now() + 3000;
  let lastValue;
  while (Date.now() < deadline) {
    lastValue = await predicate();
    if (lastValue) {
      return lastValue;
    }
    await new Promise((resolve) => setTimeout(resolve, 50));
  }
  assert.fail(`Timed out waiting for ${label}. Last value: ${JSON.stringify(lastValue)}`);
}

test("terminal hub lists, snapshots, inputs, resizes, and cleans up tmux panes", { skip: !hasTmux }, async () => {
  const { adapter, hub } = makeHub();
  const cwd = fs.mkdtempSync(path.join(os.tmpdir(), "mms-remote-terminal-hub-"));
  const sessionName = `mmsremote${Date.now()}`;

  try {
    const initial = await hub.list();
    assert.deepEqual(initial.panes, []);

    await hub.create({
      name: sessionName,
      cwd,
      cols: 100,
      rows: 30,
      command: "printf 'ready\\n'; exec sh",
    });
    const createdResult = await hub.create({
      name: `${sessionName}b`,
      cwd,
      command: "printf 'ready_b\\n'; exec sh",
    });
    assert.match(createdResult.created.paneId, /^%\d+$/);
    assert.equal(createdResult.selectedPane.paneId, createdResult.created.paneId);
    await hub.kill({ sessionName: `${sessionName}b` });

    const pane = await waitFor(async () => {
      const list = await hub.list();
      return list.panes.find((candidate) => candidate.sessionName === sessionName);
    }, "created tmux pane");

    assert.equal(pane.cwd, fs.realpathSync(cwd));
    assert.match(pane.paneKey, new RegExp(`^${sessionName}:0\\.0$`));

    const readySnapshot = await waitFor(async () => {
      const result = await hub.snapshot({ paneId: pane.paneId });
      return result.content.includes("ready") ? result : null;
    }, "initial pane output");
    assert.equal(readySnapshot.pane.paneId, pane.paneId);

    await hub.input({ paneId: pane.paneId, input: { kind: "text", text: "printf mms_input_ok" } });
    await hub.input({ paneId: pane.paneId, input: { kind: "key", key: "enter" } });

    await waitFor(async () => {
      const result = await hub.snapshot({ paneId: pane.paneId });
      return result.content.includes("mms_input_ok") ? result : null;
    }, "input output");

    const resized = await hub.resize({ paneId: pane.paneId, cols: 90, rows: 20 });
    assert.equal(resized.ok, true);

    const resizedPane = await waitFor(async () => {
      const list = await hub.list();
      return list.panes.find((candidate) => candidate.paneId === pane.paneId && candidate.cols === 90 && candidate.rows === 20);
    }, "resized pane dimensions");
    assert.equal(resizedPane.rows, 20);

    await hub.create({ kind: "split", target: pane.paneId, cwd, command: "printf 'second\\n'; exec sh" });
    const panesAfterSplit = await waitFor(async () => {
      const list = await hub.list();
      return list.panes.filter((candidate) => candidate.sessionName === sessionName).length === 2 ? list.panes : null;
    }, "split pane");
    assert.equal(panesAfterSplit.filter((candidate) => candidate.sessionName === sessionName).length, 2);

    await hub.kill({ sessionName });
    await waitFor(async () => {
      const list = await hub.list();
      return list.panes.every((candidate) => candidate.sessionName !== sessionName) ? true : null;
    }, "session cleanup");
  } finally {
    await cleanup(adapter);
  }
});

test("handleTerminalMethod dispatches terminal/list", { skip: !hasTmux }, async () => {
  const { adapter, hub } = makeHub();
  try {
    const result = await handleTerminalMethod("terminal/list", {}, { hub });
    assert.equal(Array.isArray(result.sessions), true);
    assert.equal(Array.isArray(result.windows), true);
    assert.equal(Array.isArray(result.panes), true);
  } finally {
    await cleanup(adapter);
  }
});

test("tmux adapter maps SwiftTerm special byte input to tmux keys", async () => {
  const calls = [];
  const adapter = createTmuxAdapter({
    execFile(file, args, options, callback) {
      calls.push({ file, args, options });
      callback(null, "", "");
    },
  });

  await adapter.sendInput({
    paneId: "%1",
    input: {
      kind: "bytes",
      base64: Buffer.from("\u001b[D").toString("base64"),
    },
  });

  assert.equal(calls[0].file, "tmux");
  assert.deepEqual(calls[0].args, ["send-keys", "-t", "%1", "Left"]);
});

test("tmux adapter maps Mac-style shortcut keys to tmux keys", async () => {
  const calls = [];
  const adapter = createTmuxAdapter({
    execFile(file, args, options, callback) {
      calls.push({ file, args, options });
      callback(null, "", "");
    },
  });

  await adapter.sendInput({ paneId: "%1", input: { kind: "key", key: "option-left" } });
  await adapter.sendInput({ paneId: "%1", input: { kind: "key", key: "option-right" } });
  await adapter.sendInput({ paneId: "%1", input: { kind: "key", key: "shift-tab" } });
  await adapter.sendInput({ paneId: "%1", input: { kind: "key", key: "ctrl-r" } });
  await adapter.sendInput({ paneId: "%1", input: { kind: "key", key: "f12" } });
  await adapter.sendInput({ paneId: "%1", input: { kind: "key", key: "command-control-=" } });
  await adapter.sendInput({ paneId: "%1", input: { kind: "key", key: "control-option-delete" } });
  await adapter.sendInput({ paneId: "%1", input: { kind: "key", key: "command-control-a" } });
  await adapter.sendInput({ paneId: "%1", input: { kind: "key", key: "command-shift-1" } });
  await adapter.sendInput({ paneId: "%1", input: { kind: "key", key: "control-option-9" } });

  assert.deepEqual(calls.map((call) => call.args), [
    ["send-keys", "-t", "%1", "M-b"],
    ["send-keys", "-t", "%1", "M-f"],
    ["send-keys", "-t", "%1", "BTab"],
    ["send-keys", "-t", "%1", "C-r"],
    ["send-keys", "-t", "%1", "F12"],
    ["send-keys", "-t", "%1", "C-M-="],
    ["send-keys", "-t", "%1", "C-M-DC"],
    ["send-keys", "-t", "%1", "C-M-a"],
    ["send-keys", "-t", "%1", "M-S-1"],
    ["send-keys", "-t", "%1", "C-M-9"],
  ]);
});

test("tmux adapter captures only the visible viewport for SwiftTerm snapshots", async () => {
  const calls = [];
  const adapter = createTmuxAdapter({
    execFile(file, args, options, callback) {
      calls.push({ file, args, options });
      callback(null, "visible\n", "");
    },
  });

  const result = await adapter.capturePane({
    target: "%1",
    viewportOnly: true,
    preserveAnsi: true,
    joinWrapped: false,
  });

  assert.equal(result.content, "visible");
  assert.deepEqual(calls[0].args, ["capture-pane", "-t", "%1", "-p", "-e"]);
});

test("tmux adapter can capture the full pane history", async () => {
  const calls = [];
  const adapter = createTmuxAdapter({
    execFile(file, args, options, callback) {
      calls.push({ file, args, options });
      callback(null, "full history\n", "");
    },
  });

  const result = await adapter.capturePane({
    target: "%1",
    start: "-",
    end: "-",
    preserveAnsi: true,
    joinWrapped: false,
  });

  assert.equal(result.content, "full history");
  assert.deepEqual(calls[0].args, ["capture-pane", "-t", "%1", "-p", "-S", "-", "-E", "-", "-e"]);
});

test("terminal hub forwards full-history snapshot requests", async () => {
  const captureStarts = [];
  const captureEnds = [];
  const captureBuffers = [];
  const hub = createTerminalHub({
    adapter: {
      async version() {
        return "tmux mock";
      },
      async findPane(target) {
        return { id: target, paneId: target, paneKey: "mms:0.0", sessionName: "mms", windowIndex: 0, paneIndex: 0 };
      },
      async capturePane(params) {
        captureStarts.push(params.start);
        captureEnds.push(params.end);
        captureBuffers.push(params.maxBuffer);
        return { paneId: params.target, content: "full pane", capturedAt: "now" };
      },
    },
  });

  const result = await hub.snapshot({ paneId: "%1", start: "-", end: "-", maxBuffer: 16 });

  assert.equal(result.content, "full pane");
  assert.deepEqual(captureStarts, ["-"]);
  assert.deepEqual(captureEnds, ["-"]);
  assert.deepEqual(captureBuffers, [16]);
});

test("terminal hub lists newest panes first", async () => {
  const hub = createTerminalHub({
    adapter: {
      async version() {
        return "tmux mock";
      },
      async listAll() {
        return {
          sessions: [
            { id: "$1", name: "alpha", createdAt: 100 },
            { id: "$2", name: "zeta", createdAt: 200 },
          ],
          windows: [
            { id: "@1", sessionName: "alpha", index: 0, windowKey: "alpha:0" },
            { id: "@2", sessionName: "zeta", index: 0, windowKey: "zeta:0" },
          ],
          panes: [
            { id: "%1", paneId: "%1", paneKey: "alpha:0.0", sessionName: "alpha", windowIndex: 0, paneIndex: 0 },
            { id: "%3", paneId: "%3", paneKey: "alpha:0.1", sessionName: "alpha", windowIndex: 0, paneIndex: 1 },
            { id: "%2", paneId: "%2", paneKey: "zeta:0.0", sessionName: "zeta", windowIndex: 0, paneIndex: 0 },
          ],
        };
      },
    },
  });

  const result = await hub.list();

  assert.deepEqual(result.sessions.map((session) => session.name), ["zeta", "alpha"]);
  assert.deepEqual(result.panes.map((pane) => pane.paneId), ["%3", "%2", "%1"]);
  assert.deepEqual(result.panes.map((pane) => pane.pane_id), ["%3", "%2", "%1"]);
  assert.equal(result.panes[0].requestTarget, "%3");
  assert.deepEqual(result.panes[0].fields.slice(1, 7), ["alpha", "", "0", "", "%3", "1"]);
});

test("terminal hub snapshots the newest pane when the phone sends an empty target", async () => {
  const snapshotCalls = [];
  const hub = createTerminalHub({
    adapter: {
      async version() {
        return "tmux mock";
      },
      async listAll() {
        return {
          sessions: [],
          windows: [],
          panes: [
            { id: "%1", paneId: "%1", paneKey: "old:0.0", sessionName: "old", windowIndex: 0, paneIndex: 0 },
            { id: "%3", paneId: "%3", paneKey: "new:0.0", sessionName: "new", windowIndex: 0, paneIndex: 0 },
          ],
        };
      },
      async findPane(target) {
        return { id: target, paneId: target, paneKey: "new:0.0", sessionName: "new", windowIndex: 0, paneIndex: 0 };
      },
      async capturePane(params) {
        snapshotCalls.push(params.target);
        return { paneId: params.target, content: "new pane", capturedAt: "now" };
      },
    },
  });

  const result = await hub.snapshot({ paneId: "" });

  assert.equal(result.pane.paneId, "%3");
  assert.deepEqual(snapshotCalls, ["%3"]);
});

test("terminal hub maps iOS synthetic ordinal pane targets to real panes", async () => {
  const snapshotCalls = [];
  const hub = createTerminalHub({
    adapter: {
      async version() {
        return "tmux mock";
      },
      async listAll() {
        return {
          sessions: [],
          windows: [],
          panes: [
            { id: "%1", paneId: "%1", paneKey: "old:0.0", sessionName: "old", windowIndex: 0, paneIndex: 0 },
            { id: "%3", paneId: "%3", paneKey: "new:0.0", sessionName: "new", windowIndex: 0, paneIndex: 0 },
            { id: "%2", paneId: "%2", paneKey: "mid:0.0", sessionName: "mid", windowIndex: 0, paneIndex: 0 },
          ],
        };
      },
      async findPane(target) {
        throw new Error(`Unknown terminal pane: ${target}`);
      },
      async capturePane(params) {
        snapshotCalls.push(params.target);
        return { paneId: params.target, content: "mapped pane", capturedAt: "now" };
      },
    },
  });

  const result = await hub.snapshot({ paneId: "mms-2:0.0" });

  assert.equal(syntheticOrdinalPaneIndex("mms-2:0.0"), 1);
  assert.equal(result.pane.paneId, "%2");
  assert.equal(result.pane.requestTarget, "%2");
  assert.deepEqual(snapshotCalls, ["%2"]);
});

test("terminal hub snapshots with decorated fallback when paneId is empty", async () => {
  const snapshotCalls = [];
  const hub = createTerminalHub({
    adapter: {
      async version() {
        return "tmux mock";
      },
      async listAll() {
        return {
          sessions: [],
          windows: [],
          panes: [
            { id: "", paneId: "", target: "%9", paneKey: "fallback:0.0", sessionName: "fallback", windowIndex: 0, paneIndex: 0 },
          ],
        };
      },
      async findPane() {
        throw new Error("not found");
      },
      async capturePane(params) {
        snapshotCalls.push(params.target);
        return { paneId: params.target, content: "fallback pane", capturedAt: "now" };
      },
    },
  });

  const result = await hub.snapshot({ paneId: "" });

  assert.equal(result.pane.requestTarget, "%9");
  assert.deepEqual(snapshotCalls, ["%9"]);
});

test("handleTerminalRequest responds to terminal JSON-RPC requests", { skip: !hasTmux }, async () => {
  const { adapter, hub } = makeHub();
  let response = "";
  let resolveResponse;
  const responsePromise = new Promise((resolve) => {
    resolveResponse = resolve;
  });

  try {
    const handled = handleTerminalRequest(
      JSON.stringify({ id: "terminal-1", method: "terminal/list", params: {} }),
      (payload) => {
        response = payload;
        resolveResponse();
      },
      { hub }
    );

    assert.equal(handled, true);
    await responsePromise;
    const parsed = JSON.parse(response);
    assert.equal(parsed.id, "terminal-1");
    assert.equal(Array.isArray(parsed.result.panes), true);
  } finally {
    await cleanup(adapter);
  }
});

test("handleTerminalRequest forwards terminal stream notifications", async () => {
  const responses = [];
  const hub = {
    async handleMethod(method, params, context) {
      assert.equal(method, "terminal/stream/start");
      assert.equal(params.paneId, "%1");
      context.sendNotification("terminal/stream/event", {
        type: "terminal.stream.ready",
        streamId: "term-1",
        paneId: "%1",
        seq: 1,
        sentAt: "now",
      });
      return { ok: true, streamId: "term-1", paneId: "%1", status: "ready" };
    },
  };

  const handled = handleTerminalRequest(
    JSON.stringify({ id: "stream-1", method: "terminal/stream/start", params: { paneId: "%1" } }),
    (payload) => responses.push(JSON.parse(payload)),
    { hub }
  );

  assert.equal(handled, true);
  await waitFor(() => responses.length === 2, "stream response and notification");
  assert.equal(responses[0].method, "terminal/stream/event");
  assert.equal(responses[0].params.type, "terminal.stream.ready");
  assert.equal(responses[1].id, "stream-1");
  assert.equal(responses[1].result.status, "ready");
});

test("terminal hub accepts legacy terminal/stre stream aliases", async () => {
  const calls = [];
  const hub = createTerminalHub({
    adapter: {
      async findPane(target) {
        assert.equal(target, "%1");
        return { id: "%1", paneId: "%1", paneKey: "dev:0.0", sessionName: "dev", windowIndex: 0, paneIndex: 0 };
      },
    },
    streamHub: {
      async start(params) {
        calls.push(["start", params.paneId]);
        return { ok: true, streamId: "term-1", paneId: params.paneId, status: "ready" };
      },
      async stop(params) {
        calls.push(["stop", params.streamId]);
        return { ok: true };
      },
      async replay(params) {
        calls.push(["replay", params.streamId]);
        return { ok: true };
      },
      status(params) {
        calls.push(["status", params.streamId]);
        return { ok: true };
      },
    },
  });

  await hub.handleMethod("terminal/stre/start", { paneId: "%1" });
  await hub.handleMethod("terminal/stre/stop", { streamId: "term-1" });
  await hub.handleMethod("terminal/stre/replay", { streamId: "term-1" });
  await hub.handleMethod("terminal/stre/status", { streamId: "term-1" });

  assert.deepEqual(calls, [
    ["start", "%1"],
    ["stop", "term-1"],
    ["replay", "term-1"],
    ["status", "term-1"],
  ]);
});

test("terminal hub opens a visible macOS terminal when create requests it", async () => {
  const visibleCalls = [];
  const adapter = {
    async version() {
      return "tmux mock";
    },
    async createSession(params) {
      assert.equal(params.name, "dev");
      return { sessionName: "dev" };
    },
    async listAll() {
      return {
        sessions: [],
        windows: [],
        panes: [
          {
            id: "%1",
            paneId: "%1",
            paneKey: "dev:0.0",
            sessionName: "dev",
            windowIndex: 0,
            cwd: "/tmp/dev",
          },
        ],
      };
    },
  };
  const hub = createTerminalHub({
    adapter,
    visibleLauncher: {
      async openPane(pane) {
        visibleCalls.push(pane);
        return { ok: true, opened: true, paneId: pane.paneId };
      },
    },
  });

  const result = await hub.create({
    name: "dev",
    cwd: "/tmp/dev",
    openVisible: true,
  });

  assert.equal(visibleCalls.length, 1);
  assert.equal(visibleCalls[0].paneId, "%1");
  assert.deepEqual(result.visibleTerminal, { ok: true, opened: true, paneId: "%1" });
});

test("terminal create still succeeds when visible terminal launch fails", async () => {
  const adapter = {
    async version() {
      return "tmux mock";
    },
    async createSession() {
      return { sessionName: "dev" };
    },
    async listAll() {
      return {
        sessions: [],
        windows: [],
        panes: [
          {
            id: "%1",
            paneId: "%1",
            paneKey: "dev:0.0",
            sessionName: "dev",
            windowIndex: 0,
            cwd: "/tmp/dev",
          },
        ],
      };
    },
  };
  const hub = createTerminalHub({
    adapter,
    visibleLauncher: {
      async openPane() {
        const error = new Error("osascript denied");
        error.code = "osascript_failed";
        throw error;
      },
    },
  });

  const result = await hub.create({
    name: "dev",
    cwd: "/tmp/dev",
    openVisible: true,
  });

  assert.equal(result.created.sessionName, "dev");
  assert.equal(result.panes[0].paneId, "%1");
  assert.deepEqual(result.visibleTerminal, {
    ok: false,
    opened: false,
    error: {
      code: "osascript_failed",
      message: "osascript denied",
    },
  });
});

test("terminal hub opens an existing pane in a visible macOS terminal", async () => {
  const visibleCalls = [];
  const adapter = {
    async findPane(target) {
      assert.equal(target, "%1");
      return {
        id: "%1",
        paneId: "%1",
        paneKey: "dev:0.0",
        sessionName: "dev",
        windowIndex: 0,
        cwd: "/tmp/dev",
      };
    },
  };
  const hub = createTerminalHub({
    adapter,
    visibleLauncher: {
      async openPane(pane) {
        visibleCalls.push(pane);
        return { ok: true, opened: true, paneId: pane.paneId };
      },
    },
  });

  const result = await hub.openVisible({ paneId: "%1" });

  assert.equal(visibleCalls.length, 1);
  assert.equal(visibleCalls[0].sessionName, "dev");
  assert.deepEqual(result, { ok: true, opened: true, paneId: "%1" });
});

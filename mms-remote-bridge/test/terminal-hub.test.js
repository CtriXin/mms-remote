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
const { createTerminalHub, handleTerminalMethod, handleTerminalRequest } = require("../src/terminal-hub");
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
    async version() {
      return "tmux mock";
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
            target: "%1",
            sessionName: "dev",
            windowIndex: 0,
            cwd: "/tmp/dev",
          },
        ],
      };
    },
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

test("terminal hub resolves stale synthetic iOS pane targets", async () => {
  const adapter = {
    async version() {
      return "tmux mock";
    },
    async listAll() {
      return {
        sessions: [],
        windows: [],
        panes: [
          { id: "%3", paneId: "%3", paneKey: "new:0.0", target: "%3", sessionName: "new", windowIndex: 0, paneIndex: 0 },
          { id: "%2", paneId: "%2", paneKey: "old:0.0", target: "%2", sessionName: "old", windowIndex: 0, paneIndex: 0 },
        ],
      };
    },
    async findPane() {
      throw new Error("synthetic target should resolve before findPane");
    },
    async capturePane(params) {
      assert.equal(params.target, "%2");
      return { content: "ok", capturedAt: "now" };
    },
  };
  const hub = createTerminalHub({ adapter });

  const result = await hub.snapshot({ paneId: "mms-2:0.0" });

  assert.equal(result.pane.paneId, "%2");
  assert.equal(result.content, "ok");
});

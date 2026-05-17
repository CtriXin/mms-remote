// FILE: terminal-stream-hub.test.js
// Purpose: Verifies terminal stream hub notification ordering and replay.
// Depends on: node:test, node:assert/strict, ../src/terminal-stream-hub

const test = require("node:test");
const assert = require("node:assert/strict");
const { createTerminalStreamHub } = require("../src/terminal-stream-hub");
const { createTerminalStreamProtocol } = require("../src/terminal-protocol");

test("terminal stream hub emits ready, replay, output, and exit notifications", async () => {
  const notifications = [];
  let adapterCallbacks;
  const hub = createTerminalStreamHub({
    protocol: createTerminalStreamProtocol({ now: () => "now", uuid: () => "id" }),
    controlAdapter: {
      startOutputStream(params) {
        adapterCallbacks = params;
        return { stop() {} };
      },
    },
    async capturePane() {
      return { content: "prompt$", capturedAt: "capture-time" };
    },
    heartbeatMs: 60_000,
  });

  const result = await hub.start({
    pane: { paneId: "%7", sessionName: "dev" },
    paneId: "%7",
    cols: 80,
    rows: 24,
  }, {
    sendNotification(method, params) {
      notifications.push({ method, params });
    },
  });

  adapterCallbacks.onData(Buffer.from("live", "utf8"));
  await hub.stop({ streamId: result.streamId });

  assert.equal(result.streamId, "term-id");
  assert.deepEqual(notifications.map((item) => item.method), [
    "terminal/stream/event",
    "terminal/stream/event",
    "terminal/stream/event",
    "terminal/stream/event",
    "terminal/stream/event",
    "terminal/stream/event",
  ]);
  assert.deepEqual(notifications.map((item) => item.params.type), [
    "terminal.stream.ready",
    "terminal.stream.replayStart",
    "terminal.stream.output",
    "terminal.stream.replayEnd",
    "terminal.stream.output",
    "terminal.stream.exit",
  ]);
  assert.deepEqual(notifications.map((item) => item.params.seq), [1, 2, 3, 4, 5, 6]);
  assert.equal(Buffer.from(notifications[4].params.base64, "base64").toString("utf8"), "live");
});

test("terminal stream hub buffers live output while replay resets", async () => {
  const notifications = [];
  let adapterCallbacks;
  const hub = createTerminalStreamHub({
    protocol: createTerminalStreamProtocol({ now: () => "now", uuid: () => "race" }),
    controlAdapter: {
      startOutputStream(params) {
        adapterCallbacks = params;
        return { stop() {} };
      },
    },
    async capturePane() {
      adapterCallbacks.onData(Buffer.from("live-during-replay", "utf8"));
      return { content: "snapshot", capturedAt: "capture-time" };
    },
    heartbeatMs: 60_000,
  });

  await hub.start({
    pane: { paneId: "%8", sessionName: "dev" },
    paneId: "%8",
    cols: 80,
    rows: 24,
  }, {
    sendNotification(method, params) {
      notifications.push({ method, params });
    },
  });

  assert.deepEqual(notifications.map((item) => item.params.type), [
    "terminal.stream.ready",
    "terminal.stream.replayStart",
    "terminal.stream.output",
    "terminal.stream.replayEnd",
    "terminal.stream.output",
  ]);
  assert.equal(Buffer.from(notifications[2].params.base64, "base64").toString("utf8"), "snapshot\r\n");
  assert.equal(Buffer.from(notifications[4].params.base64, "base64").toString("utf8"), "live-during-replay");
});

test("terminal stream hub buffers live output emitted before replay starts", async () => {
  const notifications = [];
  const hub = createTerminalStreamHub({
    protocol: createTerminalStreamProtocol({ now: () => "now", uuid: () => "early" }),
    controlAdapter: {
      startOutputStream(params) {
        params.onData(Buffer.from("live-before-replay", "utf8"));
        return { stop() {} };
      },
    },
    async capturePane() {
      return { content: "snapshot", capturedAt: "capture-time" };
    },
    heartbeatMs: 60_000,
  });

  await hub.start({
    pane: { paneId: "%9", sessionName: "dev" },
    paneId: "%9",
    cols: 80,
    rows: 24,
  }, {
    sendNotification(method, params) {
      notifications.push({ method, params });
    },
  });

  assert.deepEqual(notifications.map((item) => item.params.type), [
    "terminal.stream.ready",
    "terminal.stream.replayStart",
    "terminal.stream.output",
    "terminal.stream.replayEnd",
    "terminal.stream.output",
  ]);
  assert.equal(Buffer.from(notifications[2].params.base64, "base64").toString("utf8"), "snapshot\r\n");
  assert.equal(Buffer.from(notifications[4].params.base64, "base64").toString("utf8"), "live-before-replay");
});

test("terminal stream hub drops attach output already covered by replay", async () => {
  const notifications = [];
  const hub = createTerminalStreamHub({
    protocol: createTerminalStreamProtocol({ now: () => "now", uuid: () => "mirror" }),
    controlAdapter: {
      startOutputStream(params) {
        params.onData(Buffer.from("prompt$ ", "utf8"));
        return { stop() {} };
      },
    },
    async capturePane() {
      return { content: "prompt$", capturedAt: "capture-time" };
    },
    heartbeatMs: 60_000,
  });

  await hub.start({
    pane: { paneId: "%11", sessionName: "dev" },
    paneId: "%11",
  }, {
    sendNotification(method, params) {
      notifications.push({ method, params });
    },
  });

  assert.deepEqual(notifications.map((item) => item.params.type), [
    "terminal.stream.ready",
    "terminal.stream.replayStart",
    "terminal.stream.output",
    "terminal.stream.replayEnd",
  ]);
  assert.equal(Buffer.from(notifications[2].params.base64, "base64").toString("utf8"), "prompt$\r\n");
});

test("terminal stream hub normalizes replay capture newlines once", async () => {
  const notifications = [];
  const hub = createTerminalStreamHub({
    protocol: createTerminalStreamProtocol({ now: () => "now", uuid: () => "replay-lf" }),
    controlAdapter: {
      startOutputStream() {
        return { stop() {} };
      },
    },
    async capturePane() {
      return { content: "row1\nrow2\r\r\nrow3", capturedAt: "capture-time" };
    },
    heartbeatMs: 60_000,
  });

  await hub.start({
    pane: { paneId: "%12", sessionName: "dev" },
    paneId: "%12",
  }, {
    sendNotification(method, params) {
      notifications.push({ method, params });
    },
  });

  const output = notifications.find((item) => item.params.type === "terminal.stream.output");
  assert.ok(output);
  assert.equal(Buffer.from(output.params.base64, "base64").toString("utf8"), "row1\r\nrow2\r\nrow3\r\n");
});

test("terminal stream hub can replay only the visible viewport", async () => {
  const captureOptions = [];
  const hub = createTerminalStreamHub({
    protocol: createTerminalStreamProtocol({ now: () => "now", uuid: () => "visible" }),
    controlAdapter: {
      startOutputStream() {
        return { stop() {} };
      },
    },
    async capturePane(pane, options) {
      captureOptions.push(options);
      return { content: "visible", capturedAt: "capture-time" };
    },
    heartbeatMs: 60_000,
  });

  await hub.start({
    pane: { paneId: "%10", sessionName: "dev" },
    paneId: "%10",
    replayViewportOnly: true,
  }, {
    sendNotification() {},
  });

  assert.equal(captureOptions[0].viewportOnly, true);
  assert.equal(captureOptions[0].joinWrapped, false);
});

test("terminal stream hub forwards full-history replay options", async () => {
  const captureOptions = [];
  const hub = createTerminalStreamHub({
    protocol: createTerminalStreamProtocol({ now: () => "now", uuid: () => "full-history" }),
    controlAdapter: {
      startOutputStream() {
        return { stop() {} };
      },
    },
    async capturePane(pane, options) {
      captureOptions.push(options);
      return { content: "full history", capturedAt: "capture-time" };
    },
    heartbeatMs: 60_000,
  });

  await hub.start({
    pane: { paneId: "%13", sessionName: "dev" },
    paneId: "%13",
    start: "-",
    end: "-",
    maxBuffer: 16,
  }, {
    sendNotification() {},
  });

  assert.equal(captureOptions[0].viewportOnly, false);
  assert.equal(captureOptions[0].start, "-");
  assert.equal(captureOptions[0].end, "-");
  assert.equal(captureOptions[0].maxBuffer, 16);
  assert.equal(captureOptions[0].joinWrapped, false);
});

test("terminal stream hub stopAll releases active streams without notifications", async () => {
  const stopped = [];
  const notifications = [];
  const hub = createTerminalStreamHub({
    protocol: createTerminalStreamProtocol({ now: () => "now", uuid: () => `id-${stopped.length}` }),
    controlAdapter: {
      startOutputStream(params) {
        return { stop() { stopped.push(params.paneId); } };
      },
    },
    heartbeatMs: 60_000,
  });

  await hub.start({ pane: { paneId: "%1", sessionName: "dev" }, paneId: "%1", replay: false }, {
    sendNotification(method, params) { notifications.push({ method, params }); },
  });
  const result = hub.stopAll({ reason: "relay_disconnected", notify: false });

  assert.deepEqual(result, { ok: true, stopped: 1 });
  assert.deepEqual(stopped, ["%1"]);
  assert.equal(hub.status().streams.length, 0);
  assert.deepEqual(notifications.map((item) => item.params.type), ["terminal.stream.ready"]);
});

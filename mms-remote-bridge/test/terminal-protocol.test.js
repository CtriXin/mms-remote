// FILE: terminal-protocol.test.js
// Purpose: Verifies terminal stream protocol v2 envelopes.
// Depends on: node:test, node:assert/strict, ../src/terminal-protocol

const test = require("node:test");
const assert = require("node:assert/strict");
const {
  TERMINAL_STREAM_EVENT_METHOD,
  TerminalStreamMessageTypes,
  createTerminalStreamProtocol,
} = require("../src/terminal-protocol");

test("terminal protocol creates ordered output envelopes", () => {
  const protocol = createTerminalStreamProtocol({
    now: () => "2026-05-15T00:00:00.000Z",
    uuid: () => "abc",
  });
  const streamId = protocol.createStreamId();
  const message = protocol.makeOutput({
    streamId,
    paneId: "%1",
    seq: 2,
    bytes: Buffer.from("\u001b[31mred\u001b[0m", "utf8"),
  });

  assert.equal(TERMINAL_STREAM_EVENT_METHOD, "terminal/stream/event");
  assert.equal(streamId, "term-abc");
  assert.equal(message.type, TerminalStreamMessageTypes.OUTPUT);
  assert.equal(message.seq, 2);
  assert.equal(Buffer.from(message.base64, "base64").toString("utf8"), "\u001b[31mred\u001b[0m");
  assert.equal(message.sentAt, "2026-05-15T00:00:00.000Z");
  assert.equal(protocol.validateMessage(message), true);
});

test("terminal protocol validates start params safely", () => {
  const protocol = createTerminalStreamProtocol();
  assert.deepEqual(protocol.validateStartParams({ target: "%9", cols: 120, rows: 40 }), {
    paneId: "%9",
    cols: 120,
    rows: 40,
    replay: true,
  });
  assert.deepEqual(protocol.validateStartParams({ paneId: " ", cols: -1, replay: false }), {
    paneId: "",
    cols: null,
    rows: null,
    replay: false,
  });
});

// FILE: tmux-control-adapter.test.js
// Purpose: Verifies tmux control-mode parsing and adapter stream lifecycle.
// Depends on: node:test, node:assert/strict, node:events, ../src/tmux-control-adapter

const test = require("node:test");
const assert = require("node:assert/strict");
const { EventEmitter } = require("node:events");
const {
  createTerminalOutputNormalizer,
  createTmuxControlAdapter,
  decodeTmuxControlEscapes,
  normalizeTerminalOutputText,
  parseTmuxControlLine,
} = require("../src/tmux-control-adapter");

test("decodeTmuxControlEscapes decodes octal control bytes", () => {
  const decoded = decodeTmuxControlEscapes("hello\\033[31m red\\015\\012");
  assert.deepEqual([...decoded], [...Buffer.from("hello\u001b[31m red\r\n", "utf8")]);
});

test("parseTmuxControlLine parses output and extended output", () => {
  const output = parseTmuxControlLine("%output %4 hi\\012");
  assert.equal(output.type, "%output");
  assert.equal(output.paneId, "%4");
  assert.equal(output.bytes.toString("utf8"), "hi\n");

  const extended = parseTmuxControlLine("%extended-output %4 12 ignored : ok\\012");
  assert.equal(extended.type, "%extended-output");
  assert.equal(extended.bytes.toString("utf8"), "ok\n");
});

test("normalizeTerminalOutputText converts bare LF and strips private glyphs", () => {
  assert.equal(normalizeTerminalOutputText("pwd\n/Users/xin\n"), "pwd\r\n/Users/xin\r\n");
  assert.equal(normalizeTerminalOutputText("ok\r\nnext"), "ok\r\nnext");
  assert.equal(normalizeTerminalOutputText("prompt \uE0B0 box"), "prompt   box");
});

test("terminal output normalizer preserves split UTF-8 characters", () => {
  const normalizer = createTerminalOutputNormalizer();
  const bytes = Buffer.from("你\n\uE0B0\n", "utf8");
  const first = normalizer.write(bytes.subarray(0, 1));
  const rest = normalizer.write(bytes.subarray(1));

  assert.equal(Buffer.concat([first, rest]).toString("utf8"), "你\r\n \r\n");
});

test("tmux control adapter filters selected pane output and writes activation commands", async () => {
  const writes = [];
  let fakeChild;
  function fakeSpawn(bin, args) {
    assert.equal(bin, "tmux");
    assert.deepEqual(args, ["-C", "attach-session", "-f", "read-only,ignore-size,active-pane", "-t", "dev"]);
    fakeChild = new EventEmitter();
    fakeChild.stdout = new EventEmitter();
    fakeChild.stderr = new EventEmitter();
    fakeChild.stdin = { writable: true, write: (value) => writes.push(value) };
    fakeChild.kill = () => fakeChild.emit("exit", 0, null);
    return fakeChild;
  }

  const chunks = [];
  const adapter = createTmuxControlAdapter({ spawn: fakeSpawn });
  const stream = adapter.startOutputStream({
    pane: { paneId: "%2", sessionName: "dev" },
    cols: 90,
    rows: 28,
    onData: (bytes) => chunks.push(bytes.toString("utf8")),
  });
  await new Promise((resolve) => setImmediate(resolve));

  fakeChild.stdout.emit("data", Buffer.from("%output %1 nope\\012\n%output %2 yes\\012\n"));
  assert.deepEqual(chunks, ["yes\r\n"]);
  assert.equal(stream.paneId, "%2");
  assert.ok(writes.includes("select-pane -t '%2'\n"));
  assert.ok(writes.includes("refresh-client -A '%2:on'\n"));
  assert.ok(writes.includes("refresh-client -C 90x28\n"));
});

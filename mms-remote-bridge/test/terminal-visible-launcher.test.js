// FILE: terminal-visible-launcher.test.js
// Purpose: Verifies macOS visible terminal launch command construction without opening Terminal.app.
// Layer: Unit test
// Exports: node:test suite
// Depends on: node:test, node:assert/strict, ../src/terminal-visible-launcher

const test = require("node:test");
const assert = require("node:assert/strict");
const {
  buildTerminalAttachShellCommand,
  createTerminalVisibleLauncher,
} = require("../src/terminal-visible-launcher");

test("buildTerminalAttachShellCommand selects and attaches the created tmux pane", () => {
  const command = buildTerminalAttachShellCommand({
    tmuxBin: "/opt/homebrew/bin/tmux",
    socketName: "mms-test",
    pane: {
      paneId: "%3",
      sessionName: "dev",
      windowIndex: 2,
      cwd: "/tmp/dev dir",
    },
  });

  assert.match(command, /^cd '\/tmp\/dev dir' && exec/);
  assert.match(command, /'\/opt\/homebrew\/bin\/tmux'/);
  assert.match(command, /'-L' 'mms-test'/);
  assert.match(command, /'select-window' '-t' 'dev:2'/);
  assert.match(command, /'select-pane' '-t' '%3'/);
  assert.match(command, /'attach-session' '-t' 'dev'/);
});

test("visible launcher uses osascript on macOS and never opens during tests", async () => {
  const calls = [];
  const launcher = createTerminalVisibleLauncher({
    platform: "darwin",
    socketName: "mms-test",
    execFile(file, args, options, callback) {
      calls.push({ file, args, options });
      callback(null, "", "");
    },
  });

  const result = await launcher.openPane({
    paneId: "%1",
    sessionName: "dev",
    windowIndex: 0,
    cwd: "/tmp/dev",
  });

  assert.equal(result.opened, true);
  assert.equal(calls.length, 1);
  assert.equal(calls[0].file, "osascript");
  assert.deepEqual(calls[0].args.slice(0, 1), ["-e"]);
  assert.match(calls[0].args[1], /tell application "Terminal"/);
  assert.match(calls[0].args[1], /attach-session/);
});

test("visible launcher no-ops on non-macOS platforms", async () => {
  const launcher = createTerminalVisibleLauncher({
    platform: "linux",
    execFile() {
      throw new Error("osascript should not run outside macOS");
    },
  });

  const result = await launcher.openPane({
    paneId: "%1",
    sessionName: "dev",
  });

  assert.equal(result.opened, false);
  assert.equal(result.reason, "unsupported_platform");
});

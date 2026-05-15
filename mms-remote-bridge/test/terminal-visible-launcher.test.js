// FILE: terminal-visible-launcher.test.js
// Purpose: Verifies macOS visible terminal launch command construction without opening GUI apps.
// Layer: Unit test
// Exports: node:test suite
// Depends on: node:test, node:assert/strict, ../src/terminal-visible-launcher

const test = require("node:test");
const assert = require("node:assert/strict");
const {
  buildTerminalAttachShellCommand,
  createTerminalVisibleLauncher,
  normalizeVisibleTerminalApp,
  resolveVisibleTerminalApp,
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

test("visible launcher auto-prefers Ghostty when it is installed", async () => {
  const calls = [];
  const launcher = createTerminalVisibleLauncher({
    platform: "darwin",
    socketName: "mms-test",
    appExists(path) {
      return path === "/Applications/Ghostty.app";
    },
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
  assert.equal(result.app, "ghostty");
  assert.equal(calls.length, 1);
  assert.equal(calls[0].file, "open");
  assert.deepEqual(calls[0].args.slice(0, 4), ["-na", "Ghostty.app", "--args", "-e"]);
  assert.equal(calls[0].args.includes("attach-session"), false);
  assert.match(calls[0].args.at(-1), /attach-session/);
});

test("visible launcher can explicitly open iTerm2", async () => {
  const calls = [];
  const launcher = createTerminalVisibleLauncher({
    platform: "darwin",
    visibleApp: "iterm",
    execFile(file, args, options, callback) {
      calls.push({ file, args, options });
      callback(null, "", "");
    },
  });

  const result = await launcher.openPane({
    paneId: "%1",
    sessionName: "dev",
    windowIndex: 0,
  });

  assert.equal(result.app, "iterm");
  assert.equal(calls[0].file, "osascript");
  assert.match(calls[0].args[1], /tell application "iTerm2"/);
  assert.match(calls[0].args[1], /create window with default profile/);
  assert.match(calls[0].args[1], /attach-session/);
});

test("visible launcher can explicitly open Terminal.app", async () => {
  const calls = [];
  const launcher = createTerminalVisibleLauncher({
    platform: "darwin",
    visibleApp: "terminal",
    execFile(file, args, options, callback) {
      calls.push({ file, args, options });
      callback(null, "", "");
    },
  });

  const result = await launcher.openPane({
    paneId: "%1",
    sessionName: "dev",
    windowIndex: 0,
  });

  assert.equal(result.app, "terminal");
  assert.equal(calls[0].file, "osascript");
  assert.match(calls[0].args[1], /tell application "Terminal"/);
  assert.match(calls[0].args[1], /do script/);
  assert.match(calls[0].args[1], /attach-session/);
});

test("visible launcher accepts per-call visible app override", async () => {
  const calls = [];
  const launcher = createTerminalVisibleLauncher({
    platform: "darwin",
    visibleApp: "terminal",
    execFile(file, args, options, callback) {
      calls.push({ file, args, options });
      callback(null, "", "");
    },
  });

  const result = await launcher.openPane({ paneId: "%1", sessionName: "dev" }, { visibleApp: "ghostty" });

  assert.equal(result.app, "ghostty");
  assert.equal(calls[0].file, "open");
});

test("visible launcher no-ops on non-macOS platforms", async () => {
  const launcher = createTerminalVisibleLauncher({
    platform: "linux",
    execFile() {
      throw new Error("launcher should not run outside macOS");
    },
  });

  const result = await launcher.openPane({
    paneId: "%1",
    sessionName: "dev",
  });

  assert.equal(result.opened, false);
  assert.equal(result.reason, "unsupported_platform");
});

test("visible terminal app normalization and auto fallback are stable", () => {
  assert.equal(normalizeVisibleTerminalApp("iTerm2"), "iterm");
  assert.equal(normalizeVisibleTerminalApp("Terminal.app"), "terminal");
  assert.equal(resolveVisibleTerminalApp("auto", { appExists: () => false }).id, "terminal");
  assert.throws(() => normalizeVisibleTerminalApp("wezterm"), /auto, ghostty, iterm, or terminal/);
});

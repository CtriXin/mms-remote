// FILE: tmux-adapter.js
// Purpose: Safe tmux command wrapper for managed terminal sessions.
// Layer: Service adapter
// Exports: createTmuxAdapter, TmuxAdapterError
// Depends on: child_process, crypto, os, path

const { execFile } = require("child_process");
const crypto = require("crypto");
const path = require("path");

const FIELD_SEPARATOR = "\u001f";
const DEFAULT_TIMEOUT_MS = 5000;
const DEFAULT_HISTORY_LINES = 2000;

class TmuxAdapterError extends Error {
  constructor(message, { code = "tmux_error", stderr = "", cause = null } = {}) {
    super(message);
    this.name = "TmuxAdapterError";
    this.code = code;
    this.stderr = stderr;
    if (cause) {
      this.cause = cause;
    }
  }
}

function createTmuxAdapter(options = {}) {
  const tmuxBin = options.tmuxBin || "tmux";
  const socketName = normalizeOptionalString(options.socketName);
  const timeoutMs = Number.isInteger(options.timeoutMs) ? options.timeoutMs : DEFAULT_TIMEOUT_MS;
  const env = options.env || process.env;
  const execFileImpl = options.execFile || execFile;

  function baseArgs(args) {
    return socketName ? ["-L", socketName, ...args] : args;
  }

  function run(args, runOptions = {}) {
    return new Promise((resolve, reject) => {
      execFileImpl(
        tmuxBin,
        baseArgs(args),
        {
          cwd: runOptions.cwd || process.cwd(),
          env,
          timeout: runOptions.timeoutMs || timeoutMs,
          maxBuffer: runOptions.maxBuffer || 1024 * 1024 * 8,
        },
        (error, stdout, stderr) => {
          if (error) {
            reject(new TmuxAdapterError(stderr?.trim() || error.message, {
              code: error.code === "ENOENT" ? "tmux_not_found" : "tmux_command_failed",
              stderr,
              cause: error,
            }));
            return;
          }
          resolve({ stdout, stderr });
        }
      );
    });
  }

  async function version() {
    const { stdout } = await run(["-V"]);
    return stdout.trim();
  }

  async function listSessions() {
    const format = [
      "#{session_id}",
      "#{session_name}",
      "#{session_windows}",
      "#{session_attached}",
      "#{session_created}",
    ].join(FIELD_SEPARATOR);
    const { stdout } = await run(["list-sessions", "-F", format]).catch((error) => {
      if (isNoServerError(error)) {
        return { stdout: "" };
      }
      throw error;
    });
    return parseRows(stdout, 5).map((fields) => ({
      id: fields[0],
      name: fields[1],
      windowCount: toInteger(fields[2]),
      attachedCount: toInteger(fields[3]),
      createdAt: toInteger(fields[4]),
    }));
  }

  async function listWindows() {
    const format = [
      "#{session_id}",
      "#{session_name}",
      "#{window_id}",
      "#{window_index}",
      "#{window_name}",
      "#{window_active}",
      "#{window_panes}",
      "#{window_layout}",
    ].join(FIELD_SEPARATOR);
    const { stdout } = await run(["list-windows", "-a", "-F", format]).catch((error) => {
      if (isNoServerError(error)) {
        return { stdout: "" };
      }
      throw error;
    });
    return parseRows(stdout, 8).map((fields) => ({
      id: fields[2],
      sessionId: fields[0],
      sessionName: fields[1],
      index: toInteger(fields[3]),
      name: fields[4],
      active: fields[5] === "1",
      paneCount: toInteger(fields[6]),
      layout: fields[7],
      windowKey: `${fields[1]}:${fields[3]}`,
    }));
  }

  async function listPanes() {
    const format = [
      "#{session_id}",
      "#{session_name}",
      "#{window_id}",
      "#{window_index}",
      "#{window_name}",
      "#{pane_id}",
      "#{pane_index}",
      "#{pane_title}",
      "#{pane_current_command}",
      "#{pane_current_path}",
      "#{pane_width}",
      "#{pane_height}",
      "#{pane_active}",
      "#{pane_dead}",
    ].join(FIELD_SEPARATOR);
    const { stdout } = await run(["list-panes", "-a", "-F", format]).catch((error) => {
      if (isNoServerError(error)) {
        return { stdout: "" };
      }
      throw error;
    });
    return parseRows(stdout, 14).map((fields) => {
      const paneKey = `${fields[1]}:${fields[3]}.${fields[6]}`;
      return {
        id: fields[5],
        paneId: fields[5],
        paneKey,
        target: fields[5],
        sessionId: fields[0],
        sessionName: fields[1],
        windowId: fields[2],
        windowIndex: toInteger(fields[3]),
        windowName: fields[4],
        paneIndex: toInteger(fields[6]),
        title: fields[7],
        currentCommand: fields[8],
        cwd: fields[9],
        cols: toInteger(fields[10]),
        rows: toInteger(fields[11]),
        active: fields[12] === "1",
        dead: fields[13] === "1",
      };
    });
  }

  async function listAll() {
    const [sessions, windows, panes] = await Promise.all([
      listSessions(),
      listWindows(),
      listPanes(),
    ]);
    return { sessions, windows, panes };
  }

  async function createSession(params = {}) {
    const name = normalizeSessionName(params.name || `mms-${crypto.randomUUID().slice(0, 8)}`);
    const cwd = normalizeCwd(params.cwd);
    const args = ["new-session", "-d", "-P", "-F", "#{pane_id}", "-s", name];
    if (Number.isInteger(params.cols) && Number.isInteger(params.rows)) {
      args.push("-x", String(params.cols), "-y", String(params.rows));
    }
    if (cwd) {
      args.push("-c", cwd);
    }
    if (params.command) {
      args.push(String(params.command));
    }
    const { stdout } = await run(args);
    return { sessionName: name, paneId: stdout.trim() };
  }

  async function createWindow(params = {}) {
    const session = normalizeTarget(params.session || params.sessionName);
    const cwd = normalizeCwd(params.cwd);
    const args = ["new-window", "-d", "-P", "-F", "#{pane_id}", "-t", session];
    if (params.name) {
      args.push("-n", normalizeWindowName(params.name));
    }
    if (cwd) {
      args.push("-c", cwd);
    }
    if (params.command) {
      args.push(String(params.command));
    }
    const { stdout } = await run(args);
    return { paneId: stdout.trim() };
  }

  async function splitPane(params = {}) {
    const target = normalizeTarget(params.target || params.paneId || params.paneKey);
    const cwd = normalizeCwd(params.cwd);
    const args = ["split-window", "-d", "-P", "-F", "#{pane_id}", "-t", target];
    if (params.horizontal) {
      args.push("-h");
    }
    if (cwd) {
      args.push("-c", cwd);
    }
    if (params.command) {
      args.push(String(params.command));
    }
    const { stdout } = await run(args);
    return { paneId: stdout.trim() };
  }

  async function capturePane(params = {}) {
    const target = normalizeTarget(params.target || params.paneId || params.paneKey);
    const viewportOnly = params.viewportOnly === true || params.start === "visible";
    const args = ["capture-pane", "-t", target, "-p"];
    if (!viewportOnly) {
      const start = params.start === "-" ? "-" : (Number.isInteger(params.start) ? params.start : -DEFAULT_HISTORY_LINES);
      args.push("-S", String(start));
    }
    if (Number.isInteger(params.end)) {
      args.push("-E", String(params.end));
    }
    if (params.preserveAnsi) {
      args.push("-e");
    }
    if (params.joinWrapped !== false) {
      args.push("-J");
    }
    const { stdout } = await run(args, { maxBuffer: params.maxBuffer });
    return {
      paneId: target,
      content: trimTrailingBlankLines(stdout),
      capturedAt: new Date().toISOString(),
    };
  }

  async function sendText(params = {}) {
    const target = normalizeTarget(params.target || params.paneId || params.paneKey);
    const text = typeof params.text === "string" ? params.text : "";
    if (!text) {
      return { ok: true };
    }
    await run(["send-keys", "-t", target, "-l", text]);
    return { ok: true };
  }

  async function sendKey(params = {}) {
    const target = normalizeTarget(params.target || params.paneId || params.paneKey);
    const key = normalizeTmuxKey(params.key);
    await run(["send-keys", "-t", target, key]);
    return { ok: true };
  }

  async function sendBytes(params = {}) {
    const target = normalizeTarget(params.target || params.paneId || params.paneKey);
    const base64 = normalizeOptionalString(params.base64 || params.data || params.bytes);
    if (!base64) {
      return { ok: true };
    }
    const buffer = Buffer.from(base64, "base64");
    if (!buffer.length) {
      return { ok: true };
    }
    const specialKey = tmuxKeyForByteSequence(buffer);
    if (specialKey) {
      await run(["send-keys", "-t", target, specialKey]);
      return { ok: true };
    }
    if (containsControlByte(buffer)) {
      await run(["send-keys", "-t", target, "-H", ...[...buffer].map((byte) => byte.toString(16).padStart(2, "0"))]);
      return { ok: true };
    }
    const text = buffer.toString("utf8").replace(/\u0000/g, "");
    if (!text) {
      return { ok: true };
    }
    await run(["send-keys", "-t", target, "-l", text]);
    return { ok: true };
  }

  async function sendInput(params = {}) {
    const input = params.input || {};
    if (input.kind === "text") {
      return sendText({ target: params.target || params.paneId || params.paneKey, text: input.text });
    }
    if (input.kind === "key") {
      return sendKey({ target: params.target || params.paneId || params.paneKey, key: input.key });
    }
    if (input.kind === "bytes") {
      return sendBytes({
        target: params.target || params.paneId || params.paneKey,
        base64: input.base64 || input.data || input.bytes,
      });
    }
    if (typeof params.text === "string") {
      return sendText(params);
    }
    if (params.key) {
      return sendKey(params);
    }
    throw new TmuxAdapterError("Terminal input must include text or key", { code: "invalid_terminal_input" });
  }

  async function resizePane(params = {}) {
    const target = normalizeTarget(params.target || params.paneId || params.paneKey);
    const cols = toPositiveInteger(params.cols, "cols");
    const rows = toPositiveInteger(params.rows, "rows");
    const pane = await findPane(target);
    await run(["resize-window", "-t", `${pane.sessionName}:${pane.windowIndex}`, "-x", String(cols), "-y", String(rows)]);
    return { ok: true, paneId: pane.paneId, cols, rows };
  }

  async function killPane(params = {}) {
    const target = normalizeTarget(params.target || params.paneId || params.paneKey);
    await run(["kill-pane", "-t", target]);
    return { ok: true };
  }

  async function killSession(params = {}) {
    const target = normalizeTarget(params.target || params.session || params.sessionName);
    await run(["kill-session", "-t", target]);
    return { ok: true };
  }

  async function killServer() {
    await run(["kill-server"]).catch((error) => {
      if (!isNoServerError(error)) {
        throw error;
      }
    });
    return { ok: true };
  }

  async function findPane(target) {
    const panes = await listPanes();
    const pane = panes.find((candidate) => candidate.paneId === target || candidate.paneKey === target);
    if (!pane) {
      throw new TmuxAdapterError(`Unknown terminal pane: ${target}`, { code: "terminal_pane_not_found" });
    }
    return pane;
  }

  return {
    capturePane,
    createSession,
    createWindow,
    findPane,
    killPane,
    killServer,
    killSession,
    listAll,
    listPanes,
    listSessions,
    listWindows,
    resizePane,
    run,
    sendInput,
    sendKey,
    sendText,
    splitPane,
    version,
  };
}

function parseRows(stdout, expectedFieldCount) {
  return stdout
    .split(/\r?\n/)
    .filter((line) => line.length > 0)
    .map((line) => {
      const fields = line.split(FIELD_SEPARATOR);
      while (fields.length < expectedFieldCount) {
        fields.push("");
      }
      return fields;
    });
}

function isNoServerError(error) {
  return error?.stderr?.includes("no server running")
    || error?.message?.includes("no server running")
    || error?.stderr?.includes("failed to connect to server")
    || error?.stderr?.includes("error connecting to");
}

function normalizeOptionalString(value) {
  return typeof value === "string" && value.trim() ? value.trim() : "";
}

function normalizeTarget(value) {
  const target = normalizeOptionalString(value);
  if (!target) {
    throw new TmuxAdapterError("Terminal pane target is required", { code: "invalid_terminal_target" });
  }
  return target;
}

function normalizeSessionName(value) {
  const name = normalizeOptionalString(value);
  if (!/^[A-Za-z0-9][A-Za-z0-9_.-]{0,79}$/.test(name)) {
    throw new TmuxAdapterError("Terminal session names may contain letters, numbers, dot, dash, and underscore", {
      code: "invalid_terminal_session_name",
    });
  }
  return name;
}

function normalizeWindowName(value) {
  const name = normalizeOptionalString(value);
  if (!name || name.length > 80 || /[\r\n:]/.test(name)) {
    throw new TmuxAdapterError("Terminal window name is invalid", { code: "invalid_terminal_window_name" });
  }
  return name;
}

function normalizeCwd(value) {
  if (!value) {
    return "";
  }
  const rawCwd = String(value);
  if (!path.isAbsolute(rawCwd)) {
    throw new TmuxAdapterError("Terminal cwd must be absolute", { code: "invalid_terminal_cwd" });
  }
  return path.resolve(rawCwd);
}

function normalizeTmuxKey(value) {
  const key = String(value || "")
    .trim()
    .toLowerCase()
    .replace(/_/g, "-")
    .replace(/\s+/g, "-");
  const keyMap = new Map([
    ["enter", "Enter"],
    ["return", "Enter"],
    ["backspace", "BSpace"],
    ["bs", "BSpace"],
    ["delete", "DC"],
    ["del", "DC"],
    ["tab", "Tab"],
    ["shift-tab", "BTab"],
    ["backtab", "BTab"],
    ["escape", "Escape"],
    ["esc", "Escape"],
    ["up", "Up"],
    ["down", "Down"],
    ["left", "Left"],
    ["right", "Right"],
    ["home", "Home"],
    ["end", "End"],
    ["pageup", "PageUp"],
    ["page-up", "PageUp"],
    ["pgup", "PageUp"],
    ["pagedown", "PageDown"],
    ["page-down", "PageDown"],
    ["pgdn", "PageDown"],
    ["ctrl-c", "C-c"],
    ["ctrl-d", "C-d"],
    ["ctrl-z", "C-z"],
    ["ctrl-a", "C-a"],
    ["ctrl-e", "C-e"],
  ]);
  const tmuxKey = keyMap.get(key);
  if (tmuxKey) {
    return tmuxKey;
  }
  const functionKey = normalizeFunctionKey(key);
  if (functionKey) {
    return functionKey;
  }
  const compoundKey = normalizeCompoundTmuxKey(key);
  if (compoundKey) {
    return compoundKey;
  }
  const ctrlKey = normalizeModifiedTmuxKey(key, ["ctrl", "control", "c"], "C");
  if (ctrlKey) {
    return ctrlKey;
  }
  const altKey = normalizeModifiedTmuxKey(key, ["alt", "option", "meta", "m"], "M");
  if (altKey) {
    return altKey;
  }
  const shiftKey = normalizeModifiedTmuxKey(key, ["shift", "s"], "S");
  if (shiftKey) {
    return shiftKey;
  }
  throw new TmuxAdapterError(`Unsupported terminal key: ${value}`, { code: "unsupported_terminal_key" });
}

function normalizeFunctionKey(key) {
  const match = /^f([1-9]|1[0-2])$/.exec(key);
  return match ? `F${match[1]}` : null;
}

function normalizeCompoundTmuxKey(key) {
  const parts = key.split("-").filter(Boolean);
  if (parts.length < 2) {
    return null;
  }

  const modifiers = new Set();
  let index = 0;
  while (index < parts.length - 1) {
    const modifier = tmuxModifierForToken(parts[index]);
    if (!modifier) {
      break;
    }
    modifiers.add(modifier);
    index += 1;
  }

  if (!modifiers.size || index >= parts.length) {
    return null;
  }

  const suffix = parts.slice(index).join("-");
  if (modifiers.size === 1 && modifiers.has("M") && suffix === "left") {
    return "M-b";
  }
  if (modifiers.size === 1 && modifiers.has("M") && suffix === "right") {
    return "M-f";
  }

  const normalizedSuffix = normalizeModifiedKeySuffix(suffix);
  if (!normalizedSuffix) {
    return null;
  }

  const orderedModifiers = [];
  if (modifiers.has("C")) {
    orderedModifiers.push("C");
  }
  if (modifiers.has("M")) {
    orderedModifiers.push("M");
  }
  if (modifiers.has("S")) {
    orderedModifiers.push("S");
  }
  return `${orderedModifiers.join("-")}-${normalizedSuffix}`;
}

function tmuxModifierForToken(token) {
  switch (token) {
    case "command":
    case "cmd":
    case "option":
    case "alt":
    case "meta":
      return "M";
    case "control":
    case "ctrl":
      return "C";
    case "shift":
      return "S";
    default:
      return null;
  }
}

function normalizeModifiedTmuxKey(key, prefixes, modifier) {
  const suffix = modifiedKeySuffix(key, prefixes);
  if (!suffix) {
    return null;
  }
  if (modifier === "M" && suffix === "left") {
    return "M-b";
  }
  if (modifier === "M" && suffix === "right") {
    return "M-f";
  }
  const normalizedSuffix = normalizeModifiedKeySuffix(suffix);
  if (!normalizedSuffix) {
    return null;
  }
  return `${modifier}-${normalizedSuffix}`;
}

function modifiedKeySuffix(key, prefixes) {
  for (const prefix of prefixes) {
    const dashed = `${prefix}-`;
    if (key.startsWith(dashed)) {
      return key.slice(dashed.length);
    }
    if (key.startsWith(prefix) && key.length === prefix.length + 1) {
      return key.slice(prefix.length);
    }
  }
  return "";
}

function normalizeModifiedKeySuffix(suffix) {
  const aliases = new Map([
    ["escape", "["],
    ["esc", "["],
    ["space", "Space"],
    ["backspace", "BSpace"],
    ["bs", "BSpace"],
    ["delete", "DC"],
    ["del", "DC"],
    ["tab", "Tab"],
    ["enter", "Enter"],
    ["return", "Enter"],
    ["up", "Up"],
    ["down", "Down"],
    ["left", "Left"],
    ["right", "Right"],
    ["home", "Home"],
    ["end", "End"],
    ["pageup", "PageUp"],
    ["page-up", "PageUp"],
    ["pagedown", "PageDown"],
    ["page-down", "PageDown"],
    ["pgup", "PageUp"],
    ["pgdn", "PageDown"],
  ]);
  if (aliases.has(suffix)) {
    return aliases.get(suffix);
  }
  const functionKey = normalizeFunctionKey(suffix);
  if (functionKey) {
    return functionKey;
  }
  if (suffix.length === 1) {
    return suffix;
  }
  return null;
}

function tmuxKeyForByteSequence(buffer) {
  const sequence = Buffer.from(buffer).toString("binary");
  const sequenceMap = new Map([
    ["\r", "Enter"],
    ["\n", "Enter"],
    ["\t", "Tab"],
    ["\u007f", "BSpace"],
    ["\u001b", "Escape"],
    ["\u0003", "C-c"],
    ["\u0004", "C-d"],
    ["\u001a", "C-z"],
    ["\u0001", "C-a"],
    ["\u0005", "C-e"],
    ["\u001b[A", "Up"],
    ["\u001b[B", "Down"],
    ["\u001b[C", "Right"],
    ["\u001b[D", "Left"],
    ["\u001b[H", "Home"],
    ["\u001b[F", "End"],
    ["\u001b[5~", "PageUp"],
    ["\u001b[6~", "PageDown"],
    ["\u001b[Z", "BTab"],
  ]);
  return sequenceMap.get(sequence) || null;
}

function containsControlByte(buffer) {
  return [...buffer].some((byte) => byte < 0x20 || byte === 0x7f);
}

function toInteger(value) {
  const parsed = Number.parseInt(value, 10);
  return Number.isNaN(parsed) ? 0 : parsed;
}

function toPositiveInteger(value, name) {
  const parsed = Number.parseInt(value, 10);
  if (!Number.isInteger(parsed) || parsed <= 0) {
    throw new TmuxAdapterError(`Terminal ${name} must be a positive integer`, { code: "invalid_terminal_size" });
  }
  return parsed;
}

function trimTrailingBlankLines(text) {
  return String(text || "").replace(/[\r\n\s]*$/g, "");
}

module.exports = {
  createTmuxAdapter,
  TmuxAdapterError,
};

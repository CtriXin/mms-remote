// FILE: tmux-control-adapter.js
// Purpose: Streams tmux control-mode pane output as raw terminal bytes.
// Layer: Adapter
// Exports: createTmuxControlAdapter, decodeTmuxControlEscapes, parseTmuxControlLine
// Depends on: child_process

const { spawn } = require("child_process");
const { StringDecoder } = require("string_decoder");

class TmuxControlAdapterError extends Error {
  constructor(message, { code = "tmux_control_error", cause = null } = {}) {
    super(message);
    this.name = "TmuxControlAdapterError";
    this.code = code;
    if (cause) {
      this.cause = cause;
    }
  }
}

function createTmuxControlAdapter(options = {}) {
  const tmuxBin = options.tmuxBin || "tmux";
  const socketName = normalizeOptionalString(options.socketName);
  const spawnImpl = options.spawn || spawn;
  const env = options.env || process.env;
  const logger = options.logger || console;

  function baseArgs(args) {
    return socketName ? ["-L", socketName, ...args] : args;
  }

  function startOutputStream(params = {}) {
    const pane = params.pane || {};
    const paneId = normalizePaneId(params.paneId || pane.paneId || pane.target || pane.id);
    const sessionName = normalizeOptionalString(params.sessionName || pane.sessionName || sessionNameFromPaneKey(pane.paneKey));
    if (!paneId) {
      throw new TmuxControlAdapterError("Terminal stream requires a pane id", { code: "terminal_stream_pane_required" });
    }
    if (!sessionName) {
      throw new TmuxControlAdapterError("Terminal stream requires a tmux session", { code: "terminal_stream_session_required" });
    }

    const args = baseArgs(["-C", "attach-session", "-f", "read-only,ignore-size,active-pane", "-t", sessionName]);
    const child = spawnImpl(tmuxBin, args, {
      env,
      stdio: ["pipe", "pipe", "pipe"],
    });

    let stopped = false;
    let stdoutBuffer = "";
    let stderrBuffer = "";
    let stdoutDecoder = new StringDecoder("utf8");
    const normalizeOutput = createTerminalOutputNormalizer();

    const onData = typeof params.onData === "function" ? params.onData : () => {};
    const onExit = typeof params.onExit === "function" ? params.onExit : () => {};
    const onError = typeof params.onError === "function" ? params.onError : () => {};

    const activatePane = () => {
      writeControlCommand(child, `select-pane -t '${paneId}'`);
      writeControlCommand(child, `refresh-client -A '${paneId}:on'`);
      if (Number.isInteger(params.cols) && Number.isInteger(params.rows) && params.cols > 0 && params.rows > 0) {
        writeControlCommand(child, `refresh-client -C ${params.cols}x${params.rows}`);
      }
    };

    child.stdout?.on("data", (chunk) => {
      stdoutBuffer += stdoutDecoder.write(chunk);
      const lines = stdoutBuffer.split(/\r?\n/);
      stdoutBuffer = lines.pop() || "";
      for (const line of lines) {
        const parsed = parseTmuxControlLine(line);
        if (!parsed) {
          continue;
        }
        if ((parsed.type === "%output" || parsed.type === "%extended-output") && parsed.paneId === paneId) {
          const bytes = normalizeOutput.write(parsed.bytes);
          if (bytes.length) {
            onData(bytes);
          }
        } else if (parsed.type === "%exit") {
          onExit({ reason: parsed.reason || "tmux control client exited" });
        }
      }
    });

    child.stderr?.on("data", (chunk) => {
      stderrBuffer += chunk.toString("utf8");
      if (stderrBuffer.length > 8192) {
        stderrBuffer = stderrBuffer.slice(-8192);
      }
    });

    child.on?.("error", (error) => {
      onError(new TmuxControlAdapterError(error.message, { code: "tmux_control_spawn_failed", cause: error }));
    });

    child.on?.("exit", (code, signal) => {
      if (stopped) {
        return;
      }
      onExit({ code, signal, reason: stderrBuffer.trim() });
    });

    // Delay first commands until spawn listeners are attached; fake spawns in tests also see this.
    queueMicrotask(activatePane);

    return {
      paneId,
      sessionName,
      stop() {
        if (stopped) {
          return;
        }
        stopped = true;
        try {
          writeControlCommand(child, `refresh-client -A '${paneId}:off'`);
          writeControlCommand(child, "detach-client");
        } catch {}
        if (typeof child.kill === "function") {
          try {
            child.kill();
          } catch (error) {
            logger?.debug?.(`[mms-remote] tmux control stop ignored: ${error.message}`);
          }
        }
      },
    };
  }

  return { startOutputStream };
}

function parseTmuxControlLine(line) {
  if (typeof line !== "string" || !line.startsWith("%")) {
    return null;
  }
  if (line.startsWith("%output ")) {
    const match = line.match(/^%output\s+(%\d+)\s+([\s\S]*)$/);
    if (!match) {
      return null;
    }
    return {
      type: "%output",
      paneId: match[1],
      bytes: decodeTmuxControlEscapes(match[2]),
    };
  }
  if (line.startsWith("%extended-output ")) {
    const match = line.match(/^%extended-output\s+(%\d+)\s+.*?\s:\s([\s\S]*)$/);
    if (!match) {
      return null;
    }
    return {
      type: "%extended-output",
      paneId: match[1],
      bytes: decodeTmuxControlEscapes(match[2]),
    };
  }
  if (line.startsWith("%exit")) {
    return { type: "%exit", reason: line.replace(/^%exit\s*/, "") };
  }
  return { type: line.split(/\s+/, 1)[0] };
}

function decodeTmuxControlEscapes(value) {
  const bytes = [];
  for (let index = 0; index < String(value || "").length; index += 1) {
    const ch = value[index];
    if (ch === "\\") {
      const octal = value.slice(index + 1, index + 4);
      if (/^[0-7]{3}$/.test(octal)) {
        bytes.push(Number.parseInt(octal, 8));
        index += 3;
        continue;
      }
      if (index + 1 < value.length) {
        bytes.push(value.charCodeAt(index + 1));
        index += 1;
        continue;
      }
    }
    const encoded = Buffer.from(ch, "utf8");
    for (const byte of encoded) {
      bytes.push(byte);
    }
  }
  return Buffer.from(bytes);
}

function createTerminalOutputNormalizer() {
  const decoder = new StringDecoder("utf8");
  const state = { lastWasCR: false };
  return {
    write(buffer) {
      const text = decoder.write(Buffer.isBuffer(buffer) ? buffer : Buffer.from(buffer || []));
      return Buffer.from(normalizeTerminalOutputText(text, state), "utf8");
    },
    end() {
      const text = decoder.end();
      return Buffer.from(normalizeTerminalOutputText(text, state), "utf8");
    },
  };
}

function normalizeTerminalOutputText(text, state = { lastWasCR: false }) {
  let normalized = "";
  for (const character of String(text || "")) {
    if (character === "\n" && !state.lastWasCR) {
      normalized += "\r";
    }
    normalized += isUnsupportedTerminalScalar(character) ? " " : character;
    state.lastWasCR = character === "\r";
  }
  return normalized;
}

function isUnsupportedTerminalScalar(character) {
  const scalar = character.codePointAt(0);
  return scalar === 0xfffd
    || (scalar >= 0xe000 && scalar <= 0xf8ff)
    || (scalar >= 0xf0000 && scalar <= 0xffffd)
    || (scalar >= 0x100000 && scalar <= 0x10fffd);
}

function writeControlCommand(child, command) {
  if (child?.stdin?.writable === false) {
    return;
  }
  child?.stdin?.write?.(`${command}\n`);
}

function normalizeOptionalString(value) {
  return typeof value === "string" ? value.trim() : "";
}

function normalizePaneId(value) {
  const normalized = normalizeOptionalString(value);
  return normalized.startsWith("%") ? normalized : "";
}

function sessionNameFromPaneKey(value) {
  const normalized = normalizeOptionalString(value);
  const index = normalized.indexOf(":");
  return index > 0 ? normalized.slice(0, index) : "";
}

module.exports = {
  TmuxControlAdapterError,
  createTerminalOutputNormalizer,
  createTmuxControlAdapter,
  decodeTmuxControlEscapes,
  normalizeTerminalOutputText,
  parseTmuxControlLine,
};

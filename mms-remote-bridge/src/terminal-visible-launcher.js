// FILE: terminal-visible-launcher.js
// Purpose: Opens a macOS Terminal.app window attached to a managed tmux pane.
// Layer: Service adapter
// Exports: createTerminalVisibleLauncher, buildTerminalAttachShellCommand
// Depends on: child_process

const { execFile } = require("child_process");

const DEFAULT_TIMEOUT_MS = 8000;

function createTerminalVisibleLauncher(options = {}) {
  const execFileImpl = options.execFile || execFile;
  const platform = options.platform || process.platform;
  const terminalApp = options.terminalApp || "Terminal";
  const timeoutMs = Number.isInteger(options.timeoutMs) ? options.timeoutMs : DEFAULT_TIMEOUT_MS;
  const tmuxBin = options.tmuxBin || "tmux";
  const socketName = normalizeOptionalString(options.socketName);

  async function openPane(pane = {}) {
    if (platform !== "darwin") {
      return {
        ok: false,
        opened: false,
        reason: "unsupported_platform",
      };
    }

    const command = buildTerminalAttachShellCommand({
      pane,
      socketName,
      tmuxBin,
    });
    const script = buildTerminalAppleScript({
      command,
      terminalApp,
    });
    await runOsaScript(execFileImpl, script, timeoutMs);
    return {
      ok: true,
      opened: true,
      app: terminalApp,
      paneId: pane.paneId || pane.id || "",
      sessionName: pane.sessionName || "",
    };
  }

  return {
    openPane,
  };
}

function buildTerminalAttachShellCommand({
  pane = {},
  socketName = "",
  tmuxBin = "tmux",
} = {}) {
  const sessionName = requireNonEmptyString(pane.sessionName, "pane.sessionName");
  const paneId = requireNonEmptyString(pane.paneId || pane.id, "pane.paneId");
  const windowIndex = Number.isInteger(pane.windowIndex) ? pane.windowIndex : 0;
  const cwd = normalizeOptionalString(pane.cwd);
  const tmuxArgs = [];

  if (socketName) {
    tmuxArgs.push("-L", socketName);
  }
  tmuxArgs.push(
    "select-window",
    "-t",
    `${sessionName}:${windowIndex}`,
    ";",
    "select-pane",
    "-t",
    paneId,
    ";",
    "attach-session",
    "-t",
    sessionName
  );

  const attachCommand = `exec ${[tmuxBin, ...tmuxArgs].map(shellQuote).join(" ")}`;
  if (!cwd) {
    return attachCommand;
  }
  return `cd ${shellQuote(cwd)} && ${attachCommand}`;
}

function buildTerminalAppleScript({ command, terminalApp = "Terminal" } = {}) {
  return [
    `tell application ${appleScriptString(terminalApp)}`,
    "  activate",
    `  do script ${appleScriptString(command)}`,
    "end tell",
  ].join("\n");
}

function runOsaScript(execFileImpl, script, timeoutMs) {
  return new Promise((resolve, reject) => {
    execFileImpl(
      "osascript",
      ["-e", script],
      {
        timeout: timeoutMs,
        maxBuffer: 1024 * 1024,
      },
      (error, stdout, stderr) => {
        if (error) {
          const message = stderr?.trim() || error.message || "Failed to open Terminal.app";
          const launchError = new Error(message);
          launchError.code = error.code || "terminal_visible_launch_failed";
          launchError.stderr = stderr || "";
          launchError.stdout = stdout || "";
          reject(launchError);
          return;
        }
        resolve({ stdout, stderr });
      }
    );
  });
}

function requireNonEmptyString(value, name) {
  const normalized = normalizeOptionalString(value);
  if (!normalized) {
    throw new Error(`${name} is required to open a visible terminal`);
  }
  return normalized;
}

function normalizeOptionalString(value) {
  return typeof value === "string" && value.trim() ? value.trim() : "";
}

function shellQuote(value) {
  return `'${String(value).replace(/'/g, "'\\''")}'`;
}

function appleScriptString(value) {
  return `"${String(value)
    .replace(/\\/g, "\\\\")
    .replace(/"/g, "\\\"")
    .replace(/\r/g, "\\r")
    .replace(/\n/g, "\\n")}"`;
}

module.exports = {
  buildTerminalAppleScript,
  buildTerminalAttachShellCommand,
  createTerminalVisibleLauncher,
};

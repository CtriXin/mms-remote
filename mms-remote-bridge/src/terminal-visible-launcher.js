// FILE: terminal-visible-launcher.js
// Purpose: Opens a macOS terminal emulator attached to a managed tmux pane.
// Layer: Service adapter
// Exports: createTerminalVisibleLauncher, buildTerminalAttachShellCommand
// Depends on: child_process, fs

const { execFile } = require("child_process");
const fs = require("fs");

const DEFAULT_TIMEOUT_MS = 8000;
const DEFAULT_VISIBLE_TERMINAL = "auto";
const VISIBLE_TERMINAL_APPS = {
  ghostty: {
    id: "ghostty",
    appName: "Ghostty",
    openAppName: "Ghostty.app",
    candidates: ["/Applications/Ghostty.app"],
  },
  iterm: {
    id: "iterm",
    appName: "iTerm2",
    candidates: ["/Applications/iTerm.app", "/Applications/iTerm2.app"],
  },
  terminal: {
    id: "terminal",
    appName: "Terminal",
    candidates: ["/System/Applications/Utilities/Terminal.app", "/Applications/Utilities/Terminal.app"],
  },
};
const AUTO_TERMINAL_ORDER = ["ghostty", "iterm", "terminal"];

function createTerminalVisibleLauncher(options = {}) {
  const execFileImpl = options.execFile || execFile;
  const platform = options.platform || process.platform;
  const env = options.env || process.env;
  const appExists = options.appExists || defaultAppExists;
  const preferredVisibleApp = normalizeVisibleTerminalApp(
    options.visibleApp || options.terminalApp || env.MMS_REMOTE_VISIBLE_TERMINAL || DEFAULT_VISIBLE_TERMINAL
  );
  const timeoutMs = Number.isInteger(options.timeoutMs) ? options.timeoutMs : DEFAULT_TIMEOUT_MS;
  const tmuxBin = options.tmuxBin || "tmux";
  const socketName = normalizeOptionalString(options.socketName);

  async function openPane(pane = {}, launchOptions = {}) {
    if (platform !== "darwin") {
      return {
        ok: false,
        opened: false,
        reason: "unsupported_platform",
      };
    }

    const visibleApp = resolveVisibleTerminalApp(
      launchOptions.visibleApp || launchOptions.terminalApp || preferredVisibleApp,
      { appExists }
    );
    const command = buildTerminalAttachShellCommand({
      pane,
      socketName,
      tmuxBin,
    });
    const launch = buildVisibleTerminalLaunch({ command, visibleApp });
    await runLaunchCommand(execFileImpl, launch, timeoutMs);
    return {
      ok: true,
      opened: true,
      app: visibleApp.id,
      appName: visibleApp.appName,
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

function buildVisibleTerminalLaunch({ command, visibleApp } = {}) {
  switch (visibleApp?.id) {
    case "ghostty":
      return buildGhosttyLaunch({ command, visibleApp });
    case "iterm":
      return {
        file: "osascript",
        args: ["-e", buildITermAppleScript({ command })],
      };
    case "terminal":
      return {
        file: "osascript",
        args: ["-e", buildTerminalAppleScript({ command, terminalApp: visibleApp.appName })],
      };
    default:
      throw new Error(`Unsupported visible terminal app: ${visibleApp?.id || "unknown"}`);
  }
}

function buildGhosttyLaunch({ command, visibleApp = VISIBLE_TERMINAL_APPS.ghostty } = {}) {
  return {
    file: "osascript",
    args: ["-e", buildGhosttyAppleScript({ command, terminalApp: visibleApp.appName || "Ghostty" })],
  };
}

function buildGhosttyAppleScript({ command, terminalApp = "Ghostty" } = {}) {
  const launchCommand = `/bin/zsh -lc ${shellQuote(command)}`;
  return [
    `tell application ${appleScriptString(terminalApp)}`,
    `  set launchConfig to new surface configuration from {command:${appleScriptString(launchCommand)}, wait after command:true}`,
    "  if (count of windows) > 0 then",
    "    set createdTab to new tab in front window with configuration launchConfig",
    "    select tab createdTab",
    "  else",
    "    set createdWindow to new window with configuration launchConfig",
    "    activate window createdWindow",
    "  end if",
    "  activate",
    "end tell",
  ].join("\n");
}

function buildTerminalAppleScript({ command, terminalApp = "Terminal" } = {}) {
  return [
    `tell application ${appleScriptString(terminalApp)}`,
    "  activate",
    `  do script ${appleScriptString(command)}`,
    "end tell",
  ].join("\n");
}

function buildITermAppleScript({ command } = {}) {
  return [
    'tell application "iTerm2"',
    "  if (count of windows) > 0 then",
    "    tell current window",
    "      create tab with default profile",
    "      tell current session",
    `        write text ${appleScriptString(command)}`,
    "      end tell",
    "    end tell",
    "  else",
    "    set newWindow to (create window with default profile)",
    "    tell current session of newWindow",
    `      write text ${appleScriptString(command)}`,
    "    end tell",
    "  end if",
    "  activate",
    "end tell",
  ].join("\n");
}

function resolveVisibleTerminalApp(value = DEFAULT_VISIBLE_TERMINAL, { appExists = defaultAppExists } = {}) {
  const normalized = normalizeVisibleTerminalApp(value);
  if (normalized !== "auto") {
    return VISIBLE_TERMINAL_APPS[normalized];
  }

  for (const appId of AUTO_TERMINAL_ORDER) {
    const app = VISIBLE_TERMINAL_APPS[appId];
    if (app.candidates.some(appExists)) {
      return app;
    }
  }

  return VISIBLE_TERMINAL_APPS.terminal;
}

function normalizeVisibleTerminalApp(value) {
  const normalized = normalizeOptionalString(value).toLowerCase();
  const aliases = new Map([
    ["", "auto"],
    ["auto", "auto"],
    ["ghostty", "ghostty"],
    ["iterm", "iterm"],
    ["iterm2", "iterm"],
    ["iterm.app", "iterm"],
    ["iterm2.app", "iterm"],
    ["terminal", "terminal"],
    ["terminal.app", "terminal"],
  ]);
  const appId = aliases.get(normalized);
  if (!appId) {
    throw new Error("Visible terminal app must be auto, ghostty, iterm, or terminal");
  }
  return appId;
}

function defaultAppExists(candidatePath) {
  return fs.existsSync(candidatePath);
}

function runLaunchCommand(execFileImpl, launch, timeoutMs) {
  return new Promise((resolve, reject) => {
    execFileImpl(
      launch.file,
      launch.args,
      {
        timeout: timeoutMs,
        maxBuffer: 1024 * 1024,
      },
      (error, stdout, stderr) => {
        if (error) {
          const message = stderr?.trim() || error.message || "Failed to open visible terminal";
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
    .replace(/"/g, '\\"')
    .replace(/\r/g, "\\r")
    .replace(/\n/g, "\\n")}"`;
}

module.exports = {
  buildGhosttyAppleScript,
  buildGhosttyLaunch,
  buildITermAppleScript,
  buildTerminalAppleScript,
  buildTerminalAttachShellCommand,
  buildVisibleTerminalLaunch,
  createTerminalVisibleLauncher,
  normalizeVisibleTerminalApp,
  resolveVisibleTerminalApp,
};

// FILE: mmschat-live-actions.js
// Purpose: Runs explicitly guarded MMSChat live actions through existing tmux/terminal adapters.
// Layer: Service adapter
// Exports: createMMSChatLiveActionRunner plus live action guard helpers.
// Depends on: path, ./tmux-adapter, ./terminal-visible-launcher, ./mmschat-protocol

const path = require("path");
const { createTerminalVisibleLauncher } = require("./terminal-visible-launcher");
const { createTmuxAdapter } = require("./tmux-adapter");
const { MMSCHAT_ERROR_CODES, MMSCHAT_FEATURES } = require("./mmschat-protocol");

const LIVE_ACTION_METHODS = Object.freeze([
  "mmschat/resume",
  "mmschat/send",
  "mmschat/openVisible",
]);

function createMMSChatLiveActionRunner(options = {}) {
  const adapter = options.adapter || createTmuxAdapter(options.tmux || {});
  const visibleLauncher = options.visibleLauncher || createTerminalVisibleLauncher({
    ...(options.visibleTerminal || {}),
    socketName: options.tmux?.socketName || options.visibleTerminal?.socketName || "",
    tmuxBin: options.tmux?.tmuxBin || options.visibleTerminal?.tmuxBin || undefined,
  });
  const mmsBin = readOptionalString(options.mmsBin) || "mms";

  return {
    async resume(session) {
      if (session.tmuxPaneId) {
        const pane = await resolveLivePane(adapter, session.tmuxPaneId);
        return {
          processAlive: true,
          resumeStarted: false,
          tmuxPaneId: pane.paneId,
          tmuxSessionName: pane.sessionName,
        };
      }

      if (!session.nativeClaudeSessionId) {
        throw createLiveActionError(
          MMSCHAT_ERROR_CODES.resumeFailed,
          "MMSChat resume requires a native Claude session id."
        );
      }

      const created = await adapter.createSession({
        command: buildResumeCommand(session, { mmsBin }),
        cwd: normalizeAbsoluteCwd(session.cwd),
        name: buildTmuxSessionName(session),
      });

      return {
        processAlive: true,
        resumeStarted: true,
        tmuxPaneId: created.paneId,
        tmuxSessionName: created.sessionName,
      };
    },

    async send(session, params = {}) {
      const pane = await resolveLivePane(adapter, session.tmuxPaneId);
      await adapter.sendText({ paneId: pane.paneId, text: params.text });
      await adapter.sendKey({ paneId: pane.paneId, key: "Enter" });
      return {
        processAlive: true,
        sent: true,
        tmuxPaneId: pane.paneId,
        tmuxSessionName: pane.sessionName,
      };
    },

    async openVisible(session, params = {}) {
      const pane = await resolveLivePane(adapter, session.tmuxPaneId);
      const visible = await visibleLauncher.openPane(pane, { visibleApp: params.visibleApp });
      return {
        opened: true,
        tmuxPaneId: pane.paneId,
        tmuxSessionName: pane.sessionName,
        visibleApp: visible?.visibleApp || params.visibleApp || null,
      };
    },
  };
}

function buildLiveActionsState(env = process.env) {
  const enabled = env?.[MMSCHAT_FEATURES.liveActionsEnvName] === "1";
  return {
    enabled,
    envName: MMSCHAT_FEATURES.liveActionsEnvName,
    requiresConfirmation: true,
    supportedMethods: LIVE_ACTION_METHODS,
    guard: `${MMSCHAT_FEATURES.liveActionsEnvName}=1 + confirmLiveAction=true`,
  };
}

function isLiveActionAuthorized(params = {}, env = process.env) {
  return buildLiveActionsState(env).enabled && params.confirmLiveAction === true;
}

function buildLiveActionDisabledResult(action, env = process.env) {
  return {
    accepted: false,
    disabled: true,
    errorCode: MMSCHAT_ERROR_CODES.sendDisabled,
    action,
    liveActions: buildLiveActionsState(env),
  };
}

async function resolveLivePane(adapter, tmuxPaneId) {
  if (!tmuxPaneId) {
    throw createLiveActionError(
      MMSCHAT_ERROR_CODES.paneDead,
      "MMSChat live action requires a tmux pane. Resume the session first."
    );
  }

  const pane = await adapter.findPane(tmuxPaneId);
  if (pane.dead) {
    throw createLiveActionError(MMSCHAT_ERROR_CODES.paneDead, `MMSChat pane is dead: ${tmuxPaneId}`);
  }
  return pane;
}

function buildResumeCommand(session, { mmsBin }) {
  const argv = [mmsBin, "claude"];
  if (session.provider) {
    argv.push("--provider", session.provider);
  }
  if (session.model) {
    argv.push("--model", session.model);
  }
  argv.push("--resume", session.nativeClaudeSessionId);
  return argv.map(shellQuote).join(" ");
}

function buildTmuxSessionName(session) {
  const project = readOptionalString(session.project) || path.basename(readOptionalString(session.cwd) || "mmschat");
  const nativeId = readOptionalString(session.nativeClaudeSessionId) || session.mmschatId || "session";
  const raw = `mmschat-${project}-${nativeId.slice(0, 8)}`;
  return raw.replace(/[^A-Za-z0-9_.-]+/g, "-").replace(/^-+/, "m").slice(0, 80) || "mmschat-live";
}

function normalizeAbsoluteCwd(value) {
  const cwd = readOptionalString(value);
  return cwd && path.isAbsolute(cwd) ? cwd : process.cwd();
}

function shellQuote(value) {
  const text = String(value || "");
  if (/^[A-Za-z0-9_@%+=:,./-]+$/.test(text)) {
    return text;
  }
  return `'${text.replace(/'/g, `'"'"'`)}'`;
}

function createLiveActionError(errorCode, message) {
  const error = new Error(message);
  error.errorCode = errorCode;
  return error;
}

function readOptionalString(value) {
  return typeof value === "string" && value.trim() ? value.trim() : null;
}

module.exports = {
  buildLiveActionDisabledResult,
  buildLiveActionsState,
  createMMSChatLiveActionRunner,
  isLiveActionAuthorized,
};

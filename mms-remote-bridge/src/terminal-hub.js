// FILE: terminal-hub.js
// Purpose: Coordinates managed terminal pane RPC over tmux.
// Layer: Service coordinator
// Exports: createTerminalHub, handleTerminalMethod, handleTerminalRequest
// Depends on: ./tmux-adapter, ./terminal-visible-launcher

const { createTmuxAdapter, TmuxAdapterError } = require("./tmux-adapter");
const { createTerminalVisibleLauncher } = require("./terminal-visible-launcher");

function createTerminalHub(options = {}) {
  const adapter = options.adapter || createTmuxAdapter(options.tmux || {});
  const visibleLauncher = options.visibleLauncher || createTerminalVisibleLauncher({
    ...(options.visibleTerminal || {}),
    socketName: options.tmux?.socketName || options.visibleTerminal?.socketName || "",
    tmuxBin: options.tmux?.tmuxBin || options.visibleTerminal?.tmuxBin || undefined,
  });

  async function list() {
    const [tmuxVersion, tree] = await Promise.all([
      adapter.version().catch(() => "tmux unavailable"),
      adapter.listAll(),
    ]);
    return {
      tmuxVersion,
      sessions: tree.sessions,
      windows: tree.windows,
      panes: tree.panes,
    };
  }

  async function create(params = {}) {
    const cwd = params.cwd || process.cwd();
    let created;
    if (params.kind === "window") {
      created = await adapter.createWindow({
        session: params.session || params.sessionName,
        name: params.name,
        cwd,
        command: params.command,
      });
    } else if (params.kind === "split") {
      created = await adapter.splitPane({
        target: params.target || params.paneId || params.paneKey,
        cwd,
        command: params.command,
        horizontal: Boolean(params.horizontal),
      });
    } else {
      created = await adapter.createSession({
        name: params.name || params.sessionName,
        cwd,
        command: params.command,
        cols: params.cols,
        rows: params.rows,
      });
    }
    const terminalList = await list();
    const result = {
      created,
      ...terminalList,
    };

    if (params.openVisible) {
      result.visibleTerminal = await openVisibleTerminalForCreatedPane({
        created,
        terminalList,
      });
    }

    return result;
  }

  async function snapshot(params = {}) {
    const pane = await resolvePane(params.paneId || params.paneKey || params.target);
    const capture = await adapter.capturePane({
      target: pane.paneId,
      start: Number.isInteger(params.start) ? params.start : -2000,
      preserveAnsi: Boolean(params.preserveAnsi),
      joinWrapped: params.joinWrapped !== false,
    });
    return {
      pane,
      content: capture.content,
      capturedAt: capture.capturedAt,
    };
  }

  async function input(params = {}) {
    const pane = await resolvePane(params.paneId || params.paneKey || params.target);
    await adapter.sendInput({ paneId: pane.paneId, input: params.input, text: params.text, key: params.key });
    return { ok: true, paneId: pane.paneId };
  }

  async function resize(params = {}) {
    const pane = await resolvePane(params.paneId || params.paneKey || params.target);
    return adapter.resizePane({ paneId: pane.paneId, cols: params.cols, rows: params.rows });
  }

  async function kill(params = {}) {
    if (params.session || params.sessionName) {
      return adapter.killSession({ session: params.session || params.sessionName });
    }
    const pane = await resolvePane(params.paneId || params.paneKey || params.target);
    return adapter.killPane({ paneId: pane.paneId });
  }

  async function attach(params = {}) {
    return snapshot(params);
  }

  async function detach(params = {}) {
    const pane = await resolvePane(params.paneId || params.paneKey || params.target);
    return { ok: true, paneId: pane.paneId };
  }

  async function openVisible(params = {}) {
    const pane = await resolvePane(params.paneId || params.paneKey || params.target);
    return visibleLauncher.openPane(pane);
  }

  async function resolvePane(target) {
    if (!target) {
      throw new TmuxAdapterError("Terminal pane id is required", { code: "terminal_pane_required" });
    }
    return adapter.findPane(String(target));
  }

  async function openVisibleTerminalForCreatedPane({ created, terminalList }) {
    const pane = findCreatedPane({ created, terminalList });
    if (!pane) {
      throw new TmuxAdapterError("Created terminal pane could not be resolved for visible launch", {
        code: "terminal_created_pane_not_found",
      });
    }
    return visibleLauncher.openPane(pane);
  }

  async function handleMethod(method, params = {}) {
    switch (method) {
      case "terminal/list":
        return list();
      case "terminal/create":
        return create(params);
      case "terminal/snapshot":
        return snapshot(params);
      case "terminal/attach":
        return attach(params);
      case "terminal/detach":
        return detach(params);
      case "terminal/openVisible":
        return openVisible(params);
      case "terminal/input":
        return input(params);
      case "terminal/resize":
        return resize(params);
      case "terminal/kill":
        return kill(params);
      case "terminal/status":
        return { ok: true, ...(await list()) };
      default:
        throw new TmuxAdapterError(`Unsupported terminal method: ${method}`, { code: "unsupported_terminal_method" });
    }
  }

  return {
    adapter,
    attach,
    create,
    detach,
    handleMethod,
    input,
    kill,
    list,
    openVisible,
    resize,
    snapshot,
    visibleLauncher,
  };
}

function findCreatedPane({ created = {}, terminalList = {} } = {}) {
  const panes = terminalList.panes || [];
  if (created.paneId) {
    const byPaneId = panes.find((pane) => pane.paneId === created.paneId || pane.id === created.paneId);
    if (byPaneId) {
      return byPaneId;
    }
  }
  if (created.sessionName) {
    return panes.find((pane) => pane.sessionName === created.sessionName) || null;
  }
  return null;
}

async function handleTerminalMethod(method, params = {}, options = {}) {
  const hub = options.hub || createTerminalHub(options);
  return hub.handleMethod(method, params);
}

function handleTerminalRequest(rawMessage, sendResponse, options = {}) {
  const message = safeParseJSON(rawMessage);
  if (!message || typeof message.method !== "string" || !message.method.startsWith("terminal/")) {
    return false;
  }

  handleTerminalMethod(message.method, message.params || {}, options)
    .then((result) => {
      sendResponse(JSON.stringify({ id: message.id ?? null, result }));
    })
    .catch((error) => {
      sendResponse(JSON.stringify({
        id: message.id ?? null,
        error: {
          code: -32000,
          message: error.message || "Terminal request failed",
          data: {
            errorCode: error.code || "terminal_error",
          },
        },
      }));
    });
  return true;
}

function safeParseJSON(rawMessage) {
  try {
    return JSON.parse(rawMessage);
  } catch {
    return null;
  }
}

module.exports = {
  createTerminalHub,
  findCreatedPane,
  handleTerminalMethod,
  handleTerminalRequest,
};

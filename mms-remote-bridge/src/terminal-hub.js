// FILE: terminal-hub.js
// Purpose: Coordinates managed terminal pane RPC over tmux.
// Layer: Service coordinator
// Exports: createTerminalHub, handleTerminalMethod, handleTerminalRequest
// Depends on: ./tmux-adapter

const { createTmuxAdapter, TmuxAdapterError } = require("./tmux-adapter");

function createTerminalHub(options = {}) {
  const adapter = options.adapter || createTmuxAdapter(options.tmux || {});

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
    return {
      created,
      ...(await list()),
    };
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

  async function resolvePane(target) {
    if (!target) {
      throw new TmuxAdapterError("Terminal pane id is required", { code: "terminal_pane_required" });
    }
    return adapter.findPane(String(target));
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
    resize,
    snapshot,
  };
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
          code: error.code || "terminal_error",
          message: error.message || "Terminal request failed",
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
  handleTerminalMethod,
  handleTerminalRequest,
};

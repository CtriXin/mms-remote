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
    const sortedTree = sortTerminalTreeByRecentPane(tree);
    return {
      tmuxVersion,
      sessions: sortedTree.sessions,
      windows: sortedTree.windows,
      panes: sortedTree.panes,
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
        visibleApp: params.visibleApp || params.terminalApp,
      }).catch(formatVisibleTerminalFailure);
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
    return visibleLauncher.openPane(pane, {
      visibleApp: params.visibleApp || params.terminalApp,
    });
  }

  async function resolvePane(target) {
    if (!target) {
      throw new TmuxAdapterError("Terminal pane id is required", { code: "terminal_pane_required" });
    }
    return adapter.findPane(String(target));
  }

  async function openVisibleTerminalForCreatedPane({ created, terminalList, visibleApp }) {
    const pane = findCreatedPane({ created, terminalList });
    if (!pane) {
      throw new TmuxAdapterError("Created terminal pane could not be resolved for visible launch", {
        code: "terminal_created_pane_not_found",
      });
    }
    return visibleLauncher.openPane(pane, { visibleApp });
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

function sortTerminalTreeByRecentPane(tree = {}) {
  const sessions = [...(tree.sessions || [])].sort(compareSessionsByRecent);
  const sessionCreatedAtByName = new Map(sessions.map((session) => [session.name, toFiniteNumber(session.createdAt)]));
  const windows = [...(tree.windows || [])].sort((lhs, rhs) => (
    compareNumbersDesc(tmuxObjectIdNumber(lhs.id), tmuxObjectIdNumber(rhs.id))
    || compareNumbersDesc(sessionCreatedAtByName.get(lhs.sessionName), sessionCreatedAtByName.get(rhs.sessionName))
    || compareNumbersDesc(lhs.index, rhs.index)
    || compareStrings(lhs.windowKey, rhs.windowKey)
  ));
  const panes = [...(tree.panes || [])].sort((lhs, rhs) => (
    compareNumbersDesc(tmuxObjectIdNumber(lhs.paneId || lhs.id), tmuxObjectIdNumber(rhs.paneId || rhs.id))
    || compareNumbersDesc(sessionCreatedAtByName.get(lhs.sessionName), sessionCreatedAtByName.get(rhs.sessionName))
    || compareNumbersDesc(lhs.windowIndex, rhs.windowIndex)
    || compareNumbersDesc(lhs.paneIndex, rhs.paneIndex)
    || compareStrings(lhs.paneKey, rhs.paneKey)
  ));

  return { sessions, windows, panes };
}

function compareSessionsByRecent(lhs, rhs) {
  return compareNumbersDesc(toFiniteNumber(lhs.createdAt), toFiniteNumber(rhs.createdAt))
    || compareNumbersDesc(tmuxObjectIdNumber(lhs.id), tmuxObjectIdNumber(rhs.id))
    || compareStrings(lhs.name, rhs.name);
}

function compareNumbersDesc(lhs, rhs) {
  const left = toFiniteNumber(lhs);
  const right = toFiniteNumber(rhs);
  if (left === right) {
    return 0;
  }
  return left > right ? -1 : 1;
}

function compareStrings(lhs, rhs) {
  return String(lhs || "").localeCompare(String(rhs || ""));
}

function tmuxObjectIdNumber(value) {
  const match = String(value || "").match(/\d+/);
  return match ? Number.parseInt(match[0], 10) : Number.NEGATIVE_INFINITY;
}

function toFiniteNumber(value) {
  const number = Number(value);
  return Number.isFinite(number) ? number : Number.NEGATIVE_INFINITY;
}

function formatVisibleTerminalFailure(error) {
  return {
    ok: false,
    opened: false,
    error: {
      code: String(error?.code || "terminal_visible_launch_failed"),
      message: error?.message || "Failed to open the visible terminal on Mac.",
    },
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
  formatVisibleTerminalFailure,
  handleTerminalMethod,
  handleTerminalRequest,
  sortTerminalTreeByRecentPane,
};

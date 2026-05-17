// FILE: terminal-hub.js
// Purpose: Coordinates managed terminal pane RPC over tmux.
// Layer: Service coordinator
// Exports: createTerminalHub, handleTerminalMethod, handleTerminalRequest
// Depends on: ./tmux-adapter, ./terminal-visible-launcher, ./terminal-stream-hub

const { createTmuxAdapter, TmuxAdapterError } = require("./tmux-adapter");
const { createTerminalStreamHub } = require("./terminal-stream-hub");
const { createTerminalVisibleLauncher } = require("./terminal-visible-launcher");

function createTerminalHub(options = {}) {
  const adapter = options.adapter || createTmuxAdapter(options.tmux || {});
  const visibleLauncher = options.visibleLauncher || createTerminalVisibleLauncher({
    ...(options.visibleTerminal || {}),
    socketName: options.tmux?.socketName || options.visibleTerminal?.socketName || "",
    tmuxBin: options.tmux?.tmuxBin || options.visibleTerminal?.tmuxBin || undefined,
  });
  const streamHub = options.streamHub || createTerminalStreamHub({
    ...(options.stream || {}),
    tmux: {
      ...(options.tmux || {}),
      ...(options.stream?.tmux || {}),
    },
    capturePane: (pane, params) => capturePaneSnapshot(pane, params),
  });

  async function list() {
    const [tmuxVersion, tree] = await Promise.all([
      adapter.version().catch(() => "tmux unavailable"),
      adapter.listAll(),
    ]);
    const sortedTree = decorateTerminalTree(sortTerminalTreeByRecentPane(tree));
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
    const createdPane = findCreatedPane({ created, terminalList });
    const result = {
      created,
      ...(createdPane ? { createdPane, selectedPane: createdPane } : {}),
      ...terminalList,
    };

    if (params.openVisible) {
      result.visibleTerminal = await openVisibleTerminalForCreatedPane({
        created,
        terminalList,
        createdPane,
        visibleApp: params.visibleApp || params.terminalApp,
      }).catch(formatVisibleTerminalFailure);
    }

    return result;
  }

  async function snapshot(params = {}) {
    const pane = await resolvePane(params.paneId || params.paneKey || params.target);
    const capture = await capturePaneSnapshot(pane, params);
    return {
      pane: decoratePane(pane),
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

  async function streamStart(params = {}, context = {}) {
    const pane = await resolvePane(params.paneId || params.paneKey || params.target);
    return streamHub.start({
      ...params,
      pane: decoratePane(pane),
      paneId: pane.paneId,
    }, context);
  }

  async function streamStop(params = {}) {
    return streamHub.stop(params);
  }

  async function streamReplay(params = {}) {
    return streamHub.replay(params);
  }

  async function streamStatus(params = {}) {
    return streamHub.status(params);
  }

  async function resolvePane(target) {
    const normalizedTarget = normalizePaneTarget(target);
    if (!normalizedTarget) {
      const fallbackPane = await newestPane();
      if (fallbackPane) {
        return fallbackPane;
      }
      throw new TmuxAdapterError("Terminal pane id is required", { code: "terminal_pane_required" });
    }
    const ordinalPane = await resolveOrdinalFallbackPane(normalizedTarget);
    if (ordinalPane) {
      return ordinalPane;
    }
    try {
      return await adapter.findPane(normalizedTarget);
    } catch (error) {
      throw error;
    }
  }

  async function newestPane() {
    const terminalList = await list();
    return terminalList.panes.find((pane) => paneCaptureTarget(pane)) || terminalList.panes[0] || null;
  }

  async function resolveOrdinalFallbackPane(target) {
    const ordinalIndex = syntheticOrdinalPaneIndex(target);
    if (ordinalIndex == null) {
      return null;
    }
    const terminalList = await list();
    return terminalList.panes[ordinalIndex] || null;
  }

  async function capturePaneSnapshot(pane, params = {}) {
    const captureTarget = paneCaptureTarget(pane);
    if (!captureTarget) {
      const fallbackPane = await newestPane();
      const fallbackTarget = paneCaptureTarget(fallbackPane);
      if (fallbackTarget) {
        return captureWithTarget(fallbackTarget, params);
      }
    }
    try {
      return await captureWithTarget(captureTarget, params);
    } catch (error) {
      if (error?.code !== "invalid_terminal_target") {
        throw error;
      }
      const fallbackPane = await newestPane();
      const fallbackTarget = paneCaptureTarget(fallbackPane);
      if (!fallbackTarget || fallbackTarget === captureTarget) {
        throw error;
      }
      return captureWithTarget(fallbackTarget, params);
    }
  }

  function captureWithTarget(target, params = {}) {
    const viewportOnly = params.viewportOnly === true;
    return adapter.capturePane({
      target,
      viewportOnly,
      start: captureStart(params, viewportOnly),
      end: captureEnd(params, viewportOnly),
      preserveAnsi: Boolean(params.preserveAnsi),
      joinWrapped: params.joinWrapped !== false,
      maxBuffer: Number.isInteger(params.maxBuffer) ? params.maxBuffer : undefined,
    });
  }

  function captureStart(params = {}, viewportOnly = false) {
    if (viewportOnly) {
      return "visible";
    }
    if (params.historyStart === "-" || params.start === "-") {
      return "-";
    }
    if (Number.isInteger(params.historyStart)) {
      return params.historyStart;
    }
    if (Number.isInteger(params.start)) {
      return params.start;
    }
    return -2000;
  }

  function captureEnd(params = {}, viewportOnly = false) {
    if (viewportOnly) {
      return undefined;
    }
    if (params.end === "-") {
      return "-";
    }
    if (Number.isInteger(params.end)) {
      return params.end;
    }
    return undefined;
  }

  async function openVisibleTerminalForCreatedPane({ created, terminalList, createdPane, visibleApp }) {
    const pane = createdPane || findCreatedPane({ created, terminalList });
    if (!pane) {
      throw new TmuxAdapterError("Created terminal pane could not be resolved for visible launch", {
        code: "terminal_created_pane_not_found",
      });
    }
    return visibleLauncher.openPane(pane, { visibleApp });
  }

  async function handleMethod(method, params = {}, context = {}) {
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
      case "terminal/stream/start":
      case "terminal/stre/start":
        return streamStart(params, context);
      case "terminal/stream/stop":
      case "terminal/stre/stop":
        return streamStop(params);
      case "terminal/stream/replay":
      case "terminal/stre/replay":
        return streamReplay(params);
      case "terminal/stream/status":
      case "terminal/stre/status":
        return streamStatus(params);
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
    stopAllStreams: streamHub.stopAll,
    streamHub,
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

function decorateTerminalTree(tree = {}) {
  return {
    sessions: tree.sessions || [],
    windows: tree.windows || [],
    panes: (tree.panes || []).map(decoratePane),
  };
}

function decoratePane(pane = {}) {
  const paneId = String(pane.paneId || pane.id || "");
  const paneKey = String(pane.paneKey || "");
  const sessionName = String(pane.sessionName || "");
  const windowIndex = Number.isFinite(Number(pane.windowIndex)) ? Number(pane.windowIndex) : 0;
  const paneIndex = Number.isFinite(Number(pane.paneIndex)) ? Number(pane.paneIndex) : 0;
  const target = String(pane.target || paneId || paneKey || "");
  return {
    ...pane,
    id: String(pane.id || paneId || target || paneKey),
    paneId,
    paneKey,
    target,
    requestTarget: target || paneKey,
    paneAddress: paneKey || (sessionName ? `${sessionName}:${windowIndex}.${paneIndex}` : ""),
    pane_id: paneId,
    pane_key: paneKey,
    session_id: String(pane.sessionId || ""),
    session_name: sessionName,
    window_id: String(pane.windowId || ""),
    window_index: windowIndex,
    window_name: String(pane.windowName || ""),
    pane_index: paneIndex,
    pane_title: String(pane.title || ""),
    pane_current_command: String(pane.currentCommand || ""),
    pane_current_path: String(pane.cwd || ""),
    pane_width: Number.isFinite(Number(pane.cols)) ? Number(pane.cols) : 0,
    pane_height: Number.isFinite(Number(pane.rows)) ? Number(pane.rows) : 0,
    pane_active: Boolean(pane.active),
    pane_dead: Boolean(pane.dead),
    fields: [
      String(pane.sessionId || ""),
      sessionName,
      String(pane.windowId || ""),
      String(windowIndex),
      String(pane.windowName || ""),
      paneId,
      String(paneIndex),
      String(pane.title || ""),
      String(pane.currentCommand || ""),
      String(pane.cwd || ""),
      String(Number.isFinite(Number(pane.cols)) ? Number(pane.cols) : 0),
      String(Number.isFinite(Number(pane.rows)) ? Number(pane.rows) : 0),
      pane.active ? "1" : "0",
      pane.dead ? "1" : "0",
    ],
  };
}

function normalizePaneTarget(target) {
  const value = String(target || "").trim();
  if (!value || value === "unknown" || value === ":" || value === ":." || value === "::") {
    return "";
  }
  if (value.startsWith(":") || value.endsWith(":") || value.endsWith(".")) {
    return "";
  }
  return value;
}

function paneCaptureTarget(pane = {}) {
  return normalizePaneTarget(
    pane.paneId || pane.target || pane.requestTarget || pane.paneKey || pane.paneAddress || pane.id
  );
}

function syntheticOrdinalPaneIndex(target) {
  const match = String(target || "").trim().match(/^mms-(\d+):\d+\.\d+$/);
  if (!match) {
    return null;
  }
  const ordinal = Number.parseInt(match[1], 10);
  return Number.isInteger(ordinal) && ordinal > 0 ? ordinal - 1 : null;
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
  return hub.handleMethod(method, params, options);
}

function handleTerminalRequest(rawMessage, sendResponse, options = {}) {
  const message = safeParseJSON(rawMessage);
  if (!message || typeof message.method !== "string" || !message.method.startsWith("terminal/")) {
    return false;
  }

  const logger = options.logger || console;
  logTerminalRpcRequest(logger, message.method, message.params || {});
  const sendNotification = (method, params) => {
    sendResponse(JSON.stringify({ method, params }));
  };
  handleTerminalMethod(message.method, message.params || {}, { ...options, sendNotification })
    .then((result) => {
      logTerminalRpcResult(logger, message.method, result);
      sendResponse(JSON.stringify({ id: message.id ?? null, result }));
    })
    .catch((error) => {
      logTerminalRpcError(logger, message.method, error);
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

function logTerminalRpcRequest(logger, method, params) {
  if (!logger || typeof logger.log !== "function" || method === "terminal/list" || method === "terminal/status") {
    return;
  }
  const target = normalizePaneTarget(params?.paneId || params?.paneKey || params?.target);
  logger.log(`[mms-remote] ${method} request target=${target || "(empty)"}`);
}

function logTerminalRpcResult(logger, method, result) {
  if (!logger || typeof logger.log !== "function") {
    return;
  }
  if (method === "terminal/attach" || method === "terminal/snapshot") {
    logger.log(
      `[mms-remote] ${method} ok target=${normalizePaneTarget(result?.pane?.requestTarget || result?.pane?.paneId || result?.pane?.target) || "(empty)"} content=${String(result?.content || "").length}`
    );
    return;
  }
  if (method === "terminal/list" || method === "terminal/status" || method === "terminal/create") {
    logger.log(
      `[mms-remote] ${method} ok sessions=${countArray(result?.sessions)} windows=${countArray(result?.windows)} panes=${countArray(result?.panes)}`
    );
    return;
  }
  logger.log(`[mms-remote] ${method} ok`);
}

function logTerminalRpcError(logger, method, error) {
  if (!logger || typeof logger.error !== "function") {
    return;
  }
  logger.error(`[mms-remote] ${method} failed code=${error?.code || "terminal_error"} message=${error?.message || "Terminal request failed"}`);
}

function countArray(value) {
  return Array.isArray(value) ? value.length : 0;
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
  syntheticOrdinalPaneIndex,
};

// FILE: terminal-stream-hub.js
// Purpose: Coordinates terminal stream lifecycle and JSON-RPC notifications.
// Layer: Service coordinator
// Exports: createTerminalStreamHub
// Depends on: ./terminal-protocol, ./tmux-control-adapter

const {
  TERMINAL_STREAM_EVENT_METHOD,
  TerminalStreamMessageTypes,
  createTerminalStreamProtocol,
} = require("./terminal-protocol");
const { createTmuxControlAdapter, normalizeTerminalOutputBuffer } = require("./tmux-control-adapter");

function createTerminalStreamHub(options = {}) {
  const protocol = options.protocol || createTerminalStreamProtocol(options.protocolOptions || {});
  const controlAdapter = options.controlAdapter || createTmuxControlAdapter(options.tmux || {});
  const capturePane = options.capturePane;
  const streams = new Map();
  const streamsByPaneId = new Map();

  async function start(params = {}, context = {}) {
    const pane = params.pane || {};
    const paneId = pane.paneId || pane.target || params.paneId;
    const streamId = params.streamId || protocol.createStreamId();
    const sendNotification = notificationSender(context.sendNotification);
    const existingStreamId = streamsByPaneId.get(paneId);
    const shouldReplayOnStart = params.replay !== false && typeof capturePane === "function";
    if (existingStreamId) {
      await stop({ streamId: existingStreamId });
    }

    const state = {
      streamId,
      paneId,
      pane,
      seq: 0,
      sendNotification,
      status: "starting",
      startedAt: new Date().toISOString(),
      bytesSent: 0,
      chunksSent: 0,
      adapterStream: null,
      heartbeatTimer: null,
      isReplaying: shouldReplayOnStart,
      replayBuffer: [],
      replayMirrorText: "",
      replayViewportOnly: params.replayViewportOnly === true,
      replayStart: replayStart(params),
      replayEnd: replayEnd(params),
      replayMaxBuffer: replayMaxBuffer(params),
    };
    streams.set(streamId, state);
    streamsByPaneId.set(paneId, streamId);

    state.adapterStream = controlAdapter.startOutputStream({
      pane,
      paneId,
      cols: params.cols,
      rows: params.rows,
      onData: (bytes) => emitOutput(state, bytes),
      onExit: (event) => emitExit(state, event),
      onError: (error) => emitError(state, error),
    });

    state.status = "ready";
    emit(state, protocol.makeReady({
      streamId,
      paneId,
      seq: nextSeq(state),
      cols: params.cols,
      rows: params.rows,
    }));

    if (shouldReplayOnStart) {
      await replay({
        streamId,
        reset: true,
        viewportOnly: state.replayViewportOnly,
      }).catch((error) => emitError(state, error));
    }

    state.heartbeatTimer = setInterval(() => {
      if (streams.has(streamId)) {
        emit(state, protocol.makeMessage(TerminalStreamMessageTypes.HEARTBEAT, {
          streamId,
          paneId,
          seq: nextSeq(state),
          extra: { status: state.status },
        }));
      }
    }, options.heartbeatMs || 15_000);
    state.heartbeatTimer.unref?.();

    return { ok: true, streamId, paneId, status: state.status };
  }

  async function stop(params = {}) {
    const streamId = params.streamId || streamsByPaneId.get(params.paneId);
    const state = streams.get(streamId);
    if (!state) {
      return { ok: true, stopped: false, streamId: streamId || "" };
    }
    stopState(state, { reason: "stopped", notify: params.notify !== false });
    return { ok: true, stopped: true, streamId: state.streamId };
  }

  async function replay(params = {}) {
    const state = streams.get(params.streamId) || streams.get(streamsByPaneId.get(params.paneId));
    if (!state) {
      return { ok: false, replayed: false, reason: "stream_not_found" };
    }
    if (typeof capturePane !== "function") {
      return { ok: false, replayed: false, reason: "capture_unavailable" };
    }
    state.isReplaying = true;
    try {
      emit(state, protocol.makeMessage(TerminalStreamMessageTypes.REPLAY_START, {
        streamId: state.streamId,
        paneId: state.paneId,
        seq: nextSeq(state),
        extra: { reset: params.reset !== false },
      }));
      const capture = await capturePane(state.pane, {
        preserveAnsi: true,
        joinWrapped: false,
        viewportOnly: params.viewportOnly === true || state.replayViewportOnly === true,
        start: replayStart(params, state.replayStart),
        end: replayEnd(params, state.replayEnd),
        maxBuffer: replayMaxBuffer(params, state.replayMaxBuffer),
      });
      const content = normalizeTerminalOutputBuffer(Buffer.from(`${capture.content || ""}\r\n`, "utf8"));
      state.replayMirrorText = normalizeReplayMirrorText(content);
      if (content.length > 2) {
        emitOutput(state, content, { replay: true });
      }
      emit(state, protocol.makeMessage(TerminalStreamMessageTypes.REPLAY_END, {
        streamId: state.streamId,
        paneId: state.paneId,
        seq: nextSeq(state),
        extra: { capturedAt: capture.capturedAt || new Date().toISOString() },
      }));
    } finally {
      state.isReplaying = false;
      flushReplayBuffer(state);
    }
    return { ok: true, replayed: true, streamId: state.streamId };
  }

  function status(params = {}) {
    const streamId = params.streamId || streamsByPaneId.get(params.paneId);
    if (streamId) {
      const state = streams.get(streamId);
      return state ? summarizeStream(state) : { ok: false, streamId, status: "missing" };
    }
    return { ok: true, streams: [...streams.values()].map(summarizeStream) };
  }

  function stopAll(params = {}) {
    const states = [...streams.values()];
    for (const state of states) {
      stopState(state, {
        reason: params.reason || "stopped",
        notify: params.notify !== false,
      });
    }
    return { ok: true, stopped: states.length };
  }

  function emitOutput(state, bytes, options = {}) {
    const buffer = Buffer.isBuffer(bytes) ? bytes : Buffer.from(bytes || []);
    if (!buffer.length || !streams.has(state.streamId)) {
      return;
    }
    if (state.isReplaying && options.replay !== true) {
      state.replayBuffer.push(buffer);
      return;
    }
    state.bytesSent += buffer.length;
    state.chunksSent += 1;
    emit(state, protocol.makeOutput({
      streamId: state.streamId,
      paneId: state.paneId,
      seq: nextSeq(state),
      bytes: buffer,
    }));
  }

  function emitExit(state, event = {}) {
    if (!streams.has(state.streamId)) {
      return;
    }
    stopState(state, {
      reason: event.reason || "exited",
      code: event.code,
      signal: event.signal,
      status: "exited",
      notify: true,
    });
  }

  function emitError(state, error) {
    if (!streams.has(state.streamId)) {
      return;
    }
    state.status = "error";
    emit(state, protocol.makeError({
      streamId: state.streamId,
      paneId: state.paneId,
      seq: nextSeq(state),
      code: error?.code || "terminal_stream_error",
      message: error?.message || "Terminal stream failed.",
      recoverable: true,
    }));
  }

  function nextSeq(state) {
    state.seq += 1;
    return state.seq;
  }

  function emit(state, message) {
    protocol.validateMessage(message);
    try {
      state.sendNotification(TERMINAL_STREAM_EVENT_METHOD, message);
    } catch {}
  }

  function flushReplayBuffer(state) {
    if (!state.replayBuffer.length || !streams.has(state.streamId)) {
      state.replayBuffer = [];
      return;
    }
    const buffered = dropReplayMirroredPrefix(state.replayBuffer, state.replayMirrorText);
    state.replayBuffer = [];
    state.replayMirrorText = "";
    for (const buffer of buffered) {
      emitOutput(state, buffer, { replay: true });
    }
  }

  function stopState(state, options = {}) {
    clearInterval(state.heartbeatTimer);
    state.adapterStream?.stop?.();
    streams.delete(state.streamId);
    streamsByPaneId.delete(state.paneId);
    state.replayBuffer = [];
    state.replayMirrorText = "";
    state.isReplaying = false;
    state.status = options.status || "stopped";
    if (options.notify === false) {
      return;
    }
    emit(state, protocol.makeMessage(TerminalStreamMessageTypes.EXIT, {
      streamId: state.streamId,
      paneId: state.paneId,
      seq: nextSeq(state),
      extra: {
        reason: options.reason || "stopped",
        code: options.code,
        signal: options.signal,
      },
    }));
  }

  function summarizeStream(state) {
    return {
      ok: true,
      streamId: state.streamId,
      paneId: state.paneId,
      status: state.status,
      seq: state.seq,
      bytesSent: state.bytesSent,
      chunksSent: state.chunksSent,
      startedAt: state.startedAt,
    };
  }

  return { replay, start, status, stop, stopAll };
}

function notificationSender(sendNotification) {
  if (typeof sendNotification === "function") {
    return sendNotification;
  }
  return () => {};
}

function replayStart(params = {}, fallback) {
  if (params.historyStart === "-" || params.start === "-") {
    return "-";
  }
  if (Number.isInteger(params.historyStart)) {
    return params.historyStart;
  }
  if (Number.isInteger(params.start)) {
    return params.start;
  }
  return fallback;
}

function replayEnd(params = {}, fallback) {
  if (params.end === "-") {
    return "-";
  }
  if (Number.isInteger(params.end)) {
    return params.end;
  }
  return fallback;
}

function replayMaxBuffer(params = {}, fallback) {
  return Number.isInteger(params.maxBuffer) ? params.maxBuffer : fallback;
}

function dropReplayMirroredPrefix(buffers, replayMirrorText) {
  if (!Array.isArray(buffers) || !buffers.length || !replayMirrorText) {
    return buffers || [];
  }

  const output = [...buffers];
  while (output.length && isReplayMirroredChunk(output[0], replayMirrorText)) {
    output.shift();
  }
  return output;
}

function isReplayMirroredChunk(buffer, replayMirrorText) {
  const text = normalizeReplayMirrorText(buffer);
  if (text.length < 3) {
    return false;
  }
  if (replayMirrorText.endsWith(text)) {
    return true;
  }
  if (text.length >= 8 && replayMirrorText.includes(text)) {
    return true;
  }

  const replayLines = replayMirrorText.split("\n").filter(Boolean);
  const lastLine = replayLines[replayLines.length - 1] || "";
  return lastLine.length >= 3 && (lastLine === text || lastLine.endsWith(text) || text.startsWith(lastLine));
}

function normalizeReplayMirrorText(value) {
  const text = Buffer.isBuffer(value) ? value.toString("utf8") : String(value || "");
  return stripTerminalControl(text)
    .replace(/\r\n/g, "\n")
    .replace(/\r/g, "\n")
    .trim();
}

function stripTerminalControl(text) {
  return String(text || "")
    .replace(/\x1b\][^\x07]*(?:\x07|\x1b\\)/g, "")
    .replace(/\x1b\[[0-?]*[ -/]*[@-~]/g, "")
    .replace(/\x1b[@-Z\\-_]/g, "");
}

module.exports = { createTerminalStreamHub };

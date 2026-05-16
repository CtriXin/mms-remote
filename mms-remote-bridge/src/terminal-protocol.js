// FILE: terminal-protocol.js
// Purpose: Terminal stream protocol v2 helpers shared by Bridge tests and runtime.
// Layer: Protocol
// Exports: TerminalStreamMessageTypes, createTerminalStreamProtocol
// Depends on: crypto

const { randomUUID } = require("crypto");

const TERMINAL_STREAM_EVENT_METHOD = "terminal/stream/event";

const TerminalStreamMessageTypes = Object.freeze({
  READY: "terminal.stream.ready",
  OUTPUT: "terminal.stream.output",
  INPUT_ACK: "terminal.stream.inputAck",
  RESIZE_ACK: "terminal.stream.resizeAck",
  TITLE: "terminal.stream.title",
  CWD: "terminal.stream.cwd",
  BELL: "terminal.stream.bell",
  EXIT: "terminal.stream.exit",
  ERROR: "terminal.stream.error",
  HEARTBEAT: "terminal.stream.heartbeat",
  REPLAY_START: "terminal.stream.replayStart",
  REPLAY_END: "terminal.stream.replayEnd",
});

const knownMessageTypes = new Set(Object.values(TerminalStreamMessageTypes));

function createTerminalStreamProtocol(options = {}) {
  const now = options.now || (() => new Date().toISOString());
  const uuid = options.uuid || randomUUID;

  function createStreamId() {
    return `term-${uuid()}`;
  }

  function normalizeStreamId(value) {
    return normalizeString(value);
  }

  function normalizePaneId(value) {
    return normalizeString(value);
  }

  function makeMessage(type, fields = {}) {
    if (!knownMessageTypes.has(type)) {
      throw new Error(`Unsupported terminal stream message type: ${type}`);
    }
    const streamId = normalizeStreamId(fields.streamId);
    const paneId = normalizePaneId(fields.paneId);
    if (!streamId) {
      throw new Error("Terminal stream message requires streamId");
    }
    if (!paneId) {
      throw new Error("Terminal stream message requires paneId");
    }
    const seq = Number.isInteger(fields.seq) && fields.seq > 0 ? fields.seq : 1;
    return {
      type,
      streamId,
      paneId,
      seq,
      sentAt: fields.sentAt || now(),
      ...withoutUndefined(fields.extra || {}),
    };
  }

  function makeReady(fields) {
    return makeMessage(TerminalStreamMessageTypes.READY, {
      ...fields,
      extra: {
        status: "ready",
        cols: positiveIntegerOrNull(fields.cols),
        rows: positiveIntegerOrNull(fields.rows),
      },
    });
  }

  function makeOutput(fields) {
    const bytes = Buffer.isBuffer(fields.bytes) ? fields.bytes : Buffer.from(fields.bytes || []);
    const base64 = fields.base64 || bytes.toString("base64");
    return makeMessage(TerminalStreamMessageTypes.OUTPUT, {
      ...fields,
      extra: {
        base64,
        byteLength: Buffer.from(base64, "base64").length,
      },
    });
  }

  function makeAck(type, fields) {
    return makeMessage(type, {
      ...fields,
      extra: {
        ok: fields.ok !== false,
        cols: positiveIntegerOrNull(fields.cols),
        rows: positiveIntegerOrNull(fields.rows),
      },
    });
  }

  function makeError(fields) {
    return makeMessage(TerminalStreamMessageTypes.ERROR, {
      ...fields,
      extra: {
        code: normalizeString(fields.code) || "terminal_stream_error",
        message: normalizeString(fields.message) || "Terminal stream failed.",
        recoverable: fields.recoverable !== false,
      },
    });
  }

  function validateStartParams(params = {}) {
    const paneId = normalizePaneId(params.paneId || params.paneKey || params.target);
    const cols = positiveIntegerOrNull(params.cols);
    const rows = positiveIntegerOrNull(params.rows);
    const replay = params.replay !== false;
    return { paneId, cols, rows, replay };
  }

  function validateMessage(message = {}) {
    if (!knownMessageTypes.has(message.type)) {
      throw new Error(`Unsupported terminal stream message type: ${message.type || "(missing)"}`);
    }
    if (!normalizeStreamId(message.streamId)) {
      throw new Error("Terminal stream message requires streamId");
    }
    if (!normalizePaneId(message.paneId)) {
      throw new Error("Terminal stream message requires paneId");
    }
    if (!Number.isInteger(message.seq) || message.seq <= 0) {
      throw new Error("Terminal stream message requires positive integer seq");
    }
    return true;
  }

  return {
    createStreamId,
    makeAck,
    makeError,
    makeMessage,
    makeOutput,
    makeReady,
    validateMessage,
    validateStartParams,
  };
}

function normalizeString(value) {
  return typeof value === "string" ? value.trim() : "";
}

function positiveIntegerOrNull(value) {
  const number = Number(value);
  return Number.isInteger(number) && number > 0 ? number : null;
}

function withoutUndefined(object) {
  return Object.fromEntries(Object.entries(object).filter(([, value]) => value !== undefined && value !== null));
}

module.exports = {
  TERMINAL_STREAM_EVENT_METHOD,
  TerminalStreamMessageTypes,
  createTerminalStreamProtocol,
};

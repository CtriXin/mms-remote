// FILE: terminal-trace.js
// Purpose: Opt-in byte-level terminal diagnostics without logging payload text or bearer-like ids.

const crypto = require("crypto");

function isTerminalTraceEnabled(env = process.env) {
  const value = String(env.MMS_REMOTE_TERMINAL_TRACE || "").trim().toLowerCase();
  return value === "1" || value === "true" || value === "yes" || value === "on";
}

function traceTerminalBytes(logger, label, fields = {}, bytes = Buffer.alloc(0), env = process.env) {
  if (!isTerminalTraceEnabled(env)) {
    return;
  }
  const buffer = Buffer.isBuffer(bytes) ? bytes : Buffer.from(bytes || []);
  const parts = [`[mms-remote][terminal-trace] ${label}`];
  for (const [key, value] of Object.entries(fields)) {
    if (value === undefined || value === null || value === "") {
      continue;
    }
    parts.push(`${key}=${String(value)}`);
  }
  parts.push(`len=${buffer.length}`);
  parts.push(`sha=${byteDigest(buffer)}`);
  parts.push(`head=${byteHex(buffer.subarray(0, 8))}`);
  parts.push(`tail=${byteHex(buffer.subarray(Math.max(0, buffer.length - 8)))}`);
  const line = parts.join(" ");
  if (logger && typeof logger.log === "function") {
    logger.log(line);
  } else {
    console.log(line);
  }
}

function traceTerminalEvent(logger, label, fields = {}, env = process.env) {
  if (!isTerminalTraceEnabled(env)) {
    return;
  }
  const parts = [`[mms-remote][terminal-trace] ${label}`];
  for (const [key, value] of Object.entries(fields)) {
    if (value === undefined || value === null || value === "") {
      continue;
    }
    parts.push(`${key}=${String(value)}`);
  }
  const line = parts.join(" ");
  if (logger && typeof logger.log === "function") {
    logger.log(line);
  } else {
    console.log(line);
  }
}

function redactedId(value) {
  const text = String(value || "");
  if (!text) {
    return "";
  }
  return crypto.createHash("sha256").update(text).digest("hex").slice(0, 10);
}

function byteDigest(buffer) {
  return crypto.createHash("sha256").update(buffer).digest("hex").slice(0, 12);
}

function byteHex(buffer) {
  return Buffer.from(buffer || []).toString("hex") || "-";
}

module.exports = {
  byteDigest,
  isTerminalTraceEnabled,
  redactedId,
  traceTerminalBytes,
  traceTerminalEvent,
};

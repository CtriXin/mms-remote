# MMSChat P1 Registry + Store

- trace_id: `trc-20260516T082907Z-f43b858883`
- base_commit: `ac7275b008c7f33ea7753f779600334c100547e1`
- branch: `p184/mmschat-p1-store`
- scope: `P1 bridge registry/store only`

## Implemented

- Added `mms-remote-bridge/src/mmschat-store.js` with local-state-root path resolution, atomic temp-file + rename JSON writes, best-effort `0600` chmod, and corrupt JSON quarantine fallback.
- Added `mms-remote-bridge/src/mmschat-registry.js` with local-first registry CRUD (`register`, `update`, `list`, `hide`, `clearCache`, `getById`, `getByNativeClaudeSessionId`) and liveness-driven status transitions.
- Registry sorting now returns visible sessions by `lastActivityAt` descending.
- Registry persistence rejects raw secret-like fields such as `apiKey`, `authToken`, `token`, relay-style `sessionId`, pairing secrets, transcript secrets, and provider credential material keys.
- `hide` and `clearCache` preserve registry identity plus native Claude linkage while only changing hidden/cache-derived fields.

## Tests Added

- `mmschat-store.test.js`: state-root path, atomic rename behavior, corrupt JSON quarantine fallback.
- `mmschat-registry.test.js`: CRUD, sorting, secret rejection, hide vs cache clear, liveness transitions, native session lookup.

## Notes

- Store data stays under the existing MMS Remote state root (`MMS_REMOTE_DEVICE_STATE_DIR` or `~/.mms-remote`), not `agent-im` paths.
- Transcript persistence remains intentionally limited to preview/cache metadata; native Claude JSONL remains untouched for P3 observation work.

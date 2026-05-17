# MMSChat S0 Transcript Source Evidence

- task: `s184-0-mmschat-phase0-s0-s3`
- trace_id: `trc-20260516T082907Z-f43b858883`
- commit: `1cc3ceab49a2b2e2c32802968073d25a26cb347e`
- current_head: `dae9397f91fd73b7e4255e051169601a6451fe05` (pack commit is ancestor; user instructed executor to continue after drift)
- mode: passive evidence only; no new live Claude/model session; no `tmux send-keys`; no private transcript content copied.

## Conclusion

MMSChat should treat Claude native project JSONL as the transcript source of truth, keep `tmux capture-pane` only as preview/raw fallback, and not rely on `--output-format` for normal interactive Claude sessions.

## Source Priority

| Rank | Source | Decision | Evidence | Confidence |
|---:|---|---|---|---|
| 1 | Claude native project JSONL | Primary source for persisted transcript and structured message blocks. | `/Users/xin/.claude/projects` exists with 43 project dirs and 147 `*.jsonl` files. Safe shape sampling showed top-level `sessionId`, `uuid`, `parentUuid`, `cwd`, `timestamp`, `type`, `message`; sampled lines commonly had `sessionId` equal to the JSONL filename. | High |
| 2 | `claude -p --output-format stream-json/json` | Useful only for MMS-controlled non-interactive `--print` launches, not for current interactive Terminal Claude sessions. | `claude --help` states `--output-format` works only with `--print`; `stream-json` supports partial messages and hook events only in that mode. | Medium |
| 3 | `tmux capture-pane -p` | Passive preview/status fallback; not a structured transcript source. | Existing Terminal plan already treats capture snapshots as rendered terminal text, not a PTY byte stream or conversation AST. Capture cannot reliably preserve role boundaries, hidden tool metadata, or full scrollback. | Medium |
| 4 | Raw-only fallback | Last-resort UX when native file unavailable or unparseable. | Safe fallback can show stripped recent terminal output and `lastPreviewText` without pretending user/assistant segmentation. | High |

## Native File Evidence

Observed read-only, redacted filesystem shape:

```text
/Users/xin/.claude/
  projects/<project-key>/<session-uuid>.jsonl
  transcripts/<transcript-id>.jsonl
  todos/<session-id>.json
```

`projects` JSONL safe sampling, without message content:

```text
project dirs: 43
project jsonl files: 147
sampled top-level keys: type, sessionId, parentUuid, isSidechain, uuid, timestamp, userType, entrypoint, cwd, version, gitBranch, message, requestId, toolUseResult
sampled message keys: role, content, model, id, type, stop_reason, usage, diagnostics
sampled content shapes: string, list, list_item_text, list_item_thinking, list_item_tool_use, list_item_tool_result
sessionId equals JSONL filename in most sampled lines from newest files
```

`transcripts` top-level JSONL files were also present, but safe sampling showed event/tool-style records with `type`, `timestamp`, `tool_name`, `tool_input`, `tool_output`, `content` and no stable `sessionId`/`cwd` context in sampled records. They are not the preferred source for MMSChat session transcript identity.

## `nativeClaudeSessionId` Strategy

Safest strategy for MMS-owned launches:

1. MMS launcher generates a UUID before starting Claude.
2. Start Claude with `--session-id <uuid>` and the selected provider/model/profile environment.
3. Register MMSChat with `nativeClaudeSessionId=<uuid>` immediately in `pending` state.
4. Verify creation/update of `/Users/xin/.claude/projects/<cwd-key>/<uuid>.jsonl` by checking file existence and JSONL `sessionId` fields, without logging transcript content.
5. Resume with `claude --resume <uuid>` plus the saved launch profile fingerprint/auth secret reference.

Why this is safest:

- It avoids scraping terminal title/output for IDs.
- It avoids racing against recently modified JSONL files.
- It keeps Claude native session as source of truth.
- It lets MMSChat store only an ID, cwd/project, launch profile fingerprint, and `authSecretRef` instead of credentials.

Fallback if MMS cannot pass `--session-id`:

- Watch the expected `projects/<cwd-key>/*.jsonl` directory for a new/updated file after launch time.
- Confirm candidate records have matching `cwd` and fresh `timestamp`.
- Mark `nativeClaudeSessionId` as `pending` until confirmed.
- Treat this as lower confidence and require a guarded live test before P3 relies on it.

## Open Gaps

- S0 did not start a new live Claude session because this executor pack forbids live paid/model probes.
- `--session-id <uuid>` is documented in `claude --help`, but this run did not prove interactive launch persistence with a new live session.
- Provider/model resume compatibility is still S1 scope and must not be assumed from this S0 result.
- Live send/input safety remains S2 scope; S0 makes no claim about writing to a running Claude pane.

## P3 Implication

P3 should implement native project JSONL reading first, with role/content parsing from `message.content` blocks. Keep raw terminal fallback for missing/corrupt/native-unmapped sessions. Do not build MMSChat as a second source-of-truth chat database.

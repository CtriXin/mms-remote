# MMS Remote Data Protection Notes

MMS Remote is designed for local-first operation. Conversation content,
workspace actions, git operations, pairing state, and Codex session data stay
on the machines and relay infrastructure you operate.

The public source tree does not configure a hosted relay, managed push service,
or subscription service. If you enable push notifications, public tunneling,
or a hosted relay, document that deployment separately and keep credentials out
of the repository.

Default local state paths:

- Bridge pairing and daemon state: `~/.mms-remote`
- Codex session data: `~/.codex`
- Runtime registry target from the development plan: `~/.mms-remote/runtimes.jsonl`

# Upstream Remodex Watchlist / OSS Memory — 2026-05-18

- id: upstream-remodex-watchlist-20260518
- updated: 2026-05-18T06:54:00-04:00
- owner: codex
- cli: codex
- model: gpt-5
- status: recorded
- next action: continue MMS Remote development; use upstream as reference only unless user explicitly reopens contribution work

## Recorded Decisions

- Remodex remains Apache-2.0; MMS Remote can continue as a renamed/rebranded derivative while preserving `LICENSE` and `NOTICE` attribution.
- Rename, branding, package name, bundle id, commercial release, and open-source release are OK under Apache-2.0; do not imply upstream endorsement.
- Do not import upstream Terminal SSH/GhosttyKit/Citadel wholesale. Our architecture remains Mac-local Bridge/tmux/SwiftTerm.
- Do not invest in a large upstream tmux Terminal PR now. Remodex is not actively accepting broad contributions; if this changes, open issue/RFC first and send only tiny focused patches.
- Check license/provenance for every new third-party dependency or vendor binary before importing.

## Future Watchlist

- iPad support via existing MMS Remote target.
- iOS foreground WebSocket keepalive.
- Composer draft persistence.
- My Macs / multi-Mac UX adapted to current trusted Mac registry.
- Relay subpath support for reverse-proxy/self-host.
- Timeline/markdown performance ideas only if local bottleneck remains.
- Terminal SSH UX ideas only: keybar/platform mapping/profile nickname/known-host reset.

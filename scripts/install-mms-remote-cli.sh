#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CLI="$ROOT/mms-remote-bridge/bin/mms-remote.js"
BIN_DIR="${MMS_REMOTE_BIN_DIR:-$HOME/.local/bin}"
LINK="$BIN_DIR/mms-remote"

mkdir -p "$BIN_DIR"
ln -sf "$CLI" "$LINK"
chmod +x "$CLI"

cat <<MSG
Installed mms-remote CLI symlink:
  $LINK -> $CLI

If your shell cannot find it, add this to ~/.zshrc:
  export PATH="$BIN_DIR:\$PATH"

Then open a new terminal or run:
  export PATH="$BIN_DIR:\$PATH"

Join current terminal to managed tmux:
  mms-remote terminal join
  mms-remote terminal join my-session
  mms-remote terminal join --name my-session --cwd "\$PWD"
MSG

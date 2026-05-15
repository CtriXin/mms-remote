#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT="$ROOT/CodexMobile/CodexMobile.xcodeproj"
SCHEME="CodexMobile"

if ! command -v xed >/dev/null 2>&1; then
  open -a Xcode "$PROJECT"
else
  xed "$PROJECT"
fi

cat <<MSG
Opened Xcode project:
  $PROJECT

Next:
  1. Select scheme: $SCHEME
  2. Select your iPhone device
  3. Press Cmd+R to install + launch

Optional bridge, in another terminal:
  cd "$ROOT/mms-remote-bridge"
  npm start
MSG

#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT="$ROOT/CodexMobile/CodexMobile.xcodeproj"
SCHEME="CodexMobile"
BUNDLE_ID="com.mms.remote"
DERIVED="$ROOT/.build/xcode-derived"
DEVICE=""
OPEN_XCODE=0
LAUNCH=1

usage() {
  cat <<USAGE
Usage:
  scripts/ios-install-device.sh [--device <UDID|name>] [--open-xcode] [--no-launch]

Examples:
  scripts/ios-install-device.sh
  scripts/ios-install-device.sh --device 00008150-00186C142E44401C
  scripts/ios-install-device.sh --open-xcode
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --device)
      DEVICE="${2:-}"
      shift 2
      ;;
    --open-xcode)
      OPEN_XCODE=1
      shift
      ;;
    --no-launch)
      LAUNCH=0
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown arg: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing command: $1" >&2
    exit 1
  fi
}

pick_device() {
  local destinations
  destinations="$(xcodebuild -project "$PROJECT" -scheme "$SCHEME" -showdestinations 2>/dev/null)"
  python3 -c '
import re, sys
text = sys.argv[1]
for line in text.splitlines():
    if "platform:iOS" not in line or "Simulator" in line or "Any iOS Device" in line:
        continue
    match = re.search(r"id:([^,} ]+)", line)
    if match:
        print(match.group(1))
        sys.exit(0)
sys.exit(1)
' "$destinations"
}

require_cmd xcodebuild
require_cmd xcrun
require_cmd python3

if [[ -z "$DEVICE" ]]; then
  if ! DEVICE="$(pick_device)"; then
    echo "No paired physical iPhone found." >&2
    echo "Plug in/unlock iPhone, enable Developer Mode, then run:" >&2
    echo "  xcrun devicectl list devices" >&2
    exit 1
  fi
fi

echo "Device: $DEVICE"
echo "Project: $PROJECT"
echo "Scheme: $SCHEME"

if [[ "$OPEN_XCODE" -eq 1 ]]; then
  open -a Xcode "$PROJECT"
fi

mkdir -p "$DERIVED"

xcodebuild \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration Debug \
  -destination "platform=iOS,id=$DEVICE" \
  -derivedDataPath "$DERIVED" \
  build

APP="$DERIVED/Build/Products/Debug-iphoneos/CodexMobile.app"
if [[ ! -d "$APP" ]]; then
  echo "Built app not found: $APP" >&2
  exit 1
fi

xcrun devicectl device install app --device "$DEVICE" "$APP"

if [[ "$LAUNCH" -eq 1 ]]; then
  xcrun devicectl device process launch --device "$DEVICE" --terminate-existing "$BUNDLE_ID"
fi

echo "Installed: $BUNDLE_ID"
echo "Bridge command:"
echo "  cd '$ROOT/mms-remote-bridge' && npm start"

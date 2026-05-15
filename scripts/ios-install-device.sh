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
  local json
  json="$(mktemp)"
  trap 'rm -f "$json"' RETURN
  xcrun devicectl list devices --json-output "$json" >/dev/null
  python3 - <<'PY' "$json"
import json, sys
path = sys.argv[1]
data = json.load(open(path))
devices = data.get("result", {}).get("devices", [])
for device in devices:
    hw = device.get("hardwareProperties", {})
    props = device.get("deviceProperties", {})
    conn = device.get("connectionProperties", {})
    if hw.get("platform") != "iOS":
        continue
    if hw.get("reality") != "physical":
        continue
    if conn.get("pairingState") != "paired":
        continue
    if props.get("developerModeStatus") not in ("enabled", "unknown", None):
        continue
    print(hw.get("udid") or device.get("identifier") or props.get("name"))
    sys.exit(0)
sys.exit(1)
PY
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

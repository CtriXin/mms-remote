#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_PATH="$ROOT_DIR/CodexMobile.xcodeproj"
SCHEME="${SCHEME:-CodexMobile}"
CONFIGURATION="${CONFIGURATION:-Debug}"
BUNDLE_ID="${BUNDLE_ID:-com.mms.remote}"
DERIVED_DATA="${DERIVED_DATA:-/tmp/mms-remote-ios-device}"

DEVICE_QUERY=""
DEVICE_NAME_QUERY=""
LAUNCH_APP=1

usage() {
  cat <<'EOF'
Usage:
  CodexMobile/scripts/deploy-ios-device.sh [--device <id|udid|name>] [--name <substring>] [--no-launch]

Examples:
  ./CodexMobile/scripts/deploy-ios-device.sh
  ./CodexMobile/scripts/deploy-ios-device.sh --device 009568BB-3B27-5C91-A94D-34B683F6BCD5
  ./CodexMobile/scripts/deploy-ios-device.sh --name song

Environment:
  SCHEME=CodexMobile
  CONFIGURATION=Debug
  BUNDLE_ID=com.mms.remote
  DERIVED_DATA=/tmp/mms-remote-ios-device
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --device|-d)
      DEVICE_QUERY="${2:-}"
      if [[ -z "$DEVICE_QUERY" ]]; then
        echo "Missing value for --device" >&2
        exit 2
      fi
      shift 2
      ;;
    --name|-n)
      DEVICE_NAME_QUERY="${2:-}"
      if [[ -z "$DEVICE_NAME_QUERY" ]]; then
        echo "Missing value for --name" >&2
        exit 2
      fi
      shift 2
      ;;
    --no-launch)
      LAUNCH_APP=0
      shift
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if ! command -v xcodebuild >/dev/null 2>&1; then
  echo "xcodebuild not found. Please install/open Xcode first." >&2
  exit 1
fi

if ! xcrun --find devicectl >/dev/null 2>&1; then
  echo "devicectl not found. Please use a recent Xcode." >&2
  exit 1
fi

if ! security default-keychain >/dev/null 2>&1; then
  cat >&2 <<EOF
No default keychain is available for this shell, so Xcode signing will fail.
Run this script from a normal macOS Terminal/Ghostty/iTerm2 login shell where Xcode is signed in.

Command:
  cd "$(cd "$ROOT_DIR/.." && pwd)"
  ./CodexMobile/scripts/deploy-ios-device.sh
EOF
  exit 1
fi

devices_json="$(mktemp)"
cleanup() {
  rm -f "$devices_json"
}
trap cleanup EXIT

xcrun devicectl list devices --json-output "$devices_json" >/dev/null

selection="$(
  python3 - "$devices_json" "$DEVICE_QUERY" "$DEVICE_NAME_QUERY" <<'PY'
import json
import sys

path, query, name_query = sys.argv[1:4]
data = json.load(open(path, "r", encoding="utf-8"))
devices = data.get("result", {}).get("devices", [])

def field(device, *keys):
    value = device
    for key in keys:
        if not isinstance(value, dict):
            return None
        value = value.get(key)
    return value

def is_candidate(device):
    return (
        field(device, "hardwareProperties", "platform") == "iOS"
        and field(device, "hardwareProperties", "deviceType") == "iPhone"
        and field(device, "hardwareProperties", "reality") == "physical"
    )

def matches_query(device, value):
    if not value:
        return True
    values = [
        device.get("identifier"),
        field(device, "hardwareProperties", "udid"),
        field(device, "hardwareProperties", "serialNumber"),
        field(device, "deviceProperties", "name"),
    ]
    return any(str(item) == value for item in values if item)

def matches_name(device, value):
    if not value:
        return True
    name = field(device, "deviceProperties", "name") or ""
    return value.lower() in name.lower()

candidates = [
    device for device in devices
    if is_candidate(device) and matches_query(device, query) and matches_name(device, name_query)
]

connected = [
    device for device in candidates
    if field(device, "connectionProperties", "tunnelState") == "connected"
]

pool = connected if connected else candidates
ready = [
    device for device in pool
    if field(device, "deviceProperties", "ddiServicesAvailable") is True
]
pool = ready if ready else pool

def describe(device):
    name = field(device, "deviceProperties", "name") or "Unknown"
    identifier = device.get("identifier") or "?"
    udid = field(device, "hardwareProperties", "udid") or "?"
    tunnel = field(device, "connectionProperties", "tunnelState") or "?"
    ddi = field(device, "deviceProperties", "ddiServicesAvailable")
    return f"{name} | devicectl={identifier} | xcodebuild={udid} | tunnel={tunnel} | ddi={ddi}"

if len(pool) != 1:
    print("ERROR", file=sys.stderr)
    if not candidates:
        print("No physical iPhone matched.", file=sys.stderr)
    else:
        print("Please choose one device with --device or --name:", file=sys.stderr)
        for device in candidates:
            print(f"  - {describe(device)}", file=sys.stderr)
    sys.exit(10)

device = pool[0]
name = field(device, "deviceProperties", "name") or "iPhone"
devicectl_id = device.get("identifier") or field(device, "hardwareProperties", "udid")
xcodebuild_id = field(device, "hardwareProperties", "udid") or devicectl_id
if not devicectl_id or not xcodebuild_id:
    print("Selected device does not expose a usable identifier.", file=sys.stderr)
    sys.exit(11)

print(f"{devicectl_id}\t{xcodebuild_id}\t{name}")
PY
)"

IFS=$'\t' read -r DEVICECTL_ID XCODEBUILD_ID DEVICE_NAME <<<"$selection"

echo "Device: $DEVICE_NAME"
echo "  devicectl:  $DEVICECTL_ID"
echo "  xcodebuild: $XCODEBUILD_ID"
echo "DerivedData: $DERIVED_DATA"

# Bump build number for CodexMobile target
CURRENT_BUILD=$(grep -B 5 'INFOPLIST_FILE = "BuildSupport/CodexMobile-Info.plist"' "$PROJECT_PATH/project.pbxproj" | grep 'CURRENT_PROJECT_VERSION' | sed -E 's/.*= ([0-9]+);.*/\1/' | head -1)
NEW_BUILD=$((CURRENT_BUILD + 1))
echo "Bumping build number: $CURRENT_BUILD -> $NEW_BUILD"
sed -i '' "s/CURRENT_PROJECT_VERSION = $CURRENT_BUILD;/CURRENT_PROJECT_VERSION = $NEW_BUILD;/g" "$PROJECT_PATH/project.pbxproj"

xcodebuild \
  -project "$PROJECT_PATH" \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -destination "platform=iOS,id=$XCODEBUILD_ID" \
  -derivedDataPath "$DERIVED_DATA" \
  -allowProvisioningUpdates \
  build

app_path="$DERIVED_DATA/Build/Products/${CONFIGURATION}-iphoneos/CodexMobile.app"
if [[ ! -d "$app_path" ]]; then
  app_path="$(find "$DERIVED_DATA/Build/Products" -type d -name 'CodexMobile.app' -print -quit 2>/dev/null || true)"
fi

if [[ -z "$app_path" || ! -d "$app_path" ]]; then
  echo "Built app not found under $DERIVED_DATA/Build/Products" >&2
  exit 1
fi

echo "Installing: $app_path"
xcrun devicectl device install app --device "$DEVICECTL_ID" "$app_path"

if [[ "$LAUNCH_APP" == "1" ]]; then
  echo "Launching: $BUNDLE_ID"
  if ! xcrun devicectl device process launch --device "$DEVICECTL_ID" "$BUNDLE_ID"; then
    echo "Installed, but launch failed. Open CodexMobile manually on the iPhone." >&2
  fi
fi

echo "Done."

#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="GlyphBar"
BUNDLE_ID="com.wenjiexu.GlyphBar"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DERIVED_DATA="$ROOT_DIR/DerivedData"
APP_BUNDLE="$DERIVED_DATA/Build/Products/Debug/$APP_NAME.app"
PROJECT="$ROOT_DIR/GlyphBar.xcodeproj"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

resolve_developer_dir() {
  if [[ -n "${DEVELOPER_DIR:-}" && -x "$DEVELOPER_DIR/usr/bin/xcodebuild" ]]; then
    echo "$DEVELOPER_DIR"
    return 0
  fi

  local selected
  selected="$(xcode-select -p 2>/dev/null || true)"
  if [[ -n "$selected" && "$selected" != *CommandLineTools* && -x "$selected/usr/bin/xcodebuild" ]]; then
    echo "$selected"
    return 0
  fi

  local candidate
  for candidate in \
    "/Applications/Xcode-beta.app/Contents/Developer" \
    "/Applications/Xcode.app/Contents/Developer"
  do
    if [[ -x "$candidate/usr/bin/xcodebuild" ]]; then
      echo "$candidate"
      return 0
    fi
  done

  while IFS= read -r app_path; do
    candidate="$app_path/Contents/Developer"
    if [[ -x "$candidate/usr/bin/xcodebuild" ]]; then
      echo "$candidate"
      return 0
    fi
  done < <(find /Applications -maxdepth 1 -name 'Xcode*.app' -type d 2>/dev/null | sort)

  echo "error: full Xcode not found. Install Xcode or set DEVELOPER_DIR to Xcode.app/Contents/Developer." >&2
  return 1
}

export DEVELOPER_DIR="$(resolve_developer_dir)"
XCODEBUILD="$DEVELOPER_DIR/usr/bin/xcodebuild"
SIGNING_OVERRIDES=(
  CODE_SIGNING_ALLOWED=NO
  CODE_SIGNING_REQUIRED=NO
  CODE_SIGN_IDENTITY=
)

build_app() {
  "$XCODEBUILD" \
    -project "$PROJECT" \
    -scheme "$APP_NAME" \
    -configuration Debug \
    -destination 'platform=macOS' \
    -derivedDataPath "$DERIVED_DATA" \
    "${SIGNING_OVERRIDES[@]}" \
    build
}

test_app() {
  "$XCODEBUILD" \
    -project "$PROJECT" \
    -scheme "$APP_NAME" \
    -configuration Debug \
    -destination 'platform=macOS' \
    -derivedDataPath "$DERIVED_DATA" \
    "${SIGNING_OVERRIDES[@]}" \
    test
}

pkill -x "$APP_NAME" >/dev/null 2>&1 || true

register_app() {
  if [[ -x "$LSREGISTER" ]]; then
    local conflicting_bundle
    for conflicting_bundle in \
      "$ROOT_DIR/build/Debug/$APP_NAME.app" \
      "$ROOT_DIR/build/Release/$APP_NAME.app"
    do
      if [[ -d "$conflicting_bundle" && "$conflicting_bundle" != "$APP_BUNDLE" ]]; then
        "$LSREGISTER" -u "$conflicting_bundle" >/dev/null 2>&1 || true
      fi
    done
    "$LSREGISTER" -f -R -trusted "$APP_BUNDLE" >/dev/null 2>&1 || true
  fi
}

open_app() {
  register_app
  /usr/bin/open -n "$APP_BUNDLE"
}

verify_app() {
  pgrep -f "$APP_BUNDLE/Contents/MacOS/$APP_NAME" >/dev/null
}

case "$MODE" in
  run)
    build_app
    open_app
    ;;
  --build|build)
    build_app
    ;;
  --test|test)
    test_app
    ;;
  --debug|debug)
    build_app
    lldb -- "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
    ;;
  --logs|logs)
    build_app
    open_app
    /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\""
    ;;
  --telemetry|telemetry)
    build_app
    open_app
    /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\""
    ;;
  --verify|verify)
    build_app
    open_app
    sleep 1
    verify_app
    ;;
  *)
    echo "usage: $0 [run|--build|--test|--debug|--logs|--telemetry|--verify]" >&2
    exit 2
    ;;
esac

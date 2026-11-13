#!/usr/bin/env bash
# =============================================================================
#  build.sh — export the game under ANY name you like.
#
#    ./build.sh hefland android      ->  build/hefland.apk   (title: "hefland")
#    ./build.sh hefland windows      ->  build/hefland.exe
#    ./build.sh hefland linux        ->  build/hefland.x86_64
#    ./build.sh hefland macos        ->  build/hefland.zip   (contains hefland.app)
#    ./build.sh hefland all          ->  all of the above
#
#  The name becomes the title screen text, the window title and (on Android)
#  the app name under the icon. Each name also gets its own Android package
#  id, so differently-named builds can be installed side by side.
#
#  Desktop builds ALSO rename themselves at runtime: rename hefland.exe to
#  dragonpuzzle.exe and the title screen says DRAGONPUZZLE. Android cannot
#  do that (it renames every installed APK to base.apk), which is why the
#  name is baked in here.
#
#  Requirements: Godot 4.4+ on PATH (or GODOT=/path/to/godot) with matching
#  export templates installed (Editor > Manage Export Templates). Android also
#  needs the Android SDK + a debug keystore configured in Editor Settings
#  (Godot creates a debug keystore automatically on first Android export).
#  Set RELEASE=1 to make release builds (Android then needs a release keystore).
# =============================================================================
set -euo pipefail

NAME="${1:-}"
PLATFORM="${2:-all}"
GODOT="${GODOT:-godot}"
if [[ -z "$NAME" ]]; then
  echo "Usage: ./build.sh <game-name> [android|windows|linux|macos|all]"
  exit 1
fi
if ! command -v "$GODOT" >/dev/null 2>&1; then
  echo "Godot not found. Put it on PATH or run: GODOT=/path/to/godot ./build.sh $NAME $PLATFORM"
  exit 1
fi

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT="$ROOT/build"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$OUT"

# File-safe version of the name (spaces -> underscores) and a package-safe id.
FILE_NAME="$(echo "$NAME" | tr ' ' '_' | tr -cd 'A-Za-z0-9_.-')"
PKG_ID="$(echo "$NAME" | tr '[:upper:]' '[:lower:]' | tr -cd 'a-z0-9')"
[[ -z "$PKG_ID" ]] && PKG_ID="custom"
[[ "$PKG_ID" =~ ^[0-9] ]] && PKG_ID="g$PKG_ID"
DISPLAY_NAME="$(echo "$NAME" | tr '_' ' ' | sed 's/"/\\"/g')"

echo "==> Building \"$DISPLAY_NAME\" ($PLATFORM)"
# Work on a copy so your project files stay untouched.
tar -C "$ROOT" --exclude=./.godot --exclude=./build --exclude=./.git -cf - . | tar -C "$WORK" -xf -
sed -i.bak "s|^config/name=.*|config/name=\"$DISPLAY_NAME\"|" "$WORK/project.godot"
sed -i.bak "s|^package/unique_name=.*|package/unique_name=\"com.blockloot.$PKG_ID\"|" "$WORK/export_presets.cfg"
sed -i.bak "s|^application/bundle_identifier=.*|application/bundle_identifier=\"com.blockloot.$PKG_ID\"|" "$WORK/export_presets.cfg"
rm -f "$WORK"/*.bak

echo "==> Importing assets"
"$GODOT" --headless --path "$WORK" --import >/dev/null 2>&1 || "$GODOT" --headless --path "$WORK" --editor --quit >/dev/null 2>&1 || true

MODE="--export-debug"
[[ "${RELEASE:-0}" == "1" ]] && MODE="--export-release"

export_one() {
  local preset="$1" file="$2"
  echo "==> Exporting $preset -> build/$file"
  "$GODOT" --headless --path "$WORK" "$MODE" "$preset" "$OUT/$file"
}

case "$PLATFORM" in
  android) export_one "Android" "$FILE_NAME.apk" ;;
  windows) export_one "Windows Desktop" "$FILE_NAME.exe" ;;
  linux)   export_one "Linux" "$FILE_NAME.x86_64" ;;
  macos)   export_one "macOS" "$FILE_NAME.zip" ;;
  all)
    export_one "Android" "$FILE_NAME.apk"
    export_one "Windows Desktop" "$FILE_NAME.exe"
    export_one "Linux" "$FILE_NAME.x86_64"
    export_one "macOS" "$FILE_NAME.zip"
    ;;
  *) echo "Unknown platform: $PLATFORM"; exit 1 ;;
esac
echo "==> Done! Look in: $OUT"

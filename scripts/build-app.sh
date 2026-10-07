#!/bin/bash
# Builds build/CubeHub.app from the Swift package, for both Apple Silicon and Intel.
# Pass --zip to also write build/CubeHub.zip, ready to attach to a release.
set -euo pipefail
cd "$(dirname "$0")/.."

ARCHS=(--arch arm64 --arch x86_64)
swift build -c release "${ARCHS[@]}"
BIN="$(swift build -c release "${ARCHS[@]}" --show-bin-path)/CubeHub"

APP="build/CubeHub.app"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# The app draws its own icon; scale it into an .icns.
ICONSET="$WORK/AppIcon.iconset"
mkdir -p "$ICONSET"
"$BIN" --icon "$WORK/icon-1024.png"
for size in 16 32 128 256 512; do
    sips -z "$size" "$size" "$WORK/icon-1024.png" --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
    double=$((size * 2))
    sips -z "$double" "$double" "$WORK/icon-1024.png" --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$WORK/AppIcon.icns"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/CubeHub"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp "$WORK/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
codesign --force --sign - "$APP" >/dev/null 2>&1

echo "Built $APP"

if [[ "${1:-}" == "--zip" ]]; then
    # ditto keeps the code signature intact, which plain zip does not.
    rm -f build/CubeHub.zip
    ditto -c -k --keepParent "$APP" build/CubeHub.zip
    echo "Built build/CubeHub.zip"
fi

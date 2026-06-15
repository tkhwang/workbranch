#!/usr/bin/env bash
set -euo pipefail

APP_VERSION="1.12.1" # x-release-please-version

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
COMPANION_DIR=$(cd "$SCRIPT_DIR/.." && pwd -P)
APP_DIR="$COMPANION_DIR/dist/WorkbranchCompanion.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

cd "$COMPANION_DIR"
if [ "${WORKBRANCH_COMPANION_UNIVERSAL:-0}" = "1" ]; then
  swift build -c release --product WorkbranchCompanion --arch arm64 --arch x86_64
  BINARY_SRC="$COMPANION_DIR/.build/apple/Products/Release/WorkbranchCompanion"
else
  swift build -c release --product WorkbranchCompanion
  BINARY_SRC="$COMPANION_DIR/.build/release/WorkbranchCompanion"
fi

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"
cp "$BINARY_SRC" "$MACOS_DIR/WorkbranchCompanion"
chmod +x "$MACOS_DIR/WorkbranchCompanion"
cp "$COMPANION_DIR/Resources/AppIcon.icns" "$RESOURCES_DIR/AppIcon.icns"
cat > "$CONTENTS_DIR/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleExecutable</key>
  <string>WorkbranchCompanion</string>
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
  <key>CFBundleIdentifier</key>
  <string>com.tkhwang.workbranch-companion</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>WorkbranchCompanion</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>${APP_VERSION}</string>
  <key>CFBundleVersion</key>
  <string>${APP_VERSION}</string>
  <key>LSMinimumSystemVersion</key>
  <string>13.0</string>
  <key>LSUIElement</key>
  <true/>
  <key>NSHighResolutionCapable</key>
  <true/>
</dict>
</plist>
PLIST

/usr/bin/codesign --force --sign - "$APP_DIR" >/dev/null
printf '[+] Built %s (v%s)\n' "$APP_DIR" "$APP_VERSION"

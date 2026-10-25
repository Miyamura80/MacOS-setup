#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
swift build -c release
binary_dir="$(swift build -c release --show-bin-path)"
staging_dir="$(mktemp -d "$PWD/.build/app-stage.XXXXXX")"
trap 'rm -rf "$staging_dir"' EXIT
app="$staging_dir/UsageBar.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$binary_dir/UsageBar" "$app/Contents/MacOS/UsageBar"
ditto "$binary_dir/UsageBar_UsageBar.bundle" "$app/Contents/Resources/UsageBar_UsageBar.bundle"
cat > "$app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>me.eito.usagebar</string>
<key>CFBundleName</key><string>UsageBar</string>
<key>CFBundleDisplayName</key><string>UsageBar</string>
<key>CFBundleExecutable</key><string>UsageBar</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>1.0.0</string>
<key>CFBundleVersion</key><string>1</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>LSUIElement</key><true/>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
plutil -lint "$app/Contents/Info.plist"
codesign --force --sign "${CODE_SIGN_IDENTITY:--}" "$app"
codesign --verify --strict "$app"
# Publish only a complete, signed bundle; keep the previous app until replacement succeeds.
mkdir -p dist
if [ -e dist/UsageBar.app ]; then mv dist/UsageBar.app "$staging_dir/previous.app"; fi
if ! mv "$app" dist/UsageBar.app; then
    if [ -e "$staging_dir/previous.app" ]; then mv "$staging_dir/previous.app" dist/UsageBar.app; fi
    exit 1
fi
printf 'Built %s/dist/UsageBar.app\n' "$PWD"

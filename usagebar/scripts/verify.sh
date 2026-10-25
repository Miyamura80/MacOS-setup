#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
./scripts/test.sh
./scripts/build.sh
source_dir="$PWD"
verification_dir="$(mktemp -d "$PWD/.build/relocated-app.XXXXXX")"
trap 'rm -rf "$verification_dir"' EXIT
# A relocated bundle must find its resources without the source or SwiftPM build directory.
ditto dist/UsageBar.app "$verification_dir/UsageBar.app"
(
    cd "$verification_dir"
    ./UsageBar.app/Contents/MacOS/UsageBar --render-preview "$source_dir/.build/previews"
    codesign --verify --strict UsageBar.app
)
for preview in light dark tray; do test -s ".build/previews/$preview.png"; done
test "$(plutil -extract LSUIElement raw -o - dist/UsageBar.app/Contents/Info.plist)" = true
printf 'Verified regression suite, release bundle, relocated SVG resources, and light/dark/tray rendering.\n'
